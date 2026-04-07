import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../utils/network_client.dart';
import '../utils/clean_helper.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';

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

  MusicBrainzTrackMatch({
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
    this.resolvedCover,
  });

  ResolvedCover? resolvedCover;

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
    if (resolvedCover != null) {
      return resolvedCover!.thumbnailUrl;
    }
    if (releaseId == null || releaseId!.isEmpty) return null;
    return 'https://coverartarchive.org/release/$releaseId/front-250';
  }
}

class ResolvedCover {
  final String endpoint;
  final String id;
  final String? largeUrl;
  final String? thumbnailUrl;

  const ResolvedCover({
    required this.endpoint,
    required this.id,
    this.largeUrl,
    this.thumbnailUrl,
  });
}

class MusicBrainzTagSelectionResult {
  final SongMetadata metadata;
  final Uint8List? artworkBytes;
  final String? thumbnailPath;
  final MusicBrainzTrackMatch match;

  const MusicBrainzTagSelectionResult({
    required this.metadata,
    required this.artworkBytes,
    this.thumbnailPath,
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
            headers: {'User-Agent': 'PurePlayer/1.0 (Codex desktop)'},
          );

  final NetworkClient _client;
  final MetadataDatabase _db = MetadataDatabase();

  static final Map<String, List<MusicBrainzTrackMatch>> _searchCache = {};
  static final Map<String, _CoverArtResult> _coverCache = {};
  static final Map<String, Future<ResolvedCover?>> _coverResolutionInFlight =
      {};

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

    final fallbackTitle = CleanHelper.deriveCleanTitleFromFileName(songPath);
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
    final desiredCount = limit.clamp(1, 50).toInt();
    const pageSize = 20;
    const maxFetchedPerQuery = 100;

    for (final candidateTitle in titleCandidates) {
      final queries = _buildQueries(
        title: candidateTitle,
        artist: normalizedArtist,
        album: normalizedAlbum,
        durationMillis: durationMillis,
      );

      for (final query in queries) {
        var offset = 0;
        while (offset < maxFetchedPerQuery) {
          final page = await _searchWithCache(
            query,
            limit: pageSize,
            offset: offset,
          );

          final matches = page.matches;
          if (matches.isEmpty) break;

          for (final match in matches) {
            final key = match.recordingId.isNotEmpty
                ? match.recordingId
                : '${match.title}|${match.artist}|${match.album ?? ''}';
            collected[key] ??= match;
          }

          if (collected.length >= desiredCount) {
            break;
          }

          final nextOffset = offset + matches.length;
          final totalCount = page.count;
          if (matches.length < pageSize ||
              (totalCount != null && nextOffset >= totalCount)) {
            break;
          }

          offset = nextOffset;
        }

        if (collected.length >= desiredCount) break;
      }

      if (collected.length >= desiredCount) break;
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

    return results.take(desiredCount).toList();
  }

  Future<MusicBrainzTagSelectionResult> applySelection({
    required String songPath,
    required MusicBrainzTrackMatch match,
    SongMetadata? existingMetadata,
    int? fallbackDurationMillis,
  }) async {
    final cover = await _downloadCoverArt(match);
    final saved = await MetadataHelper.saveSelectedSongMetadata(
      filePath: songPath,
      title: match.title,
      artist: match.artist,
      album: match.album ?? 'Unknown Album',
      duration: fallbackDurationMillis ?? match.durationMillis,
      trackNumber: match.trackNumber,
      artworkBytes: cover?.bytes,
      artworkPath: cover?.path,
      thumbnailPath: cover?.thumbnailPath,
      artworkWidth: cover?.width,
      artworkHeight: cover?.height,
      existingMetadata: existingMetadata,
    );

    if (saved == null) {
      throw StateError('Failed to save selected MusicBrainz metadata.');
    }

    final updated = saved.$1;

    return MusicBrainzTagSelectionResult(
      metadata: updated,
      artworkBytes: cover?.bytes,
      thumbnailPath: updated.thumbnailPath,
      match: match,
    );
  }

  Future<_SearchPage> _searchWithCache(
    String query, {
    required int limit,
    required int offset,
  }) async {
    final cacheKey = '${query.trim()}|limit=$limit|offset=$offset';
    if (_searchCache.containsKey(cacheKey)) {
      return _SearchPage(
        matches: _searchCache[cacheKey]!,
        count: null,
        offset: offset,
      );
    }

    try {
      await _rateLimit();
      final response = await _client.get(
        '/ws/2/recording/',
        queryParameters: {
          'query': query,
          'fmt': 'json',
          'limit': '$limit',
          'offset': '$offset',
        },
      );
      final data = response.data;
      final count = data is Map<String, dynamic>
          ? (data['count'] as num?)?.toInt()
          : null;
      final recordings = data is Map<String, dynamic>
          ? (data['recordings'] as List<dynamic>? ?? const [])
          : const [];
      final matches = recordings
          .whereType<Map<String, dynamic>>()
          .map(MusicBrainzTrackMatch.fromJson)
          .toList();
      _searchCache[cacheKey] = matches;
      return _SearchPage(matches: matches, count: count, offset: offset);
    } catch (e) {
      debugPrint('MusicBrainz search failed for "$query": $e');
      return _SearchPage(matches: const [], count: null, offset: offset);
    }
  }

  Future<ResolvedCover?> resolveCover(MusicBrainzTrackMatch match) async {
    if (match.resolvedCover != null) return match.resolvedCover;

    final candidates = <({String endpoint, String id})>[];
    if (_hasMeaningfulText(match.releaseId)) {
      candidates.add((endpoint: 'release', id: match.releaseId!));
    }
    if (_hasMeaningfulText(match.releaseGroupId)) {
      candidates.add((endpoint: 'release-group', id: match.releaseGroupId!));
    }

    for (final candidate in candidates) {
      final metadata = await _resolveCoverMetadataWithCache(
        endpoint: candidate.endpoint,
        id: candidate.id,
      );
      if (metadata != null) {
        match.resolvedCover = metadata;
        return metadata;
      }
    }

    return null;
  }

  Future<ResolvedCover?> _resolveCoverMetadataWithCache({
    required String endpoint,
    required String id,
  }) async {
    // Try database cache first
    if (endpoint == 'release') {
      final cached = await _db.getReleaseCoverCache(id);
      if (cached != null && _hasMeaningfulText(cached.largeUrl)) {
        return ResolvedCover(
          endpoint: endpoint,
          id: id,
          largeUrl: cached.largeUrl,
          thumbnailUrl: cached.thumbnailUrl,
        );
      }
    }

    // Check in-flight requests
    final cacheKey = '$endpoint|$id';
    final inFlight = _coverResolutionInFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _resolveCoverMetadataFromEndpoint(endpoint: endpoint, id: id)
        .whenComplete(() {
          _coverResolutionInFlight.remove(cacheKey);
        });
    _coverResolutionInFlight[cacheKey] = future;

    final resolved = await future;
    if (resolved != null && endpoint == 'release') {
      // Save to database cache
      await _db.insertOrUpdateReleaseCoverCache(
        ReleaseCoverCacheRecord(
          releaseId: id,
          largeUrl: resolved.largeUrl,
          thumbnailUrl: resolved.thumbnailUrl,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    return resolved;
  }

  Future<ResolvedCover?> _resolveCoverMetadataFromEndpoint({
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

      Map<String, dynamic>? selectedImage;
      // 1. Try to find the front cover image
      selectedImage = images.firstWhere(
        (img) => img['front'] == true,
        orElse: () => <String, dynamic>{},
      );

      // 2. Fallback to the first available image if no front image was found
      if (selectedImage.isEmpty) {
        selectedImage = images.isNotEmpty ? images.first : null;
      }

      if (selectedImage == null || selectedImage.isEmpty) return null;

      final thumbnails = selectedImage['thumbnails'];
      String? largeUrl;
      String? thumbnailUrl;

      if (thumbnails is Map<String, dynamic>) {
        largeUrl =
            selectedImage['image'] as String? ??
            thumbnails['1200'] as String? ??
            thumbnails['large'] as String?;
        thumbnailUrl =
            thumbnails['small'] as String? ??
            thumbnails['250'] as String? ??
            thumbnails['large'] as String? ??
            largeUrl;
      } else {
        largeUrl = selectedImage['image'] as String?;
        thumbnailUrl = largeUrl;
      }

      if (!_hasMeaningfulText(largeUrl)) return null;

      return ResolvedCover(
        endpoint: endpoint,
        id: id,
        largeUrl: largeUrl,
        thumbnailUrl: thumbnailUrl,
      );
    } catch (e) {
      debugPrint('MusicBrainz metadata resolution failed: $e');
      return null;
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

    final resolved = await resolveCover(match);
    if (resolved == null || resolved.largeUrl == null) return null;

    final cover = await _downloadResolvedCover(resolved);
    if (cover != null) {
      _coverCache[cacheKey] = cover;
      return cover;
    }

    return null;
  }

  Future<_CoverArtResult?> _downloadResolvedCover(
    ResolvedCover resolved,
  ) async {
    try {
      final candidateUrls = <String>[
        if (_hasMeaningfulText(resolved.largeUrl)) resolved.largeUrl!,
        if (_hasMeaningfulText(resolved.thumbnailUrl) &&
            resolved.thumbnailUrl != resolved.largeUrl)
          resolved.thumbnailUrl!,
      ];

      Uint8List? bytes;
      for (final imageUrl in candidateUrls) {
        try {
          await _rateLimit();
          debugPrint('MusicBrainz cover image download: $imageUrl');
          final bytesResponse = await _client.get<List<int>>(
            imageUrl,
            options: Options(responseType: ResponseType.bytes),
          );
          final data = bytesResponse.data ?? const <int>[];
          if (data.isNotEmpty) {
            bytes = Uint8List.fromList(data);
            break;
          }
        } catch (e) {
          debugPrint('MusicBrainz cover image candidate failed: $e');
        }
      }

      if (bytes == null || bytes.isEmpty) return null;

      // 1. Process and save both large image and thumbnail
      final artworkInfo = await MetadataHelper.saveArtworkAndThumbnail(
        resolved.id, // Using resolving ID as part of name
        bytes,
      );

      if (artworkInfo == null) return null;

      return _CoverArtResult(
        path: artworkInfo['artworkPath'] as String,
        thumbnailPath: artworkInfo['thumbnailPath'] as String,
        bytes: bytes,
        width: artworkInfo['width'] as int? ?? 1200,
        height: artworkInfo['height'] as int? ?? 1200,
      );
    } catch (e) {
      debugPrint('MusicBrainz cover download failed: $e');
      return null;
    }
  }
}

class _SearchPage {
  final List<MusicBrainzTrackMatch> matches;
  final int? count;
  final int offset;

  const _SearchPage({
    required this.matches,
    required this.count,
    required this.offset,
  });
}

class _CoverArtResult {
  final String path;
  final String thumbnailPath;
  final Uint8List bytes;
  final int width;
  final int height;

  const _CoverArtResult({
    required this.path,
    required this.thumbnailPath,
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

String _normalizeField(String? value) {
  if (!_hasMeaningfulText(value)) return '';
  return value!.trim();
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
