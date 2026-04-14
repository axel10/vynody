part of 'lyrics_controller.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

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

class _LyricsGenerationRuntime {
  int serial = 0;
  Completer<void>? completer;

  bool get isGenerating => completer != null;

  void start() {
    serial++;
    completer = Completer<void>();
  }

  void finish() {
    final currentCompleter = completer;
    if (currentCompleter != null && !currentCompleter.isCompleted) {
      currentCompleter.complete();
    }
    completer = null;
  }
}

extension LyricsControllerGeneration on LyricsController {
  _LyricsGenerationSession _beginLyricsGeneration(
    MusicFile song, {
    required String statusLabel,
  }) {
    // 生成流程开始后，先让任何尚未完成的 lrclib 拉取失效，
    // 避免它们在 AI 结果出来后“晚到覆盖”当前歌词。
    _cancelOngoingLyricsFetch(reason: 'lyrics generation started');
    _lyricsGeneration.start();
    _lyricsSearchAttempted = true;
    _startLyricsGenerationStatus(statusLabel);
    _setLyricsGenerating(
      true,
      phase: LyricsGenerationPhase.uploading,
      progress: 0.0,
    );

    return _LyricsGenerationSession(
      id: _lyricsGeneration.serial,
      songPath: song.path,
    );
  }

  bool _isActiveLyricsGeneration(_LyricsGenerationSession session) {
    return session.id == _lyricsGeneration.serial &&
        _currentMusic()?.path == session.songPath;
  }

  void _updateLyricsGenerationStage(
    _LyricsGenerationSession session,
    String stage,
  ) {
    if (!_isActiveLyricsGeneration(session)) return;

    _setGenerationStage(stage);
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
          : _buildLyricsLines(const [], normalizedText),
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

    _hasLyrics = true;
    _isLyricsLoading = false;
    _setLyricsGenerating(
      true,
      phase: LyricsGenerationPhase.generating,
      progress: 1.0,
    );
    _lyricsSearchAttempted = true;
    _currentLyricsLines = lyrics.syncedLines;
    _currentLyricsText = lyrics.plainText;

    final updated = _replaceCurrentSongIfPath(
      song.path,
      (currentSong) => currentSong.copyWith(lyrics: lyrics),
    );
    if (updated != null) {
      unawaited(restoreCachedTranslations(updated));
    }

    _bumpRevision();
  }

  void _finalizeLyricsGeneration(_LyricsGenerationSession session) {
    if (session.id != _lyricsGeneration.serial) return;

    _lyricsGeneration.finish();
    _setLyricsGenerating(
      false,
      phase: LyricsGenerationPhase.idle,
      progress: 0.0,
    );
    _clearLyricsGenerationStatus();
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

          _setLyricsGenerating(
            true,
            phase: LyricsGenerationPhase.uploading,
            progress: progress.clamp(0.0, 1.0),
          );
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
            source: _lyricsProviderTag(),
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
        source: _lyricsProviderTag(),
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

  Future<String?> generateLyricsForCurrentSong() async {
    final song = _currentMusic();
    if (song == null) {
      debugPrint('[LyricsController] generate lyrics skipped: no current song');
      return '没有可用的当前歌曲。';
    }
    if (_lyricsGeneration.isGenerating) {
      debugPrint(
        '[LyricsController] generate lyrics skipped: already generating '
        'path=${song.path}',
      );
      return '歌词正在生成中，请稍后再试。';
    }

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
              return _lyricsAiService.generateLyricsFromFile(
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

  Future<String?> generateTimelineForCurrentSong() async {
    final song = _currentMusic();
    if (song == null) {
      debugPrint(
        '[LyricsController] generate timeline skipped: no current song',
      );
      return '没有可用的当前歌曲。';
    }
    if (_lyricsGeneration.isGenerating) {
      debugPrint(
        '[LyricsController] generate timeline skipped: already generating '
        'path=${song.path}',
      );
      return '歌词正在生成中，请稍后再试。';
    }

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
            _currentMusic()?.lyrics?.translations ??
            const <String, MusicLyricTranslation>{},
        invoke:
            ({
              required onUploadProgress,
              required onStageChanged,
              required onProgress,
            }) {
              return _lyricsAiService.generateTimelineFromLyrics(
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

  Future<String?> regenerateLyricsForCurrentSong() async {
    final song = _currentMusic();
    if (song == null) {
      debugPrint(
        '[LyricsController] regenerate lyrics skipped: no current song',
      );
      return '没有可用的当前歌曲。';
    }

    await clearLyricsCacheForCurrentSong();
    if (_currentMusic()?.path != song.path) {
      return '当前歌曲已切换，重新生成已取消。';
    }

    return generateLyricsForCurrentSong();
  }

  Future<void> _saveGeneratedLyricsToDatabase({
    required MusicFile song,
    required String generatedLyrics,
    required List<LyricLine> syncedLines,
    LyricsCacheSource source = LyricsCacheSource.aiGenerate,
  }) async {
    try {
      final duration = await _resolveLyricsDuration(song);
      final query = LyricsQuery(
        filePath: song.path,
        fileName: song.name,
        title: _lyricsTitleForQuery(song),
        artist: _lyricsArtistForQuery(song),
        album: _lyricsAlbumForQuery(song),
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
      await _lyricsCacheRepository.saveLyricsCache(record);
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
      // 保留原始 LRC 文本，让“重新生成时间轴”有机会基于现有时间戳修正，
      // 而不是把已有时间轴先清掉再重打一次。
      return lyrics.plainText.trim();
    }

    return _currentLyricsText.trim();
  }
}
