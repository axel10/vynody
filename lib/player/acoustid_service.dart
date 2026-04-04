import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:audio_core/audio_core.dart';
import '../utils/network_client.dart';
import 'metadata_database.dart';

class AcoustIDResult {
  final String recordingId;
  final String title;
  final String artist;
  final String? album;
  final String? releaseId;
  final int? durationMillis;
  final double score;
  final List<String> acoustIds;
  final Map<String, dynamic> raw;

  AcoustIDResult({
    required this.recordingId,
    required this.title,
    required this.artist,
    this.album,
    this.releaseId,
    this.durationMillis,
    required this.score,
    required this.acoustIds,
    required this.raw,
  });

  String? get thumbnailUrl {
    if (releaseId == null || releaseId!.isEmpty) return null;
    return 'https://coverartarchive.org/release/$releaseId/front-250';
  }

  factory AcoustIDResult.fromJson(Map<String, dynamic> json) {
    // Accept cached, already-flattened records.
    if (!json.containsKey('recordings')) {
      return AcoustIDResult(
        recordingId: json['recordingId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? 'Unknown Artist',
        album: json['album'] as String?,
        releaseId: json['releaseId'] as String?,
        durationMillis: (json['durationMillis'] as num?)?.toInt(),
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
        acoustIds: (json['acoustIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        raw: json['raw'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(json['raw'] as Map)
            : json,
      );
    }

    final results = AcoustIDResult.fromLookupResult(json);
    if (results.isEmpty) {
      return AcoustIDResult(
        recordingId: '',
        title: '',
        artist: 'Unknown Artist',
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
        acoustIds: const [],
        raw: json,
      );
    }

    return results.first;
  }

  static List<AcoustIDResult> fromLookupResult(Map<String, dynamic> json) {
    final recordings = (json['recordings'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    return recordings
        .map((recording) {
          final title = recording['title'] as String? ?? '';
          final artists = (recording['artists'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();
          final artist = artists
              .map((a) => a['name'] as String? ?? '')
              .join(', ');

          final releases = (recording['releases'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();
          final album = releases.isNotEmpty
              ? releases.first['title'] as String?
              : null;
          final releaseId = releases.isNotEmpty
              ? releases.first['id'] as String?
              : null;
          final recordingId = recording['id'] as String? ?? '';
          final durationMillis = (recording['length'] as num?)?.toInt();

          final acoustIds = <String>[];
          if (recordingId.isNotEmpty) {
            acoustIds.add(recordingId);
          }

          return AcoustIDResult(
            recordingId: recordingId,
            title: title,
            artist: artist.isEmpty ? 'Unknown Artist' : artist,
            album: album,
            releaseId: releaseId,
            durationMillis: durationMillis,
            score: (json['score'] as num?)?.toDouble() ?? 0.0,
            acoustIds: acoustIds,
            raw: {
              'lookupId': json['id'],
              'score': json['score'],
              'recording': recording,
            },
          );
        })
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() {
    return {
      'recordingId': recordingId,
      'title': title,
      'artist': artist,
      'album': album,
      'releaseId': releaseId,
      'durationMillis': durationMillis,
      'score': score,
      'acoustIds': acoustIds,
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
    : _client = NetworkClient(
        baseUrl: 'https://api.acoustid.org',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'User-Agent': 'VibeFlow/1.0 (Desktop Audio Player)'},
      ),
      _db = db ?? MetadataDatabase();

  final String apiKey;
  final NetworkClient _client;
  final MetadataDatabase _db;
  final Map<String, Future<List<AcoustIDResult>>> _inFlight = {};

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

    final existing = _inFlight[fingerprint];
    if (existing != null) {
      return existing;
    }

    final future =
        _lookupAndCache(
          fingerprint: fingerprint,
          durationSeconds: durationSeconds,
        ).whenComplete(() {
          _inFlight.remove(fingerprint);
        });
    _inFlight[fingerprint] = future;

    return future;
  }

  Future<List<AcoustIDResult>?> _loadFromDatabase(String fingerprint) async {
    try {
      final record = await _db.getAcoustIDCache(fingerprint);
      if (record == null) return null;

      final decoded = jsonDecode(record.resultsJson);
      if (decoded is! List) return const [];

      return decoded
          .whereType<Map>()
          .map(
            (item) => AcoustIDResult.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
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
        '/v2/lookup',
        queryParameters: {
          'client': apiKey,
          'fingerprint': fingerprint,
          'duration': durationSeconds.toString(),
          'meta': 'recordings releases',
        },
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
          .toList();

      final parsed = results
          .expand((e) => AcoustIDResult.fromLookupResult(e))
          .toList();
      await _saveToDatabase(
        fingerprint: fingerprint,
        durationSeconds: durationSeconds,
        results: parsed,
      );
      return parsed;
    } catch (e) {
      debugPrint('AcoustID lookup failed: $e');
      return const [];
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
