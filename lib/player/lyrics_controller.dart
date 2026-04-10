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

part 'lyrics_controller_fetch.dart';
part 'lyrics_controller_translation.dart';
part 'lyrics_controller_generation.dart';
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
}
