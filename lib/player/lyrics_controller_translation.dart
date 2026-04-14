part of 'lyrics_controller.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

extension LyricsControllerTranslation on LyricsController {
  Future<void> translateLyricsForCurrentSong({
    String? targetLanguageCode,
  }) async {
    final song = _currentMusic();
    if (song == null || _isLyricsTranslating) return;

    final normalizedLanguageCode = LanguageCodeUtils.normalizeLanguageCode(
      targetLanguageCode ?? state.lyricsTranslationLanguageCode,
    );
    if (normalizedLanguageCode.isEmpty) return;
    if (state.lyricsTranslationLanguageCode != normalizedLanguageCode) {
      state = state.copyWith(
        lyricsTranslationLanguageCode: normalizedLanguageCode,
      );
    }

    if (_lyricsGeneration.isGenerating && _currentMusic()?.path == song.path) {
      _isLyricsTranslating = true;
      _lyricsTranslationStatus = '正在翻译歌词';
      await _waitForLyricsGenerationToFinish(song.path);
    }

    try {
      final currentSong = _currentMusic();
      if (currentSong == null || currentSong.path != song.path) return;

      final sourceLyrics = _lyricsSourceForTranslation(currentSong);
      if (sourceLyrics.isEmpty) return;

      final request = await _buildLyricsTranslationRequest(
        currentSong,
        normalizedLanguageCode: normalizedLanguageCode,
        sourceLyrics: sourceLyrics,
      );
      if (request == null) return;

      await _runLyricsTranslationRequest(request);
    } finally {
      _isLyricsTranslating = false;
      _lyricsTranslationStatus = '';
    }
  }

  Future<_LyricsTranslationRequest?> _buildLyricsTranslationRequest(
    MusicFile song, {
    required String normalizedLanguageCode,
    required String sourceLyrics,
  }) async {
    final query = await _buildLyricsQueryForSong(song);
    if (query == null) return null;

    final lyricsId = _lyricsIdForSong(song, sourceLyrics: sourceLyrics);
    if (lyricsId.isEmpty) return null;

    final translationKey = _lyricsTranslationCacheKey(
      query.cacheKey,
      normalizedLanguageCode,
    );

    final currentLyrics = song.lyrics;
    if (currentLyrics != null && !currentLyrics.hasId) {
      _replaceCurrentSongIfPath(
        song.path,
        (queueSong) =>
            queueSong.copyWith(lyrics: currentLyrics.copyWith(id: lyricsId)),
      );
    }

    if (_translationInFlightKeys.contains(translationKey)) return null;
    if (currentLyrics?.translationFor(normalizedLanguageCode)?.hasContent ==
        true) {
      return null;
    }
    if (_translatedLyricsKeys.contains(translationKey)) return null;

    return _LyricsTranslationRequest(
      songPath: song.path,
      cacheKey: query.cacheKey,
      languageCode: normalizedLanguageCode,
      sourceLyrics: sourceLyrics,
      lyricsId: lyricsId,
      translationKey: translationKey,
    );
  }

  Future<void> _runLyricsTranslationRequest(
    _LyricsTranslationRequest request,
  ) async {
    if (_translationInFlightKeys.contains(request.translationKey)) return;

    _translationInFlightKeys.add(request.translationKey);
    _isLyricsTranslating = true;
    _lyricsTranslationStatus = '正在翻译歌词';

    try {
      final success = await _lyricsAiService.translateLyricsStream(
        lyrics: request.sourceLyrics,
        targetLanguageCode: request.languageCode,
        onProgress: (translatedLines, translatedText) {
          _syncTranslatedLyricsToCurrentSong(
            request.songPath,
            request.lyricsId,
            request.languageCode,
            translatedLines,
            translatedText,
          );
        },
      );
      if (success) {
        _translatedLyricsKeys.add(request.translationKey);
        await _saveTranslatedLyricsToDatabase(
          songPath: request.songPath,
          cacheKey: request.cacheKey,
          languageCode: request.languageCode,
        );
      }
    } finally {
      _translationInFlightKeys.remove(request.translationKey);
    }
  }

  String _lyricsSourceForTranslation(MusicFile song) {
    final lyrics = song.lyrics;
    if (lyrics?.syncedLines.isNotEmpty == true) {
      return _lyricsTextWithTimestamps(lyrics!);
    }
    return _currentLyricsText.trim();
  }

  void _syncTranslatedLyricsToCurrentSong(
    String songPath,
    String lyricsId,
    String languageCode,
    List<String> translatedLines,
    String translatedText,
  ) {
    MusicFile? updatedSong;
    _replaceCurrentSongIfPath(songPath, (currentSong) {
      final existingLyrics = currentSong.lyrics ?? const MusicLyric();
      final existingTranslation = existingLyrics.translationFor(languageCode);
      final updatedTranslation = _buildLyricsTranslation(
        languageCode: languageCode,
        translatedLines: translatedLines,
        translatedText: translatedText,
      );
      if (existingTranslation == updatedTranslation) {
        updatedSong = currentSong;
        return currentSong;
      }

      final updatedTranslations = Map<String, MusicLyricTranslation>.from(
        existingLyrics.translations,
      )..[languageCode] = updatedTranslation;

      updatedSong = currentSong.copyWith(
        lyrics: existingLyrics.copyWith(
          id: lyricsId.isEmpty ? existingLyrics.id : lyricsId,
          translations: updatedTranslations,
        ),
      );
      return updatedSong!;
    });

    if (updatedSong == null) return;
    _bumpRevision();
  }

  Future<void> _waitForLyricsGenerationToFinish(String songPath) async {
    while (_lyricsGeneration.isGenerating &&
        _currentMusic()?.path == songPath) {
      final completer = _lyricsGeneration.completer;
      if (completer == null) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }

      try {
        await completer.future;
      } catch (_) {
        return;
      }
    }
  }

  Future<void> _saveTranslatedLyricsToDatabase({
    required String songPath,
    required String cacheKey,
    required String languageCode,
  }) async {
    try {
      final current = _currentMusic();
      if (current == null || current.path != songPath) return;

      final lyrics = current.lyrics;
      if (lyrics == null) return;

      final translation = lyrics.translationFor(languageCode);
      if (translation == null || !translation.hasContent) return;

      final record = LyricsTranslationCacheRecord(
        cacheKey: cacheKey,
        languageCode: languageCode,
        translatedText: translation.translatedText,
        translatedLines: translation.translatedLines,
        provider: translation.provider,
        updatedAtMillis:
            translation.updatedAt?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
      );
      await _lyricsCacheRepository.saveLyricsTranslationCache(record);
    } catch (e) {
      debugPrint('[LyricsController] Failed to cache translated lyrics: $e');
    }
  }

  MusicLyricTranslation _buildLyricsTranslation({
    required String languageCode,
    required List<String> translatedLines,
    required String translatedText,
  }) {
    final normalizedLines = translatedLines
        .map((line) => line.trim())
        .toList(growable: false);
    return MusicLyricTranslation(
      languageCode: languageCode,
      translatedText: translatedText,
      translatedLines: normalizedLines,
      provider: _translationProviderTag(),
      updatedAt: DateTime.now(),
    );
  }

  String _lyricsTranslationCacheKey(String cacheKey, String languageCode) {
    return '$cacheKey|$languageCode';
  }

  String _translationProviderTag() {
    return LyricsAiProvider.googleAiStudio.storageValue;
  }
}
