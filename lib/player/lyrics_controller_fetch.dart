part of 'lyrics_controller.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

extension LyricsControllerFetch on LyricsController {
  void scheduleFetch(MusicFile song) {
    unawaited(fetchAndLog(song));
    unawaited(retryFetchUntilReady(song));
  }

  Future<void> fetchAndLog(MusicFile song) async {
    if (_geminiGeneration.isGenerating) {
      _logDebug(
        'fetch skipped because Gemini generation is in progress -> '
        'title="${song.displayName}" path="${song.path}"',
      );
      return;
    }

    final queryDuration = await _resolveLyricsDuration(song);
    if (queryDuration == null) {
      _logDebug(
        'fetch skipped, duration not ready -> title="${song.displayName}" '
        'path="${song.path}" playerDuration=${_playerDuration()} '
        'songDuration=${song.durationMillis}',
      );
      _isLyricsLoading = false;
      return;
    }

    final requestId = ++_lyricsRequestSerial;
    final query = LyricsQuery(
      filePath: song.path,
      fileName: song.name,
      title: _lyricsTitleForQuery(song),
      artist: _lyricsArtistForQuery(song),
      album: _lyricsAlbumForQuery(song),
      duration: queryDuration,
    );

    _isLyricsLoading = true;
    _logDebug(
      'fetch start -> title="${song.displayName}" path="${song.path}" '
      'queryDuration=$queryDuration playerDuration=${_playerDuration()} '
      'requestId=$requestId',
    );

    try {
      final result = await _lyricsService.fetchBestLyrics(query: query);
      if (requestId != _lyricsRequestSerial ||
          _currentMusic()?.path != song.path) {
        _logDebug(
          'fetch ignored due to stale request -> title="${song.displayName}" '
          'requestId=$requestId latest=$_lyricsRequestSerial '
          'currentPath="${_currentMusic()?.path}"',
        );
        return;
      }

      _isLyricsLoading = false;
      _lyricsSearchAttempted = true;
      _hasLyrics = result != null && result.track.hasLyrics;
      _currentLyricsLines = _buildLyricsLines(
        result?.syncedLines ?? const [],
        result?.lyricsText ?? '',
      );
      _currentLyricsText = result?.lyricsText ?? '';

      final updated = _replaceCurrentSongIfPath(
        song.path,
        (currentSong) => currentSong.copyWith(
          lyrics: MusicLyric(
            id:
                result?.track.lyricsId ??
                LyricsIdUtils.fromLyricsText(_currentLyricsText),
            syncedLines: _currentLyricsLines,
            plainText: _currentLyricsText,
            source: result?.source ?? 'lrclib',
            timelineOffset:
                result?.timelineOffset ??
                song.lyrics?.timelineOffset ??
                Duration.zero,
          ),
        ),
      );
      if (updated != null) {
        unawaited(restoreCachedTranslations(updated));
      }

      _bumpRevision();
      _lyricsService.debugPrintSelection(query, result);
    } catch (e) {
      debugPrint('[LyricsController] Failed to fetch lyrics: $e');
      if (requestId == _lyricsRequestSerial &&
          _currentMusic()?.path == song.path) {
        _isLyricsLoading = false;
        _lyricsSearchAttempted = true;
      }
    }
  }

  Future<void> retryFetchUntilReady(MusicFile song) async {
    if (_geminiGeneration.isGenerating) {
      return;
    }

    final retryId = ++_lyricsRetrySerial;
    for (var attempt = 0; attempt < 12; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));

      if (retryId != _lyricsRetrySerial) return;
      if (!_isLyricsActive() || _currentMusic()?.path != song.path) {
        return;
      }
      if (_hasLyrics || _isLyricsLoading || _lyricsSearchAttempted) {
        return;
      }

      if (await _resolveLyricsDuration(song) != null) {
        unawaited(fetchAndLog(song));
        return;
      }
    }
  }

  Future<void> clearAllLyricsCache() async {
    await _lyricsCacheRepository.clearAllLyricsCaches();

    final queue = _queue();
    for (var i = 0; i < queue.length; i++) {
      final song = queue[i];
      if (song.lyrics == null) continue;
      queue[i] = _copySongWithLyrics(song, null);
    }

    _translatedLyricsKeys.clear();
    _translationInFlightKeys.clear();
    _lyricsTranslationStatus = '';
    _hasLyrics = false;
    _isLyricsLoading = false;
    _isLyricsTranslating = false;
    _setLyricsGenerating(
      false,
      phase: LyricsGenerationPhase.idle,
      progress: 0.0,
    );
    _lyricsSearchAttempted = false;
    _currentLyricsLines = const [];
    _currentLyricsText = '';
    _bumpRevision();

    final current = _currentMusic();
    if (_isLyricsActive() && current != null) {
      scheduleFetch(current);
    }
  }

  Future<void> clearLyricsCacheForCurrentSong() async {
    final song = _currentMusic();
    if (song == null) return;

    final cacheKey = await _lyricsCacheKeyForSong(song);
    if (cacheKey.isNotEmpty) {
      await _lyricsCacheRepository.clearAllLyricsCachesByKey(cacheKey);
      _translatedLyricsKeys.removeWhere((key) => key.startsWith('$cacheKey|'));
      _translationInFlightKeys.removeWhere(
        (key) => key.startsWith('$cacheKey|'),
      );
    }

    if (_currentMusic()?.path != song.path) return;

    _lyricsRequestSerial++;
    _lyricsRetrySerial++;
    _clearLyricsStateForPath(song.path);
    _lyricsTranslationStatus = '';
    _bumpRevision();
  }

  Future<void> clearTranslationCacheForCurrentSong() async {
    final song = _currentMusic();
    if (song == null) return;

    final cacheKey = await _lyricsCacheKeyForSong(song);
    if (cacheKey.isNotEmpty) {
      await _lyricsCacheRepository.clearLyricsTranslationCacheByKey(cacheKey);
      _translatedLyricsKeys.removeWhere((key) => key.startsWith('$cacheKey|'));
      _translationInFlightKeys.removeWhere(
        (key) => key.startsWith('$cacheKey|'),
      );
    }

    if (_currentMusic()?.path != song.path) return;

    _clearTranslationStateForPath(song.path);
    _lyricsTranslationStatus = '';
    _bumpRevision();
  }

  Future<void> requeryLyricsForCurrentSong() async {
    final song = _currentMusic();
    if (song == null) return;

    await clearLyricsCacheForCurrentSong();
    if (_currentMusic()?.path != song.path) return;
    scheduleFetch(song);
  }

  Future<void> clearTranslationCache() async {
    await _lyricsCacheRepository.clearLyricsTranslationCache();

    _translatedLyricsKeys.clear();
    _translationInFlightKeys.clear();
    _lyricsTranslationStatus = '';

    final queue = _queue();
    for (var i = 0; i < queue.length; i++) {
      final song = queue[i];
      final lyrics = song.lyrics;
      if (lyrics == null || lyrics.translations.isEmpty) continue;

      queue[i] = song.copyWith(
        lyrics: lyrics.copyWith(
          translations: const <String, MusicLyricTranslation>{},
        ),
      );
    }

    _bumpRevision();
  }

  Future<void> restoreCachedTranslations(MusicFile song) async {
    final lyrics = song.lyrics;
    if (lyrics == null) return;

    final query = await _buildLyricsQueryForSong(song);
    if (query == null) return;

    try {
      final cachedTranslations = await _lyricsCacheRepository
          .getLyricsTranslationCaches(query.cacheKey);
      if (cachedTranslations.isEmpty) return;

      final preferredLanguageCode =
          LanguageCodeUtils.currentSystemLanguageCode();
      cachedTranslations.sort((a, b) {
        final aPreferred = a.languageCode == preferredLanguageCode;
        final bPreferred = b.languageCode == preferredLanguageCode;
        if (aPreferred != bPreferred) {
          return aPreferred ? -1 : 1;
        }
        return b.updatedAtMillis.compareTo(a.updatedAtMillis);
      });

      final updatedTranslations = Map<String, MusicLyricTranslation>.from(
        lyrics.translations,
      );
      var changed = false;

      for (final record in cachedTranslations) {
        if (updatedTranslations.containsKey(record.languageCode)) continue;
        final translation = MusicLyricTranslation(
          languageCode: record.languageCode,
          translatedText: record.translatedText,
          translatedLines: record.translatedLines,
          provider: record.provider,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            record.updatedAtMillis,
          ),
        );
        final existing = updatedTranslations[record.languageCode];
        if (existing == translation) continue;
        updatedTranslations[record.languageCode] = translation;
        changed = true;
      }

      if (!changed) return;

      final queue = _queue();
      for (var i = 0; i < queue.length; i++) {
        final queuedSong = queue[i];
        if (queuedSong.path != song.path) continue;
        final queuedLyrics = queuedSong.lyrics;
        if (queuedLyrics == null) continue;
        queue[i] = queuedSong.copyWith(
          lyrics: queuedLyrics.copyWith(translations: updatedTranslations),
        );
      }

      _bumpRevision();
    } catch (e) {
      debugPrint('[LyricsController] Failed to restore translated lyrics: $e');
    }
  }
}
