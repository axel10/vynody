part of 'lyrics_controller.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

extension LyricsControllerGeneration on LyricsController {
  _GeminiGenerationSession _beginGeminiGeneration(MusicFile song) {
    _geminiGeneration.start();
    _isLyricsLoading = false;
    _setLyricsGenerating(
      true,
      phase: LyricsGenerationPhase.uploading,
      progress: 0.0,
    );

    return _GeminiGenerationSession(
      id: _geminiGeneration.serial,
      songPath: song.path,
    );
  }

  bool _isActiveGeminiGeneration(_GeminiGenerationSession session) {
    return session.id == _geminiGeneration.serial &&
        _currentMusic()?.path == session.songPath;
  }

  void _updateGeminiGenerationStage(
    _GeminiGenerationSession session,
    String stage,
  ) {
    if (!_isActiveGeminiGeneration(session)) return;

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
    _GeminiGenerationSession session, {
    required MusicFile song,
    required MusicLyric lyrics,
  }) {
    if (!_isActiveGeminiGeneration(session)) return;

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

  void _finalizeGeminiGeneration(_GeminiGenerationSession session) {
    if (session.id != _geminiGeneration.serial) return;

    _geminiGeneration.finish();
    _setLyricsGenerating(
      false,
      phase: LyricsGenerationPhase.idle,
      progress: 0.0,
    );
  }

  Future<void> _runGeminiGeneration({
    required MusicFile song,
    required LyricsCacheSource databaseSource,
    required _GeminiGenerationInvoker invoke,
    Map<String, MusicLyricTranslation> Function()? translationProvider,
  }) async {
    final session = _beginGeminiGeneration(song);
    try {
      final generatedText = await invoke(
        onUploadProgress: (progress) {
          if (!_isActiveGeminiGeneration(session)) {
            return;
          }

          _setLyricsGenerating(
            true,
            phase: LyricsGenerationPhase.uploading,
            progress: progress.clamp(0.0, 1.0),
          );
        },
        onStageChanged: (stage) {
          _updateGeminiGenerationStage(session, stage);
        },
        onProgress: (partialText, isFinal) {
          if (!_isActiveGeminiGeneration(session)) {
            return;
          }

          final progressText = partialText.trim();
          if (progressText.isEmpty) return;
          final progressLyrics = _buildGeneratedLyrics(
            text: progressText,
            source: 'gemini',
            timelineOffset: song.lyrics?.timelineOffset ?? Duration.zero,
            translations:
                translationProvider?.call() ??
                const <String, MusicLyricTranslation>{},
          );
          _publishGeneratedLyrics(session, song: song, lyrics: progressLyrics);
        },
      );

      if (!_isActiveGeminiGeneration(session)) {
        return;
      }

      if (generatedText == null || generatedText.trim().isEmpty) {
        return;
      }

      final lyrics = _buildGeneratedLyrics(
        text: generatedText,
        source: 'gemini',
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
    } finally {
      _finalizeGeminiGeneration(session);
    }
  }

  Future<void> generateLyricsForCurrentSong() async {
    final song = _currentMusic();
    if (song == null) {
      debugPrint('[LyricsController] generate lyrics skipped: no current song');
      return;
    }
    if (_geminiGeneration.isGenerating) {
      debugPrint(
        '[LyricsController] generate lyrics skipped: already generating '
        'path=${song.path}',
      );
      return;
    }

    try {
      await _runGeminiGeneration(
        song: song,
        databaseSource: LyricsCacheSource.geminiGenerate,
        invoke:
            ({
              required onUploadProgress,
              required onStageChanged,
              required onProgress,
            }) {
              return _geminiLyricsService.generateLyricsFromFile(
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
    }
  }

  Future<void> generateTimelineForCurrentSong() async {
    final song = _currentMusic();
    if (song == null) {
      debugPrint(
        '[LyricsController] generate timeline skipped: no current song',
      );
      return;
    }
    if (_geminiGeneration.isGenerating) {
      debugPrint(
        '[LyricsController] generate timeline skipped: already generating '
        'path=${song.path}',
      );
      return;
    }

    final sourceLyrics = _timelineSourceLyricsForSong(song).trim();
    if (sourceLyrics.isEmpty) {
      debugPrint(
        '[LyricsController] generate timeline skipped: no usable lyrics '
        'path=${song.path}',
      );
      return;
    }

    try {
      await _runGeminiGeneration(
        song: song,
        databaseSource: LyricsCacheSource.geminiTimeline,
        translationProvider: () =>
            _currentMusic()?.lyrics?.translations ??
            const <String, MusicLyricTranslation>{},
        invoke:
            ({
              required onUploadProgress,
              required onStageChanged,
              required onProgress,
            }) {
              return _geminiLyricsService.generateTimelineFromLyrics(
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
    }
  }

  Future<void> regenerateLyricsForCurrentSong() async {
    final song = _currentMusic();
    if (song == null) {
      debugPrint(
        '[LyricsController] regenerate lyrics skipped: no current song',
      );
      return;
    }

    await clearLyricsCacheForCurrentSong();
    if (_currentMusic()?.path != song.path) {
      return;
    }

    await generateLyricsForCurrentSong();
  }

  Future<void> _saveGeneratedLyricsToDatabase({
    required MusicFile song,
    required String generatedLyrics,
    required List<LyricLine> syncedLines,
    LyricsCacheSource source = LyricsCacheSource.geminiGenerate,
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
