import 'dart:async';
import 'dart:convert';

import 'package:audio_core/audio_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:vynody/utils/query_url_utils.dart';
import 'package:vynody/utils/network_client.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

part 'acoustid_service.freezed.dart';

String acoustIDReleaseGroupThumbnailUrl(String releaseGroupId) =>
    'https://coverartarchive.org/release-group/$releaseGroupId/front-250';

String acoustIDReleaseGroupLargeUrl(String releaseGroupId) =>
    'https://coverartarchive.org/release-group/$releaseGroupId/front';

String acoustIDReleaseThumbnailUrl(String releaseId) =>
    'https://coverartarchive.org/release/$releaseId/front-250';

String acoustIDReleaseLargeUrl(String releaseId) =>
    'https://coverartarchive.org/release/$releaseId/front';

class AcoustIDClientException implements Exception {
  const AcoustIDClientException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => 'AcoustIDClientException($statusCode): $message';
}

@freezed
abstract class AcoustIDArtist with _$AcoustIDArtist {
  const AcoustIDArtist._();

  const factory AcoustIDArtist({required String id, required String name}) =
      _AcoustIDArtist;

  factory AcoustIDArtist.fromJson(Map<String, dynamic> json) {
    return AcoustIDArtist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name};
  }
}

@freezed
abstract class AcoustIDRelease with _$AcoustIDRelease {
  const AcoustIDRelease._();

  const factory AcoustIDRelease({
    required String id,
    required String title,
    String? country,
    String? dateLabel,
    int? trackCount,
    required Map<String, dynamic> raw,
  }) = _AcoustIDRelease;

  String get thumbnailUrl => acoustIDReleaseThumbnailUrl(id);

  String get largeUrl => acoustIDReleaseLargeUrl(id);

  factory AcoustIDRelease.fromJson(Map<String, dynamic> json) {
    return AcoustIDRelease(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      country: json['country'] as String?,
      dateLabel: _formatDateLabel(json['date'] ?? json['dateLabel']),
      trackCount:
          (json['track_count'] as num?)?.toInt() ??
          (json['trackCount'] as num?)?.toInt(),
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'country': country,
      'dateLabel': dateLabel,
      'trackCount': trackCount,
      'raw': raw,
    };
  }
}

@freezed
abstract class AcoustIDReleaseGroup with _$AcoustIDReleaseGroup {
  const AcoustIDReleaseGroup._();

  const factory AcoustIDReleaseGroup({
    required String id,
    required String title,
    String? type,
    @Default(<String>[]) List<String> secondaryTypes,
    @Default(<AcoustIDRelease>[]) List<AcoustIDRelease> releases,
    required Map<String, dynamic> raw,
  }) = _AcoustIDReleaseGroup;

  String get thumbnailUrl => acoustIDReleaseGroupThumbnailUrl(id);

  String get largeUrl => acoustIDReleaseGroupLargeUrl(id);

  factory AcoustIDReleaseGroup.fromJson(Map<String, dynamic> json) {
    final releases =
        (json['releases'] as List<dynamic>? ??
                json['releasesJson'] as List<dynamic>? ??
                const [])
            .whereType<Map<String, dynamic>>()
            .map(AcoustIDRelease.fromJson)
            .toList(growable: false);

    return AcoustIDReleaseGroup(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String?,
      secondaryTypes:
          (json['secondarytypes'] as List<dynamic>? ??
                  json['secondaryTypes'] as List<dynamic>? ??
                  const [])
              .cast<dynamic>()
              .map((item) => item?.toString() ?? '')
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
      releases: releases,
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'secondaryTypes': secondaryTypes,
      'releases': releases.map((item) => item.toJson()).toList(),
      'raw': raw,
    };
  }
}

@freezed
abstract class AcoustIDRecording with _$AcoustIDRecording {
  const AcoustIDRecording._();

  const factory AcoustIDRecording({
    required String id,
    required String title,
    required String artist,
    int? durationMillis,
    @Default(<AcoustIDReleaseGroup>[]) List<AcoustIDReleaseGroup> releaseGroups,
    required Map<String, dynamic> raw,
  }) = _AcoustIDRecording;

  factory AcoustIDRecording.fromJson(Map<String, dynamic> json) {
    final artistEntries =
        (json['artists'] as List<dynamic>? ??
                json['artistEntries'] as List<dynamic>? ??
                const [])
            .whereType<Map<String, dynamic>>()
            .map(AcoustIDArtist.fromJson)
            .toList(growable: false);
    final artistName = _joinArtistNames(artistEntries);
    final rawArtist = json['artist'];
    final cachedArtist = rawArtist is String ? rawArtist.trim() : '';

    final releaseGroups =
        (json['releasegroups'] as List<dynamic>? ??
                json['releaseGroups'] as List<dynamic>? ??
                const [])
            .whereType<Map<String, dynamic>>()
            .map(AcoustIDReleaseGroup.fromJson)
            .toList(growable: false);

    return AcoustIDRecording(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: cachedArtist.isNotEmpty ? cachedArtist : artistName,
      durationMillis: _durationFromJson(json),
      releaseGroups: releaseGroups,
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'artists':
          raw['artists'] ??
          (artist.isNotEmpty
              ? [
                  {'name': artist},
                ]
              : const []),
      'duration': durationMillis == null ? null : durationMillis! / 1000.0,
      'length': durationMillis,
      'durationMillis': durationMillis,
      'releasegroups': releaseGroups.map((item) => item.toJson()).toList(),
      'releaseGroups': releaseGroups.map((item) => item.toJson()).toList(),
      'raw': raw,
    };
  }

  String get durationLabel {
    final ms = durationMillis;
    if (ms == null || ms <= 0) return '--:--';
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

@freezed
abstract class AcoustIDResult with _$AcoustIDResult {
  const AcoustIDResult._();

  const factory AcoustIDResult({
    required String id,
    required double score,
    @Default(<AcoustIDRecording>[]) List<AcoustIDRecording> recordings,
    required Map<String, dynamic> raw,
  }) = _AcoustIDResult;

  bool get hasRecordings => recordings.isNotEmpty;

  AcoustIDRecording? get primaryRecording =>
      recordings.isNotEmpty ? recordings.first : null;

  String get title => primaryRecording?.title ?? '';

  String get artist => primaryRecording?.artist ?? 'Unknown Artist';

  String? get album {
    final recording = primaryRecording;
    if (recording == null || recording.releaseGroups.isEmpty) return null;
    return recording.releaseGroups.first.title;
  }

  int? get durationMillis => primaryRecording?.durationMillis;

  String? get thumbnailUrl {
    for (final recording in recordings) {
      for (final releaseGroup in recording.releaseGroups) {
        if (releaseGroup.thumbnailUrl.isNotEmpty) {
          return releaseGroup.thumbnailUrl;
        }
        for (final release in releaseGroup.releases) {
          if (release.thumbnailUrl.isNotEmpty) {
            return release.thumbnailUrl;
          }
        }
      }
    }
    return null;
  }

  String? get largeUrl {
    for (final recording in recordings) {
      for (final releaseGroup in recording.releaseGroups) {
        if (releaseGroup.largeUrl.isNotEmpty) {
          return releaseGroup.largeUrl;
        }
        for (final release in releaseGroup.releases) {
          if (release.largeUrl.isNotEmpty) {
            return release.largeUrl;
          }
        }
      }
    }
    return null;
  }

  factory AcoustIDResult.fromJson(Map<String, dynamic> json) {
    final recordings = (json['recordings'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AcoustIDRecording.fromJson)
        .toList(growable: false);

    return AcoustIDResult(
      id: json['id'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      recordings: recordings,
      raw: _asMap(json['raw']) ?? Map<String, dynamic>.from(json),
    );
  }

  factory AcoustIDResult.fromLookupResult(
    Map<String, dynamic> json, {
    double fallbackScore = 0.0,
  }) {
    final recordings = (json['recordings'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AcoustIDRecording.fromJson)
        .where((recording) => recording.id.isNotEmpty)
        .toList(growable: false);

    if (recordings.isEmpty) {
      return AcoustIDResult(
        id: json['id'] as String? ?? '',
        score: (json['score'] as num?)?.toDouble() ?? fallbackScore,
        recordings: const [],
        raw: Map<String, dynamic>.from(json),
      );
    }

    return AcoustIDResult(
      id: json['id'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? fallbackScore,
      recordings: recordings,
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'score': score,
      'recordings': recordings.map((item) => item.toJson()).toList(),
      'raw': raw,
    };
  }

  String get durationLabel {
    final ms = durationMillis;
    if (ms == null || ms <= 0) return '--:--';
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class AcoustIDService {
  AcoustIDService({required this.apiKey, MetadataDatabase? db})
    : _client = NetworkClient.instance,
      _db = db ?? MetadataDatabase();

  final String apiKey;
  final NetworkClient _client;
  final MetadataDatabase _db;
  final Map<String, Future<List<AcoustIDResult>>> _fingerprintInFlight = {};
  final Map<String, Future<AcoustIDResult?>> _trackLookupInFlight = {};

  Future<List<AcoustIDResult>> lookupByFingerprint({
    required String filePath,
    required int durationSeconds,
  }) async {
    String fingerprint;
    try {
      fingerprint = await getAudioFingerprint(path: filePath);
    } catch (e) {
      debugPrint('AcoustID: Failed to get fingerprint: $e');
      return const [];
    }

    if (fingerprint.isEmpty) {
      debugPrint('AcoustID: Empty fingerprint');
      return const [];
    }

    final cached = await _loadFromDatabase(fingerprint);
    if (cached != null) {
      debugPrint('AcoustID: Cache hit for fingerprint $fingerprint');
      return cached;
    }

    final existing = _fingerprintInFlight[fingerprint];
    if (existing != null) {
      return existing;
    }

    final future =
        _lookupAndCache(
          fingerprint: fingerprint,
          durationSeconds: durationSeconds,
        ).whenComplete(() {
          _fingerprintInFlight.remove(fingerprint);
        });
    _fingerprintInFlight[fingerprint] = future;

    return future;
  }

  Future<Uint8List?> downloadCoverBytes({
    required List<String?> candidateUrls,
  }) async {
    for (final url in candidateUrls) {
      if (!_hasMeaningfulText(url)) continue;
      try {
        final response = await _client.get<List<int>>(
          url!,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Accept': 'image/jpeg, image/png, image/*, */*'},
          ),
        );
        final data = response.data;
        if (data != null && data.isNotEmpty) {
          return Uint8List.fromList(data);
        }
      } catch (e) {
        debugPrint('AcoustID: Cover download failed for $url: $e');
      }
    }
    return null;
  }

  bool _hasMeaningfulText(String? value) {
    if (value == null) return false;
    return value.trim().isNotEmpty;
  }

  Future<List<AcoustIDResult>?> _loadFromDatabase(String fingerprint) async {
    try {
      final record = await _db.getAcoustIDCache(fingerprint);
      if (record == null) return null;

      final decoded = jsonDecode(record.resultsJson);
      if (decoded is! List) return const [];

      final results = decoded
          .whereType<Map>()
          .map(
            (item) => AcoustIDResult.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.hasRecordings)
          .toList(growable: false);

      if (results.isEmpty) {
        debugPrint(
          'AcoustID: Cached fingerprint $fingerprint has no valid recordings, treating as cache miss.',
        );
        return null;
      }

      return results;
    } catch (e) {
      debugPrint(
        'AcoustID: Failed to load cache for fingerprint $fingerprint: $e',
      );
      return null;
    }
  }

  Future<List<AcoustIDResult>> _lookupAndCache({
    required String fingerprint,
    required int durationSeconds,
  }) async {
    try {
      final response = await _client.get(
        QueryUrlUtils.buildUrl(
          'https://api.acoustid.org/v2/lookup',
          queryParameters: {
            'client': apiKey,
            'fingerprint': fingerprint,
            'duration': durationSeconds.toString(),
          },
        ),
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];

      final status = data['status'] as String?;
      if (status != 'ok') {
        final error = data['error']?['message'] as String?;
        debugPrint('AcoustID API error: $error');
        return const [];
      }

      final results = (data['results'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      if (results.isEmpty) return const [];

      final detailedResults = <AcoustIDResult>[];
      for (final seed in results) {
        final trackId = seed['id'] as String? ?? '';
        if (trackId.isEmpty) continue;

        final result = await _lookupTrackDetails(
          trackId: trackId,
          fallbackScore: (seed['score'] as num?)?.toDouble() ?? 0.0,
        );
        if (result != null && result.hasRecordings) {
          detailedResults.add(result);
        }
      }

      if (detailedResults.isEmpty) {
        debugPrint(
          'AcoustID: fingerprint $fingerprint returned ${results.length} seed results, but none had recordings after track lookup.',
        );
        return const [];
      }

      await _saveToDatabase(
        fingerprint: fingerprint,
        durationSeconds: durationSeconds,
        results: detailedResults,
      );
      return detailedResults;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode != null && statusCode >= 400 && statusCode < 500) {
        throw AcoustIDClientException(
          statusCode: statusCode,
          message: _extractErrorMessage(e),
        );
      }
      debugPrint('AcoustID lookup failed: $e');
      return const [];
    } on AcoustIDClientException {
      rethrow;
    } catch (e) {
      debugPrint('AcoustID lookup failed: $e');
      return const [];
    }
  }

  Future<AcoustIDResult?> _lookupTrackDetails({
    required String trackId,
    required double fallbackScore,
  }) async {
    final existing = _trackLookupInFlight[trackId];
    if (existing != null) {
      return existing;
    }

    final future =
        _fetchTrackDetails(
          trackId: trackId,
          fallbackScore: fallbackScore,
        ).whenComplete(() {
          _trackLookupInFlight.remove(trackId);
        });
    _trackLookupInFlight[trackId] = future;

    return future;
  }

  Future<AcoustIDResult?> _fetchTrackDetails({
    required String trackId,
    required double fallbackScore,
  }) async {
    try {
      final response = await _client.get(
        QueryUrlUtils.buildUrl(
          'https://api.acoustid.org/v2/lookup',
          queryParameters: {'client': apiKey, 'trackid': trackId},
          rawQueryParameters: {'meta': 'recordings+releasegroups+releases'},
        ),
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) return null;

      final status = data['status'] as String?;
      if (status != 'ok') {
        final error = data['error']?['message'] as String?;
        debugPrint('AcoustID track lookup error for $trackId: $error');
        return null;
      }

      final results = (data['results'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      if (results.isEmpty) return null;

      Map<String, dynamic>? selected;
      for (final candidate in results) {
        final recordings = candidate['recordings'];
        if (recordings is List && recordings.isNotEmpty) {
          selected = candidate;
          break;
        }
      }
      selected ??= results.firstWhere(
        (candidate) =>
            (candidate['recordings'] as List<dynamic>? ?? const []).isNotEmpty,
        orElse: () => <String, dynamic>{},
      );

      if (selected.isEmpty) return null;

      final result = AcoustIDResult.fromLookupResult(
        selected,
        fallbackScore: fallbackScore,
      );
      return result.hasRecordings ? result : null;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode != null && statusCode >= 400 && statusCode < 500) {
        throw AcoustIDClientException(
          statusCode: statusCode,
          message: _extractErrorMessage(e),
        );
      }
      debugPrint('AcoustID track lookup failed for $trackId: $e');
      return null;
    } catch (e) {
      debugPrint('AcoustID track lookup failed for $trackId: $e');
      return null;
    }
  }

  Future<void> _saveToDatabase({
    required String fingerprint,
    required int durationSeconds,
    required List<AcoustIDResult> results,
  }) async {
    try {
      final record = AcoustIDCacheRecord(
        fingerprint: fingerprint,
        durationSeconds: durationSeconds,
        resultsJson: jsonEncode(
          results.map((result) => result.toJson()).toList(),
        ),
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await _db.insertOrUpdateAcoustIDCache(record);
    } catch (e) {
      debugPrint(
        'AcoustID: Failed to cache results for fingerprint $fingerprint: $e',
      );
    }
  }
}

String _joinArtistNames(List<AcoustIDArtist> artists) {
  final names = artists
      .map((artist) => artist.name.trim())
      .where((name) => name.isNotEmpty)
      .toList(growable: false);
  if (names.isEmpty) return 'Unknown Artist';
  return names.join(', ');
}

String? _formatDateLabel(dynamic value) {
  if (value == null) return null;

  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final year = map['year'];
    final month = map['month'];
    final day = map['day'];
    if (year == null && month == null && day == null) return null;

    final parts = <String>[];
    if (year != null) parts.add(year.toString());
    if (month != null) parts.add(month.toString().padLeft(2, '0'));
    if (day != null) parts.add(day.toString().padLeft(2, '0'));
    return parts.join('-');
  }

  return value.toString();
}

int? _durationFromJson(Map<String, dynamic> json) {
  final duration = json['duration'];
  if (duration is num) {
    return (duration * 1000).round();
  }

  final length = json['length'];
  if (length is num) {
    return length.round();
  }

  final durationMillis = json['durationMillis'];
  if (durationMillis is num) {
    return durationMillis.round();
  }

  return null;
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String _extractErrorMessage(DioException error) {
  final response = error.response;
  final responseData = response?.data;
  if (responseData is Map) {
    final errorMap = responseData['error'];
    if (errorMap is Map) {
      final message = errorMap['message']?.toString().trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }
  }

  final message = error.message?.trim();
  if (message != null && message.isNotEmpty) {
    return message;
  }

  return PlatformDispatcher.instance.locale.languageCode == 'zh'
      ? 'AcoustID 请求失败'
      : 'AcoustID request failed';
}
