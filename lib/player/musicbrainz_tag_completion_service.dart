import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:palette_generator/palette_generator.dart';

import '../utils/network_client.dart';
import 'metadata_database.dart';
import 'theme_color_helper.dart';

class MusicBrainzTrackMatch {
  final String recordingId;
  final String title;
  final String artist;
  final String? album;
  final String? releaseId;
  final String? releaseGroupId;
  final String? releaseDate;
  final String? country;
  final int? durationMillis;
  final int? trackNumber;
  final int score;
  final String? disambiguation;
  final Map<String, dynamic> raw;

  const MusicBrainzTrackMatch({
    required this.recordingId,
    required this.title,
    required this.artist,
    required this.album,
    required this.releaseId,
    required this.releaseGroupId,
    required this.releaseDate,
    required this.country,
    required this.durationMillis,
    required this.trackNumber,
    required this.score,
    required this.disambiguation,
    required this.raw,
  });

  factory MusicBrainzTrackMatch.fromJson(Map<String, dynamic> json) {
    final releases = (json['releases'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    Map<String, dynamic>? firstRelease;
    for (final release in releases) {
      final media = (release['media'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (media.isNotEmpty) {
        firstRelease = release;
        break;
      }
    }
    firstRelease ??= releases.isNotEmpty ? releases.first : null;

    String? album;
    String? releaseId;
    String? releaseGroupId;
    String? releaseDate;
    String? country;
    int? trackNumber;

    if (firstRelease != null) {
      album = firstRelease['title'] as String?;
      releaseId = firstRelease['id'] as String?;
      releaseDate = firstRelease['date'] as String?;
      country = firstRelease['country'] as String?;

      final releaseGroup = firstRelease['release-group'];
      if (releaseGroup is Map<String, dynamic>) {
        releaseGroupId = releaseGroup['id'] as String?;
      }

      final media = (firstRelease['media'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (media.isNotEmpty) {
        final tracks = (media.first['track'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
        if (tracks.isNotEmpty) {
          trackNumber = int.tryParse(tracks.first['number']?.toString() ?? '');
        }
      }
    }

    final artist = _joinArtistCredit(
      json['artist-credit'] as List<dynamic>? ?? const [],
    );

    return MusicBrainzTrackMatch(
      recordingId: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: artist.isEmpty ? 'Unknown Artist' : artist,
      album: album,
      releaseId: releaseId,
      releaseGroupId: releaseGroupId,
      releaseDate: releaseDate,
      country: country,
      durationMillis: (json['length'] as num?)?.toInt(),
      trackNumber: trackNumber,
      score: int.tryParse(json['score']?.toString() ?? '') ?? 0,
      disambiguation: json['disambiguation'] as String?,
      raw: json,
    );
  }

  String get durationLabel {
    final ms = durationMillis;
    if (ms == null || ms <= 0) return '--:--';
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String? get thumbnailUrl {
    if (releaseId == null || releaseId!.isEmpty) return null;
    return 'https://coverartarchive.org/release/$releaseId/front-250';
  }
}

class MusicBrainzTagSelectionResult {
  final SongMetadata metadata;
  final Uint8List? artworkBytes;
  final MusicBrainzTrackMatch match;

  const MusicBrainzTagSelectionResult({
    required this.metadata,
    required this.artworkBytes,
    required this.match,
  });
}

class MusicBrainzTagCompletionService {
  MusicBrainzTagCompletionService({NetworkClient? client})
    : _client =
          client ??
          NetworkClient(
            baseUrl: 'https://musicbrainz.org',
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            headers: {
              'User-Agent': 'PurePlayer/1.0 (Codex desktop)',
            },
          );

  final NetworkClient _client;
  final MetadataDatabase _db = MetadataDatabase();

  static final Map<String, List<MusicBrainzTrackMatch>> _searchCache = {};
  static final Map<String, _CoverArtResult> _coverCache = {};

  static Future<void> _rateLimit() async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequestAt);
    if (elapsed < const Duration(seconds: 1)) {
      await Future.delayed(const Duration(seconds: 1) - elapsed);
    }
    _lastRequestAt = DateTime.now();
  }

  static DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<List<MusicBrainzTrackMatch>> searchMatches({
    required String songPath,
    required String? title,
    required String? artist,
    required String? album,
    required int? durationMillis,
    int limit = 12,
  }) async {
    final titleCandidates = <String>[];
    if (_hasMeaningfulText(title)) {
      titleCandidates.add(title!.trim());
    }

    final fallbackTitle = _deriveFallbackTitle(songPath);
    if (_hasMeaningfulText(fallbackTitle) &&
        !titleCandidates.any(
          (candidate) => _sameText(candidate, fallbackTitle),
        )) {
      titleCandidates.add(fallbackTitle);
    }

    if (titleCandidates.isEmpty) {
      titleCandidates.add(p.basenameWithoutExtension(songPath));
    }

    final normalizedArtist = _normalizeField(artist);
    final normalizedAlbum = _normalizeField(album);

    final collected = <String, MusicBrainzTrackMatch>{};

    for (final candidateTitle in titleCandidates) {
      final queries = _buildQueries(
        title: candidateTitle,
        artist: normalizedArtist,
        album: normalizedAlbum,
        durationMillis: durationMillis,
      );

      for (final query in queries) {
        final matches = await _searchWithCache(query);
        for (final match in matches) {
          final key = match.recordingId.isNotEmpty
              ? match.recordingId
              : '${match.title}|${match.artist}|${match.album ?? ''}';
          collected[key] ??= match;
        }
        if (collected.isNotEmpty) {
          break;
        }
      }

      if (collected.isNotEmpty) break;
    }

    final results = collected.values.toList()
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) return scoreCompare;

        final durationA = a.durationMillis;
        final durationB = b.durationMillis;
        final diffA = durationMillis == null || durationA == null
            ? 0
            : (durationA - durationMillis).abs();
        final diffB = durationMillis == null || durationB == null
            ? 0
            : (durationB - durationMillis).abs();
        final diffCompare = diffA.compareTo(diffB);
        if (diffCompare != 0) return diffCompare;

        return a.title.compareTo(b.title);
      });

    return results.take(limit).toList();
  }

  Future<MusicBrainzTagSelectionResult> applySelection({
    required String songPath,
    required MusicBrainzTrackMatch match,
    SongMetadata? existingMetadata,
    int? fallbackDurationMillis,
  }) async {
    final current = existingMetadata ?? await _db.getSongMetadata(songPath);
    final cover = await _downloadCoverArt(match);

    Uint8List? themeColorsBlob;
    if (cover?.bytes != null) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          MemoryImage(cover!.bytes),
          maximumColorCount: 20,
        );
        themeColorsBlob = ThemeColorHelper.paletteToBlob(palette);
      } catch (e) {
        debugPrint('Error generating MusicBrainz palette for $songPath: $e');
      }
    } else {
      themeColorsBlob = current?.themeColorsBlob;
    }

    final updated = SongMetadata(
      id: current?.id,
      path: songPath,
      title: match.title.trim().isNotEmpty
          ? match.title.trim()
          : current?.title ?? p.basenameWithoutExtension(songPath),
      album: _preferText(
        match.album,
        current?.album,
        fallback: 'Unknown Album',
      ),
      artist: _preferText(
        match.artist,
        current?.artist,
        fallback: 'Unknown Artist',
      ),
      duration:
          current?.duration ?? fallbackDurationMillis ?? match.durationMillis,
      artworkPath: cover?.path ?? current?.artworkPath,
      artworkWidth: cover?.width ?? current?.artworkWidth,
      artworkHeight: cover?.height ?? current?.artworkHeight,
      trackNumber: match.trackNumber ?? current?.trackNumber,
      themeColorsBlob: themeColorsBlob,
      waveformBlob: current?.waveformBlob,
    );

    await _db.insertOrUpdateSong(updated);

    return MusicBrainzTagSelectionResult(
      metadata: updated,
      artworkBytes: cover?.bytes,
      match: match,
    );
  }

  Future<List<MusicBrainzTrackMatch>> _searchWithCache(String query) async {
    final cacheKey = query.trim();
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    try {
      await _rateLimit();
      final response = await _client.get(
        '/ws/2/recording/',
        queryParameters: {'query': query, 'fmt': 'json', 'limit': '20'},
      );
      final data = response.data;
      final recordings = data is Map<String, dynamic>
          ? (data['recordings'] as List<dynamic>? ?? const [])
          : const [];
      final matches = recordings
          .whereType<Map<String, dynamic>>()
          .map(MusicBrainzTrackMatch.fromJson)
          .toList();
      _searchCache[cacheKey] = matches;
      return matches;
    } catch (e) {
      debugPrint('MusicBrainz search failed for "$query": $e');
      return const [];
    }
  }

  Future<_CoverArtResult?> _downloadCoverArt(
    MusicBrainzTrackMatch match,
  ) async {
    final cacheKey =
        match.releaseId ?? match.releaseGroupId ?? match.recordingId;
    if (_coverCache.containsKey(cacheKey)) {
      return _coverCache[cacheKey];
    }

    final candidates = <({String endpoint, String id})>[];
    if (_hasMeaningfulText(match.releaseId)) {
      candidates.add((endpoint: 'release', id: match.releaseId!));
    }
    if (_hasMeaningfulText(match.releaseGroupId)) {
      candidates.add((endpoint: 'release-group', id: match.releaseGroupId!));
    }

    for (final candidate in candidates) {
      final cover = await _downloadCoverArtFromEndpoint(
        endpoint: candidate.endpoint,
        id: candidate.id,
      );
      if (cover != null) {
        _coverCache[cacheKey] = cover;
        return cover;
      }
    }

    return null;
  }

  Future<_CoverArtResult?> _downloadCoverArtFromEndpoint({
    required String endpoint,
    required String id,
  }) async {
    try {
      await _rateLimit();
      final apiUrl = Uri.https('coverartarchive.org', '/$endpoint/$id');
      debugPrint('MusicBrainz cover metadata URL: $apiUrl');
      final response = await _client.get(
        apiUrl.toString(),
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;

      final images = (data['images'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (images.isEmpty) return null;

      String? imageUrl;
      for (final image in images) {
        final thumbnails = image['thumbnails'];
        if (thumbnails is Map<String, dynamic>) {
          imageUrl =
              thumbnails['1200'] as String? ??
              thumbnails['large'] as String? ??
              image['image'] as String?;
          if (_hasMeaningfulText(imageUrl)) break;
        } else {
          imageUrl = image['image'] as String?;
          if (_hasMeaningfulText(imageUrl)) break;
        }
      }

      if (!_hasMeaningfulText(imageUrl)) {
        return null;
      }

      await _rateLimit();
      debugPrint('MusicBrainz cover image URL: $imageUrl');
      final bytesResponse = await _client.get<List<int>>(
        imageUrl!,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(bytesResponse.data ?? const <int>[]);
      if (bytes.isEmpty) return null;

      final tempDir = await getTemporaryDirectory();
      final coversDir = Directory(p.join(tempDir.path, 'musicbrainz_covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final fileName =
          '${_sanitizeFileName('${endpoint}_$id')}_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final filePath = p.join(coversDir.path, fileName);
      await File(filePath).writeAsBytes(bytes, flush: true);

      return _CoverArtResult(
        path: filePath,
        bytes: bytes,
        width: 1200,
        height: 1200,
      );
    } catch (e) {
      debugPrint('MusicBrainz cover download failed for $endpoint/$id: $e');
      return null;
    }
  }
}

class _CoverArtResult {
  final String path;
  final Uint8List bytes;
  final int width;
  final int height;

  const _CoverArtResult({
    required this.path,
    required this.bytes,
    required this.width,
    required this.height,
  });
}

List<String> _buildQueries({
  required String title,
  required String? artist,
  required String? album,
  required int? durationMillis,
}) {
  final queries = <String>[];

  final titleTerm = _fieldTerm('recording', title);
  final artistTerm = _hasMeaningfulText(artist)
      ? _fieldTerm('artistname', artist!)
      : null;
  final albumTerm = _hasMeaningfulText(album)
      ? _fieldTerm('release', album!)
      : null;
  final durationTerm = durationMillis != null && durationMillis > 0
      ? _durationTerm(durationMillis)
      : null;

  void addQuery(List<String?> terms) {
    final query = terms
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' AND ');
    if (query.isNotEmpty && !queries.contains(query)) {
      queries.add(query);
    }
  }

  addQuery([titleTerm, artistTerm, albumTerm, durationTerm]);
  addQuery([titleTerm, artistTerm, durationTerm]);
  addQuery([titleTerm, albumTerm, durationTerm]);
  addQuery([titleTerm, durationTerm]);
  addQuery([titleTerm, artistTerm]);
  addQuery([titleTerm]);

  return queries;
}

String _fieldTerm(String field, String value) {
  return '$field:"${_escapeLucene(value)}"';
}

String _durationTerm(int durationMillis) {
  final lower = durationMillis - 5000 < 0 ? 0 : durationMillis - 5000;
  final upper = durationMillis + 5000;
  return 'dur:[$lower TO $upper]';
}

String _escapeLucene(String value) {
  const specialChars = r'+-!(){}[]^"~*?:\/&|';
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (specialChars.contains(char)) {
      buffer.write('\\');
    }
    buffer.write(char);
  }
  return buffer.toString();
}

String _sanitizeFileName(String value) {
  return value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
}

String _deriveFallbackTitle(String songPath) {
  final base = p.basenameWithoutExtension(songPath).trim();
  final stripped = base.replaceFirst(RegExp(r'^\s*(?:\d{1,3}[\s._-]*)+'), '');
  final candidate = stripped.trim();
  return candidate.isEmpty ? base : candidate;
}

String _normalizeField(String? value) {
  if (!_hasMeaningfulText(value)) return '';
  return value!.trim();
}

String _preferText(
  String? preferred,
  String? fallbackValue, {
  required String fallback,
}) {
  if (_hasMeaningfulText(preferred)) return preferred!.trim();
  if (_hasMeaningfulText(fallbackValue)) return fallbackValue!.trim();
  return fallback;
}

bool _hasMeaningfulText(String? value) {
  if (value == null) return false;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  return lower != 'unknown' &&
      lower != 'unknown artist' &&
      lower != 'unknown album';
}

bool _sameText(String left, String right) {
  return left.trim().toLowerCase() == right.trim().toLowerCase();
}

String _joinArtistCredit(List<dynamic> credits) {
  final buffer = StringBuffer();
  for (final entry in credits) {
    if (entry is! Map<String, dynamic>) continue;
    final artist = entry['artist'];
    if (artist is Map<String, dynamic>) {
      buffer.write(artist['name']?.toString() ?? '');
    }
    buffer.write(entry['joinphrase']?.toString() ?? '');
  }
  return buffer.toString().trim();
}
