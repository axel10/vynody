import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/lyrics/sources/lyrics_source_provider.dart';
import 'package:vynody/player/lyrics/sources/media_server_lyrics_result.dart';
import 'package:vynody/utils/lrc_utils.dart';
import 'package:vynody/utils/lyrics_id_utils.dart';

/// 媒体库服务端歌词（Subsonic / Navidrome、Jellyfin）。
///
/// 服务端返回四态结论（见 [MediaServerLyricsStatus]），本类只关心 `hit`：
/// 其余三种都视作「这一层没有」，继续交给下一个 provider。
/// 能力探测缓存由客户端在遇到「接口不存在」时写入，这里不重复判断。
class MediaServerLyricsProvider implements LyricsSourceProvider {
  MediaServerLyricsProvider({
    required LyricsCacheRepository cacheRepository,
    required Future<MediaServerLyricsResult> Function(
      LyricsQuery query, {
      CancelToken? cancelToken,
    })?
    remoteLyricsFetcher,
  }) : _cacheRepository = cacheRepository,
       _remoteLyricsFetcher = remoteLyricsFetcher;

  final LyricsCacheRepository _cacheRepository;
  final Future<MediaServerLyricsResult> Function(
    LyricsQuery query, {
    CancelToken? cancelToken,
  })?
  _remoteLyricsFetcher;

  @override
  String get id => 'media_server';

  @override
  bool handles(LyricsQuery query) {
    if (_remoteLyricsFetcher == null) return false;
    final path = query.filePath;
    // WebDAV 的同目录 `.lrc` 由 SidecarLrcProvider 处理（与本地文件同一层），
    // 媒体库这里只负责 subsonic / jellyfin 的歌词接口。
    return path.startsWith('subsonic://') || path.startsWith('jellyfin://');
  }

  @override
  Future<LyricSelectionResult?> load(
    LyricsQuery query, {
    bool saveToDb = true,
    CancelToken? cancelToken,
  }) async {
    final fetcher = _remoteLyricsFetcher;
    if (fetcher == null) return null;

    final MediaServerLyricsResult remote;
    try {
      remote = await fetcher(query, cancelToken: cancelToken);
    } catch (e) {
      debugPrint('[Lyrics] fetch remote server lyrics error: $e');
      return null;
    }

    if (!remote.isHit) {
      debugPrint(
        '[Lyrics] fetch remote server lyrics rejected -> key="${query.cacheKey}" '
        '${remote.status.name}${remote.diagnostic == null ? '' : ' (${remote.diagnostic})'}',
      );
      return null;
    }

    final remoteLrc = remote.text?.trim() ?? '';
    if (remoteLrc.isEmpty) return null;

    debugPrint(
      '[Lyrics] fetch remote server lyrics hit -> key="${query.cacheKey}" '
      'variant=${remote.variant} synced=${remote.synced}',
    );

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
