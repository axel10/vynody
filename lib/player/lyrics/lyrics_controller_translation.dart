import 'dart:async';

import 'package:dio/dio.dart' show CancelToken, DioException;
import 'package:flutter/foundation.dart';

import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_lyric.dart';
import 'package:vynody/models/music_lyric_translation.dart';
import 'package:vynody/utils/localized_text.dart';
import 'package:vynody/utils/lrc_utils.dart';
import 'package:vynody/utils/language_code_utils.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/lyrics/lyrics_controller_context.dart';
import 'package:vynody/player/lyrics/lyrics_controller_utils.dart';
import 'package:vynody/player/lyrics/lyrics_generation_display_state.dart';
import 'package:vynody/player/lyrics/lyrics_generation_phase.dart';
import 'package:vynody/player/settings/settings_service.dart';

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

class LyricsTranslationCoordinator {
  LyricsTranslationCoordinator(this._context, this._support);

  final LyricsControllerContext _context;
  final LyricsControllerSupport _support;

  Future<String?> translateLyricsForCurrentSong({
    String? targetLanguageCode,
  }) async {
    final song = _context.currentMusic();
    debugPrint(
      '[LyricsTranslation] translateLyricsForCurrentSong invoked -> '
      'song="${song?.displayName}" path="${song?.path}" targetLang="$targetLanguageCode" '
      'stateLang="${_context.state.lyricsTranslationLanguageCode}"',
    );
    if (!_context.isProUnlocked()) {
      debugPrint('[LyricsTranslation] Blocked: pro trial expired or not unlocked');
      return _l10n().proTrialExpired;
    }
    if (song == null) {
      debugPrint('[LyricsTranslation] Blocked: no current song available');
      return _l10n().noCurrentSongAvailable;
    }

    final normalizedLanguageCode = LanguageCodeUtils.normalizeLanguageCode(
      targetLanguageCode ?? _context.state.lyricsTranslationLanguageCode,
    );
    if (normalizedLanguageCode.isEmpty) {
      debugPrint('[LyricsTranslation] Blocked: invalid target language code');
      return _l10n().invalidTargetLanguage;
    }
    if (_context.state.lyricsTranslationLanguageCode !=
        normalizedLanguageCode) {
      debugPrint(
        '[LyricsTranslation] Language changed: ${_context.state.lyricsTranslationLanguageCode} -> $normalizedLanguageCode',
      );
      _context.setLyricsTranslationStatus('');
      _context.setState(
        _context.state.copyWith(
          lyricsTranslationLanguageCode: normalizedLanguageCode,
        ),
      );
    }

    if (_context.isLyricsTranslationBusyForSong(song.path)) {
      debugPrint('[LyricsTranslation] Blocked: song already busy for translation');
      return _l10n().songAlreadyQueuedForTranslation;
    }

    debugPrint('[LyricsTranslation] Enqueueing translation task for "${song.displayName}"');
    _context.updateSongTaskState(
      song.path,
      (current) => current.copyWith(
        isTranslationQueued: true,
        translationStatus: _l10n().translatingLyrics,
      ),
    );

    return _context.lyricsAiTaskQueue.enqueue(() {
      return _translateLyricsForSong(
        song,
        normalizedLanguageCode: normalizedLanguageCode,
      );
    });
  }

  Future<String?> _translateLyricsForSong(
    MusicFile song, {
    required String normalizedLanguageCode,
  }) async {
    debugPrint(
      '[LyricsTranslation] _translateLyricsForSong start -> song="${song.displayName}" '
      'path="${song.path}" targetLang="$normalizedLanguageCode"',
    );
    if (!_context.isProUnlocked()) {
      debugPrint('[LyricsTranslation] _translateLyricsForSong aborted: pro not unlocked');
      return _l10n().proTrialExpired;
    }
    final currentSong = _support.songForPath(song.path);
    if (currentSong == null) {
      debugPrint('[LyricsTranslation] _translateLyricsForSong aborted: song no longer exists in queue');
      return _l10n().songNoLongerExistsForTranslation;
    }

    final cancelToken = CancelToken();
    _context.lyricsAiCancelToken = cancelToken;

    try {
      final sourceLyrics = _lyricsSourceForTranslation(currentSong);
      if (sourceLyrics.isEmpty) {
        debugPrint('[LyricsTranslation] _translateLyricsForSong aborted: no lyrics available for translation');
        return _l10n().noLyricsAvailableForTranslation;
      }

      final request = await _buildLyricsTranslationRequest(
        currentSong,
        normalizedLanguageCode: normalizedLanguageCode,
        sourceLyrics: sourceLyrics,
      );
      if (request == null) {
        debugPrint('[LyricsTranslation] _translateLyricsForSong aborted: _buildLyricsTranslationRequest returned null');
        return null;
      }

      return await _runLyricsTranslationRequest(request, cancelToken);
    } catch (e) {
      if (cancelToken.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        debugPrint('[LyricsTranslation] lyrics translation cancelled by user.');
        return null;
      }
      debugPrint('[LyricsTranslation] Exception during translation: $e');
      rethrow;
    } finally {
      if (_context.lyricsAiCancelToken == cancelToken) {
        _context.lyricsAiCancelToken = null;
      }
      if (_context.lyricsGenerationDisplayState.songPath == song.path) {
        _context.updateLyricsGenerationDisplayState(
          const LyricsGenerationDisplayState(),
        );
      }
      _context.updateSongTaskState(
        song.path,
        (current) => current.copyWith(
          isTranslationQueued: false,
          isTranslationRunning: false,
          translationStatus: '',
        ),
      );
      debugPrint('[LyricsTranslation] _translateLyricsForSong finally: cleanup completed for "${song.displayName}"');
    }
  }

  Future<_LyricsTranslationRequest?> _buildLyricsTranslationRequest(
    MusicFile song, {
    required String normalizedLanguageCode,
    required String sourceLyrics,
  }) async {
    final query = await _support.buildLyricsQueryForSong(song);
    if (query == null) {
      debugPrint('[LyricsTranslation] Request build failed: query is null (duration not ready)');
      return null;
    }

    final lyricsId = _support.lyricsIdForSong(song, sourceLyrics: sourceLyrics);
    if (lyricsId.isEmpty) {
      debugPrint('[LyricsTranslation] Request build failed: lyricsId is empty');
      return null;
    }

    final translationKey = _lyricsTranslationCacheKey(
      query.cacheKey,
      normalizedLanguageCode,
    );

    final currentLyrics = song.lyrics;
    if (currentLyrics != null && !currentLyrics.hasId) {
      _support.replaceSongIfPath(
        song.path,
        (queueSong) =>
            queueSong.copyWith(lyrics: currentLyrics.copyWith(id: lyricsId)),
      );
    }

    if (_context.translationInFlightKeys.contains(translationKey)) {
      debugPrint('[LyricsTranslation] Request skipped: translation already in-flight for key "$translationKey"');
      return null;
    }
    if (currentLyrics?.translationFor(normalizedLanguageCode)?.hasContent ==
        true) {
      debugPrint(
        '[LyricsTranslation] Request skipped: memory lyrics already has translation for "$normalizedLanguageCode"',
      );
      return null;
    }
    if (_context.translatedLyricsKeys.contains(translationKey)) {
      debugPrint(
        '[LyricsTranslation] Request skipped: key "$translationKey" already in translatedLyricsKeys cache set',
      );
      return null;
    }

    debugPrint(
      '[LyricsTranslation] Request built successfully: key="$translationKey", lyricsId="$lyricsId", '
      'sourceLength=${sourceLyrics.length}',
    );

    return _LyricsTranslationRequest(
      songPath: song.path,
      cacheKey: query.cacheKey,
      languageCode: normalizedLanguageCode,
      sourceLyrics: sourceLyrics,
      lyricsId: lyricsId,
      translationKey: translationKey,
    );
  }

  Future<String?> _runLyricsTranslationRequest(
    _LyricsTranslationRequest request,
    CancelToken cancelToken,
  ) async {
    if (_context.translationInFlightKeys.contains(request.translationKey)) {
      debugPrint('[LyricsTranslation] Request already in flight: ${request.translationKey}');
      return null;
    }

    _context.translationInFlightKeys.add(request.translationKey);
    _context.updateSongTaskState(
      request.songPath,
      (current) => current.copyWith(
        isTranslationQueued: false,
        isTranslationRunning: true,
        translationStatus: _l10n().translatingLyrics,
      ),
    );

    final initialModelLabel =
        _context.lyricsAiService.currentTranslationModelLabel;
    debugPrint(
      '[LyricsTranslation] Starting translation stream -> key="${request.translationKey}" '
      'model="$initialModelLabel" targetLang="${request.languageCode}"',
    );
    _context.updateLyricsGenerationDisplayState(
      LyricsGenerationDisplayState(
        songPath: request.songPath,
        statusLabel: _l10n().translatingLyrics,
        modelLabel: initialModelLabel,
        phase: LyricsGenerationPhase.requesting,
        progress: 0.0,
      ),
    );

    List<String> latestTranslatedLines = const [];
    String latestTranslatedText = '';

    try {
      final errorMessage = await _context.lyricsAiService.translateLyricsStream(
        lyrics: request.sourceLyrics,
        targetLanguageCode: request.languageCode,
        onModelLabelChanged: (modelLabel) {
          debugPrint('[LyricsTranslation] Model label changed: $modelLabel');
          _updateTranslationModelLabel(modelLabel);
        },
        onStageChanged: (stage) {
          debugPrint('[LyricsTranslation] Stage changed: $stage');
          final current = _context.lyricsGenerationDisplayState;
          final phase = switch (stage) {
            'requesting' => LyricsGenerationPhase.requesting,
            'generating' => LyricsGenerationPhase.generating,
            _ => current.phase,
          };
          _context.updateLyricsGenerationDisplayState(
            current.copyWith(
              songPath: request.songPath,
              phase: phase,
            ),
          );
        },
        cancelToken: cancelToken,
        onProgress: (translatedLines, translatedText) {
          final current = _context.lyricsGenerationDisplayState;
          if (current.phase != LyricsGenerationPhase.generating) {
            _context.updateLyricsGenerationDisplayState(
              current.copyWith(
                songPath: request.songPath,
                phase: LyricsGenerationPhase.generating,
              ),
            );
          }
          latestTranslatedLines = translatedLines;
          latestTranslatedText = translatedText;
          debugPrint(
            '[LyricsTranslation] Stream progress chunk received -> lines=${translatedLines.length}, '
            'nonEmptyLines=${translatedLines.where((l) => l.trim().isNotEmpty).length}, '
            'textLen=${translatedText.length}',
          );
          _syncTranslatedLyricsToSong(
            request.songPath,
            request.lyricsId,
            request.languageCode,
            translatedLines,
            translatedText,
            cacheKey: request.cacheKey,
            bumpLayoutRevision: false,
          );
        },
      );
      debugPrint(
        '[LyricsTranslation] Stream translate finished -> errorMessage="$errorMessage", '
        'latestLinesCount=${latestTranslatedLines.length}, latestTextLen=${latestTranslatedText.length}',
      );
      if (errorMessage == null) {
        final hasContent = latestTranslatedLines.any((line) => line.trim().isNotEmpty) ||
            latestTranslatedText.trim().isNotEmpty;
        debugPrint(
          '[LyricsTranslation] Translation finished with success. hasContent=$hasContent, '
          'isScrolling=${_context.isLyricsPanelScrolling()}',
        );
        if (hasContent) {
          if (_context.isLyricsPanelScrolling()) {
            debugPrint('[LyricsTranslation] Panel is scrolling, stashing pending translation update');
            _context.stashPendingLyricsTranslationUpdate(
              songPath: request.songPath,
              cacheKey: request.cacheKey,
              languageCode: request.languageCode,
              lyricsId: request.lyricsId,
              translatedLines: latestTranslatedLines,
              translatedText: latestTranslatedText,
              completed: true,
            );
            return null;
          }

          _syncTranslatedLyricsToSong(
            request.songPath,
            request.lyricsId,
            request.languageCode,
            latestTranslatedLines,
            latestTranslatedText,
            cacheKey: request.cacheKey,
            bumpLayoutRevision: true,
          );

          _context.translatedLyricsKeys.add(request.translationKey);
          debugPrint('[LyricsTranslation] Added key to translatedLyricsKeys: ${request.translationKey}');
          await _saveTranslatedLyricsToDatabase(
            songPath: request.songPath,
            cacheKey: request.cacheKey,
            languageCode: request.languageCode,
          );
        } else {
          debugPrint('[LyricsTranslation] Warning: Translation completed but hasContent is false!');
        }
        return null;
      }

      if (latestTranslatedLines.any((line) => line.trim().isNotEmpty) ||
          latestTranslatedText.trim().isNotEmpty) {
        try {
          debugPrint('[LyricsTranslation] Saving partial translation on error...');
          await _saveTranslatedLyricsToDatabase(
            songPath: request.songPath,
            cacheKey: request.cacheKey,
            languageCode: request.languageCode,
          );
        } catch (dbError) {
          debugPrint('[LyricsTranslation] Failed to save partial translation on error: $dbError');
        }
      }

      if (cancelToken.isCancelled || errorMessage == 'cancelled') {
        debugPrint('[LyricsTranslation] Translation request cancelled');
        return null;
      }
      debugPrint('[LyricsTranslation] Translation failed with error: $errorMessage');
      return errorMessage;
    } catch (e) {
      debugPrint('[LyricsTranslation] Translation request threw exception: $e');
      if (latestTranslatedLines.any((line) => line.trim().isNotEmpty) ||
          latestTranslatedText.trim().isNotEmpty) {
        try {
          await _saveTranslatedLyricsToDatabase(
            songPath: request.songPath,
            cacheKey: request.cacheKey,
            languageCode: request.languageCode,
          );
        } catch (dbError) {
          debugPrint('[LyricsTranslation] Failed to save partial translation on error: $dbError');
        }
      }
      if (cancelToken.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        debugPrint('[LyricsTranslation] lyrics translation cancelled by user.');
        return null;
      }
      rethrow;
    } finally {
      _context.translationInFlightKeys.remove(request.translationKey);
      _context.updateSongTaskState(
        request.songPath,
        (current) => current.copyWith(
          isTranslationQueued: false,
          isTranslationRunning: false,
          translationStatus: '',
        ),
      );
      if (_context.lyricsGenerationDisplayState.songPath == request.songPath) {
        _context.updateLyricsGenerationDisplayState(
          const LyricsGenerationDisplayState(),
        );
      }
      debugPrint('[LyricsTranslation] _runLyricsTranslationRequest finally finished for key ${request.translationKey}');
    }
  }

  Future<void> flushPendingLyricsTranslationUpdates() async {
    final pendingUpdates = _context.pendingLyricsTranslationUpdates.values
        .toList(growable: false);
    if (pendingUpdates.isEmpty) return;

    for (final pending in pendingUpdates) {
      _context.pendingLyricsTranslationUpdates.remove(pending.songPath);
      _syncTranslatedLyricsToSong(
        pending.songPath,
        pending.lyricsId,
        pending.languageCode,
        pending.translatedLines,
        pending.translatedText,
        cacheKey: pending.cacheKey,
        bumpLayoutRevision: false,
      );
      if (pending.completed) {
        await _saveTranslatedLyricsToDatabase(
          songPath: pending.songPath,
          cacheKey: pending.cacheKey,
          languageCode: pending.languageCode,
        );
        _context.translatedLyricsKeys.add(
          _lyricsTranslationCacheKey(pending.cacheKey, pending.languageCode),
        );
      }
    }

    _context.bumpLyricsLayoutRevision();
  }

  void _updateTranslationModelLabel(String? modelLabel) {
    final current = _context.lyricsGenerationDisplayState;
    _context.updateLyricsGenerationDisplayState(
      current.copyWith(modelLabel: modelLabel ?? ''),
    );
  }

  String _lyricsSourceForTranslation(MusicFile song) {
    final lyrics = song.lyrics;
    if (lyrics != null) {
      final text = _support.lineSyncedLyricsText(lyrics);
      if (text.isNotEmpty) {
        return text;
      }
    }
    final state = _context.state;
    if (state.currentLyricsLines.any((line) => line.isTimed)) {
      return LrcUtils.formatLineSyncedLyrics(state.currentLyricsLines).trim();
    }
    final currentText = state.currentLyricsText.trim();
    if (currentText.isNotEmpty) {
      return LrcUtils.stripWordTimestamps(currentText).trim();
    }
    return '';
  }

  void _syncTranslatedLyricsToSong(
    String songPath,
    String lyricsId,
    String languageCode,
    List<String> translatedLines,
    String translatedText, {
    String? cacheKey,
    bool bumpLayoutRevision = true,
  }) {
    if (_context.isLyricsPanelScrolling()) {
      debugPrint(
        '[LyricsTranslation] Translation sync deferred while panel scrolling -> '
        'path="$songPath" lang="$languageCode" '
        'lines=${translatedLines.length} textLen=${translatedText.trim().length}',
      );
      _context.stashPendingLyricsTranslationUpdate(
        songPath: songPath,
        cacheKey: cacheKey ?? '',
        languageCode: languageCode,
        lyricsId: lyricsId,
        translatedLines: translatedLines,
        translatedText: translatedText,
      );
      return;
    }

    MusicFile? updatedSong;
    _support.replaceSongIfPath(songPath, (currentSong) {
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

    if (updatedSong == null) {
      debugPrint(
        '[LyricsTranslation] Warning: replaceSongIfPath returned null for path="$songPath", cannot apply translation sync!',
      );
      return;
    }
    debugPrint(
      '[LyricsTranslation] Translation sync applied -> path="$songPath" lang="$languageCode" '
      'lines=${translatedLines.length} textLen=${translatedText.trim().length} '
      'bumpLayout=$bumpLayoutRevision hasLyrics=${updatedSong?.lyrics?.hasTranslatedLyrics}',
    );
    _context.bumpRevision();
    if (bumpLayoutRevision) {
      _context.bumpLyricsLayoutRevision();
    }
    if (cacheKey != null) {
      unawaited(_saveTranslatedLyricsToDatabase(
        songPath: songPath,
        cacheKey: cacheKey,
        languageCode: languageCode,
      ));
    }
  }

  Future<void> _saveTranslatedLyricsToDatabase({
    required String songPath,
    required String cacheKey,
    required String languageCode,
  }) async {
    try {
      final current = _support.songForPath(songPath);
      if (current == null) {
        debugPrint('[LyricsTranslation] Save to DB failed: song not found for path "$songPath"');
        return;
      }

      final lyrics = current.lyrics;
      if (lyrics == null) {
        debugPrint('[LyricsTranslation] Save to DB failed: lyrics is null for song "${current.displayName}"');
        return;
      }

      final translation = lyrics.translationFor(languageCode);
      if (translation == null || !translation.hasContent) {
        debugPrint(
          '[LyricsTranslation] Save to DB failed: translation for "$languageCode" is null or empty in song "${current.displayName}"',
        );
        return;
      }

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
      await _context.lyricsCacheRepository.saveLyricsTranslationCache(record);
      debugPrint(
        '[LyricsTranslation] Successfully cached translation to DB: cacheKey="$cacheKey", '
        'lang="$languageCode", linesCount=${record.translatedLines.length}, provider=${record.provider}',
      );
    } catch (e) {
      debugPrint('[LyricsTranslation] Failed to cache translated lyrics: $e');
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
    final provider = _context.settingsService.translationPrimaryModel.provider;
    return provider.storageValue;
  }
}

AppLocalizations _l10n() => currentAppL10n;
