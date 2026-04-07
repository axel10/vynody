import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/lyric_line.dart';
import '../models/music_file.dart';
import '../models/music_lyric.dart';
import '../models/music_lyric_translation.dart';
import '../utils/lrc_utils.dart';
import '../utils/lyrics_id_utils.dart';
import '../utils/language_code_utils.dart';
import 'gemini_lyrics_translation_service.dart';
import 'lyrics_generation_phase.dart';
import 'lyrics_service.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';

class LyricsController extends ChangeNotifier {
  LyricsController({
    required MetadataDatabase db,
    required MusicFile? Function() currentMusic,
    required List<MusicFile> Function() queue,
    required int Function() currentIndex,
    required Duration Function() playerDuration,
    required bool Function() isLyricsActive,
    required void Function(String path, int durationMillis) cacheSongDuration,
    LyricsService? lyricsService,
    GeminiLyricsTranslationService? geminiLyricsTranslationService,
  }) : _db = db,
       _currentMusic = currentMusic,
       _queue = queue,
       _currentIndex = currentIndex,
       _playerDuration = playerDuration,
       _isLyricsActive = isLyricsActive,
       _cacheSongDuration = cacheSongDuration,
       _lyricsService = lyricsService ?? LyricsService(db: db),
       _geminiLyricsTranslationService =
           geminiLyricsTranslationService ?? GeminiLyricsTranslationService();

  final MetadataDatabase _db;
  final MusicFile? Function() _currentMusic;
  final List<MusicFile> Function() _queue;
  final int Function() _currentIndex;
  final Duration Function() _playerDuration;
  final bool Function() _isLyricsActive;
  final void Function(String path, int durationMillis) _cacheSongDuration;
  final LyricsService _lyricsService;
  final GeminiLyricsTranslationService _geminiLyricsTranslationService;

  int _lyricsRequestSerial = 0;
  final Set<String> _translatedLyricsKeys = <String>{};
  final Set<String> _translationInFlightKeys = <String>{};
  Completer<void>? _lyricsGenerationCompleter;
  int _lyricsRetrySerial = 0;
  bool _isLyricsLoading = false;
  bool _isLyricsTranslating = false;
  bool _isLyricsGenerating = false;
  String _lyricsTranslationStatus = '';
  bool _hasLyrics = false;
  bool _lyricsSearchAttempted = false;
  bool _isLyricsSynced = false;
  int _lyricsGenerationSerial = 0;
  LyricsGenerationPhase _lyricsGenerationPhase = LyricsGenerationPhase.idle;
  double _lyricsGenerationProgress = 0.0;
  List<LyricLine> _currentLyricsLines = const [];
  String _currentLyricsText = '';
  String? _currentLyricsTitle;
  String _lyricsTranslationLanguageCode =
      LanguageCodeUtils.currentSystemLanguageCode();

  bool get isLyricsLoading => _isLyricsLoading;
  bool get isLyricsTranslating => _isLyricsTranslating;
  bool get isLyricsGenerating => _isLyricsGenerating;
  String get lyricsTranslationStatus => _lyricsTranslationStatus;
  LyricsGenerationPhase get lyricsGenerationPhase => _lyricsGenerationPhase;
  double get lyricsGenerationProgress => _lyricsGenerationProgress;
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
    _isLyricsGenerating = false;
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

    if (_isLyricsGenerating && _currentMusic()?.path == song.path) {
      _isLyricsTranslating = true;
      _lyricsTranslationStatus = '等待歌词生成完毕';
      notifyListeners();
      await _waitForLyricsGenerationToFinish(song.path);
    }

    String? translationKey;
    try {
      final currentSong = _currentMusic();
      if (currentSong == null || currentSong.path != song.path) return;

      final sourceLyrics = currentSong.lyrics?.syncedLines.isNotEmpty == true
          ? currentSong.lyrics!.syncedLines
                .map((line) => line.text)
                .join('\n')
                .trim()
          : _currentLyricsText.trim();
      if (sourceLyrics.isEmpty) return;

      final query = await _buildLyricsQueryForSong(currentSong);
      if (query == null) return;

      final lyricsId = _lyricsIdForSong(
        currentSong,
        sourceLyrics: sourceLyrics,
      );
      if (lyricsId.isEmpty) return;

      final activeTranslationKey = _lyricsTranslationCacheKey(
        query.cacheKey,
        normalizedLanguageCode,
      );
      translationKey = activeTranslationKey;

      final currentLyrics = currentSong.lyrics;
      if (currentLyrics != null && !currentLyrics.hasId) {
        _replaceCurrentSongIfPath(
          currentSong.path,
          (queueSong) =>
              queueSong.copyWith(lyrics: currentLyrics.copyWith(id: lyricsId)),
        );
      }

      if (_translationInFlightKeys.contains(activeTranslationKey)) return;
      if ((currentSong.lyrics ?? currentLyrics)
              ?.translationFor(normalizedLanguageCode)
              ?.hasContent ==
          true) {
        return;
      }
      if (_translatedLyricsKeys.contains(activeTranslationKey)) return;

      _translationInFlightKeys.add(activeTranslationKey);
      _isLyricsTranslating = true;
      _lyricsTranslationStatus = '正在处理';
      notifyListeners();

      final success = await _geminiLyricsTranslationService
          .translateLyricsStream(
            lyrics: sourceLyrics,
            targetLanguageCode: normalizedLanguageCode,
            onProgress: (translatedLines, translatedText) {
              _syncTranslatedLyricsToCurrentSong(
                currentSong.path,
                lyricsId,
                normalizedLanguageCode,
                translatedLines,
                translatedText,
              );
            },
          );
      if (success) {
        _translatedLyricsKeys.add(activeTranslationKey);
        await _saveTranslatedLyricsToDatabase(
          songPath: currentSong.path,
          cacheKey: query.cacheKey,
          languageCode: normalizedLanguageCode,
        );
      }
    } finally {
      if (translationKey != null) {
        _translationInFlightKeys.remove(translationKey);
      }
      _isLyricsTranslating = false;
      _lyricsTranslationStatus = '';
      notifyListeners();
    }
  }

  Future<void> clearAllLyricsCache() async {
    await _db.clearLyricsCache();
    await _db.clearLyricsTranslationCache();

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
    _isLyricsGenerating = false;
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

  Future<void> clearTranslationCache() async {
    await _db.clearLyricsTranslationCache();

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

  Future<void> generateLyricsForCurrentSong() async {
    final song = _currentMusic();
    if (song == null) {
      debugPrint('[LyricsController] generate lyrics skipped: no current song');
      return;
    }
    if (_isLyricsGenerating) {
      debugPrint(
        '[LyricsController] generate lyrics skipped: already generating '
        'path=${song.path}',
      );
      return;
    }

    final generationId = ++_lyricsGenerationSerial;
    final generationCompleter = Completer<void>();
    _lyricsGenerationCompleter = generationCompleter;
    _isLyricsGenerating = true;
    _isLyricsLoading = false;
    _lyricsGenerationPhase = LyricsGenerationPhase.uploading;
    _lyricsGenerationProgress = 0.0;
    notifyListeners();

    try {
      final generatedLyrics = await _geminiLyricsTranslationService
          .generateLyricsFromFile(
            filePath: song.path,
            onUploadProgress: (progress) {
              if (generationId != _lyricsGenerationSerial ||
                  _currentMusic()?.path != song.path) {
                return;
              }

              _lyricsGenerationPhase = LyricsGenerationPhase.uploading;
              _lyricsGenerationProgress = progress.clamp(0.0, 1.0);
              notifyListeners();
            },
            onStageChanged: (stage) {
              if (generationId != _lyricsGenerationSerial ||
                  _currentMusic()?.path != song.path) {
                return;
              }

              switch (stage) {
                case 'uploading':
                  _lyricsGenerationPhase = LyricsGenerationPhase.uploading;
                  _lyricsGenerationProgress = 0.0;
                  break;
                case 'processing':
                  _lyricsGenerationPhase = LyricsGenerationPhase.processing;
                  _lyricsGenerationProgress = 1.0;
                  break;
                case 'generating':
                  _lyricsGenerationPhase = LyricsGenerationPhase.generating;
                  _lyricsGenerationProgress = 1.0;
                  break;
                default:
                  _lyricsGenerationPhase = LyricsGenerationPhase.idle;
                  _lyricsGenerationProgress = 0.0;
                  break;
              }
              notifyListeners();
            },
            onProgress: (partialText, isFinal) {
              if (generationId != _lyricsGenerationSerial ||
                  _currentMusic()?.path != song.path) {
                return;
              }

              final progressText = partialText.trim();
              if (progressText.isEmpty) return;
              final progressLyrics = MusicLyric(
                id: LyricsIdUtils.fromLyricsText(progressText),
                syncedLines: _parseGeneratedLyrics(progressText),
                plainText: progressText,
              );

              _hasLyrics = true;
              _isLyricsLoading = false;
              _lyricsGenerationPhase = LyricsGenerationPhase.generating;
              _lyricsGenerationProgress = 1.0;
              _isLyricsSynced = progressLyrics.syncedLines.any(
                (line) => line.isTimed,
              );
              _lyricsSearchAttempted = true;
              _currentLyricsLines = progressLyrics.syncedLines;
              _currentLyricsText = progressLyrics.plainText;
              _currentLyricsTitle = song.displayName;

              final updated = _replaceCurrentSongIfPath(
                song.path,
                (currentSong) => currentSong.copyWith(lyrics: progressLyrics),
              );
              if (updated != null) {
                unawaited(restoreCachedTranslations(updated));
              }

              notifyListeners();
            },
          );

      if (generationId != _lyricsGenerationSerial ||
          _currentMusic()?.path != song.path) {
        return;
      }

      if (generatedLyrics == null || generatedLyrics.trim().isEmpty) {
        return;
      }

      final generatedLines = _parseGeneratedLyrics(generatedLyrics);
      final lyrics = MusicLyric(
        id: LyricsIdUtils.fromLyricsText(generatedLyrics),
        syncedLines: generatedLines.isNotEmpty
            ? generatedLines
            : _buildLyricsLines(const [], generatedLyrics),
        plainText: generatedLyrics.trim(),
      );

      _hasLyrics = true;
      _isLyricsLoading = false;
      _lyricsGenerationPhase = LyricsGenerationPhase.idle;
      _lyricsGenerationProgress = 0.0;
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

      await _saveGeneratedLyricsToDatabase(
        song: song,
        generatedLyrics: generatedLyrics,
        syncedLines: generatedLines,
      );

      notifyListeners();
    } catch (e) {
      debugPrint('[LyricsController] Failed to generate lyrics: $e');
    } finally {
      if (generationId == _lyricsGenerationSerial) {
        _isLyricsGenerating = false;
        _lyricsGenerationPhase = LyricsGenerationPhase.idle;
        _lyricsGenerationProgress = 0.0;
        if (!generationCompleter.isCompleted) {
          generationCompleter.complete();
        }
        if (identical(_lyricsGenerationCompleter, generationCompleter)) {
          _lyricsGenerationCompleter = null;
        }
        notifyListeners();
      }
    }
  }

  Future<void> restoreCachedTranslations(MusicFile song) async {
    final lyrics = song.lyrics;
    if (lyrics == null) return;

    final query = await _buildLyricsQueryForSong(song);
    if (query == null) return;

    try {
      final cachedTranslations = await _db.getLyricsTranslationCaches(
        query.cacheKey,
      );
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
    while (_isLyricsGenerating && _currentMusic()?.path == songPath) {
      final completer = _lyricsGenerationCompleter;
      if (completer != null) {
        try {
          await completer.future;
        } catch (_) {
          return;
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 100));
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
      await _db.insertOrUpdateLyricsTranslationCache(record);
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
        source: 'gemini_generate',
        isSynced: syncedLines.any((line) => line.isTimed),
        syncedLyrics: syncedLines.any((line) => line.isTimed)
            ? generatedLyrics
            : null,
        syncedLines: syncedLines.map((line) => line.toJson()).toList(),
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await _db.insertOrUpdateLyricsCache(record);
    } catch (e) {
      debugPrint('[LyricsController] Failed to cache generated lyrics: $e');
    }
  }

  List<LyricLine> _parseGeneratedLyrics(String? lyrics) {
    return LrcUtils.parseTimedLyrics(lyrics);
  }

  String _lyricsTranslationCacheKey(String cacheKey, String languageCode) {
    return '$cacheKey|$languageCode';
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
