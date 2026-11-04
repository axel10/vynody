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

/// 旁挂同名 `.lrc` 文件来源。
///
/// 本地走文件系统，WebDAV / SMB 走注入的 [remoteSidecarReader]（由
/// `RemoteMediaResolver.fetchSidecarLrc` 提供）。两条路径只差「怎么拿到文本」，
/// 解析、落库与快照逻辑共用一份。
class SidecarLrcProvider implements LyricsSourceProvider {
  SidecarLrcProvider({
    required LyricsCacheRepository cacheRepository,
    Future<String?> Function(String songPath)? remoteSidecarReader,
  }) : _cacheRepository = cacheRepository,
       _remoteSidecarReader = remoteSidecarReader;

  final LyricsCacheRepository _cacheRepository;
  final Future<String?> Function(String songPath)? _remoteSidecarReader;

  @override
  String get id => 'sidecar_lrc';

  @override
  bool handles(LyricsQuery query) {
    final path = query.filePath;
    if (path.isEmpty) return false;
    if (RemoteMediaResolver.isRemoteUri(path)) {
      // 远程必须有 reader 才能探测，否则只是白跑一次网络。
      return _remoteSidecarReader != null;
    }
    return true;
  }

  @override
  Future<LyricSelectionResult?> load(
    LyricsQuery query, {
    bool saveToDb = true,
    CancelToken? cancelToken,
  }) async {
    final songPath = query.filePath;
    if (songPath.isEmpty) return null;

    final isRemote = RemoteMediaResolver.isRemoteUri(songPath);
    final String? rawLyrics;
    final String snapshotLabel;

    if (isRemote) {
      final reader = _remoteSidecarReader;
      if (reader == null) return null;
      try {
        rawLyrics = await reader(songPath);
      } catch (e) {
        debugPrint('[Lyrics] Error reading remote sidecar lrc "$songPath": $e');
        return null;
      }
      snapshotLabel = 'Remote LRC';
    } else {
      try {
        rawLyrics = await _readLocalLrc(songPath);
      } catch (e) {
        debugPrint('[Lyrics] Error reading local lrc file: $e');
        return null;
      }
      snapshotLabel = 'Local LRC';
    }

    if (rawLyrics == null || rawLyrics.trim().isEmpty) {
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
      source: isRemote ? 'remote_lrc' : 'local_lrc',
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
        unawaited(
          LyricsTimelineService.instance.ensureInitialSnapshot(
            cacheKey: query.cacheKey,
            lyrics: rawLyrics,
            timelineOffsetMillis: 0,
            description: snapshotLabel,
          ),
        );
      } catch (e) {
        debugPrint('[Lyrics] Failed to cache sidecar lrc lyrics: $e');
      }
    }

    return result;
  }

  Future<String?> _readLocalLrc(String songPath) async {
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
    return lrcFile.readAsString();
  }
}
