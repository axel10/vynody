import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../utils/network_client.dart';
import 'metadata_database.dart';

class LyricsQuery {
  final String filePath;
  final String fileName;
  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;

  const LyricsQuery({
    required this.filePath,
    required this.fileName,
    required this.title,
    this.artist,
    this.album,
    this.duration,
  });

  String get cacheKey {
    final parts = <String>[
      _normalizeForKey(filePath),
      _normalizeForKey(title),
      _normalizeForKey(artist),
      _normalizeForKey(album),
      duration?.inSeconds.toString() ?? '',
    ];
    return parts.join('|');
  }
}

class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({required this.timestamp, required this.text});

  Map<String, dynamic> toJson() {
    return {'timestampMs': timestamp.inMilliseconds, 'text': text};
  }

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      timestamp: Duration(milliseconds: (json['timestampMs'] as num).round()),
      text: json['text'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LyricLine &&
            timestamp == other.timestamp &&
            text == other.text;
  }

  @override
  int get hashCode => Object.hash(timestamp, text);
}

class LyricTrack {
  final int? id;
  final String? name;
  final String? trackName;
  final String? artistName;
  final String? albumName;
  final double? duration;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;

  const LyricTrack({
    this.id,
    this.name,
    this.trackName,
    this.artistName,
    this.albumName,
    this.duration,
    required this.instrumental,
    this.plainLyrics,
    this.syncedLyrics,
  });

  factory LyricTrack.fromJson(Map<String, dynamic> json) {
    return LyricTrack(
      id: json['id'] as int?,
      name: json['name'] as String?,
      trackName: json['trackName'] as String?,
      artistName: json['artistName'] as String?,
      albumName: json['albumName'] as String?,
      duration: (json['duration'] as num?)?.toDouble(),
      instrumental: json['instrumental'] as bool? ?? false,
      plainLyrics: json['plainLyrics'] as String?,
      syncedLyrics: json['syncedLyrics'] as String?,
    );
  }

  String get displayTitle => (trackName?.trim().isNotEmpty ?? false)
      ? trackName!.trim()
      : (name?.trim().isNotEmpty ?? false ? name!.trim() : '');

  bool get hasLyrics =>
      (plainLyrics?.trim().isNotEmpty ?? false) ||
      (syncedLyrics?.trim().isNotEmpty ?? false);

  bool get hasSyncedLyrics => syncedLyrics?.trim().isNotEmpty ?? false;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'trackName': trackName,
      'artistName': artistName,
      'albumName': albumName,
      'duration': duration,
      'instrumental': instrumental,
      'plainLyrics': plainLyrics,
      'syncedLyrics': syncedLyrics,
    };
  }
}

class LyricScoreBreakdown {
  final double title;
  final double artist;
  final double album;
  final double duration;
  final double lyricsQuality;
  final double instrumentalPenalty;

  const LyricScoreBreakdown({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.lyricsQuality,
    required this.instrumentalPenalty,
  });

  double get total =>
      title + artist + album + duration + lyricsQuality + instrumentalPenalty;
}

class LyricSelectionResult {
  final LyricTrack track;
  final bool fromGetApi;
  final double score;
  final LyricScoreBreakdown breakdown;
  final int durationDiffSeconds;
  final List<LyricLine> syncedLines;
  final String lyricsText;

  const LyricSelectionResult({
    required this.track,
    required this.fromGetApi,
    required this.score,
    required this.breakdown,
    required this.durationDiffSeconds,
    required this.syncedLines,
    required this.lyricsText,
  });

  bool get isSynced => syncedLines.isNotEmpty;
}

class LyricsService {
  LyricsService({NetworkClient? client, MetadataDatabase? db})
    : _client =
          client ??
          NetworkClient(
            baseUrl: 'https://lrclib.net/api',
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 12),
            sendTimeout: const Duration(seconds: 12),
          ),
      _db = db ?? MetadataDatabase();

  final NetworkClient _client;
  final MetadataDatabase _db;
  final Map<String, Future<LyricSelectionResult?>> _inFlight = {};
  final Map<String, LyricSelectionResult?> _cache = {};

  static const double _acceptThreshold = 65.0;

  Future<LyricSelectionResult?> fetchBestLyrics({
    required LyricsQuery query,
    bool debugLog = false,
  }) async {
    final cacheKey = query.cacheKey;
    final cached = _cache[cacheKey];
    if (_cache.containsKey(cacheKey)) {
      if (debugLog) {
        debugPrintSelection(query, cached, source: 'cache');
      }
      return cached;
    }

    final cachedFromDb = await _loadFromDatabase(cacheKey);
    if (cachedFromDb != null) {
      _cache[cacheKey] = cachedFromDb;
      if (debugLog) {
        debugPrintSelection(query, cachedFromDb, source: 'sqlite');
      }
      return cachedFromDb;
    }

    final existing = _inFlight[cacheKey];
    if (existing != null) {
      final result = await existing;
      if (debugLog) {
        debugPrintSelection(query, result, source: 'in-flight');
      }
      return result;
    }

    final future = _fetchBestLyricsInternal(query).whenComplete(() {
      _inFlight.remove(cacheKey);
    });
    _inFlight[cacheKey] = future;

    final result = await future;
    _cache[cacheKey] = result;

    if (debugLog) {
      debugPrintSelection(query, result);
    }

    return result;
  }

  Future<LyricSelectionResult?> _fetchBestLyricsInternal(
    LyricsQuery query,
  ) async {
    final completeQuery = _buildCompleteQuery(query);
    if (completeQuery != null) {
      final direct = await _fetchGet(completeQuery);
      if (direct != null) {
        final scored = _scoreCandidate(completeQuery, direct, fromGetApi: true);
        if (scored != null && scored.score >= _acceptThreshold) {
          await _saveToDatabase(query: completeQuery, result: scored);
          return scored;
        }
      }
    }

    final searchQuery = _buildSearchQuery(query);
    final searchResults = await _search(searchQuery);
    if (searchResults.isEmpty) {
      return null;
    }

    final scoredResults = <LyricSelectionResult>[];
    for (final candidate in searchResults) {
      final scored = _scoreCandidate(searchQuery, candidate, fromGetApi: false);
      if (scored != null) {
        scoredResults.add(scored);
      }
    }

    if (scoredResults.isEmpty) {
      return null;
    }

    scoredResults.sort(_compareSelectionResults);
    var bestCandidate = scoredResults.first;

    if (bestCandidate.score < _acceptThreshold) {
      // 检查是否有时间极其接近的（3秒内）作为兜底
      final fallbackCandidates =
          scoredResults.where((r) => r.durationDiffSeconds <= 3).toList();

      if (fallbackCandidates.isNotEmpty) {
        // 在3秒以内的候选中，优先选择时长差距最小的
        // 如果时长差距相同，则取评分较高的
        fallbackCandidates.sort((a, b) {
          final diffCompare = a.durationDiffSeconds.compareTo(
            b.durationDiffSeconds,
          );
          if (diffCompare != 0) return diffCompare;
          return b.score.compareTo(a.score);
        });
        bestCandidate = fallbackCandidates.first;
      } else {
        return null;
      }
    }

    await _saveToDatabase(query: searchQuery, result: bestCandidate);
    return bestCandidate;
  }

  Future<LyricSelectionResult?> _loadFromDatabase(String cacheKey) async {
    try {
      final record = await _db.getLyricsCache(cacheKey);
      if (record == null) return null;
      return _selectionFromRecord(record);
    } catch (e) {
      debugPrint('[Lyrics] Failed to load cache for "$cacheKey": $e');
      return null;
    }
  }

  LyricsQuery? _buildCompleteQuery(LyricsQuery query) {
    final title = _cleanField(query.title);
    final artist = _cleanField(query.artist);
    final album = _cleanField(query.album);
    final duration = query.duration?.inSeconds;
    if (title == null ||
        artist == null ||
        album == null ||
        duration == null ||
        duration <= 0) {
      return null;
    }
    return LyricsQuery(
      filePath: query.filePath,
      fileName: query.fileName,
      title: title,
      artist: artist,
      album: album,
      duration: Duration(seconds: duration),
    );
  }

  LyricsQuery _buildSearchQuery(LyricsQuery query) {
    final rawFallback = p.basenameWithoutExtension(query.fileName).trim();
    final fallbackTitle = _removeBrackets(rawFallback);
    final title = _cleanField(query.title) ?? fallbackTitle;
    return LyricsQuery(
      filePath: query.filePath,
      fileName: query.fileName,
      title: title,
      artist: _cleanField(query.artist),
      album: _cleanField(query.album),
      duration: query.duration,
    );
  }

  Future<LyricTrack?> _fetchGet(LyricsQuery query) async {
    try {
      final response = await _client.get(
        '/get',
        queryParameters: {
          'track_name': query.title,
          'artist_name': query.artist,
          'album_name': query.album,
          'duration': query.duration?.inSeconds,
        }..removeWhere((_, value) => value == null),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        final track = LyricTrack.fromJson(data);
        return track.hasLyrics ? track : null;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        debugPrint('[Lyrics] GET failed for "${query.title}": ${e.message}');
      }
    } catch (e) {
      debugPrint('[Lyrics] GET error for "${query.title}": $e');
    }
    return null;
  }

  Future<List<LyricTrack>> _search(LyricsQuery query) async {
    try {
      final params =
          <String, dynamic>{
            'track_name': query.title,
            'artist_name': query.artist,
            'album_name': query.album,
            'q': _buildSearchText(query),
          }..removeWhere(
            (_, value) =>
                value == null || (value is String && value.trim().isEmpty),
          );

      final response = await _client.get('/search', queryParameters: params);

      final data = response.data;
      if (data is List) {
        return data
            .whereType<Map>()
            .map((item) => LyricTrack.fromJson(Map<String, dynamic>.from(item)))
            .where((track) => track.hasLyrics)
            .toList();
      }
    } on DioException catch (e) {
      debugPrint('[Lyrics] SEARCH failed for "${query.title}": ${e.message}');
    } catch (e) {
      debugPrint('[Lyrics] SEARCH error for "${query.title}": $e');
    }
    return const [];
  }

  Future<void> _saveToDatabase({
    required LyricsQuery query,
    required LyricSelectionResult result,
  }) async {
    try {
      final record = LyricsCacheRecord(
        cacheKey: query.cacheKey,
        filePath: query.filePath,
        title: query.title,
        artist: query.artist,
        album: query.album,
        duration: query.duration?.inSeconds,
        source: result.fromGetApi ? 'get' : 'search',
        trackId: result.track.id,
        score: result.score,
        isSynced: result.isSynced,
        instrumental: result.track.instrumental,
        plainLyrics: result.track.plainLyrics,
        syncedLyrics: result.track.syncedLyrics,
        syncedLines: result.syncedLines.map((line) => line.toJson()).toList(),
        rawJson: result.track.toJson(),
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await _db.insertOrUpdateLyricsCache(record);
    } catch (e) {
      debugPrint('[Lyrics] Failed to cache lyrics for "${query.title}": $e');
    }
  }

  LyricSelectionResult _selectionFromRecord(LyricsCacheRecord record) {
    final track = LyricTrack(
      id: record.trackId,
      name: record.title,
      trackName: record.title,
      artistName: record.artist,
      albumName: record.album,
      duration: record.duration?.toDouble(),
      instrumental: record.instrumental,
      plainLyrics: record.plainLyrics,
      syncedLyrics: record.syncedLyrics,
    );

    final syncedLines = record.syncedLines
        .map((item) => LyricLine.fromJson(item))
        .toList(growable: false);

    return LyricSelectionResult(
      track: track,
      fromGetApi: record.source == 'get',
      score: record.score,
      breakdown: LyricScoreBreakdown(
        title: 0,
        artist: 0,
        album: 0,
        duration: 0,
        lyricsQuality: record.isSynced ? 5 : 3,
        instrumentalPenalty: 0,
      ),
      durationDiffSeconds: record.duration == null ? (1 << 30) : 0,
      syncedLines: syncedLines,
      lyricsText: record.isSynced
          ? (record.syncedLyrics ?? '')
          : (record.plainLyrics ?? ''),
    );
  }

  String _buildSearchText(LyricsQuery query) {
    final parts = <String>[
      query.title,
      if (query.artist != null && query.artist!.trim().isNotEmpty)
        query.artist!,
      if (query.album != null && query.album!.trim().isNotEmpty) query.album!,
    ];
    return parts.join(' ').trim();
  }

  LyricSelectionResult? _scoreCandidate(
    LyricsQuery query,
    LyricTrack candidate, {
    required bool fromGetApi,
  }) {
    if (!candidate.hasLyrics) {
      return null;
    }

    final queryTitle = _normalizeTitle(query.title);
    final candidateTitle = _normalizeTitle(candidate.displayTitle);
    final queryArtist = _normalizeText(query.artist);
    final candidateArtist = _normalizeText(candidate.artistName);
    final queryAlbum = _normalizeText(query.album);
    final candidateAlbum = _normalizeText(candidate.albumName);
    final durationSeconds = query.duration?.inSeconds;
    final candidateDuration = candidate.duration?.round();
    final durationDiffSeconds =
        durationSeconds == null || candidateDuration == null
        ? (1 << 30)
        : (durationSeconds - candidateDuration).abs();

    final titleScore = _similarity(queryTitle, candidateTitle);
    final artistScore = _similarity(queryArtist, candidateArtist);
    final albumScore = _similarity(queryAlbum, candidateAlbum);
    final durationScore = _durationScore(durationSeconds, candidateDuration);
    final lyricsQualityScore = candidate.hasSyncedLyrics ? 1.0 : 0.65;
    final instrumentalPenalty =
        candidate.instrumental &&
            !candidate.hasSyncedLyrics &&
            candidate.plainLyrics == null
        ? -20.0
        : candidate.instrumental
        ? -8.0
        : 0.0;

    if (!fromGetApi) {
      final obviousMismatch =
          (titleScore < 0.18 && artistScore < 0.18) ||
          (durationSeconds != null &&
              candidateDuration != null &&
              (durationSeconds - candidateDuration).abs() > 8);
      if (obviousMismatch) {
        return null;
      }
    }

    final weighted = <double>[];
    final weights = <double>[];

    void addWeighted(double weight, double? score) {
      if (score == null) return;
      weights.add(weight);
      weighted.add(weight * score);
    }

    addWeighted(45.0, queryTitle.isEmpty ? null : titleScore);
    addWeighted(25.0, queryArtist.isEmpty ? null : artistScore);
    addWeighted(15.0, queryAlbum.isEmpty ? null : albumScore);
    addWeighted(10.0, durationSeconds == null ? null : durationScore);
    addWeighted(5.0, lyricsQualityScore);

    final totalWeight = weights.fold<double>(0, (sum, value) => sum + value);
    if (totalWeight <= 0) {
      return null;
    }

    var total = weighted.fold<double>(0, (sum, value) => sum + value);
    total = (total / totalWeight) * 100.0;
    total += instrumentalPenalty;
    total = total.clamp(0.0, 100.0);

    final syncedLines = _parseSyncedLyrics(candidate.syncedLyrics);
    final lyricsText = candidate.hasSyncedLyrics
        ? candidate.syncedLyrics!.trim()
        : candidate.plainLyrics!.trim();

    return LyricSelectionResult(
      track: candidate,
      fromGetApi: fromGetApi,
      score: total,
      breakdown: LyricScoreBreakdown(
        title: titleScore * 45.0,
        artist: artistScore * 25.0,
        album: albumScore * 15.0,
        duration: durationScore * 10.0,
        lyricsQuality: lyricsQualityScore * 5.0,
        instrumentalPenalty: instrumentalPenalty,
      ),
      durationDiffSeconds: durationDiffSeconds,
      syncedLines: syncedLines,
      lyricsText: lyricsText,
    );
  }

  int _compareSelectionResults(LyricSelectionResult a, LyricSelectionResult b) {
    final scoreDiff = b.score.compareTo(a.score);
    if (scoreDiff != 0) return scoreDiff;

    if (a.isSynced != b.isSynced) {
      return b.isSynced ? 1 : -1;
    }

    final durationDiff = a.durationDiffSeconds.compareTo(b.durationDiffSeconds);
    if (durationDiff != 0) return durationDiff;

    final titleScoreDiff = b.breakdown.title.compareTo(a.breakdown.title);
    if (titleScoreDiff != 0) return titleScoreDiff;

    final artistScoreDiff = b.breakdown.artist.compareTo(a.breakdown.artist);
    if (artistScoreDiff != 0) return artistScoreDiff;

    return 0;
  }

  double _durationScore(int? querySeconds, int? candidateSeconds) {
    if (querySeconds == null || querySeconds <= 0) {
      return 0.75;
    }
    if (candidateSeconds == null || candidateSeconds <= 0) {
      return 0.55;
    }

    final diff = (querySeconds - candidateSeconds).abs();
    if (diff <= 2) return 1.0;
    if (diff <= 5) return 0.8;
    if (diff <= 8) return 0.45;
    return 0.0;
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) {
      return 0.0;
    }
    if (a == b) {
      return 1.0;
    }

    final levenshtein = _levenshteinSimilarity(a, b);
    final token = _tokenSimilarity(a, b);
    final prefixBonus = (a.startsWith(b) || b.startsWith(a)) ? 0.05 : 0.0;
    return (levenshtein * 0.65 + token * 0.35 + prefixBonus).clamp(0.0, 1.0);
  }

  double _levenshteinSimilarity(String a, String b) {
    final maxLen = math.max(a.length, b.length);
    if (maxLen == 0) return 1.0;
    final distance = _levenshteinDistance(a, b);
    return (1.0 - (distance / maxLen)).clamp(0.0, 1.0);
  }

  int _levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = math.min(
          math.min(curr[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + cost,
        );
      }
      for (var j = 0; j <= b.length; j++) {
        prev[j] = curr[j];
      }
    }

    return prev[b.length];
  }

  double _tokenSimilarity(String a, String b) {
    final tokensA = a.split(' ').where((token) => token.isNotEmpty).toSet();
    final tokensB = b.split(' ').where((token) => token.isNotEmpty).toSet();
    if (tokensA.isEmpty || tokensB.isEmpty) {
      return 0.0;
    }
    final intersection = tokensA.intersection(tokensB).length.toDouble();
    final union = tokensA.union(tokensB).length.toDouble();
    if (union == 0) {
      return 0.0;
    }
    return (intersection / union).clamp(0.0, 1.0);
  }

  List<LyricLine> _parseSyncedLyrics(String? syncedLyrics) {
    if (syncedLyrics == null || syncedLyrics.trim().isEmpty) {
      return const [];
    }

    final lines = <LyricLine>[];
    for (final rawLine in syncedLyrics.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final timestamps = <Duration>[];
      var index = 0;
      while (index < line.length) {
        final end = line.indexOf(']', index);
        if (index >= line.length || line[index] != '[' || end == -1) {
          break;
        }
        final token = line.substring(index + 1, end);
        final parsed = _parseTimestampToken(token);
        if (parsed == null) {
          break;
        }
        timestamps.add(parsed);
        index = end + 1;
      }

      final text = line.substring(index).trim();
      if (timestamps.isEmpty || text.isEmpty) {
        continue;
      }

      for (final timestamp in timestamps) {
        lines.add(LyricLine(timestamp: timestamp, text: text));
      }
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  Duration? _parseTimestampToken(String token) {
    final match = RegExp(
      r'^(\d{2}):(\d{2})(?:\.(\d{1,3}))?$',
    ).firstMatch(token);
    if (match == null) return null;

    final minutes = int.tryParse(match.group(1)!);
    final seconds = int.tryParse(match.group(2)!);
    final fractionText = match.group(3) ?? '0';
    if (minutes == null || seconds == null) return null;

    final fraction = int.tryParse(
      fractionText.padRight(3, '0').substring(0, 3),
    );
    if (fraction == null) return null;

    return Duration(minutes: minutes, seconds: seconds, milliseconds: fraction);
  }

  void debugPrintSelection(
    LyricsQuery query,
    LyricSelectionResult? result, {
    String? source,
  }) {
    final buffer = StringBuffer()
      ..writeln('[Lyrics] ${source ?? 'fetch'} ${query.fileName}')
      ..writeln(
        '[Lyrics] query title="${query.title}" artist="${query.artist ?? ''}" album="${query.album ?? ''}" duration="${query.duration?.inSeconds ?? 'n/a'}s"',
      );

    if (result == null) {
      buffer.writeln('[Lyrics] no reliable lyrics found');
      debugPrint(buffer.toString());
      return;
    }

    buffer.writeln(
      '[Lyrics] selected id=${result.track.id ?? 'n/a'} score=${result.score.toStringAsFixed(1)} from=${result.fromGetApi ? 'get' : 'search'} synced=${result.isSynced} instrumental=${result.track.instrumental}',
    );
    buffer.writeln(
      '[Lyrics] breakdown title=${result.breakdown.title.toStringAsFixed(1)} artist=${result.breakdown.artist.toStringAsFixed(1)} album=${result.breakdown.album.toStringAsFixed(1)} duration=${result.breakdown.duration.toStringAsFixed(1)} lyrics=${result.breakdown.lyricsQuality.toStringAsFixed(1)} penalty=${result.breakdown.instrumentalPenalty.toStringAsFixed(1)}',
    );

    if (result.isSynced) {
      buffer.writeln('[Lyrics] synced lyrics:');
      for (final line in result.syncedLines) {
        buffer.writeln('[${_formatTimestamp(line.timestamp)}] ${line.text}');
      }
    } else {
      buffer.writeln('[Lyrics] plain lyrics:');
      buffer.writeln(result.lyricsText);
    }

    debugPrint(buffer.toString());
  }

  String _formatTimestamp(Duration duration) {
    final totalMilliseconds = duration.inMilliseconds;
    final minutes = totalMilliseconds ~/ 60000;
    final seconds = (totalMilliseconds % 60000) ~/ 1000;
    final centiseconds = (totalMilliseconds % 1000) ~/ 10;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${centiseconds.toString().padLeft(2, '0')}';
  }
}

String? _cleanField(String? value) {
  var text = value?.trim();
  if (text == null || text.isEmpty) return null;

  text = _removeBrackets(text);
  if (text.isEmpty) return null;

  final lower = text.toLowerCase();
  if (lower == 'unknown' ||
      lower == 'unknown artist' ||
      lower == 'unknown album') {
    return null;
  }
  return text;
}

String _removeBrackets(String text) {
  return text
      .replaceAll(RegExp(r'[\[【][^\]】]*[\]】]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _normalizeForKey(String? value) {
  return _normalizeText(value).replaceAll(' ', '_');
}

String _normalizeText(String? value) {
  if (value == null) return '';
  var text = value.toLowerCase().trim();
  if (text.isEmpty) return '';

  text = text.replaceAll(RegExp(r'[\u2013\u2014]'), '-');
  text = text.replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), ' ');
  text = text.replaceAll(RegExp(r'\b(feat|ft|featuring)\b.*$'), ' ');
  text = text.replaceAll(
    RegExp(
      r'\b(live|remaster(?:ed)?|radio edit|album version|instrumental|karaoke|mono|stereo|official audio|edit)\b',
    ),
    ' ',
  );
  text = text.replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

String _normalizeTitle(String? value) {
  final text = _normalizeText(value);
  if (text.isEmpty) return text;

  final tokens = text.split(' ').where((token) => token.isNotEmpty).toList();
  if (tokens.isEmpty) return text;

  final filteredTokens = tokens.where((token) {
    return !<String>{
      'live',
      'remaster',
      'remastered',
      'radio',
      'edit',
      'version',
      'album',
      'instrumental',
      'karaoke',
      'mono',
      'stereo',
    }.contains(token);
  }).toList();

  return filteredTokens.isEmpty ? text : filteredTokens.join(' ');
}
