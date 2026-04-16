import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/lyric_line.dart';
import '../models/music_file.dart';
import '../models/music_lyric.dart';
import '../models/music_lyric_translation.dart';
import '../utils/lrc_utils.dart';
import '../utils/lyrics_id_utils.dart';
import 'lyrics_cache_models.dart';
import 'lyrics_controller_context.dart';
import 'lyrics_controller_utils.dart';
import 'lyrics_generation_phase.dart';
import 'lyrics_generation_result.dart';
import 'lyrics_service.dart';

typedef _LyricsGenerationInvoker =
    Future<LyricsGenerationResult> Function({
      required void Function(double progress) onUploadProgress,
      required void Function(String stage) onStageChanged,
      required void Function(String partialText, bool isFinal) onProgress,
    });

class _LyricsGenerationSession {
  _LyricsGenerationSession({required this.id, required this.songPath});

  final int id;
  final String songPath;
}

class LyricsGenerationCoordinator {
  LyricsGenerationCoordinator(this._context, this._support);

  final LyricsControllerContext _context;
  final LyricsControllerSupport _support;

  _LyricsGenerationSession _beginLyricsGeneration(
    MusicFile song, {
    required String statusLabel,
  }) {
    _support.cancelOngoingLyricsFetch(reason: 'lyrics generation started');
    _context.lyricsGeneration.beginForSong(song.path);
    _context.setLyricsSearchAttempted(true);
    _context.startLyricsGenerationStatus(statusLabel);
    _context.setLyricsGenerating(
      true,
      phase: LyricsGenerationPhase.uploading,
      progress: 0.0,
    );

    return _LyricsGenerationSession(
      id: _context.lyricsGeneration.serial,
      songPath: song.path,
    );
  }

  bool _isActiveLyricsGeneration(_LyricsGenerationSession session) {
    return session.id == _context.lyricsGeneration.serial;
  }

  bool _isCurrentSong(_LyricsGenerationSession session) {
    return _context.currentMusic()?.path == session.songPath;
  }

  void _updateLyricsGenerationStage(
    _LyricsGenerationSession session,
    String stage,
  ) {
    if (!_isActiveLyricsGeneration(session)) return;
    if (!_isCurrentSong(session)) return;
    _support.setGenerationStage(stage);
  }

  MusicLyric _buildGeneratedLyrics({
    required String text,
    required String source,
    Duration timelineOffset = Duration.zero,
    Map<String, MusicLyricTranslation> translations =
        const <String, MusicLyricTranslation>{},
  }) {
    final normalizedText = text.trim();
    final generatedLines = _parseGeneratedLyrics(normalizedText);
    return MusicLyric(
      id: LyricsIdUtils.fromLyricsText(normalizedText),
      syncedLines: generatedLines.isNotEmpty
          ? generatedLines
          : _support.buildLyricsLines(const [], normalizedText),
      plainText: normalizedText,
      source: source,
      timelineOffset: timelineOffset,
      translations: translations,
    );
  }

  void _publishGeneratedLyrics(
    _LyricsGenerationSession session, {
    required MusicFile song,
    required MusicLyric lyrics,
  }) {
    if (!_isActiveLyricsGeneration(session)) return;

    final updated = _support.replaceSongIfPath(
      song.path,
      (currentSong) => currentSong.copyWith(lyrics: lyrics),
    );
    if (updated != null) {
      unawaited(_support.restoreCachedTranslations(updated));
    }

    if (_isCurrentSong(session)) {
      _context.setHasLyrics(true);
      _context.setIsLyricsLoading(false);
      _context.setLyricsGenerating(
        true,
        phase: LyricsGenerationPhase.generating,
        progress: 1.0,
      );
      _context.setLyricsSearchAttempted(true);
      _context.setCurrentLyricsLines(lyrics.syncedLines);
      _context.setCurrentLyricsText(lyrics.plainText);
    }

    _context.bumpRevision();
  }

  void _finalizeLyricsGeneration(_LyricsGenerationSession session) {
    if (session.id != _context.lyricsGeneration.serial) return;

    _context.lyricsGeneration.finish();
    _context.setLyricsGenerating(
      false,
      phase: LyricsGenerationPhase.idle,
      progress: 0.0,
    );
    _context.clearLyricsGenerationStatus();
  }

  Future<String?> _runLyricsGeneration({
    required MusicFile song,
    required LyricsCacheSource databaseSource,
    required String statusLabel,
    required _LyricsGenerationInvoker invoke,
    Map<String, MusicLyricTranslation> Function()? translationProvider,
  }) async {
    final session = _beginLyricsGeneration(song, statusLabel: statusLabel);
    try {
      final result = await invoke(
        onUploadProgress: (progress) {
          if (!_isActiveLyricsGeneration(session)) {
            return;
          }

          if (_isCurrentSong(session)) {
            _context.setLyricsGenerating(
              true,
              phase: LyricsGenerationPhase.uploading,
              progress: progress.clamp(0.0, 1.0),
            );
          }
        },
        onStageChanged: (stage) {
          _updateLyricsGenerationStage(session, stage);
        },
        onProgress: (partialText, isFinal) {
          if (!_isActiveLyricsGeneration(session)) {
            return;
          }

          final progressText = partialText.trim();
          if (progressText.isEmpty) return;
          final progressLyrics = _buildGeneratedLyrics(
            text: progressText,
            source: _support.lyricsProviderTag(),
            timelineOffset: song.lyrics?.timelineOffset ?? Duration.zero,
            translations:
                translationProvider?.call() ??
                const <String, MusicLyricTranslation>{},
          );
          _publishGeneratedLyrics(session, song: song, lyrics: progressLyrics);
        },
      );

      if (!_isActiveLyricsGeneration(session)) {
        return null;
      }

      if (!result.isSuccess ||
          result.text == null ||
          result.text!.trim().isEmpty) {
        return result.errorMessage ?? '生成失败。';
      }

      final lyrics = _buildGeneratedLyrics(
        text: result.text!,
        source: _support.lyricsProviderTag(),
        timelineOffset: song.lyrics?.timelineOffset ?? Duration.zero,
        translations:
            translationProvider?.call() ??
            const <String, MusicLyricTranslation>{},
      );
      _publishGeneratedLyrics(session, song: song, lyrics: lyrics);

      await _saveGeneratedLyricsToDatabase(
        song: song,
        generatedLyrics: lyrics.plainText,
        syncedLines: lyrics.syncedLines,
        source: databaseSource,
      );
      return null;
    } finally {
      _finalizeLyricsGeneration(session);
    }
  }

  Future<String?> _generateLyricsForSong(MusicFile song) async {
    try {
      return await _runLyricsGeneration(
        song: song,
        databaseSource: LyricsCacheSource.aiGenerate,
        statusLabel: '正在生成歌词',
        invoke:
            ({
              required onUploadProgress,
              required onStageChanged,
              required onProgress,
            }) {
              return _context.lyricsAiService.generateLyricsFromFile(
                filePath: song.path,
                songTitle: song.title,
                onUploadProgress: onUploadProgress,
                onStageChanged: onStageChanged,
                onProgress: onProgress,
              );
            },
      );
    } catch (e) {
      debugPrint('[LyricsController] Failed to generate lyrics: $e');
      return '生成歌词时发生错误：$e';
    }
  }

  Future<String?> _generateTimelineForSong(MusicFile song) async {
    final sourceLyrics = _timelineSourceLyricsForSong(song).trim();
    if (sourceLyrics.isEmpty) {
      debugPrint(
        '[LyricsController] generate timeline skipped: no usable lyrics '
        'path=${song.path}',
      );
      return '没有可用于生成时间轴的歌词。';
    }

    try {
      return await _runLyricsGeneration(
        song: song,
        databaseSource: LyricsCacheSource.aiTimeline,
        statusLabel: '正在生成时间轴',
        translationProvider: () =>
            _support.songForPath(song.path)?.lyrics?.translations ??
            const <String, MusicLyricTranslation>{},
        invoke:
            ({
              required onUploadProgress,
              required onStageChanged,
              required onProgress,
            }) {
              return _context.lyricsAiService.generateTimelineFromLyrics(
                filePath: song.path,
                lyrics: sourceLyrics,
                songTitle: song.title,
                onUploadProgress: onUploadProgress,
                onStageChanged: onStageChanged,
                onProgress: onProgress,
              );
            },
      );
    } catch (e) {
      debugPrint('[LyricsController] Failed to generate timeline: $e');
      return '生成时间轴时发生错误：$e';
    }
  }

  Future<String?> generateLyricsForCurrentSong() async {
    final song = _context.currentMusic();
    if (song == null) {
      debugPrint('[LyricsController] generate lyrics skipped: no current song');
      return '没有可用的当前歌曲。';
    }

    return _context.lyricsAiTaskQueue.enqueue(() {
      return _generateLyricsForSong(song);
    });
  }

  Future<String?> generateTimelineForCurrentSong() async {
    final song = _context.currentMusic();
    if (song == null) {
      debugPrint(
        '[LyricsController] generate timeline skipped: no current song',
      );
      return '没有可用的当前歌曲。';
    }

    return _context.lyricsAiTaskQueue.enqueue(() {
      final activeSong = _support.songForPath(song.path) ?? song;
      return _generateTimelineForSong(activeSong);
    });
  }

  Future<String?> regenerateLyricsForCurrentSong() async {
    final song = _context.currentMusic();
    if (song == null) {
      debugPrint(
        '[LyricsController] regenerate lyrics skipped: no current song',
      );
      return '没有可用的当前歌曲。';
    }

    _support.clearLyricsStateForPath(song.path);
    return _context.lyricsAiTaskQueue.enqueue(() {
      return _generateLyricsForSong(_support.songForPath(song.path) ?? song);
    });
  }

  Future<void> _saveGeneratedLyricsToDatabase({
    required MusicFile song,
    required String generatedLyrics,
    required List<LyricLine> syncedLines,
    LyricsCacheSource source = LyricsCacheSource.aiGenerate,
  }) async {
    try {
      final duration = await _support.resolveLyricsDuration(song);
      final query = LyricsQuery(
        filePath: song.path,
        fileName: song.name,
        title: _support.lyricsTitleForQuery(song),
        artist: _support.lyricsArtistForQuery(song),
        album: _support.lyricsAlbumForQuery(song),
        duration: duration,
      );
      final record = LyricsCacheRecord(
        cacheKey: query.cacheKey,
        source: source,
        isSynced: syncedLines.any((line) => line.isTimed),
        syncedLyrics: syncedLines.any((line) => line.isTimed)
            ? generatedLyrics
            : null,
        syncedLines: syncedLines,
        timelineOffsetMillis: song.lyrics?.timelineOffset.inMilliseconds ?? 0,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await _context.lyricsCacheRepository.saveLyricsCache(record);
    } catch (e) {
      debugPrint('[LyricsController] Failed to cache generated lyrics: $e');
    }
  }

  List<LyricLine> _parseGeneratedLyrics(String? lyrics) {
    return LrcUtils.parseTimedLyrics(lyrics);
  }

  String _timelineSourceLyricsForSong(MusicFile song) {
    final lyrics = song.lyrics;
    if (lyrics != null && lyrics.plainText.trim().isNotEmpty) {
      return lyrics.plainText.trim();
    }

    return _context.getState().currentLyricsText.trim();
  }
}
