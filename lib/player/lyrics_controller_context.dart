import 'dart:async';

import 'package:dio/dio.dart';

import '../models/lyric_line.dart';
import '../models/music_file.dart';
import 'lyrics_ai_service.dart';
import 'lyrics_cache_repository.dart';
import 'lyrics_controller_state.dart';
import 'lyrics_generation_phase.dart';
import 'lyrics_service.dart';
import 'metadata_database.dart';
import 'settings_service.dart';

class LyricsGenerationRuntime {
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

class LyricsControllerContext {
  LyricsControllerContext({
    required this.db,
    required this.currentMusic,
    required this.queue,
    required this.currentIndex,
    required this.playerDuration,
    required this.isLyricsActive,
    required this.cacheSongDuration,
    required this.lyricsCacheRepository,
    required this.lyricsService,
    required this.lyricsAiService,
    required this.settingsService,
    required this.getState,
    required this.setState,
    required this.clearState,
    required this.setIsLyricsLoading,
    required this.setIsLyricsTranslating,
    required this.setLyricsTranslationStatus,
    required this.setLyricsGenerationStatus,
    required this.setHasLyrics,
    required this.setLyricsSearchAttempted,
    required this.setCurrentLyricsLines,
    required this.setCurrentLyricsText,
    required this.setLyricsGenerating,
    required this.startLyricsGenerationStatus,
    required this.clearLyricsGenerationStatus,
    required this.bumpRevision,
    required this.logDebug,
  });

  final MetadataDatabase db;
  final MusicFile? Function() currentMusic;
  final List<MusicFile> Function() queue;
  final int Function() currentIndex;
  final Duration Function() playerDuration;
  final bool Function() isLyricsActive;
  final void Function(String path, int durationMillis) cacheSongDuration;
  final LyricsCacheRepository lyricsCacheRepository;
  final LyricsService lyricsService;
  final LyricsAiService lyricsAiService;
  final SettingsService settingsService;
  final LyricsControllerState Function() getState;
  final void Function(LyricsControllerState state) setState;
  final void Function({bool notify}) clearState;
  final void Function(bool value) setIsLyricsLoading;
  final void Function(bool value) setIsLyricsTranslating;
  final void Function(String value) setLyricsTranslationStatus;
  final void Function(String value) setLyricsGenerationStatus;
  final void Function(bool value) setHasLyrics;
  final void Function(bool value) setLyricsSearchAttempted;
  final void Function(List<LyricLine> value) setCurrentLyricsLines;
  final void Function(String value) setCurrentLyricsText;
  final void Function(
    bool value, {
    LyricsGenerationPhase? phase,
    double? progress,
  })
  setLyricsGenerating;
  final void Function(String value) startLyricsGenerationStatus;
  final void Function() clearLyricsGenerationStatus;
  final void Function() bumpRevision;
  final void Function(String message) logDebug;

  final LyricsGenerationRuntime lyricsGeneration = LyricsGenerationRuntime();
  final Set<String> translatedLyricsKeys = <String>{};
  final Set<String> translationInFlightKeys = <String>{};
  int lyricsRequestSerial = 0;
  int lyricsRetrySerial = 0;
  CancelToken? lyricsFetchCancelToken;

  LyricsControllerState get state => getState();
}
