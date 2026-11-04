import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/lyrics/sources/lyrics_source_provider.dart';
import 'package:vynody/utils/lrc_utils.dart';
import 'package:vynody/utils/lyrics_id_utils.dart';

/// 媒体库服务端歌词（Subsonic / Navidrome、Jellyfin，当前实现里 WebDAV 的
/// 旁挂 `.lrc` 也临时走这条路）。
///
/// 阶段一保持既有行为不变：只做一次 `fetcher` 调用，取不到就交给下一层。
/// 阶段二会把它拆成「旁挂 lrc」与「服务端 API」两条，并引入四态结果
/// （hit / absent / unsupported / failed）与能力探测缓存。
class MediaServerLyricsProvider implements LyricsSourceProvider {
  MediaServerLyricsProvider({
    required LyricsCacheRepository cacheRepository,
    required Future<String?> Function(LyricsQuery query)? remoteLyricsFetcher,
  }) : _cacheRepository = cacheRepository,
       _remoteLyricsFetcher = remoteLyricsFetcher;

  final LyricsCacheRepository _cacheRepository;
  final Future<String?> Function(LyricsQuery query)? _remoteLyricsFetcher;

  @override
  String get id => 'media_server';

  @override
  bool handles(LyricsQuery query) {
    if (_remoteLyricsFetcher == null) return false;
    final path = query.filePath;
    return path.startsWith('subsonic://') ||
        path.startsWith('webdav://') ||
        path.startsWith('jellyfin://');
  }

  @override
  Future<LyricSelectionResult?> load(
    LyricsQuery query, {
    bool saveToDb = true,
    CancelToken? cancelToken,
  }) async {
    final fetcher = _remoteLyricsFetcher;
    if (fetcher == null) return null;

    try {
      // 传入规范化后的完整查询（含 title / artist / album），
      // 这样即使服务端不支持 getLyricsBySongId，也能用 artist+title 兜底命中。
      final remoteLrc = await fetcher(query);
      if (remoteLrc == null || remoteLrc.trim().isEmpty) {
        debugPrint('[Lyrics] fetch remote server lyrics miss -> key="${query.cacheKey}"');
        return null;
      }

      final syncedLines = LrcUtils.parseTimedLyrics(remoteLrc);
      final isSynced = syncedLines.any((line) => line.isTimed);
      final lyricsId = LyricsIdUtils.fromLyricsText(remoteLrc);
      final track = LyricTrack(
        lyricsId: lyricsId,
        name: query.title,
        trackName: query.title,
        artistName: query.artist,
        albumName: query.album,
        duration: query.duration?.inSeconds.toDouble(),
        instrumental: false,
        plainLyrics: isSynced ? null : remoteLrc,
        syncedLyrics: isSynced ? remoteLrc : null,
      );

      final result = LyricSelectionResult(
        track: track,
        fromGetApi: false,
        source: 'remote_server',
        score: 100.0,
        breakdown: LyricScoreBreakdown(
          title: 0,
          artist: 0,
          album: 0,
          duration: 0,
          lyricsQuality: isSynced ? 5 : 3,
          instrumentalPenalty: 0,
        ),
        durationDiffSeconds: 0,
        syncedLines: syncedLines.isNotEmpty
            ? syncedLines
            : remoteLrc
                  .split('\n')
                  .map((l) => LyricLine(timestamp: Duration.zero, text: l))
                  .toList(),
        lyricsText: remoteLrc,
      );
      debugPrint('[Lyrics] fetch remote server lyrics hit -> key="${query.cacheKey}"');

      if (saveToDb) {
        unawaited(
          _cacheRemoteServerLyrics(
            query: query,
            rawText: remoteLrc,
            isSynced: isSynced,
            syncedLines: syncedLines,
          ),
        );
      }
      return result;
    } catch (e) {
      debugPrint('[Lyrics] fetch remote server lyrics error: $e');
      return null;
    }
  }

  /// 把远程服务端返回的歌词写入 SQLite 缓存。
  /// 这样下次播放同一首歌时会在最前面的缓存层命中，避免每次都向服务器重新请求，
  /// 也避免后续的 LRCLIB 结果被缓存后反而抢在服务端口歌词前面。
  Future<void> _cacheRemoteServerLyrics({
    required LyricsQuery query,
    required String rawText,
    required bool isSynced,
    required List<LyricLine> syncedLines,
  }) async {
    try {
      final effectiveLines = syncedLines.isNotEmpty
          ? syncedLines
          : rawText
                .split('\n')
                .map(
                  (line) => LyricLine(
                    timestamp: Duration.zero,
                    text: line,
                    isTimed: false,
                  ),
                )
                .toList();
      final record = LyricsCacheRecord(
        cacheKey: query.cacheKey,
        source: LyricsCacheSource.external,
        isSynced: isSynced,
        syncedLyrics: rawText,
        syncedLines: effectiveLines,
        timelineOffsetMillis: 0,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await _cacheRepository.saveLyricsCache(record);
    } catch (e) {
      debugPrint('[Lyrics] Failed to cache remote server lyrics: $e');
    }
  }
}
