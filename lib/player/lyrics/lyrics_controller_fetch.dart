import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_lyric_translation.dart';
import 'package:vynody/utils/language_code_utils.dart';
import 'package:vynody/utils/lrc_utils.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/lyrics/lyrics_controller_context.dart';
import 'package:vynody/player/lyrics/lyrics_controller_utils.dart';
import 'package:vynody/player/lyrics/lyrics_generation_phase.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/lyrics/timeline/lyrics_timeline_service.dart';

class LyricsFetchCoordinator {
  LyricsFetchCoordinator(this._context, this._support);

  final LyricsControllerContext _context;
  final LyricsControllerSupport _support;

  /// duration 未就绪时的最长挂起时间。
  /// 超过这个窗口仍拿不到时长，说明这次播放的元数据链本身有问题，
  /// 继续等没有意义，交给下一次元数据刷新重新触发。
  static const Duration _durationWaitTimeout = Duration(seconds: 15);

  void scheduleFetch(MusicFile song, {Duration? preservedTimelineOffset}) {
    unawaited(
      fetchAndLog(song, preservedTimelineOffset: preservedTimelineOffset),
    );
  }

  /// 进歌词模式的唯一入口。
  ///
  /// 触发点（歌词模式开启、切歌、元数据就绪、桌面歌词开启）全部收敛到这里，
  /// 顺序固定为「队列内存 → 本地缓存 → 分层查询」，并保证同一首歌幂等：
  /// 已在途就忽略，而不是把前一个请求 cancel 掉重来。
  Future<void> ensureLyricsForSong(MusicFile song) async {
    if (_context.currentMusic()?.path != song.path) return;

    if (_context.lyricsGeneration.isGenerating &&
        _context.lyricsGeneration.songPath == song.path) {
      _support.logDebug(
        'ensure skipped, lyrics generation in progress -> '
        'title="${song.displayName}"',
      );
      return;
    }

    if (_context.lyricsFetchInFlightPath == song.path) {
      _support.logDebug(
        'ensure skipped, fetch already in flight -> '
        'title="${song.displayName}"',
      );
      return;
    }

    final queuedSong = _support.songForPath(song.path);
    final queuedLyrics = queuedSong?.lyrics;
    final hasQueuedLyrics = queuedLyrics != null &&
        (queuedLyrics.plainText.trim().isNotEmpty ||
            queuedLyrics.syncedLines.isNotEmpty ||
            queuedLyrics.translations.isNotEmpty);
    if (hasQueuedLyrics && queuedSong != null) {
      _support.logDebug(
        'ensure memory hit -> title="${song.displayName}" '
        'lines=${queuedLyrics.syncedLines.length}',
      );
      restoreFromQueuedLyrics(queuedSong);
      return;
    }

    if (await tryFastRestoreFromCache(song)) {
      return;
    }

    if (_context.currentMusic()?.path != song.path) return;
    await fetchAndLog(song);
  }

  /// 队列里的曲目已经带歌词时直接恢复，不触碰数据库与网络。
  void restoreFromQueuedLyrics(MusicFile song) {
    final songLyrics = song.lyrics;
    if (songLyrics == null) {
      _context.clearState(notify: false, preserveTaskState: true);
      return;
    }

    _context.setHasLyrics(
      songLyrics.plainText.trim().isNotEmpty ||
          songLyrics.syncedLines.isNotEmpty ||
          songLyrics.translations.isNotEmpty,
    );
    _context.setIsLyricsLoading(false);
    _context.setCurrentLyricsLines(songLyrics.syncedLines);
    _context.setCurrentLyricsText(songLyrics.plainText);
    _context.setLyricsSearchAttempted(true);
    unawaited(_support.restoreCachedTranslations(song));
    unawaited(_context.watchLyricsCacheForSong(song));
    _context.bumpRevision();
    _support.logDebug(
      'lyrics restored from queue -> title="${song.displayName}" '
      'lines=${songLyrics.syncedLines.length} synced=${songLyrics.isSynced}',
    );
  }

  /// 纯 SQLite 命中，微秒级返回。
  ///
  /// 这里刻意不走 [LyricsControllerSupport.buildLyricsQueryForSong]：
  /// 那条路要先解析出 duration，刚切歌那几秒拿不到就直接返回 null，
  /// 会让明明存在的缓存 miss。缓存键只由文件路径决定，与时长无关。
  Future<bool> tryFastRestoreFromCache(MusicFile song) async {
    final cached = await _support.readCachedLyricsRecordByPath(song.path);
    if (cached == null || cached.source == LyricsCacheSource.none) {
      return false;
    }
    final hasText = cached.syncedLyrics?.trim().isNotEmpty ?? false;
    if (!hasText && cached.syncedLines.isEmpty) {
      return false;
    }

    final cacheKey = cached.cacheKey.isNotEmpty
        ? cached.cacheKey
        : _support.lyricsCacheKeyForPath(song.path);
    final translationRecords = await _context.lyricsCacheRepository
        .getLyricsTranslationCaches(cacheKey);
    final translations = _support.translationsFromCacheRecords(
      translationRecords,
    );

    if (!_support.applyLyricsRecordToCurrent(
      songPath: song.path,
      record: cached,
      translations: translations,
    )) {
      return false;
    }

    unawaited(_context.watchLyricsCacheForSong(song));
    _context.bumpRevision();
    if (translations.isNotEmpty) {
      _context.bumpLyricsLayoutRevision();
    }
    _support.logDebug(
      'fast restore from SQLite cache hit -> title="${song.displayName}" '
      'source=${cached.source.dbValue} lines=${cached.syncedLines.length}',
    );
    return true;
  }

  /// 播放器时长首次就绪时由 AudioService 回调，用来续跑被挂起的查询。
  void onSongDurationReady(String path) {
    if (_context.lyricsDurationPendingPath != path) return;

    _context.lyricsDurationPendingTimer?.cancel();
    _context.lyricsDurationPendingTimer = null;
    _context.lyricsDurationPendingPath = null;

    final song = _context.currentMusic();
    if (song == null || song.path != path) return;
    if (_context.state.hasLyrics) return;

    _support.logDebug(
      'duration ready, resuming deferred lyrics fetch -> "$path"',
    );
    unawaited(fetchAndLog(song));
  }

  void _deferUntilDurationReady(MusicFile song) {
    _context.lyricsDurationPendingTimer?.cancel();
    _context.lyricsDurationPendingPath = song.path;
    _context.lyricsDurationPendingTimer = Timer(_durationWaitTimeout, () {
      if (_context.lyricsDurationPendingPath != song.path) return;
      _context.lyricsDurationPendingPath = null;
      _context.lyricsDurationPendingTimer = null;
      _support.logDebug(
        'duration wait expired -> title="${song.displayName}" path="${song.path}"',
      );
    });
  }

  Future<void> fetchAndLog(
    MusicFile song, {
    Duration? preservedTimelineOffset,
  }) async {
    if (_context.lyricsGeneration.isGenerating &&
        _context.lyricsGeneration.songPath == song.path) {
      _support.logDebug(
        'fetch skipped because lyrics generation is in progress for same song -> '
        'title="${song.displayName}" path="${song.path}"',
      );
      return;
    }

    _context.lyricsFetchCancelToken?.cancel(
      'replaced by a newer lyrics request',
    );
    final cancelToken = CancelToken();
    _context.lyricsFetchCancelToken = cancelToken;
    _context.lyricsFetchInFlightPath = song.path;
    _context.setIsLyricsLoading(true);

    _support.logDebug(
      'fetch request created -> title="${song.displayName}" '
      'path="${song.path}" cancelToken=${identityHashCode(cancelToken)}',
    );

    final meta = await _support.resolveLyricsQueryMetadata(song);
    final queryDuration = meta.duration;
    if (queryDuration == null) {
      _support.logDebug(
        'fetch deferred, duration not ready -> title="${song.displayName}" '
        'path="${song.path}" playerDuration=${_context.playerDuration()} '
        'songDuration=${song.durationMillis}',
      );
      if (_context.lyricsFetchCancelToken == cancelToken) {
        _context.lyricsFetchCancelToken = null;
      }
      if (_context.lyricsFetchInFlightPath == song.path) {
        _context.lyricsFetchInFlightPath = null;
      }
      _context.setIsLyricsLoading(false);
      _deferUntilDurationReady(song);
      return;
    }

    final requestId = ++_context.lyricsRequestSerial;
    final query = LyricsQuery(
      filePath: song.path,
      fileName: song.name,
      title: meta.title,
      artist: meta.artist,
      album: meta.album,
      duration: queryDuration,
    );

    _context.setIsLyricsLoading(true);
    _support.logDebug(
      '[LyricsQuery:Fetch] title="${query.title}" artist="${query.artist ?? ''}" '
      'album="${query.album ?? ''}" queryDuration=$queryDuration '
      'playerDuration=${_context.playerDuration()} requestId=$requestId '
      'cancelToken=${identityHashCode(cancelToken)}',
    );

    try {
      _support.logDebug(
        'fetch dispatching to lyrics service -> requestId=$requestId '
        'path="${song.path}"',
      );
      final result = await _context.lyricsService.fetchBestLyrics(
        query: query,
        cancelToken: cancelToken,
      );
      if (requestId != _context.lyricsRequestSerial ||
          _context.currentMusic()?.path != song.path) {
        _support.logDebug(
          'fetch ignored due to stale request -> title="${song.displayName}" '
          'requestId=$requestId latest=${_context.lyricsRequestSerial} '
          'currentPath="${_context.currentMusic()?.path}"',
        );
        return;
      }

      final rawLyricsText = result?.lyricsText ?? '';
      final parsedResult = LrcUtils.parseLyricsWithTranslation(rawLyricsText);
      final effectiveSyncedLines = _support.buildLyricsLines(
        parsedResult.syncedLines.isNotEmpty
            ? parsedResult.syncedLines
            : (result?.syncedLines ?? const []),
        rawLyricsText,
      );

      _context.setIsLyricsLoading(false);
      _context.setLyricsSearchAttempted(true);

      final translationsMap = <String, MusicLyricTranslation>{};
      final previousLyrics = _support.songForPath(song.path)?.lyrics;
      if (previousLyrics?.translations != null) {
        translationsMap.addAll(previousLyrics!.translations);
      }
      if (parsedResult.hasTranslation) {
        final langCode = LanguageCodeUtils.currentAppLanguageCode().isNotEmpty
            ? LanguageCodeUtils.currentAppLanguageCode()
            : 'zh';
        final existingTranslation = translationsMap[langCode];
        if (existingTranslation == null || !existingTranslation.hasContent) {
          translationsMap[langCode] = MusicLyricTranslation(
            languageCode: langCode,
            translatedLines: parsedResult.translatedLines!,
            translatedText: parsedResult.translatedLines!.join('\n'),
            provider: 'embedded_lrc',
            updatedAt: DateTime.now(),
          );
          // 多段 LRC 解析出的译文必须落库：缓存监视（_syncLyricsCacheWatch）
          // 只从译文缓存表读取译文，不落库的话同步时会用空译文覆盖上面的内存结果，
          // 导致播放内嵌双语文词只显示原文一行
          await _persistEmbeddedTranslationIfAbsent(
            cacheKey: query.cacheKey,
            languageCode: langCode,
            translatedLines: parsedResult.translatedLines!,
          );
        }
      }

      if (result == null || rawLyricsText.trim().isEmpty) {
        _context.setHasLyrics(false);
        _context.setCurrentLyricsLines(const <LyricLine>[]);
        _context.setCurrentLyricsText('');
        // 不写空 lyrics：写进去会让下一次 ensureLyricsForSong 走「内存恢复」
        // 分支，把一首没查到歌词的歌永久钉死在空状态。
        _context.bumpRevision();
        _support.logDebug(
          'fetch returned no lyrics -> title="${song.displayName}" '
          'requestId=$requestId',
        );
        _context.lyricsService.debugPrintSelection(query, result);
        return;
      }

      // 保留用户手工调过的偏移：网络结果默认是零偏移，
      // 直接落库会把调好的对齐关系冲掉。
      final existingOffset = previousLyrics?.timelineOffset ?? Duration.zero;
      final resultOffset = result.timelineOffset;
      final effectiveOffset = resultOffset != Duration.zero
          ? resultOffset
          : (existingOffset != Duration.zero
                ? existingOffset
                : (preservedTimelineOffset ?? Duration.zero));

      // 库与展示用同一份数据：service 层写库用的是 result.syncedLines，
      // 与这里 parse 出来的行列表可能不同，覆盖一次保证读回来一模一样。
      final unifiedRecord = LyricsCacheRecord(
        cacheKey: query.cacheKey,
        source: LyricsCacheSource.fromExternalSourceTag(result.source),
        isSynced: effectiveSyncedLines.any((line) => line.isTimed),
        syncedLyrics: rawLyricsText,
        syncedLines: effectiveSyncedLines,
        timelineOffsetMillis: effectiveOffset.inMilliseconds,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      try {
        await _context.lyricsCacheRepository.saveLyricsCache(unifiedRecord);
      } catch (e) {
        debugPrint(
          '[LyricsController] Failed to persist unified lyrics cache: $e',
        );
      }

      _support.applyLyricsRecordToCurrent(
        songPath: song.path,
        record: unifiedRecord,
        translations: translationsMap,
      );

      final updated = _support.songForPath(song.path);
      if (updated != null) {
        unawaited(_context.watchLyricsCacheForSong(updated));
        unawaited(_support.restoreCachedTranslations(updated));
      }

      if (song.path.isNotEmpty) {
        final description = switch (result.source) {
          'embedded' => 'Embedded',
          'local_lrc' => 'Local LRC',
          'remote_lrc' => 'Remote LRC',
          'remote_server' => 'Remote Media Server',
          _ => 'Online',
        };
        unawaited(
          LyricsTimelineService.instance.ensureInitialSnapshot(
            cacheKey: song.path,
            lyrics: rawLyricsText,
            translation: parsedResult.translatedLines?.join('\n'),
            timelineOffsetMillis: effectiveOffset.inMilliseconds,
            description: description,
          ),
        );
      }

      _support.logDebug(
        'fetch state committed -> title="${song.displayName}" '
        'requestId=$requestId hasLyrics=${_context.state.hasLyrics} '
        'searched=${_context.state.lyricsSearchAttempted} '
        'lines=${_context.state.currentLyricsLines.length} '
        'textLen=${_context.state.currentLyricsText.trim().length}',
      );
      _context.bumpRevision();
      _support.logDebug(
        'fetch completed -> title="${song.displayName}" requestId=$requestId '
        'hasLyrics=${result.track.hasLyrics} source=${result.source}',
      );
      _context.lyricsService.debugPrintSelection(query, result);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _support.logDebug(
          'fetch canceled -> title="${song.displayName}" '
          'path="${song.path}" requestId=$requestId '
          'cancelToken=${identityHashCode(cancelToken)}',
        );
        return;
      }
      debugPrint('[LyricsController] Failed to fetch lyrics: $e');
      if (requestId == _context.lyricsRequestSerial &&
          _context.currentMusic()?.path == song.path) {
        _context.setIsLyricsLoading(false);
        _context.setLyricsSearchAttempted(true);
      }
    } catch (e) {
      debugPrint('[LyricsController] Failed to fetch lyrics: $e');
      if (requestId == _context.lyricsRequestSerial &&
          _context.currentMusic()?.path == song.path) {
        _context.setIsLyricsLoading(false);
        _context.setLyricsSearchAttempted(true);
      }
    } finally {
      if (_context.lyricsFetchCancelToken == cancelToken) {
        _support.logDebug(
          'fetch cleanup -> title="${song.displayName}" requestId=$requestId '
          'cancelToken=${identityHashCode(cancelToken)}',
        );
        _context.lyricsFetchCancelToken = null;
      }
      if (_context.lyricsFetchInFlightPath == song.path) {
        _context.lyricsFetchInFlightPath = null;
      }
    }
  }

  /// 将多段 LRC（原文/译文同时间轴）解析出的译文写入译文缓存表。
  /// 已存在同一语言的译文记录时不覆盖，避免冲掉 AI 翻译等其他来源的结果。
  Future<void> _persistEmbeddedTranslationIfAbsent({
    required String cacheKey,
    required String languageCode,
    required List<String> translatedLines,
  }) async {
    if (cacheKey.isEmpty) return;
    try {
      final existing = await _context.lyricsCacheRepository
          .getLyricsTranslationCaches(cacheKey);
      if (existing.any((record) => record.languageCode == languageCode)) {
        return;
      }
      await _context.lyricsCacheRepository.saveLyricsTranslationCache(
        LyricsTranslationCacheRecord(
          cacheKey: cacheKey,
          languageCode: languageCode,
          translatedText: translatedLines.join('\n'),
          translatedLines: translatedLines,
          provider: 'embedded_lrc',
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      debugPrint('[LyricsController] Failed to cache embedded translation: $e');
    }
  }

  Future<void> clearAllLyricsCache() async {
    _support.cancelOngoingLyricsFetch(reason: 'lyrics cache cleared');
    await _context.lyricsCacheRepository.clearAllLyricsCaches();

    final queue = _context.queue();
    for (var i = 0; i < queue.length; i++) {
      final song = queue[i];
      if (song.lyrics == null) continue;
      final updated = _support.copySongWithLyrics(song, null);
      _context.updateSongInPlaylist(updated);
    }

    _context.translatedLyricsKeys.clear();
    _context.translationInFlightKeys.clear();
    _context.setLyricsTranslationStatus('');
    _context.setHasLyrics(false);
    _context.setIsLyricsLoading(false);
    _context.setIsLyricsTranslating(false);
    _context.setLyricsGenerating(
      false,
      phase: LyricsGenerationPhase.idle,
      progress: 0.0,
    );
    _context.setLyricsSearchAttempted(false);
    _context.setCurrentLyricsLines(const []);
    _context.setCurrentLyricsText('');
    _context.bumpRevision();

    final current = _context.currentMusic();
    if (_context.isLyricsActive() && current != null) {
      scheduleFetch(current);
    }
  }

  Future<void> clearLyricsCacheForCurrentSong() async {
    final song = _context.currentMusic();
    if (song == null) return;

    final cacheKey = await _support.lyricsCacheKeyForSong(song);
    if (cacheKey.isNotEmpty) {
      await _context.lyricsCacheRepository.clearAllLyricsCachesByKey(cacheKey);
      _context.translatedLyricsKeys.removeWhere(
        (key) => key.startsWith('$cacheKey|'),
      );
      _context.translationInFlightKeys.removeWhere(
        (key) => key.startsWith('$cacheKey|'),
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('selected_lyric_source_$cacheKey');
      } catch (e) {
        debugPrint('[LyricsController] Failed to remove selection preference: $e');
      }
    }

    if (_context.currentMusic()?.path != song.path) return;

    _support.cancelOngoingLyricsFetch(
      reason: 'lyrics cache cleared for current song',
    );
    _support.clearLyricsStateForPath(song.path);
    _context.setLyricsTranslationStatus('');
    _context.bumpRevision();
  }

  Future<void> clearTranslationCacheForCurrentSong() async {
    final song = _context.currentMusic();
    if (song == null) return;

    final cacheKey = await _support.lyricsCacheKeyForSong(song);
    if (cacheKey.isNotEmpty) {
      await _context.lyricsCacheRepository.clearLyricsTranslationCacheByKey(
        cacheKey,
      );
      _context.translatedLyricsKeys.removeWhere(
        (key) => key.startsWith('$cacheKey|'),
      );
      _context.translationInFlightKeys.removeWhere(
        (key) => key.startsWith('$cacheKey|'),
      );
    }

    if (_context.currentMusic()?.path != song.path) return;

    _context.clearPendingLyricsTranslationUpdatesForSong(song.path);
    _support.clearTranslationStateForPath(song.path);
    _context.setLyricsTranslationStatus('');
    _context.bumpRevision();
    _context.bumpLyricsLayoutRevision();
  }

  Future<void> requeryLyricsForCurrentSong() async {
    final song = _context.currentMusic();
    if (song == null) return;

    // 清缓存会连库里的 timelineOffset 一起删掉，先把用户调过的偏移抓出来，
    // 重查结束后回填，避免「重新查询」把对齐关系清零。
    final preservedOffset = _support.songForPath(song.path)?.lyrics?.timelineOffset;

    _support.logDebug(
      '[LyricsQuery:Requery] Manual requery triggered -> title="${song.displayName}" '
      'artist="${song.artist ?? ''}" album="${song.album ?? ''}" '
      'preservedOffset=${preservedOffset?.inMilliseconds ?? 0}',
    );
    await clearLyricsCacheForCurrentSong();
    if (_context.currentMusic()?.path != song.path) return;
    scheduleFetch(song, preservedTimelineOffset: preservedOffset);
  }

  Future<void> clearTranslationCache() async {
    await _context.lyricsCacheRepository.clearLyricsTranslationCache();

    _context.translatedLyricsKeys.clear();
    _context.translationInFlightKeys.clear();
    _context.setLyricsTranslationStatus('');

    final queue = _context.queue();
    for (var i = 0; i < queue.length; i++) {
      final song = queue[i];
      final lyrics = song.lyrics;
      if (lyrics == null || lyrics.translations.isEmpty) continue;

      final updated = song.copyWith(
        lyrics: lyrics.copyWith(
          translations: const <String, MusicLyricTranslation>{},
        ),
      );
      _context.updateSongInPlaylist(updated);
    }

    _context.bumpRevision();
  }

  Future<void> restoreCachedTranslations(MusicFile song) async {
    await _support.restoreCachedTranslations(song);
  }
}
