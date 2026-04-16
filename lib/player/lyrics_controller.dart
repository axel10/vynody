import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyric_line.dart';
import '../models/music_file.dart';
import '../utils/language_code_utils.dart';
import 'audio_riverpod.dart';
import 'lyrics_ai_service.dart';
import 'lyrics_cache_repository.dart';
import 'lyrics_controller_context.dart';
import 'lyrics_controller_fetch.dart';
import 'lyrics_controller_generation.dart';
import 'lyrics_controller_state.dart';
import 'lyrics_controller_translation.dart';
import 'lyrics_controller_utils.dart';
import 'lyrics_riverpod.dart';
import 'lyrics_service.dart';
import 'metadata_database.dart';
import 'lyrics_generation_phase.dart';
import 'lyrics_song_task_state.dart';
import 'settings_service.dart';

class LyricsController extends Notifier<LyricsControllerState> {
  late final MetadataDatabase _db;
  late final MusicFile? Function() _currentMusic;
  late final List<MusicFile> Function() _queue;
  late final int Function() _currentIndex;
  late final Duration Function() _playerDuration;
  late final bool Function() _isLyricsActive;
  late final void Function(String path, int durationMillis) _cacheSongDuration;
  late final LyricsCacheRepository _lyricsCacheRepository;
  late final LyricsService _lyricsService;
  late final LyricsAiService _lyricsAiService;
  late final SettingsService _settingsService;
  late final LyricsControllerContext _context;
  late final LyricsControllerSupport _support;
  late final LyricsFetchCoordinator _fetchCoordinator;
  late final LyricsGenerationCoordinator _generationCoordinator;
  late final LyricsTranslationCoordinator _translationCoordinator;

  @override
  LyricsControllerState build() {
    final dependencies = ref.watch(lyricsControllerDependenciesProvider);
    _db = dependencies.db;
    _currentMusic = dependencies.currentMusic;
    _queue = dependencies.queue;
    _currentIndex = dependencies.currentIndex;
    _playerDuration = dependencies.playerDuration;
    _isLyricsActive = dependencies.isLyricsActive;
    _cacheSongDuration = dependencies.cacheSongDuration;
    _lyricsCacheRepository = LyricsCacheRepository(db: _db);
    _lyricsService = LyricsService(
      db: _db,
      cacheRepository: _lyricsCacheRepository,
    );
    _settingsService = ref.read(settingsServiceProvider);
    _lyricsAiService = ref.read(lyricsAiServiceProvider);
    _context = LyricsControllerContext(
      db: _db,
      currentMusic: _currentMusic,
      queue: _queue,
      currentIndex: _currentIndex,
      playerDuration: _playerDuration,
      isLyricsActive: _isLyricsActive,
      cacheSongDuration: _cacheSongDuration,
      lyricsCacheRepository: _lyricsCacheRepository,
      lyricsService: _lyricsService,
      lyricsAiService: _lyricsAiService,
      settingsService: _settingsService,
      getState: () => state,
      setState: (newState) => state = newState,
      clearState: ({bool notify = false, bool preserveTaskState = true}) =>
          clearState(
            notify: notify,
            preserveTaskState: preserveTaskState,
          ),
      setIsLyricsLoading: (value) => _isLyricsLoading = value,
      setIsLyricsTranslating: (value) => _isLyricsTranslating = value,
      setLyricsTranslationStatus: (value) => _lyricsTranslationStatus = value,
      setLyricsGenerationStatus: (value) => _lyricsGenerationStatus = value,
      setHasLyrics: (value) => _hasLyrics = value,
      setLyricsSearchAttempted: (value) => _lyricsSearchAttempted = value,
      setCurrentLyricsLines: (value) => _currentLyricsLines = value,
      setCurrentLyricsText: (value) => _currentLyricsText = value,
      setLyricsGenerating: _setLyricsGenerating,
      startLyricsGenerationStatus: _startLyricsGenerationStatus,
      clearLyricsGenerationStatus: _clearLyricsGenerationStatus,
      bumpRevision: _bumpRevision,
      logDebug: _logDebug,
    );
    _support = LyricsControllerSupport(_context);
    _fetchCoordinator = LyricsFetchCoordinator(_context, _support);
    _generationCoordinator = LyricsGenerationCoordinator(_context, _support);
    _translationCoordinator = LyricsTranslationCoordinator(_context, _support);
    return LyricsControllerState(
      lyricsTranslationLanguageCode:
          LanguageCodeUtils.currentSystemLanguageCode(),
    );
  }

  set _isLyricsLoading(bool value) {
    state = state.copyWith(isLyricsLoading: value);
  }

  set _isLyricsTranslating(bool value) {
    state = state.copyWith(isLyricsTranslating: value);
  }

  set _lyricsTranslationStatus(String value) {
    state = state.copyWith(lyricsTranslationStatus: value);
  }

  set _lyricsGenerationStatus(String value) {
    state = state.copyWith(lyricsGenerationStatus: value);
  }

  set _hasLyrics(bool value) {
    state = state.copyWith(hasLyrics: value);
  }

  set _lyricsSearchAttempted(bool value) {
    state = state.copyWith(lyricsSearchAttempted: value);
  }

  set _currentLyricsLines(List<LyricLine> value) {
    state = state.copyWith(currentLyricsLines: value);
  }

  set _currentLyricsText(String value) {
    state = state.copyWith(currentLyricsText: value);
  }

  void _setLyricsGenerating(
    bool value, {
    LyricsGenerationPhase? phase,
    double? progress,
  }) {
    state = state.copyWith(
      isLyricsGenerating: value,
      lyricsGenerationPhase: phase ?? state.lyricsGenerationPhase,
      lyricsGenerationProgress: progress ?? state.lyricsGenerationProgress,
    );
  }

  void _startLyricsGenerationStatus(String status) {
    _lyricsGenerationStatus = status;
  }

  void _clearLyricsGenerationStatus() {
    _lyricsGenerationStatus = '';
  }

  void _bumpRevision() {
    state = state.copyWith(revision: state.revision + 1);
  }

  void setTranslationLanguageCode(String languageCode) {
    final normalized = LanguageCodeUtils.normalizeLanguageCode(languageCode);
    if (normalized.isEmpty ||
        normalized == state.lyricsTranslationLanguageCode) {
      return;
    }
    state = state.copyWith(lyricsTranslationLanguageCode: normalized);
  }

  void clearState({
    bool notify = false,
    bool preserveTaskState = true,
  }) {
    final current = state;
    state = LyricsControllerState(
      isLyricsLoading: false,
      isLyricsTranslating: preserveTaskState
          ? current.isLyricsTranslating
          : false,
      lyricsTranslationStatus: preserveTaskState
          ? current.lyricsTranslationStatus
          : '',
      lyricsGenerationStatus: preserveTaskState
          ? current.lyricsGenerationStatus
          : '',
      hasLyrics: false,
      lyricsSearchAttempted: false,
      currentLyricsLines: const <LyricLine>[],
      currentLyricsText: '',
      isLyricsGenerating: preserveTaskState
          ? current.isLyricsGenerating
          : false,
      lyricsGenerationPhase: preserveTaskState
          ? current.lyricsGenerationPhase
          : LyricsGenerationPhase.idle,
      lyricsGenerationProgress: preserveTaskState
          ? current.lyricsGenerationProgress
          : 0.0,
      lyricsTranslationLanguageCode: current.lyricsTranslationLanguageCode,
      revision: notify ? current.revision + 1 : current.revision,
    );
  }

  void restoreFromSongLyrics(MusicFile song) {
    final songLyrics = song.lyrics;
    if (songLyrics == null) {
      clearState();
      return;
    }

    _hasLyrics = true;
    _isLyricsLoading = false;
    _currentLyricsLines = songLyrics.syncedLines;
    _currentLyricsText = songLyrics.plainText;
    _lyricsSearchAttempted = true;
    unawaited(_support.restoreCachedTranslations(song));
    _logDebug(
      'lyrics restored from cache -> title="${song.displayName}" '
      'lines=${songLyrics.syncedLines.length} synced=${songLyrics.isSynced}',
    );
    _bumpRevision();
  }

  void scheduleFetch(MusicFile song) {
    _fetchCoordinator.scheduleFetch(song);
  }

  Future<void> fetchAndLog(MusicFile song) {
    return _fetchCoordinator.fetchAndLog(song);
  }

  Future<void> retryFetchUntilReady(MusicFile song) {
    return _fetchCoordinator.retryFetchUntilReady(song);
  }

  Future<void> clearAllLyricsCache() {
    return _fetchCoordinator.clearAllLyricsCache();
  }

  Future<void> clearLyricsCacheForCurrentSong() {
    return _fetchCoordinator.clearLyricsCacheForCurrentSong();
  }

  Future<void> clearTranslationCacheForCurrentSong() {
    return _fetchCoordinator.clearTranslationCacheForCurrentSong();
  }

  Future<void> requeryLyricsForCurrentSong() {
    return _fetchCoordinator.requeryLyricsForCurrentSong();
  }

  Future<void> clearTranslationCache() {
    return _fetchCoordinator.clearTranslationCache();
  }

  Future<void> restoreCachedTranslations(MusicFile song) {
    return _fetchCoordinator.restoreCachedTranslations(song);
  }

  Future<String?> generateLyricsForCurrentSong() {
    return _generationCoordinator.generateLyricsForCurrentSong();
  }

  Future<String?> generateTimelineForCurrentSong() {
    return _generationCoordinator.generateTimelineForCurrentSong();
  }

  Future<String?> regenerateLyricsForCurrentSong() {
    return _generationCoordinator.regenerateLyricsForCurrentSong();
  }

  Future<void> translateLyricsForCurrentSong({String? targetLanguageCode}) {
    return _translationCoordinator.translateLyricsForCurrentSong(
      targetLanguageCode: targetLanguageCode,
    );
  }

  Future<void> updateLyricsTimelineOffsetForCurrentSong(
    Duration timelineOffset,
  ) {
    return _support.updateLyricsTimelineOffsetForCurrentSong(timelineOffset);
  }

  Future<void> fillLyricsForCurrentSong(String lyricsText) {
    return _support.fillLyricsForCurrentSong(lyricsText);
  }

  LyricsSongTaskState taskStateForSong(String path) {
    return _context.taskStateForSong(path);
  }

  bool isLyricsGenerationForSong(String path) {
    return _context.isLyricsGenerationBusyForSong(path);
  }

  bool isLyricsTranslationForSong(String path) {
    return _context.isLyricsTranslationBusyForSong(path);
  }

  String? get activeLyricsGenerationSongPath {
    return _context.lyricsGeneration.songPath;
  }

  void _logDebug(String message) {
    if (!kDebugMode) return;
    debugPrint('[AudioService][Lyrics] $message');
  }
}
