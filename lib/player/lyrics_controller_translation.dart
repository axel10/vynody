import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/music_file.dart';
import '../models/music_lyric.dart';
import '../models/music_lyric_translation.dart';
import '../utils/language_code_utils.dart';
import 'lyrics_cache_models.dart';
import 'lyrics_controller_context.dart';
import 'lyrics_controller_utils.dart';
import 'settings_service.dart';

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

  Future<void> translateLyricsForCurrentSong({
    String? targetLanguageCode,
  }) async {
    final song = _context.currentMusic();
    if (song == null) return;

    final normalizedLanguageCode = LanguageCodeUtils.normalizeLanguageCode(
      targetLanguageCode ?? _context.state.lyricsTranslationLanguageCode,
    );
    if (normalizedLanguageCode.isEmpty) return;
    if (_context.state.lyricsTranslationLanguageCode !=
        normalizedLanguageCode) {
      _context.setLyricsTranslationStatus('');
      _context.setState(
        _context.state.copyWith(
          lyricsTranslationLanguageCode: normalizedLanguageCode,
        ),
      );
    }

    if (_context.isLyricsTranslationBusyForSong(song.path)) {
      return;
    }

    _context.updateSongTaskState(
      song.path,
      (current) => current.copyWith(
        isTranslationQueued: true,
        translationStatus: '正在翻译歌词',
      ),
    );

    await _context.lyricsAiTaskQueue.enqueue(() {
      return _translateLyricsForSong(
        song,
        normalizedLanguageCode: normalizedLanguageCode,
      );
    });
  }

  Future<void> _translateLyricsForSong(
    MusicFile song, {
    required String normalizedLanguageCode,
  }) async {
    final currentSong = _support.songForPath(song.path);
    if (currentSong == null) return;

    try {
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
      _context.updateSongTaskState(
        song.path,
        (current) => current.copyWith(
          isTranslationQueued: false,
          isTranslationRunning: false,
          translationStatus: '',
        ),
      );
    }
  }

  Future<_LyricsTranslationRequest?> _buildLyricsTranslationRequest(
    MusicFile song, {
    required String normalizedLanguageCode,
    required String sourceLyrics,
  }) async {
    final query = await _support.buildLyricsQueryForSong(song);
    if (query == null) return null;

    final lyricsId = _support.lyricsIdForSong(song, sourceLyrics: sourceLyrics);
    if (lyricsId.isEmpty) return null;

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

    if (_context.translationInFlightKeys.contains(translationKey)) return null;
    if (currentLyrics?.translationFor(normalizedLanguageCode)?.hasContent ==
        true) {
      return null;
    }
    if (_context.translatedLyricsKeys.contains(translationKey)) return null;

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
    if (_context.translationInFlightKeys.contains(request.translationKey)) {
      return;
    }

    _context.translationInFlightKeys.add(request.translationKey);
    _context.updateSongTaskState(
      request.songPath,
      (current) => current.copyWith(
        isTranslationQueued: false,
        isTranslationRunning: true,
        translationStatus: '正在翻译歌词',
      ),
    );

    try {
      final success = await _context.lyricsAiService.translateLyricsStream(
        lyrics: request.sourceLyrics,
        targetLanguageCode: request.languageCode,
        onProgress: (translatedLines, translatedText) {
          _syncTranslatedLyricsToSong(
            request.songPath,
            request.lyricsId,
            request.languageCode,
            translatedLines,
            translatedText,
          );
        },
      );
      if (success) {
        _context.translatedLyricsKeys.add(request.translationKey);
        await _saveTranslatedLyricsToDatabase(
          songPath: request.songPath,
          cacheKey: request.cacheKey,
          languageCode: request.languageCode,
        );
      }
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
    }
  }

  String _lyricsSourceForTranslation(MusicFile song) {
    final lyrics = song.lyrics;
    if (lyrics?.syncedLines.isNotEmpty == true) {
      return _support.lyricsTextWithTimestamps(lyrics!);
    }
    final plainText = lyrics?.plainText.trim() ?? '';
    if (plainText.isNotEmpty) {
      return plainText;
    }
    return _context.state.currentLyricsText.trim();
  }

  void _syncTranslatedLyricsToSong(
    String songPath,
    String lyricsId,
    String languageCode,
    List<String> translatedLines,
    String translatedText,
  ) {
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

    if (updatedSong == null) return;
    _context.bumpRevision();
  }

  Future<void> _saveTranslatedLyricsToDatabase({
    required String songPath,
    required String cacheKey,
    required String languageCode,
  }) async {
    try {
      final current = _support.songForPath(songPath);
      if (current == null) return;

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
      await _context.lyricsCacheRepository.saveLyricsTranslationCache(record);
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
