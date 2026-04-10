import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/lyric_line.dart';
import '../models/music_file.dart';
import '../models/music_lyric.dart';
import '../models/music_lyric_translation.dart';
import '../utils/lrc_utils.dart';
import '../utils/lyrics_id_utils.dart';
import '../utils/language_code_utils.dart';
import 'gemini_lyrics_service.dart';
import 'lyrics_cache_repository.dart';
import 'lyrics_generation_phase.dart';
import 'lyrics_service.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';

typedef _GeminiGenerationInvoker =
    Future<String?> Function({
      required void Function(double progress) onUploadProgress,
      required void Function(String stage) onStageChanged,
      required void Function(String partialText, bool isFinal) onProgress,
    });

class _GeminiGenerationSession {
  _GeminiGenerationSession({required this.id, required this.songPath});

  final int id;
  final String songPath;
}

class _LyricsTranslationRequest {
  _LyricsTranslationRequest({
    required this.songPath,
    required this.cacheKey,
    required this.languageCode,
    required this.sourceLyrics,
    required this.lyricsId,
    required this.translationKey,
  });

  final String songPath;
  final String cacheKey;
  final String languageCode;
  final String sourceLyrics;
  final String lyricsId;
  final String translationKey;
}

class _GeminiGenerationRuntime {
  int serial = 0;
  Completer<void>? completer;
  LyricsGenerationPhase phase = LyricsGenerationPhase.idle;
  double progress = 0.0;

  bool get isGenerating => completer != null;

  void start() {
    serial++;
    completer = Completer<void>();
    phase = LyricsGenerationPhase.uploading;
    progress = 0.0;
  }

  void setPhaseFromStage(String stage) {
    switch (stage) {
      case 'uploading':
        phase = LyricsGenerationPhase.uploading;
        progress = 0.0;
        break;
      case 'processing':
        phase = LyricsGenerationPhase.processing;
        progress = 1.0;
        break;
      case 'generating':
        phase = LyricsGenerationPhase.generating;
        progress = 1.0;
        break;
      default:
        phase = LyricsGenerationPhase.idle;
        progress = 0.0;
        break;
    }
  }

  void setUploadProgress(double value) {
    phase = LyricsGenerationPhase.uploading;
    progress = value.clamp(0.0, 1.0);
  }

  void finish() {
    phase = LyricsGenerationPhase.idle;
    progress = 0.0;
    final currentCompleter = completer;
    if (currentCompleter != null && !currentCompleter.isCompleted) {
      currentCompleter.complete();
    }
    completer = null;
  }
}

class LyricsController extends ChangeNotifier {
  LyricsController({
    required MetadataDatabase db,
    required MusicFile? Function() currentMusic,
    required List<MusicFile> Function() queue,
    required int Function() currentIndex,
    required Duration Function() playerDuration,
    required bool Function() isLyricsActive,
    required void Function(String path, int durationMillis) cacheSongDuration,
    LyricsCacheRepository? lyricsCacheRepository,
    LyricsService? lyricsService,
    GeminiLyricsService? geminiLyricsService,
  }) : _db = db,
       _currentMusic = currentMusic,
       _queue = queue,
       _currentIndex = currentIndex,
       _playerDuration = playerDuration,
       _isLyricsActive = isLyricsActive,
       _cacheSongDuration = cacheSongDuration,
       _lyricsCacheRepository =
           lyricsCacheRepository ?? LyricsCacheRepository(db: db),
       _lyricsService =
           lyricsService ??
           LyricsService(
             db: db,
             cacheRepository:
                 lyricsCacheRepository ?? LyricsCacheRepository(db: db),
           ),
       _geminiLyricsService = geminiLyricsService ?? GeminiLyricsService();

  final MetadataDatabase _db;
  final MusicFile? Function() _currentMusic;
  final List<MusicFile> Function() _queue;
  final int Function() _currentIndex;
  final Duration Function() _playerDuration;
  final bool Function() _isLyricsActive;
  final void Function(String path, int durationMillis) _cacheSongDuration;
  final LyricsCacheRepository _lyricsCacheRepository;
  final LyricsService _lyricsService;
  final GeminiLyricsService _geminiLyricsService;

  int _lyricsRequestSerial = 0;
  final Set<String> _translatedLyricsKeys = <String>{};
  final Set<String> _translationInFlightKeys = <String>{};
  int _lyricsRetrySerial = 0;
  bool _isLyricsLoading = false;
  bool _isLyricsTranslating = false;
  String _lyricsTranslationStatus = '';
  bool _hasLyrics = false;
  bool _lyricsSearchAttempted = false;
  bool _isLyricsSynced = false;
  final _GeminiGenerationRuntime _geminiGeneration = _GeminiGenerationRuntime();
  List<LyricLine> _currentLyricsLines = const [];
  String _currentLyricsText = '';
  String? _currentLyricsTitle;
  String _lyricsTranslationLanguageCode =
      LanguageCodeUtils.currentSystemLanguageCode();

  bool get isLyricsLoading => _isLyricsLoading;
  bool get isLyricsTranslating => _isLyricsTranslating;
  bool get isLyricsGenerating => _geminiGeneration.isGenerating;
  String get lyricsTranslationStatus => _lyricsTranslationStatus;
  LyricsGenerationPhase get lyricsGenerationPhase => _geminiGeneration.phase;
  double get lyricsGenerationProgress => _geminiGeneration.progress;
  bool get hasLyrics => _hasLyrics;
  bool get lyricsSearchAttempted => _lyricsSearchAttempted;
  bool get isLyricsSynced => _isLyricsSynced;
  List<LyricLine> get currentLyricsLines =>
      List<LyricLine>.unmodifiable(_currentLyricsLines);
  String get currentLyricsText => _currentLyricsText;
  String? get currentLyricsTitle => _currentLyricsTitle;
  String get lyricsTranslationLanguageCode => _lyricsTranslationLanguageCode;

  void setTranslationLanguageCode(String languageCode) {
    final normalized = LanguageCodeUtils.normalizeLanguageCode(languageCode);
    if (normalized.isEmpty || normalized == _lyricsTranslationLanguageCode) {
      return;
    }
    _lyricsTranslationLanguageCode = normalized;
    notifyListeners();
  }

  void clearState({bool notify = false}) {
    _isLyricsLoading = false;
    _isLyricsTranslating = false;
    _geminiGeneration.phase = LyricsGenerationPhase.idle;
    _geminiGeneration.progress = 0.0;
    _hasLyrics = false;
    _isLyricsSynced = false;
    _currentLyricsLines = const [];
    _currentLyricsText = '';
    _currentLyricsTitle = null;
    _lyricsSearchAttempted = false;
    if (notify) {
      notifyListeners();
    }
  }

  void restoreFromSongLyrics(MusicFile song) {
    final songLyrics = song.lyrics;
    if (songLyrics == null) {
      clearState();
      return;
    }

    _hasLyrics = true;
    _isLyricsLoading = false;
    _isLyricsSynced = songLyrics.isSynced;
    _currentLyricsLines = songLyrics.syncedLines;
    _currentLyricsText = songLyrics.plainText;
    _currentLyricsTitle = song.displayName;
    _lyricsSearchAttempted = true;
    unawaited(restoreCachedTranslations(song));
    _logDebug(
      'lyrics restored from cache -> title="${song.displayName}" '
      'lines=${songLyrics.syncedLines.length} synced=${songLyrics.isSynced}',
    );
  }

  void scheduleFetch(MusicFile song) {
    unawaited(fetchAndLog(song));
    unawaited(retryFetchUntilReady(song));
  }

  Future<void> fetchAndLog(MusicFile song) async {
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
    notifyListeners();

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
      _isLyricsSynced = result?.isSynced ?? false;
      _currentLyricsLines = _buildLyricsLines(
        result?.syncedLines ?? const [],
        result?.lyricsText ?? '',
      );
      _currentLyricsText = result?.lyricsText ?? '';
      final title = result?.track.displayTitle.trim();
      _currentLyricsTitle = (title != null && title.isNotEmpty)
          ? title
          : _currentMusic()?.displayName;

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
          ),
        ),
      );
      if (updated != null) {
        unawaited(restoreCachedTranslations(updated));
      }

      notifyListeners();
      _lyricsService.debugPrintSelection(query, result);
    } catch (e) {
      debugPrint('[LyricsController] Failed to fetch lyrics: $e');
      if (requestId == _lyricsRequestSerial &&
          _currentMusic()?.path == song.path) {
        _isLyricsLoading = false;
        _lyricsSearchAttempted = true;
        notifyListeners();
      }
    }
  }

  Future<void> retryFetchUntilReady(MusicFile song) async {
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

  Future<void> translateLyricsForCurrentSong({
    String? targetLanguageCode,
  }) async {
    final song = _currentMusic();
    if (song == null || _isLyricsTranslating) return;

    final normalizedLanguageCode = LanguageCodeUtils.normalizeLanguageCode(
      targetLanguageCode ?? _lyricsTranslationLanguageCode,
    );
    if (normalizedLanguageCode.isEmpty) return;
    if (_lyricsTranslationLanguageCode != normalizedLanguageCode) {
      _lyricsTranslationLanguageCode = normalizedLanguageCode;
      notifyListeners();
    }

    if (_geminiGeneration.isGenerating && _currentMusic()?.path == song.path) {
      _isLyricsTranslating = true;
      _lyricsTranslationStatus = '等待歌词生成完毕';
      notifyListeners();
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
      notifyListeners();
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
    _lyricsTranslationStatus = '正在处理';
    notifyListeners();

    try {
      final success = await _geminiLyricsService.translateLyricsStream(
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
    _geminiGeneration.phase = LyricsGenerationPhase.idle;
    _geminiGeneration.progress = 0.0;
    _isLyricsSynced = false;
    _lyricsSearchAttempted = false;
    _currentLyricsLines = const [];
    _currentLyricsText = '';
    _currentLyricsTitle = _currentMusic()?.displayName;

    notifyListeners();

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
    notifyListeners();
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
    notifyListeners();
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

    notifyListeners();
  }

  _GeminiGenerationSession _beginGeminiGeneration(MusicFile song) {
    _geminiGeneration.start();
    _isLyricsLoading = false;
    notifyListeners();

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

    _geminiGeneration.setPhaseFromStage(stage);
    notifyListeners();
  }

  MusicLyric _buildGeneratedLyrics({
    required String text,
    required String source,
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
    _geminiGeneration.phase = LyricsGenerationPhase.generating;
    _geminiGeneration.progress = 1.0;
    _isLyricsSynced = lyrics.syncedLines.any((line) => line.isTimed);
    _lyricsSearchAttempted = true;
    _currentLyricsLines = lyrics.syncedLines;
    _currentLyricsText = lyrics.plainText;
    _currentLyricsTitle = song.displayName;

    final updated = _replaceCurrentSongIfPath(
      song.path,
      (currentSong) => currentSong.copyWith(lyrics: lyrics),
    );
    if (updated != null) {
      unawaited(restoreCachedTranslations(updated));
    }

    notifyListeners();
  }

  void _finalizeGeminiGeneration(_GeminiGenerationSession session) {
    if (session.id != _geminiGeneration.serial) return;

    _geminiGeneration.finish();
    notifyListeners();
  }

  Future<void> _runGeminiGeneration({
    required MusicFile song,
    required String databaseSource,
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

          _geminiGeneration.setUploadProgress(progress);
          notifyListeners();
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
        databaseSource: 'gemini_generate',
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
        databaseSource: 'gemini_timeline',
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

      notifyListeners();
    } catch (e) {
      debugPrint('[LyricsController] Failed to restore translated lyrics: $e');
    }
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
    notifyListeners();
  }

  Future<void> _waitForLyricsGenerationToFinish(String songPath) async {
    while (_geminiGeneration.isGenerating &&
        _currentMusic()?.path == songPath) {
      final completer = _geminiGeneration.completer;
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

  String _lyricsSourceTextFromLyrics(MusicLyric lyrics) {
    if (lyrics.syncedLines.isNotEmpty) {
      return lyrics.syncedLines.map((line) => line.text).join('\n').trim();
    }
    return LrcUtils.stripTimestamps(lyrics.plainText).trim();
  }

  String _lyricsTextWithTimestamps(MusicLyric lyrics) {
    if (lyrics.syncedLines.isEmpty) {
      return lyrics.plainText.trim();
    }

    return lyrics.syncedLines
        .map((line) {
          if (!line.isTimed) return line.text.trimRight();
          return '[${_formatTimestamp(line.timestamp)}] ${line.text}';
        })
        .join('\n')
        .trim();
  }

  String _lyricsIdForSong(MusicFile song, {String? sourceLyrics}) {
    final existingId = song.lyrics?.id.trim() ?? '';
    if (existingId.isNotEmpty) return existingId;

    final text =
        (sourceLyrics ??
                _lyricsSourceTextFromLyrics(song.lyrics ?? const MusicLyric()))
            .trim();
    if (text.isEmpty) return '';
    return LyricsIdUtils.fromLyricsText(text);
  }

  String _formatTimestamp(Duration duration) {
    final totalMilliseconds = duration.inMilliseconds;
    final minutes = totalMilliseconds ~/ 60000;
    final seconds = (totalMilliseconds % 60000) ~/ 1000;
    final centiseconds = (totalMilliseconds % 1000) ~/ 10;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${centiseconds.toString().padLeft(2, '0')}';
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
      provider: 'gemini',
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _saveGeneratedLyricsToDatabase({
    required MusicFile song,
    required String generatedLyrics,
    required List<LyricLine> syncedLines,
    String source = 'gemini_generate',
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
        syncedLines: syncedLines.map((line) => line.toJson()).toList(),
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

  String _lyricsTranslationCacheKey(String cacheKey, String languageCode) {
    return '$cacheKey|$languageCode';
  }

  Future<String> _lyricsCacheKeyForSong(MusicFile song) async {
    final query = await _buildLyricsQueryForSong(song);
    return query?.cacheKey ?? '';
  }

  void _clearLyricsStateForPath(String path) {
    final queue = _queue();
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].path != path) continue;
      if (queue[i].lyrics == null) continue;
      queue[i] = _copySongWithLyrics(queue[i], null);
    }

    clearState();
  }

  void _clearTranslationStateForPath(String path) {
    final queue = _queue();
    for (var i = 0; i < queue.length; i++) {
      final queuedSong = queue[i];
      if (queuedSong.path != path) continue;
      final lyrics = queuedSong.lyrics;
      if (lyrics == null || lyrics.translations.isEmpty) continue;
      queue[i] = queuedSong.copyWith(
        lyrics: lyrics.copyWith(
          translations: const <String, MusicLyricTranslation>{},
        ),
      );
    }
  }

  Future<LyricsQuery?> _buildLyricsQueryForSong(MusicFile song) async {
    final duration = await _resolveLyricsDuration(song);
    if (duration == null) {
      _logDebug(
        'lyrics query build failed -> title="${song.displayName}" '
        'path="${song.path}" reason=no_duration '
        'songDuration=${song.durationMillis} playerDuration=${_playerDuration()}',
      );
      return null;
    }

    return LyricsQuery(
      filePath: song.path,
      fileName: song.name,
      title: _lyricsTitleForQuery(song),
      artist: _lyricsArtistForQuery(song),
      album: _lyricsAlbumForQuery(song),
      duration: duration,
    );
  }

  List<LyricLine> _buildLyricsLines(
    List<LyricLine> syncedLines,
    String fallbackPlainLyrics,
  ) {
    if (syncedLines.isNotEmpty) {
      return syncedLines;
    }

    if (fallbackPlainLyrics.trim().isEmpty) {
      return const [];
    }

    final lines = fallbackPlainLyrics.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return const [];

    return lines
        .map(
          (line) =>
              LyricLine(timestamp: Duration.zero, text: line, isTimed: false),
        )
        .toList(growable: false);
  }

  String _lyricsTitleForQuery(MusicFile song) {
    final displayName = song.displayName.trim();
    return displayName.isNotEmpty ? displayName : song.name.trim();
  }

  Duration? _lyricsDurationForQuery(MusicFile song) {
    final durationMillis = song.durationMillis;
    if (durationMillis != null && durationMillis > 0) {
      return Duration(milliseconds: durationMillis);
    }
    return null;
  }

  Future<Duration?> _resolveLyricsDuration(MusicFile song) async {
    final direct = _lyricsDurationForQuery(song);
    if (direct != null &&
        song.durationMillis != null &&
        song.durationMillis! > 0) {
      return direct;
    }

    final dbMetadata = await _db.getSongMetadata(song.path);
    final dbDuration = dbMetadata?.duration;
    if (dbDuration != null && dbDuration > 0) {
      _cacheSongDuration(song.path, dbDuration);
      return Duration(milliseconds: dbDuration);
    }

    final fileMetadata = await MetadataHelper.readMetadataFromFile(song.path);
    final fileDuration = fileMetadata?.duration;
    if (fileDuration != null && fileDuration > 0) {
      _cacheSongDuration(song.path, fileDuration);
      return Duration(milliseconds: fileDuration);
    }

    final playerDuration = _playerDuration();
    if (playerDuration > Duration.zero) {
      return playerDuration;
    }

    return direct;
  }

  String? _lyricsArtistForQuery(MusicFile song) {
    return _normalizedLyricsField(song.artist);
  }

  String? _lyricsAlbumForQuery(MusicFile song) {
    return _normalizedLyricsField(song.album);
  }

  String? _normalizedLyricsField(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }

    final lower = text.toLowerCase();
    if (lower == 'unknown' ||
        lower == 'unknown artist' ||
        lower == 'unknown album') {
      return null;
    }

    return text;
  }

  MusicFile? _replaceCurrentSongIfPath(
    String path,
    MusicFile Function(MusicFile song) update,
  ) {
    final index = _currentIndex();
    final queue = _queue();
    if (index < 0 || index >= queue.length) return null;

    final currentSong = queue[index];
    if (currentSong.path != path) return null;

    final updatedSong = update(currentSong);
    if (updatedSong == currentSong) return updatedSong;
    queue[index] = updatedSong;
    return updatedSong;
  }

  MusicFile _copySongWithLyrics(MusicFile song, MusicLyric? lyrics) {
    return MusicFile(
      path: song.path,
      name: song.name,
      title: song.title,
      artist: song.artist,
      album: song.album,
      trackNumber: song.trackNumber,
      id: song.id,
      mediaUri: song.mediaUri,
      thumbnailPath: song.thumbnailPath,
      artworkPath: song.artworkPath,
      artworkWidth: song.artworkWidth,
      artworkHeight: song.artworkHeight,
      durationMillis: song.durationMillis,
      themeColorsBlob: song.themeColorsBlob,
      waveformBlob: song.waveformBlob,
      artworkBytes: song.artworkBytes,
      lastModifiedTime: song.lastModifiedTime,
      lyrics: lyrics,
    );
  }

  void _logDebug(String message) {
    if (!kDebugMode) return;
    debugPrint('[AudioService][Lyrics] $message');
  }
}
