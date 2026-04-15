import 'package:flutter/foundation.dart';

import '../models/lyric_line.dart';
import '../models/music_file.dart';
import '../models/music_lyric.dart';
import '../models/music_lyric_translation.dart';
import '../utils/language_code_utils.dart';
import '../utils/lrc_utils.dart';
import '../utils/lyrics_id_utils.dart';
import 'lyrics_cache_models.dart';
import 'lyrics_controller_context.dart';
import 'lyrics_generation_phase.dart';
import 'lyrics_service.dart';
import 'metadata_helper.dart';
import 'settings_service.dart';

class LyricsControllerSupport {
  LyricsControllerSupport(this._context);

  final LyricsControllerContext _context;

  String lyricsProviderTag() {
    return _context.settingsService.lyricsAiProvider.storageValue;
  }

  void cancelOngoingLyricsFetch({String? reason}) {
    _context.lyricsRequestSerial++;
    _context.lyricsRetrySerial++;
    _context.lyricsFetchCancelToken?.cancel(
      reason ?? 'lyrics generation started',
    );
    _context.lyricsFetchCancelToken = null;
    _context.setIsLyricsLoading(false);
  }

  void setGenerationStage(String stage) {
    switch (stage) {
      case 'uploading':
        _context.setLyricsGenerating(
          true,
          phase: LyricsGenerationPhase.uploading,
          progress: 0.0,
        );
        return;
      case 'processing':
        _context.setLyricsGenerating(
          true,
          phase: LyricsGenerationPhase.processing,
          progress: 1.0,
        );
        return;
      case 'generating':
        _context.setLyricsGenerating(
          true,
          phase: LyricsGenerationPhase.generating,
          progress: 1.0,
        );
        return;
      default:
        _context.setLyricsGenerating(
          false,
          phase: LyricsGenerationPhase.idle,
          progress: 0.0,
        );
    }
  }

  String lyricsSourceTextFromLyrics(MusicLyric lyrics) {
    if (lyrics.syncedLines.isNotEmpty) {
      return lyrics.syncedLines.map((line) => line.text).join('\n').trim();
    }
    return LrcUtils.stripTimestamps(lyrics.plainText).trim();
  }

  String lyricsTextWithTimestamps(MusicLyric lyrics) {
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

  String lyricsIdForSong(MusicFile song, {String? sourceLyrics}) {
    final existingId = song.lyrics?.id.trim() ?? '';
    if (existingId.isNotEmpty) return existingId;

    final text =
        (sourceLyrics ??
                lyricsSourceTextFromLyrics(song.lyrics ?? const MusicLyric()))
            .trim();
    if (text.isEmpty) return '';
    return LyricsIdUtils.fromLyricsText(text);
  }

  Future<String> lyricsCacheKeyForSong(MusicFile song) async {
    final query = await buildLyricsQueryForSong(song);
    return query?.cacheKey ?? '';
  }

  void clearLyricsStateForPath(String path) {
    final queue = _context.queue();
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].path != path) continue;
      if (queue[i].lyrics == null) continue;
      queue[i] = copySongWithLyrics(queue[i], null);
    }

    _context.clearState(notify: false);
  }

  void clearTranslationStateForPath(String path) {
    final queue = _context.queue();
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

  Future<void> updateLyricsTimelineOffsetForCurrentSong(
    Duration timelineOffset,
  ) async {
    final song = _context.currentMusic();
    if (song == null) return;

    final lyrics = song.lyrics;
    if (lyrics == null) return;

    final normalizedOffset = normalizeTimelineOffset(timelineOffset);
    if (lyrics.timelineOffset == normalizedOffset) return;

    final updatedLyrics = lyrics.copyWith(timelineOffset: normalizedOffset);
    final updatedSong = replaceCurrentSongIfPath(
      song.path,
      (currentSong) => currentSong.copyWith(lyrics: updatedLyrics),
    );
    if (updatedSong == null) return;

    _context.bumpRevision();
    await saveLyricsCacheForSong(updatedSong);
  }

  Future<void> fillLyricsForCurrentSong(String lyricsText) async {
    final song = _context.currentMusic();
    if (song == null) return;

    final normalizedText = lyricsText.replaceAll('\r\n', '\n').trim();
    if (normalizedText.isEmpty) return;

    final query =
        await buildLyricsQueryForSong(song) ??
        LyricsQuery(
          filePath: song.path,
          fileName: song.name,
          title: lyricsTitleForQuery(song),
          artist: lyricsArtistForQuery(song),
          album: lyricsAlbumForQuery(song),
        );
    final cacheKey = query.cacheKey;

    if (_context.currentMusic()?.path != song.path) return;

    final filledLyrics = MusicLyric(
      id: LyricsIdUtils.fromLyricsText(normalizedText),
      syncedLines: buildLyricsLines(const [], normalizedText),
      plainText: normalizedText,
      source: LyricsCacheSource.manualAdjust.musicLyricSource,
      timelineOffset: song.lyrics?.timelineOffset ?? Duration.zero,
    );

    final updatedSong = replaceCurrentSongIfPath(
      song.path,
      (currentSong) => currentSong.copyWith(lyrics: filledLyrics),
    );
    if (updatedSong == null) return;

    if (cacheKey.isNotEmpty) {
      await _context.lyricsCacheRepository.clearAllLyricsCachesByKey(cacheKey);
      _context.translatedLyricsKeys.removeWhere(
        (key) => key.startsWith('$cacheKey|'),
      );
      _context.translationInFlightKeys.removeWhere(
        (key) => key.startsWith('$cacheKey|'),
      );
    }

    _context.setHasLyrics(true);
    _context.setIsLyricsLoading(false);
    _context.setIsLyricsTranslating(false);
    _context.setLyricsTranslationStatus('');
    _context.clearLyricsGenerationStatus();
    _context.setLyricsSearchAttempted(true);
    _context.setCurrentLyricsLines(filledLyrics.syncedLines);
    _context.setCurrentLyricsText(filledLyrics.plainText);
    _context.setLyricsGenerating(
      false,
      phase: LyricsGenerationPhase.idle,
      progress: 0.0,
    );

    _context.bumpRevision();

    try {
      await _context.lyricsCacheRepository.saveLyricsCache(
        LyricsCacheRecord(
          cacheKey: cacheKey,
          source: LyricsCacheSource.manualAdjust,
          isSynced: filledLyrics.isSynced,
          syncedLyrics: filledLyrics.plainText,
          syncedLines: filledLyrics.syncedLines,
          timelineOffsetMillis: filledLyrics.timelineOffset.inMilliseconds,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      debugPrint('[LyricsController] Failed to cache manual lyrics: $e');
    }
  }

  Future<LyricsQuery?> buildLyricsQueryForSong(MusicFile song) async {
    final duration = await resolveLyricsDuration(song);
    if (duration == null) {
      logDebug(
        'lyrics query build failed -> title="${song.displayName}" '
        'path="${song.path}" reason=no_duration '
        'songDuration=${song.durationMillis} playerDuration=${_context.playerDuration()}',
      );
      return null;
    }

    return LyricsQuery(
      filePath: song.path,
      fileName: song.name,
      title: lyricsTitleForQuery(song),
      artist: lyricsArtistForQuery(song),
      album: lyricsAlbumForQuery(song),
      duration: duration,
    );
  }

  List<LyricLine> buildLyricsLines(
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

  String lyricsTitleForQuery(MusicFile song) {
    final displayName = song.displayName.trim();
    return displayName.isNotEmpty ? displayName : song.name.trim();
  }

  Duration? lyricsDurationForQuery(MusicFile song) {
    final durationMillis = song.durationMillis;
    if (durationMillis != null && durationMillis > 0) {
      return Duration(milliseconds: durationMillis);
    }
    return null;
  }

  Future<Duration?> resolveLyricsDuration(MusicFile song) async {
    final direct = lyricsDurationForQuery(song);
    if (direct != null &&
        song.durationMillis != null &&
        song.durationMillis! > 0) {
      return direct;
    }

    final dbMetadata = await _context.db.getSongMetadata(song.path);
    final dbDuration = dbMetadata?.duration;
    if (dbDuration != null && dbDuration > 0) {
      _context.cacheSongDuration(song.path, dbDuration);
      return Duration(milliseconds: dbDuration);
    }

    final fileMetadata = await MetadataHelper.readMetadataFromFile(song.path);
    final fileDuration = fileMetadata?.duration;
    if (fileDuration != null && fileDuration > 0) {
      _context.cacheSongDuration(song.path, fileDuration);
      return Duration(milliseconds: fileDuration);
    }

    final playerDuration = _context.playerDuration();
    if (playerDuration > Duration.zero) {
      return playerDuration;
    }

    return direct;
  }

  String? lyricsArtistForQuery(MusicFile song) {
    return normalizedLyricsField(song.artist);
  }

  String? lyricsAlbumForQuery(MusicFile song) {
    return normalizedLyricsField(song.album);
  }

  String? normalizedLyricsField(String? value) {
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

  MusicFile? replaceCurrentSongIfPath(
    String path,
    MusicFile Function(MusicFile song) update,
  ) {
    final index = _context.currentIndex();
    final queue = _context.queue();
    if (index < 0 || index >= queue.length) return null;

    final currentSong = queue[index];
    if (currentSong.path != path) return null;

    final updatedSong = update(currentSong);
    if (updatedSong == currentSong) return updatedSong;
    queue[index] = updatedSong;
    return updatedSong;
  }

  MusicFile copySongWithLyrics(MusicFile song, MusicLyric? lyrics) {
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

  Future<void> saveLyricsCacheForSong(MusicFile song) async {
    final lyrics = song.lyrics;
    if (lyrics == null) return;

    final query = await buildLyricsQueryForSong(song);
    if (query == null) return;

    final plainLyrics = lyrics.plainText.trim();

    try {
      await _context.lyricsCacheRepository.saveLyricsCache(
        LyricsCacheRecord(
          cacheKey: query.cacheKey,
          source: LyricsCacheSource.fromMusicLyricSource(lyrics.source),
          isSynced: lyrics.isSynced,
          syncedLyrics: lyrics.syncedLines.isNotEmpty
              ? lyricsTextWithTimestamps(lyrics)
              : (plainLyrics.isEmpty ? null : plainLyrics),
          syncedLines: lyrics.syncedLines,
          timelineOffsetMillis: lyrics.timelineOffset.inMilliseconds,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      debugPrint('[LyricsController] Failed to cache timeline offset: $e');
    }
  }

  Duration normalizeTimelineOffset(Duration timelineOffset) {
    final clampedMillis = timelineOffset.inMilliseconds.clamp(-30000, 30000);
    final snappedMillis = ((clampedMillis / 100).round() * 100).toInt();
    return Duration(milliseconds: snappedMillis);
  }

  Future<void> restoreCachedTranslations(MusicFile song) async {
    final lyrics = song.lyrics;
    if (lyrics == null) return;

    final query = await buildLyricsQueryForSong(song);
    if (query == null) return;

    try {
      final cachedTranslations = await _context.lyricsCacheRepository
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

      final queue = _context.queue();
      for (var i = 0; i < queue.length; i++) {
        final queuedSong = queue[i];
        if (queuedSong.path != song.path) continue;
        final queuedLyrics = queuedSong.lyrics;
        if (queuedLyrics == null) continue;
        queue[i] = queuedSong.copyWith(
          lyrics: queuedLyrics.copyWith(translations: updatedTranslations),
        );
      }

      _context.bumpRevision();
    } catch (e) {
      debugPrint('[LyricsController] Failed to restore translated lyrics: $e');
    }
  }

  void logDebug(String message) {
    _context.logDebug(message);
  }

  String _formatTimestamp(Duration duration) {
    final totalMilliseconds = duration.inMilliseconds;
    final minutes = totalMilliseconds ~/ 60000;
    final seconds = (totalMilliseconds % 60000) ~/ 1000;
    final centiseconds = (totalMilliseconds % 1000) ~/ 10;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${centiseconds.toString().padLeft(2, '0')}';
  }
}
