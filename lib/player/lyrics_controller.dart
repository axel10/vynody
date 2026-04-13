import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyric_line.dart';
import '../models/music_file.dart';
import '../models/music_lyric.dart';
import '../models/music_lyric_translation.dart';
import '../utils/language_code_utils.dart';
import '../utils/lrc_utils.dart';
import '../utils/lyrics_id_utils.dart';
import 'gemini_lyrics_service.dart';
import 'lyrics_cache_repository.dart';
import 'lyrics_controller_state.dart';
import 'lyrics_generation_phase.dart';
import 'lyrics_riverpod.dart';
import 'lyrics_service.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';

part 'lyrics_controller_fetch.dart';
part 'lyrics_controller_generation.dart';
part 'lyrics_controller_translation.dart';
part 'lyrics_controller_utils.dart';

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
  late final GeminiLyricsService _geminiLyricsService;

  int _lyricsRequestSerial = 0;
  final Set<String> _translatedLyricsKeys = <String>{};
  final Set<String> _translationInFlightKeys = <String>{};
  int _lyricsRetrySerial = 0;
  final _GeminiGenerationRuntime _geminiGeneration = _GeminiGenerationRuntime();

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
    _geminiLyricsService = GeminiLyricsService();
    return LyricsControllerState(
      lyricsTranslationLanguageCode:
          LanguageCodeUtils.currentSystemLanguageCode(),
    );
  }

  bool get _isLyricsLoading => state.isLyricsLoading;
  set _isLyricsLoading(bool value) {
    state = state.copyWith(isLyricsLoading: value);
  }

  bool get _isLyricsTranslating => state.isLyricsTranslating;
  set _isLyricsTranslating(bool value) {
    state = state.copyWith(isLyricsTranslating: value);
  }

  set _lyricsTranslationStatus(String value) {
    state = state.copyWith(lyricsTranslationStatus: value);
  }

  set _lyricsGenerationStatus(String value) {
    state = state.copyWith(lyricsGenerationStatus: value);
  }

  bool get _hasLyrics => state.hasLyrics;
  set _hasLyrics(bool value) {
    state = state.copyWith(hasLyrics: value);
  }

  bool get _lyricsSearchAttempted => state.lyricsSearchAttempted;
  set _lyricsSearchAttempted(bool value) {
    state = state.copyWith(lyricsSearchAttempted: value);
  }

  List<LyricLine> get _currentLyricsLines => state.currentLyricsLines;
  set _currentLyricsLines(List<LyricLine> value) {
    state = state.copyWith(currentLyricsLines: value);
  }

  String get _currentLyricsText => state.currentLyricsText;
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

  void _setGenerationStage(String stage) {
    switch (stage) {
      case 'uploading':
        _setLyricsGenerating(
          true,
          phase: LyricsGenerationPhase.uploading,
          progress: 0.0,
        );
        return;
      case 'processing':
        _setLyricsGenerating(
          true,
          phase: LyricsGenerationPhase.processing,
          progress: 1.0,
        );
        return;
      case 'generating':
        _setLyricsGenerating(
          true,
          phase: LyricsGenerationPhase.generating,
          progress: 1.0,
        );
        return;
      default:
        _setLyricsGenerating(
          false,
          phase: LyricsGenerationPhase.idle,
          progress: 0.0,
        );
    }
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

  void clearState({bool notify = false}) {
    state = LyricsControllerState(
      lyricsTranslationLanguageCode:
          LanguageCodeUtils.currentSystemLanguageCode(),
      revision: notify ? state.revision + 1 : state.revision,
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
    unawaited(restoreCachedTranslations(song));
    _logDebug(
      'lyrics restored from cache -> title="${song.displayName}" '
      'lines=${songLyrics.syncedLines.length} synced=${songLyrics.isSynced}',
    );
    _bumpRevision();
  }
}
