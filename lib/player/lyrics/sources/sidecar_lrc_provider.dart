import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/lyrics/sources/lyrics_source_provider.dart';
import 'package:vynody/player/lyrics/timeline/lyrics_timeline_service.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/utils/lrc_utils.dart';
import 'package:vynody/utils/lyrics_id_utils.dart';

/// 旁挂同名 `.lrc` 文件来源（本地文件系统）。
///
/// 阶段一仅覆盖本地路径；SMB / WebDAV 的旁挂读取在阶段二以同样的接口补入，
/// 届时本类会增加对应后端，而调用方无需改动。
class SidecarLrcProvider implements LyricsSourceProvider {
  SidecarLrcProvider({required LyricsCacheRepository cacheRepository})
    : _cacheRepository = cacheRepository;

  final LyricsCacheRepository _cacheRepository;

  @override
  String get id => 'sidecar_lrc';

  @override
  bool handles(LyricsQuery query) {
    final path = query.filePath;
    if (path.isEmpty) return false;
    // 远程路径（smb:// webdav:// ...）在这里没有可读的本地目录，
    // 交给阶段二的后端处理，避免每次白白做一次 File.exists 探测。
    return !RemoteMediaResolver.isRemoteUri(path);
  }

  @override
  Future<LyricSelectionResult?> load(
    LyricsQuery query, {
    bool saveToDb = true,
    CancelToken? cancelToken,
  }) async {
    try {
      final songPath = query.filePath;
      if (songPath.isEmpty) return null;

      final directory = p.dirname(songPath);
      final baseName = p.basenameWithoutExtension(songPath);
      final lrcPath = p.join(directory, '$baseName.lrc');

      var lrcFile = File(lrcPath);
      if (!await lrcFile.exists()) {
        final lrcPathUpper = p.join(directory, '$baseName.LRC');
        final lrcFileUpper = File(lrcPathUpper);
        if (!await lrcFileUpper.exists()) {
          return null;
        }
        lrcFile = lrcFileUpper;
      }

      final rawLyrics = await lrcFile.readAsString();
      if (rawLyrics.trim().isEmpty) {
        return null;
      }

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
        source: 'local_lrc',
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

      if (saveToDb) {
        try {
          final record = LyricsCacheRecord(
            cacheKey: query.cacheKey,
            source: LyricsCacheSource.external,
            isSynced: isSynced,
            syncedLyrics: rawLyrics,
            syncedLines: result.syncedLines,
            timelineOffsetMillis: 0,
            updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
          );
          await _cacheRepository.saveLyricsCache(record);
          if (query.filePath.isNotEmpty) {
            unawaited(
              LyricsTimelineService.instance.ensureInitialSnapshot(
                cacheKey: query.cacheKey,
                lyrics: rawLyrics,
                timelineOffsetMillis: 0,
                description: 'Local LRC',
              ),
            );
          }
        } catch (e) {
          debugPrint('[Lyrics] Failed to cache local LRC lyrics: $e');
        }
      }

      return result;
    } catch (e) {
      debugPrint('[Lyrics] Error reading local lrc file: $e');
      return null;
    }
  }
}
