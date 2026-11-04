import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/lyrics/sources/lyrics_source_provider.dart';
import 'package:vynody/utils/lyrics_id_utils.dart';

/// 歌词来源顺序的唯一管理者。
///
/// 顺序固定为：
/// 1. 原始缓存键命中
/// 2. 规范化缓存键命中
/// 3. 按 [providers] 列表顺序遍历，第一个 `handles` 且取到内容的结果胜出
/// 4. 在线兜底（lrclib 仍留在 `LyricsService` 内部，通过 [onlineFallback] 接入）
///
/// 新增来源只需往列表里插一项，不修改本类。列表顺序即优先级，
/// 换源候选、偏好挑选等派生逻辑后续都从这里读取，避免再各自维护一份。
class LyricsResolver {
  LyricsResolver({
    required LyricsCacheRepository cacheRepository,
    required List<LyricsSourceProvider> providers,
    Future<LyricSelectionResult?> Function()? onlineFallback,
  }) : _cacheRepository = cacheRepository,
       _providers = List<LyricsSourceProvider>.unmodifiable(providers),
       _onlineFallback = onlineFallback;

  final LyricsCacheRepository _cacheRepository;
  final List<LyricsSourceProvider> _providers;
  final Future<LyricSelectionResult?> Function()? _onlineFallback;

  /// 有序的来源列表，顺序即优先级。
  List<LyricsSourceProvider> get providers => _providers;

  Future<LyricSelectionResult?> resolve({
    required LyricsQuery rawQuery,
    required LyricsQuery normalizedQuery,
    CancelToken? cancelToken,
    Future<LyricSelectionResult?> Function()? onlineFallback,
  }) async {
    final cacheKey = normalizedQuery.cacheKey;

    // 先尝试原始查询键，兼容 AI 生成结果按「当前曲目原始元数据」写入的缓存。
    // 再回退到规范化后的查询键，保持既有 LRCLib 缓存命中逻辑不变。
    final cachedFromDb = await _loadFromDatabase(rawQuery);
    if (cachedFromDb != null && cachedFromDb.track.hasLyrics) {
      debugPrint('[Lyrics] fetch cache hit -> key="$cacheKey" source=raw-db');
      return cachedFromDb;
    }

    final normalizedCachedFromDb = await _loadFromDatabase(normalizedQuery);
    if (normalizedCachedFromDb != null &&
        normalizedCachedFromDb.track.hasLyrics) {
      debugPrint(
        '[Lyrics] fetch cache hit -> key="$cacheKey" source=normalized-db',
      );
      return normalizedCachedFromDb;
    }

    for (final provider in _providers) {
      if (!provider.handles(normalizedQuery)) continue;
      final result = await provider.load(
        normalizedQuery,
        cancelToken: cancelToken,
      );
      if (result == null) continue;
      debugPrint(
        '[Lyrics] provider hit -> key="$cacheKey" provider=${provider.id}',
      );
      return result;
    }

    final fallback = onlineFallback ?? _onlineFallback;
    if (fallback == null) return null;
    debugPrint('[Lyrics] pipeline queued network -> key="$cacheKey"');
    return fallback();
  }

  Future<LyricSelectionResult?> _loadFromDatabase(LyricsQuery query) async {
    try {
      final record = await _cacheRepository.getLyricsCacheTolerant(
        query,
        ignoreNone: true,
      );
      if (record == null) {
        debugPrint('[Lyrics] Cache miss -> key="${query.cacheKey}"');
        return null;
      }
      debugPrint(
        '[Lyrics] Cache loaded from DB -> matchedKey="${record.cacheKey}" source=${record.source.dbValue} isSynced=${record.isSynced}',
      );
      return _selectionFromRecord(query, record);
    } catch (e) {
      debugPrint('[Lyrics] Failed to load cache for "${query.cacheKey}": $e');
      return null;
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

    return LyricSelectionResult(
      track: track,
      fromGetApi: false,
      source: record.source.musicLyricSource,
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
      syncedLines: record.syncedLines,
      lyricsText: lyricsText,
      timelineOffset: Duration(milliseconds: record.timelineOffsetMillis),
    );
  }

  String _lyricsTextFromRecord(LyricsCacheRecord record) {
    final syncedLyrics = record.syncedLyrics?.trim();
    if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
      return syncedLyrics;
    }

    if (record.syncedLines.isEmpty) return '';

    return record.syncedLines
        .map((line) => line.text)
        .where((line) => line.trim().isNotEmpty)
        .join('\n')
        .trim();
  }
}
