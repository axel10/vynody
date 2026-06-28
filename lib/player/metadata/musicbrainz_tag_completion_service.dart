import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vynody/utils/network_client.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_en.dart';
import '../../l10n/app_localizations_zh.dart';

part 'musicbrainz_tag_completion_service.freezed.dart';

AppLocalizations _l10n() {
  final locale = PlatformDispatcher.instance.locale;
  return locale.languageCode == 'zh' ? AppLocalizationsZh() : AppLocalizationsEn();
}

@freezed
abstract class MusicBrainzReleaseMatch with _$MusicBrainzReleaseMatch {
  const MusicBrainzReleaseMatch._();

  const factory MusicBrainzReleaseMatch({
    required String id,
    required String title,
    required String? country,
    required String? dateLabel,
    required int? trackCount,
    required String? releaseGroupId,
    required Map<String, dynamic> raw,
  }) = _MusicBrainzReleaseMatch;

  String get thumbnailUrl =>
      'https://coverartarchive.org/release/$id/front-250';

  String get largeUrl => 'https://coverartarchive.org/release/$id/front';

  factory MusicBrainzReleaseMatch.fromJson(Map<String, dynamic> json) {
    String? releaseGroupId;
    final releaseGroup = json['release-group'];
    if (releaseGroup is Map<String, dynamic>) {
      releaseGroupId = releaseGroup['id'] as String?;
    }

    return MusicBrainzReleaseMatch(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      country: json['country'] as String?,
      dateLabel: json['date'] as String?,
      trackCount: (json['track-count'] as num?)?.toInt(),
      releaseGroupId: releaseGroupId,
      raw: Map<String, dynamic>.from(json),
    );
  }
}

@freezed
abstract class MusicBrainzReleaseGroup with _$MusicBrainzReleaseGroup {
  const MusicBrainzReleaseGroup._();

  const factory MusicBrainzReleaseGroup({
    required String key,
    required String title,
    @Default(<MusicBrainzReleaseMatch>[])
    List<MusicBrainzReleaseMatch> releases,
  }) = _MusicBrainzReleaseGroup;

  String get thumbnailUrl =>
      releases.isNotEmpty ? releases.first.thumbnailUrl : '';

  String get largeUrl => releases.isNotEmpty ? releases.first.largeUrl : '';
}

@freezed
abstract class MusicBrainzTrackMatch with _$MusicBrainzTrackMatch {
  const MusicBrainzTrackMatch._();

  const factory MusicBrainzTrackMatch({
    required String recordingId,
    required String title,
    required String artist,
    required String? album,
    required String? releaseId,
    required String? releaseGroupId,
    required String? releaseDate,
    required String? country,
    required int? durationMillis,
    required int? trackNumber,
    required int score,
    required String? disambiguation,
    @Default(<MusicBrainzReleaseMatch>[])
    List<MusicBrainzReleaseMatch> releases,
    required Map<String, dynamic> raw,
    required ResolvedCover? resolvedCover,
  }) = _MusicBrainzTrackMatch;

  factory MusicBrainzTrackMatch.fromJson(Map<String, dynamic> json) {
    final releases = (json['releases'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MusicBrainzReleaseMatch.fromJson)
        .toList(growable: false);

    MusicBrainzReleaseMatch? firstRelease;
    for (final release in releases) {
      final media = (release.raw['media'] as List<dynamic>? ?? const [])
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
      album = firstRelease.title;
      releaseId = firstRelease.id;
      releaseDate = firstRelease.dateLabel;
      country = firstRelease.country;
      releaseGroupId = firstRelease.releaseGroupId;

      final media = (firstRelease.raw['media'] as List<dynamic>? ?? const [])
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
      artist: artist.isEmpty
          ? _l10n().unknownArtist
          : artist,
      album: album,
      releaseId: releaseId,
      releaseGroupId: releaseGroupId,
      releaseDate: releaseDate,
      country: country,
      durationMillis: (json['length'] as num?)?.toInt(),
      trackNumber: trackNumber,
      score: int.tryParse(json['score']?.toString() ?? '') ?? 0,
      disambiguation: json['disambiguation'] as String?,
      releases: releases,
      raw: json,
      resolvedCover: null,
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

  String? get largeUrl {
    if (resolvedCover != null) {
      return resolvedCover!.largeUrl;
    }
    if (releaseId == null || releaseId!.isEmpty) return null;
    return 'https://coverartarchive.org/release/$releaseId/front';
  }

  List<MusicBrainzReleaseGroup> get releaseGroups {
    if (releases.isEmpty) return const [];

    final groups = <String, _MusicBrainzReleaseGroupBuilder>{};
    final order = <String>[];

    for (final release in releases) {
      final key = _normalizeReleaseGroupKey(release.title);
      final builder = groups[key];
      if (builder == null) {
        groups[key] = _MusicBrainzReleaseGroupBuilder(
          key: key,
          title: release.title.trim().isNotEmpty
              ? release.title.trim()
              : _l10n().untitledRelease,
          releases: [release],
        );
        order.add(key);
      } else {
        builder.releases.add(release);
        if (builder.title == _l10n().untitledRelease &&
            release.title.trim().isNotEmpty) {
          builder.title = release.title.trim();
        }
      }
    }

    return order.map((key) => groups[key]!.toGroup()).toList(growable: false);
  }
}

class _MusicBrainzReleaseGroupBuilder {
  final String key;
  String title;
  final List<MusicBrainzReleaseMatch> releases;

  _MusicBrainzReleaseGroupBuilder({
    required this.key,
    required this.title,
    required this.releases,
  });

  MusicBrainzReleaseGroup toGroup() {
    return MusicBrainzReleaseGroup(
      key: key,
      title: title,
      releases: List<MusicBrainzReleaseMatch>.unmodifiable(releases),
    );
  }
}

@freezed
abstract class ResolvedCover with _$ResolvedCover {
  const ResolvedCover._();

  const factory ResolvedCover({
    required String endpoint,
    required String id,
    String? largeUrl,
    String? thumbnailUrl,
  }) = _ResolvedCover;
}

@freezed
abstract class MusicBrainzTagSelectionResult
    with _$MusicBrainzTagSelectionResult {
  const MusicBrainzTagSelectionResult._();

  const factory MusicBrainzTagSelectionResult({
    required SongMetadata metadata,
    required Uint8List? artworkBytes,
    String? thumbnailPath,
    required MusicBrainzTrackMatch match,
  }) = _MusicBrainzTagSelectionResult;
}

class MusicBrainzTagCompletionService {
  MusicBrainzTagCompletionService({NetworkClient? client})
    : _client = client ?? NetworkClient.instance;

  final NetworkClient _client;

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
    bool enableTitleQuery = true,
    bool enableArtistQuery = true,
    bool enableAlbumQuery = true,
    bool enableDurationQuery = true,
    int limit = 12,
  }) async {
    final desiredCount = limit.clamp(1, 50).toInt();
    final query = _buildQuery(
      title: enableTitleQuery ? _normalizeField(title) : null,
      artist: enableArtistQuery ? _normalizeField(artist) : null,
      album: enableAlbumQuery ? _normalizeField(album) : null,
      durationMillis: enableDurationQuery ? durationMillis : null,
    );

    if (query == null) {
      return const [];
    }

    final page = await _searchWithCache(query, limit: desiredCount, offset: 0);

    final results = page.matches.toList()
      ..sort((a, b) {
        final releaseCountCompare = b.releases.length.compareTo(
          a.releases.length,
        );
        if (releaseCountCompare != 0) return releaseCountCompare;

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
    MusicBrainzReleaseMatch? selectedRelease,
    SongMetadata? existingMetadata,
    int? fallbackDurationMillis,
    bool writeToFile = false,
  }) async {
    final effectiveRelease =
        selectedRelease ??
        (match.releases.isNotEmpty ? match.releases.first : null);
    final effectiveMatch = effectiveRelease != null
        ? match.copyWith(
            album: effectiveRelease.title,
            releaseId: effectiveRelease.id,
            releaseGroupId:
                effectiveRelease.releaseGroupId ?? match.releaseGroupId,
            releaseDate: effectiveRelease.dateLabel ?? match.releaseDate,
            country: effectiveRelease.country ?? match.country,
            releases: match.releases.isEmpty
                ? <MusicBrainzReleaseMatch>[effectiveRelease]
                : match.releases,
            resolvedCover: ResolvedCover(
              endpoint: 'release',
              id: effectiveRelease.id,
              largeUrl: effectiveRelease.largeUrl,
              thumbnailUrl: effectiveRelease.thumbnailUrl,
            ),
          )
        : match;

    final cover = await _downloadCoverArt(
      effectiveMatch,
      selectedRelease: effectiveRelease,
    );
    final saved = await MetadataHelper.saveSelectedSongMetadata(
      filePath: songPath,
      title: effectiveMatch.title,
      artist: effectiveMatch.artist,
      album: effectiveMatch.album ?? _l10n().unknownAlbum,
      duration: fallbackDurationMillis ?? effectiveMatch.durationMillis,
      trackNumber: effectiveMatch.trackNumber,
      artworkBytes: cover?.bytes,
      artworkPath: cover?.path,
      thumbnailPath: cover?.thumbnailPath,
      artworkWidth: cover?.width,
      artworkHeight: cover?.height,
      existingMetadata: existingMetadata,
      writeToFile: writeToFile,
    );

    if (saved == null) {
      throw StateError('Failed to save selected MusicBrainz metadata.');
    }

    final updated = saved.$1;

    return MusicBrainzTagSelectionResult(
      metadata: updated,
      artworkBytes: cover?.bytes,
      thumbnailPath: updated.thumbnailPath,
      match: effectiveMatch,
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
        'https://musicbrainz.org/ws/2/recording/',
        queryParameters: {
          'query': query,
          'fmt': 'json',
          'inc': 'artist-credits+releases+media',
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
      rethrow;
    }
  }

  Future<ResolvedCover?> resolveCover(MusicBrainzTrackMatch match) async {
    if (match.resolvedCover != null) return match.resolvedCover;

    if (_hasMeaningfulText(match.releaseId)) {
      final resolved = ResolvedCover(
        endpoint: 'release',
        id: match.releaseId!,
        largeUrl:
            'https://coverartarchive.org/release/${match.releaseId}/front',
        thumbnailUrl:
            'https://coverartarchive.org/release/${match.releaseId}/front-250',
      );
      return resolved;
    }

    return null;
  }

  Future<_CoverArtResult?> _downloadCoverArt(
    MusicBrainzTrackMatch match, {
    MusicBrainzReleaseMatch? selectedRelease,
  }) async {
    final release =
        selectedRelease ??
        (match.releases.isNotEmpty ? match.releases.first : null);
    final releaseId = release?.id ?? '';
    final cacheKey = releaseId.isNotEmpty
        ? releaseId
        : match.releaseId ?? match.recordingId;
    if (_coverCache.containsKey(cacheKey)) {
      return _coverCache[cacheKey];
    }

    final resolved = release != null
        ? ResolvedCover(
            endpoint: 'release',
            id: release.id,
            largeUrl: release.largeUrl,
            thumbnailUrl: release.thumbnailUrl,
          )
        : await resolveCover(match);
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
        saveLarge: true,
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

String? _buildQuery({
  required String? title,
  required String? artist,
  required String? album,
  required int? durationMillis,
}) {
  final titleTerm = _hasMeaningfulText(title)
      ? _fieldTerm('recording', title!)
      : null;
  final artistTerm = _hasMeaningfulText(artist)
      ? _fieldTerm('artistname', artist!)
      : null;
  final albumTerm = _hasMeaningfulText(album)
      ? _fieldTerm('release', album!)
      : null;
  final durationTerm = durationMillis != null && durationMillis > 0
      ? _durationTerm(durationMillis)
      : null;

  final query = <String?>[
    titleTerm,
    artistTerm,
    albumTerm,
    durationTerm,
  ].whereType<String>().where((value) => value.isNotEmpty).join(' AND ');

  return query.isEmpty ? null : query;
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

String _normalizeReleaseGroupKey(String title) {
  final normalized = title.trim().toLowerCase();
  return normalized.isEmpty ? '__empty__' : normalized;
}
