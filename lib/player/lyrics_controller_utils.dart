part of 'lyrics_controller.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

extension LyricsControllerUtils on LyricsController {
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

  Future<void> updateLyricsTimelineOffsetForCurrentSong(
    Duration timelineOffset,
  ) async {
    final song = _currentMusic();
    if (song == null) return;

    final lyrics = song.lyrics;
    if (lyrics == null) return;

    final normalizedOffset = _normalizeTimelineOffset(timelineOffset);
    if (lyrics.timelineOffset == normalizedOffset) return;

    final updatedLyrics = lyrics.copyWith(timelineOffset: normalizedOffset);
    final updatedSong = _replaceCurrentSongIfPath(
      song.path,
      (currentSong) => currentSong.copyWith(lyrics: updatedLyrics),
    );
    if (updatedSong == null) return;

    _bumpRevision();
    await _saveLyricsCacheForSong(updatedSong);
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

  Future<void> _saveLyricsCacheForSong(MusicFile song) async {
    final lyrics = song.lyrics;
    if (lyrics == null) return;

    final query = await _buildLyricsQueryForSong(song);
    if (query == null) return;

    final plainLyrics = lyrics.plainText.trim();

    try {
      await _lyricsCacheRepository.saveLyricsCache(
        LyricsCacheRecord(
          cacheKey: query.cacheKey,
          source: LyricsCacheSource.fromMusicLyricSource(lyrics.source),
          isSynced: lyrics.isSynced,
          syncedLyrics: lyrics.syncedLines.isNotEmpty
              ? _lyricsTextWithTimestamps(lyrics)
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

  Duration _normalizeTimelineOffset(Duration timelineOffset) {
    final clampedMillis = timelineOffset.inMilliseconds.clamp(-30000, 30000);
    final snappedMillis = ((clampedMillis / 100).round() * 100).toInt();
    return Duration(milliseconds: snappedMillis);
  }

  void _logDebug(String message) {
    if (!kDebugMode) return;
    debugPrint('[AudioService][Lyrics] $message');
  }
}
