import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_taglib/flutter_taglib.dart' as taglib;

import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/lyrics/sources/lyrics_source_provider.dart';
import 'package:vynody/player/lyrics/timeline/lyrics_timeline_service.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/utils/lrc_utils.dart';
import 'package:vynody/utils/lyrics_id_utils.dart';

/// 音频文件内嵌标签里的歌词（TagLib `LYRICS` / `UNSYNCEDLYRICS`）。
///
/// 本地直接由 TagLib 打开路径；WebDAV / SMB 交给注入的 [remoteLyricsReader]
/// （`RemoteMediaResolver.fetchEmbeddedLyrics`），底层是 HTTP Range 分片读取，
/// 不会下载整首音频。两条路径共用同一套解析与落库逻辑。
class EmbeddedTagProvider implements LyricsSourceProvider {
  EmbeddedTagProvider({
    required LyricsCacheRepository cacheRepository,
    Future<String?> Function(String songPath)? remoteLyricsReader,
  }) : _cacheRepository = cacheRepository,
       _remoteLyricsReader = remoteLyricsReader;

  final LyricsCacheRepository _cacheRepository;
  final Future<String?> Function(String songPath)? _remoteLyricsReader;

  @override
  String get id => 'embedded_tag';

  @override
  bool handles(LyricsQuery query) {
    if (query.filePath.isEmpty) return false;
    if (RemoteMediaResolver.isRemoteUri(query.filePath)) {
      return _remoteLyricsReader != null;
    }
    return taglib.TagLibFile.isSupported;
  }

  @override
  Future<LyricSelectionResult?> load(
    LyricsQuery query, {
    bool saveToDb = true,
    CancelToken? cancelToken,
  }) async {
    final songPath = query.filePath;
    if (songPath.isEmpty) return null;

    if (RemoteMediaResolver.isRemoteUri(songPath)) {
      final reader = _remoteLyricsReader;
      if (reader == null) return null;
      String? rawLyrics;
      try {
        rawLyrics = await reader(songPath);
      } catch (e) {
        debugPrint('[Lyrics] Error reading remote embedded lyrics: $e');
        return null;
      }
      if (rawLyrics == null || rawLyrics.trim().isEmpty) return null;
      return _commit(query, rawLyrics, saveToDb: saveToDb);
    }

    try {
      if (!taglib.TagLibFile.isSupported) {
        return null;
      }
      final file = File(songPath);
      if (!await file.exists()) {
        return null;
      }

      final tagFile = await taglib.TagLibFile.openAsync(songPath);
      if (tagFile == null) {
        return null;
      }

      try {
        final lyricsList = tagFile.properties[taglib.TagProperties.lyrics];
        if (lyricsList == null || lyricsList.isEmpty) {
          debugPrint(
            '[Lyrics] TagLib metadata check: TagProperties.lyrics is null/empty for "$songPath"',
          );
          return null;
        }

        final rawLyrics = lyricsList.first.trim();
        if (rawLyrics.isEmpty) {
          debugPrint(
            '[Lyrics] TagLib metadata check: TagProperties.lyrics content is empty string for "$songPath"',
          );
          return null;
        }

        return _commit(query, rawLyrics, saveToDb: saveToDb);
      } finally {
        tagFile.close();
      }
    } catch (e, st) {
      debugPrint(
        '[Lyrics] Error reading embedded lyrics from "$songPath": $e\n$st',
      );
      return null;
    }
  }

  /// 解析并（可选）落库。本地与远程共用，保证两条路径产出一致的缓存记录。
  Future<LyricSelectionResult> _commit(
    LyricsQuery query,
    String rawLyrics, {
    required bool saveToDb,
  }) async {
    final syncedLines = LrcUtils.parseTimedLyrics(rawLyrics);
    final isSynced = syncedLines.any((line) => line.isTimed);

    final lyricsId = LyricsIdUtils.fromLyricsText(rawLyrics);
    final track = LyricTrack(
      id: null,
      lyricsId: lyricsId,
      name: query.title,
      trackName: query.title,
      artistName: query.artist,
      albumName: query.album,
      duration: query.duration?.inSeconds.toDouble(),
      instrumental: false,
      plainLyrics: isSynced ? null : rawLyrics,
      syncedLyrics: isSynced ? rawLyrics : null,
    );

    final result = LyricSelectionResult(
      track: track,
      fromGetApi: false,
      source: 'embedded',
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
          : rawLyrics
                .split('\n')
                .map(
                  (line) => LyricLine(
                    timestamp: Duration.zero,
                    text: line,
                    isTimed: false,
                  ),
                )
                .toList(),
      lyricsText: rawLyrics,
      timelineOffset: Duration.zero,
    );

    debugPrint(
      '[Lyrics] Embedded lyrics hit! file="${query.filePath}" length=${rawLyrics.length} lines=${result.syncedLines.length} isSynced=$isSynced key="${query.cacheKey}"',
    );

    if (saveToDb) {
      try {
        final record = LyricsCacheRecord(
          cacheKey: query.cacheKey,
          source: LyricsCacheSource.embedded,
          isSynced: isSynced,
          syncedLyrics: rawLyrics,
          syncedLines: result.syncedLines,
          timelineOffsetMillis: 0,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        );
        await _cacheRepository.saveLyricsCache(record);
        unawaited(
          LyricsTimelineService.instance.ensureInitialSnapshot(
            cacheKey: query.cacheKey,
            lyrics: rawLyrics,
            timelineOffsetMillis: 0,
            description: 'Embedded',
          ),
        );
      } catch (e) {
        debugPrint('[Lyrics] Failed to cache embedded lyrics: $e');
      }
    }

    return result;
  }
}
