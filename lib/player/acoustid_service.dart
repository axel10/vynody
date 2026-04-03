import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:audio_core/audio_core.dart';
import '../utils/network_client.dart';

class AcoustIDResult {
  final String recordingId;
  final String title;
  final String artist;
  final String? album;
  final int? durationMillis;
  final double score;
  final List<String> acoustIds;
  final Map<String, dynamic> raw;

  AcoustIDResult({
    required this.recordingId,
    required this.title,
    required this.artist,
    this.album,
    this.durationMillis,
    required this.score,
    required this.acoustIds,
    required this.raw,
  });

  factory AcoustIDResult.fromJson(Map<String, dynamic> json) {
    final recordings =
        (json['recordings'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();

    String title = '';
    String artist = '';
    String? album;
    int? durationMillis;
    final acoustIds = <String>[];

    for (final recording in recordings) {
      if (title.isEmpty) {
        title = recording['title'] as String? ?? '';
      }

      final artists =
          (recording['artists'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();
      if (artist.isEmpty && artists.isNotEmpty) {
        artist = artists.map((a) => a['name'] as String? ?? '').join(', ');
      }

      final releases =
          (recording['releases'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();
      if (album == null && releases.isNotEmpty) {
        album = releases.first['title'] as String?;
      }

      durationMillis ??= (recording['length'] as num?)?.toInt();

      final id = recording['id'] as String?;
      if (id != null && id.isNotEmpty) {
        acoustIds.add(id);
      }
    }

    return AcoustIDResult(
      recordingId: recordings.isNotEmpty
          ? (recordings.first['id'] as String? ?? '')
          : '',
      title: title,
      artist: artist.isEmpty ? 'Unknown Artist' : artist,
      album: album,
      durationMillis: durationMillis,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      acoustIds: acoustIds,
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
}

class AcoustIDService {
  AcoustIDService({required this.apiKey})
      : _client = NetworkClient(
          baseUrl: 'https://api.acoustid.org',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'User-Agent': 'VibeFlow/1.0 (Desktop Audio Player)',
          },
        );

  final String apiKey;
  final NetworkClient _client;

  Future<AcoustIDResult?> lookupByFingerprint({
    required String filePath,
    required int durationSeconds,
  }) async {
    String fingerprint;
    try {
      fingerprint = await getAudioFingerprint(path: filePath);
    } catch (e) {
      debugPrint('AcoustID: Failed to get fingerprint: $e');
      return null;
    }

    if (fingerprint.isEmpty) {
      debugPrint('AcoustID: Empty fingerprint');
      return null;
    }

    try {
      final response = await _client.get(
        '/v2/lookup',
        queryParameters: {
          'client': apiKey,
          'fingerprint': fingerprint,
          'duration': durationSeconds.toString(),
          'meta': 'recordings releasegroups',
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) return null;

      final status = data['status'] as String?;
      if (status != 'ok') {
        final error = data['error']?['message'] as String?;
        debugPrint('AcoustID API error: $error');
        return null;
      }

      final results =
          (data['results'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();

      if (results.isEmpty) return null;

      final best = results.first;
      return AcoustIDResult.fromJson(best);
    } catch (e) {
      debugPrint('AcoustID lookup failed: $e');
      return null;
    }
  }
}
