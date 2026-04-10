import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../utils/network_client.dart';
import '../utils/clean_helper.dart';
import '../utils/lyrics_id_utils.dart';
import '../utils/lrc_utils.dart';
import '../models/lyric_line.dart';
import 'lyrics_cache_repository.dart';
import 'metadata_database.dart';

part 'lyrics_service.freezed.dart';

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

@freezed
abstract class LyricTrack with _$LyricTrack {
  const LyricTrack._();

  const factory LyricTrack({
    int? id,
    String? lyricsId,
    String? name,
    String? trackName,
    String? artistName,
    String? albumName,
    double? duration,
    @Default(false) bool instrumental,
    String? plainLyrics,
    String? syncedLyrics,
  }) = _LyricTrack;

  factory LyricTrack.fromJson(Map<String, dynamic> json) {
    return LyricTrack(
      id: json['id'] as int?,
      lyricsId: json['lyricsId'] as String?,
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
      'lyricsId': lyricsId,
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

@freezed
abstract class LyricSelectionResult with _$LyricSelectionResult {
  const LyricSelectionResult._();

  const factory LyricSelectionResult({
    required LyricTrack track,
    required bool fromGetApi,
    required String source,
    required double score,
    required LyricScoreBreakdown breakdown,
    required int durationDiffSeconds,
    @Default(<LyricLine>[]) List<LyricLine> syncedLines,
    required String lyricsText,
    @Default(Duration.zero) Duration timelineOffset,
  }) = _LyricSelectionResult;

  bool get isSynced => syncedLines.isNotEmpty;
}

class LyricsService {
  LyricsService({
    NetworkClient? client,
    MetadataDatabase? db,
    LyricsCacheRepository? cacheRepository,
  }) : _client = client ?? NetworkClient.instance,
       _cacheRepository = cacheRepository ?? LyricsCacheRepository(db: db);

  final NetworkClient _client;
  final LyricsCacheRepository _cacheRepository;
  final Map<String, Future<LyricSelectionResult?>> _inFlight = {};

  static const double _acceptThreshold = 65.0;

  /// 核心歌词获取入口。
  /// 实现了一个分层的查找策略：内存 -> SQLite 数据库 -> 在线 API。
  Future<LyricSelectionResult?> fetchBestLyrics({
    required LyricsQuery query,
    bool debugLog = false,
  }) async {
    // 对原始查询进行统一清洗，确保“查询键”与“保存键”逻辑完全一致。
    // 解决如“Song [Live]”与“Song”因为括号过滤逻辑不一导致的缓存不命中问题。
    final normalizedQuery = LyricsQuery(
      filePath: query.filePath,
      fileName: query.fileName,
      title:
          _cleanField(query.title) ??
          CleanHelper.deriveCleanTitleFromFileName(query.fileName),
      artist: _cleanField(query.artist),
      album: _cleanField(query.album),
      duration: query.duration,
    );

    final cacheKey = normalizedQuery.cacheKey;

    // 先尝试原始查询键，兼容 Gemini 生成结果按“当前曲目原始元数据”写入的缓存。
    // 再回退到规范化后的查询键，保持既有 LRCLib 缓存命中逻辑不变。
    final cachedFromDb = await _loadFromDatabase(query, ignoreEmptyCache: true);
    if (cachedFromDb != null) {
      if (debugLog) {
        debugPrintSelection(query, cachedFromDb, source: 'sqlite');
      }
      return cachedFromDb;
    }

    // 不再使用内存层缓存，而是依赖 MusicFile 自身的持有和数据库持久化。
    // 这里只保留数据库层的查找逻辑。
    final normalizedCachedFromDb = await _loadFromDatabase(normalizedQuery);
    if (normalizedCachedFromDb != null) {
      if (debugLog) {
        debugPrintSelection(
          normalizedQuery,
          normalizedCachedFromDb,
          source: 'sqlite',
        );
      }
      return normalizedCachedFromDb;
    }

    // 3. 合并正在进行的相同请求：防止同一首歌短时间内多次发起网络搜索请求
    final existing = _inFlight[cacheKey];
    if (existing != null) {
      final result = await existing;
      if (debugLog) {
        debugPrintSelection(query, result, source: 'in-flight');
      }
      return result;
    }

    // 4. 发起异步网络搜索任务
    final future = _fetchBestLyricsInternal(normalizedQuery).whenComplete(() {
      _inFlight.remove(cacheKey);
    });
    _inFlight[cacheKey] = future;

    final result = await future;

    if (debugLog) {
      debugPrintSelection(normalizedQuery, result);
    }

    return result;
  }

  /// 在线搜索逻辑：包含精准匹配与模糊评分两个阶段。
  ///
  /// 逻辑概述：
  /// - 首先尝试 /get API 进行精准匹配（通过标题/艺术家/专辑/时长作为唯一标识）。
  /// - 若无精准结果，则通过 /search API 发起全文检索，并对所有候选结果进行加权评分（相似度/时长偏差）。
  /// - 评分系统综合考虑：标题相似度(45%)、歌手(25%)、专辑(15%)、时长(10%)、同步性(5%)。
  /// - 只有综合评分高于阈值（默认 65 分）或时长偏差极小（3秒内）的结果才会作为最佳候选项保存至本地数据库并返回。
  Future<LyricSelectionResult?> _fetchBestLyricsInternal(
    LyricsQuery query,
  ) async {
    final primaryResult = await _fetchBestLyricsOnce(
      query,
      cacheQuery: query,
      cacheEmptyResult: false,
    );
    if (primaryResult != null) {
      return primaryResult;
    }

    final fallbackQuery = _buildTitleOnlyFallbackQuery(query);
    if (fallbackQuery == null) {
      await _saveEmptyToDatabase(query);
      return null;
    }

    _logDebug(
      'lyrics retry with title only -> title="${query.title}" '
      'artist="${query.artist ?? ''}" album="${query.album ?? ''}"',
    );

    final fallbackResult = await _fetchBestLyricsOnce(
      fallbackQuery,
      cacheQuery: query,
      cacheEmptyResult: true,
    );
    return fallbackResult;
  }

  Future<LyricSelectionResult?> _fetchBestLyricsOnce(
    LyricsQuery query, {
    required LyricsQuery cacheQuery,
    required bool cacheEmptyResult,
  }) async {
    final completeQuery = _buildCompleteQuery(query);
    if (completeQuery != null) {
      final direct = await _fetchGet(completeQuery);
      if (direct != null) {
        final scored = _scoreCandidate(completeQuery, direct, fromGetApi: true);
        if (scored != null && scored.score >= _acceptThreshold) {
          await _saveToDatabase(query: cacheQuery, result: scored);
          return scored;
        }
      }
    }

    final searchQuery = _buildSearchQuery(query);
    final searchResults = await _search(searchQuery);
    if (searchResults.isEmpty) {
      if (cacheEmptyResult) {
        await _saveEmptyToDatabase(cacheQuery);
      }
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
      if (cacheEmptyResult) {
        await _saveEmptyToDatabase(cacheQuery);
      }
      return null;
    }

    scoredResults.sort(_compareSelectionResults);
    var bestCandidate = scoredResults.first;

    if (bestCandidate.score < _acceptThreshold) {
      // 检查是否有时间极其接近的（3秒内）作为兜底
      final fallbackCandidates = scoredResults
          .where((r) => r.durationDiffSeconds <= 3)
          .toList();

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
        if (cacheEmptyResult) {
          await _saveEmptyToDatabase(cacheQuery);
        }
        return null;
      }
    }

    await _saveToDatabase(query: cacheQuery, result: bestCandidate);
    return bestCandidate;
  }

  Future<LyricSelectionResult?> _loadFromDatabase(
    LyricsQuery query, {
    bool ignoreEmptyCache = false,
  }) async {
    try {
      final record = await _cacheRepository.getLyricsCache(query.cacheKey);
      if (record == null) return null;
      if (ignoreEmptyCache && record.source.trim().toLowerCase() == 'none') {
        return null;
      }
      return _selectionFromRecord(query, record);
    } catch (e) {
      debugPrint('[Lyrics] Failed to load cache for "${query.cacheKey}": $e');
      return null;
    }
  }

  Future<void> _saveEmptyToDatabase(LyricsQuery query) async {
    try {
      final record = LyricsCacheRecord(
        cacheKey: query.cacheKey,
        source: 'none',
        isSynced: false,
        syncedLyrics: null,
        syncedLines: const [],
        timelineOffsetMillis: 0,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await _cacheRepository.saveLyricsCache(record);
    } catch (e) {
      debugPrint(
        '[Lyrics] Failed to cache empty result for "${query.title}": $e',
      );
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
    final fallbackTitle = CleanHelper.deriveCleanTitleFromFileName(
      query.fileName,
    );
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

  LyricsQuery? _buildTitleOnlyFallbackQuery(LyricsQuery query) {
    final title = _cleanField(query.title);
    if (title == null) {
      return null;
    }

    final hasArtist = _cleanField(query.artist) != null;
    final hasAlbum = _cleanField(query.album) != null;
    if (!hasArtist && !hasAlbum) {
      return null;
    }

    return LyricsQuery(
      filePath: query.filePath,
      fileName: query.fileName,
      title: title,
      duration: query.duration,
    );
  }

  Future<LyricTrack?> _fetchGet(LyricsQuery query) async {
    try {
      final response = await _client.get(
        'https://lrclib.net/api/get',
        queryParameters: {
          'track_name': query.title,
          'artist_name': query.artist,
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
            'q': _buildSearchText(query),
          }..removeWhere(
            (_, value) =>
                value == null || (value is String && value.trim().isEmpty),
          );

      final response = await _client.get(
        'https://lrclib.net/api/search',
        queryParameters: params,
      );

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
      final lyricsText = result.lyricsText.trim();
      final record = LyricsCacheRecord(
        cacheKey: query.cacheKey,
        source: result.fromGetApi ? 'get' : 'search',
        isSynced: result.isSynced,
        syncedLyrics: result.track.syncedLyrics ?? lyricsText,
        syncedLines: result.syncedLines.map((line) => line.toJson()).toList(),
        timelineOffsetMillis: result.timelineOffset.inMilliseconds,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await _cacheRepository.saveLyricsCache(record);
    } catch (e) {
      debugPrint('[Lyrics] Failed to cache lyrics for "${query.title}": $e');
    }
  }

  LyricSelectionResult _selectionFromRecord(
    LyricsQuery query,
    LyricsCacheRecord record,
  ) {
    final lyricsText = _lyricsTextFromRecord(record);
    final lyricsId = LyricsIdUtils.fromLyricsText(lyricsText);
    final track = LyricTrack(
      id: null,
      lyricsId: lyricsId,
      name: query.title,
      trackName: query.title,
      artistName: query.artist,
      albumName: query.album,
      duration: query.duration?.inSeconds.toDouble(),
      instrumental: false,
      plainLyrics: lyricsText,
      syncedLyrics: record.syncedLyrics,
    );

    final syncedLines = record.syncedLines
        .map((item) => LyricLine.fromJson(item))
        .toList(growable: false);

    return LyricSelectionResult(
      track: track,
      fromGetApi: record.source == 'get',
      source: _sourceFromCacheRecord(record.source),
      score: 100.0,
      breakdown: LyricScoreBreakdown(
        title: 0,
        artist: 0,
        album: 0,
        duration: 0,
        lyricsQuality: record.isSynced ? 5 : 3,
        instrumentalPenalty: 0,
      ),
      durationDiffSeconds: 0,
      syncedLines: syncedLines,
      lyricsText: lyricsText,
      timelineOffset: Duration(milliseconds: record.timelineOffsetMillis),
    );
  }

  String _buildSearchText(LyricsQuery query) {
    final parts = <String>[
      query.title,
      if (query.artist != null && query.artist!.trim().isNotEmpty)
        query.artist!,
    ];
    return parts.join(' ').trim();
  }

  String _lyricsTextFromRecord(LyricsCacheRecord record) {
    final syncedLyrics = record.syncedLyrics?.trim();
    if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
      return syncedLyrics;
    }

    if (record.syncedLines.isEmpty) return '';

    return record.syncedLines
        .map((line) => line['text']?.toString() ?? '')
        .where((line) => line.trim().isNotEmpty)
        .join('\n')
        .trim();
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
    final lyricsId = LyricsIdUtils.fromLyricsText(lyricsText);

    return LyricSelectionResult(
      track: candidate.copyWith(lyricsId: lyricsId),
      fromGetApi: fromGetApi,
      source: 'lrclib',
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
      timelineOffset: Duration.zero,
    );
  }

  String _sourceFromCacheRecord(String source) {
    final normalized = source.trim().toLowerCase();
    if (normalized.startsWith('gemini')) {
      return 'gemini';
    }
    if (normalized == 'get' || normalized == 'search') {
      return 'lrclib';
    }
    return normalized.isEmpty ? 'lrclib' : normalized;
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
    return LrcUtils.parseTimedLyrics(syncedLyrics);
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

  void _logDebug(String message) {
    if (!kDebugMode) return;
    debugPrint('[Lyrics] $message');
  }
}

String? _cleanField(String? value) {
  var text = value?.trim();
  if (text == null || text.isEmpty) return null;

  text = CleanHelper.removeBrackets(text);
  text = CleanHelper.stripSequenceNumber(text); // 增加：对不完美的 Tag 也尝试进行序号擦除
  if (text.isEmpty) return null;

  final lower = text.toLowerCase();
  if (lower == 'unknown' ||
      lower == 'unknown artist' ||
      lower == 'unknown album') {
    return null;
  }
  return text;
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
