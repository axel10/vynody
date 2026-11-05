import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_lyric.dart';
import 'package:vynody/utils/language_code_utils.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/lyrics/lyrics_ai_service.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_controller_context.dart';
import 'package:vynody/player/lyrics/lyrics_generation_display_state.dart';
import 'package:vynody/player/lyrics/lyrics_controller_fetch.dart';
import 'package:vynody/player/lyrics/lyrics_controller_generation.dart';
import 'package:vynody/player/lyrics/lyrics_controller_state.dart';
import 'package:vynody/player/lyrics/lyrics_controller_translation.dart';
import 'package:vynody/player/lyrics/lyrics_controller_utils.dart';
import 'package:vynody/player/lyrics/lyrics_riverpod.dart';
import 'package:vynody/player/lyrics/timeline/lyrics_timeline_service.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/lyrics/lyrics_generation_phase.dart';
import 'package:vynody/player/lyrics/lyrics_song_task_state.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/settings/settings_service.dart';

class LyricsController extends Notifier<LyricsControllerState> {
  late MetadataDatabase _db;
  late MusicFile? Function() _currentMusic;
  late List<MusicFile> Function() _queue;
  late int Function() _currentIndex;
  late Duration Function() _playerDuration;
  late bool Function() _isLyricsActive;
  late void Function(String path, int durationMillis) _cacheSongDuration;
  late LyricsCacheRepository _lyricsCacheRepository;
  late LyricsService _lyricsService;
  late LyricsAiService _lyricsAiService;
  late SettingsService _settingsService;
  late LyricsControllerContext _context;
  late LyricsControllerSupport _support;
  late LyricsFetchCoordinator _fetchCoordinator;
  late LyricsGenerationCoordinator _generationCoordinator;
  late LyricsTranslationCoordinator _translationCoordinator;
  StreamSubscription<List<LyricsCacheRecord>>? _lyricsCacheSubscription;
  StreamSubscription<List<LyricsTranslationCacheRecord>>?
  _lyricsTranslationCacheSubscription;
  String? _watchedLyricsCacheKey;
  String? _watchedLyricsSongPath;
  bool _lyricsCacheWatchPrimed = false;

  @override
  LyricsControllerState build() {
    final dependencies = ref.watch(lyricsControllerDependenciesProvider);
    ref.onDispose(clearLyricsCacheWatch);
    _db = dependencies.db;
    _currentMusic = dependencies.currentMusic;
    _queue = dependencies.queue;
    _currentIndex = dependencies.currentIndex;
    _playerDuration = dependencies.playerDuration;
    _isLyricsActive = dependencies.isLyricsActive;
    _cacheSongDuration = dependencies.cacheSongDuration;
    final updateSongInPlaylist = dependencies.updateSongInPlaylist;
    _lyricsCacheRepository = LyricsCacheRepository(db: _db);
    // 复用 provider 里的实例，它注入了远程服务器歌词 fetcher；
    // 自己 new 一个会让 Subsonic / WebDAV 服务端歌词分支永远不生效。
    _lyricsService = ref.read(lyricsServiceProvider);
    _settingsService = ref.read(settingsServiceProvider);
    final effectiveLanguageCode = ref.read(
      lyricsTranslationLanguageCodeProvider,
    );
    ref.listen<String>(lyricsTranslationLanguageCodeProvider, (
      previous,
      next,
    ) {
      if (state.lyricsTranslationLanguageCode == next) {
        return;
      }
      Future.microtask(() {
        if (state.lyricsTranslationLanguageCode == next) {
          return;
        }
        state = state.copyWith(
          lyricsTranslationLanguageCode: next,
        );
      });
    });
    _lyricsAiService = ref.read(lyricsAiServiceProvider);
    _context = LyricsControllerContext(
      db: _db,
      currentMusic: _currentMusic,
      queue: _queue,
      currentIndex: _currentIndex,
      playerDuration: _playerDuration,
      isLyricsActive: _isLyricsActive,
      cacheSongDuration: _cacheSongDuration,
      updateSongInPlaylist: updateSongInPlaylist,
      lyricsCacheRepository: _lyricsCacheRepository,
      lyricsService: _lyricsService,
      settingsService: _settingsService,
      lyricsAiService: _lyricsAiService,
      getState: () => state,
      setState: (newState) => state = newState,
      clearState: ({bool notify = false, bool preserveTaskState = true}) =>
          clearState(notify: notify, preserveTaskState: preserveTaskState),
      setIsLyricsLoading: (value) => _isLyricsLoading = value,
      setIsLyricsTranslating: (value) => _isLyricsTranslating = value,
      setLyricsTranslationStatus: (value) => _lyricsTranslationStatus = value,
      setTranslationDisplayLanguage: _setTranslationDisplayLanguage,
      setLyricsGenerationStatus: (value) => _lyricsGenerationStatus = value,
      setLyricsGenerationDisplayState: (value) =>
          _setLyricsGenerationDisplayState(value),
      setHasLyrics: (value) => _hasLyrics = value,
      setLyricsSearchAttempted: (value) => _lyricsSearchAttempted = value,
      setCurrentLyricsLines: (value) => _currentLyricsLines = value,
      setCurrentLyricsText: (value) => _currentLyricsText = value,
      setLyricsGenerating: _setLyricsGenerating,
      startLyricsGenerationStatus: _startLyricsGenerationStatus,
      clearLyricsGenerationStatus: _clearLyricsGenerationStatus,
      watchLyricsCacheForSong: watchLyricsCacheForSong,
      bumpRevision: _bumpRevision,
      bumpLyricsLayoutRevision: _bumpLyricsLayoutRevision,
      isLyricsPanelScrolling: () =>
          ref.read(lyricsPanelScrollAnimatingProvider),
      isProUnlocked: () => ref.read(isProUnlockedProvider),
      logDebug: _logDebug,
    );
    _support = LyricsControllerSupport(_context);
    _fetchCoordinator = LyricsFetchCoordinator(_context, _support);
    _generationCoordinator = LyricsGenerationCoordinator(_context, _support);
    _translationCoordinator = LyricsTranslationCoordinator(_context, _support);
    return LyricsControllerState(
      lyricsTranslationLanguageCode: effectiveLanguageCode,
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

  /// 只由歌词缓存记录驱动，不额外 `bumpRevision`：调用方（缓存同步）随后会统一 bump。
  ///
  /// 刻意不在这里做语言码归一化：译文表的 key 就是落库时的原值，展示侧要按同一个
  /// 字符串查表，归一化是写入方（翻译 / 选语言）的职责。
  void _setTranslationDisplayLanguage(String value) {
    final next = value.trim();
    if (state.translationDisplayLanguageCode == next) return;
    state = state.copyWith(translationDisplayLanguageCode: next);
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

  void _setLyricsGenerationDisplayState(LyricsGenerationDisplayState value) {
    if (_context.updateLyricsGenerationDisplayState(value)) {
      _bumpRevision();
    }
  }

  void _bumpRevision() {
    state = state.copyWith(revision: state.revision + 1);
  }

  void _bumpLyricsLayoutRevision() {
    ref.read(lyricsLayoutRevisionProvider.notifier).state++;
  }

  void setTranslationLanguageCode(String languageCode) {
    final normalized = LanguageCodeUtils.normalizeLanguageCode(languageCode);
    final effective = normalized.isEmpty
        ? LanguageCodeUtils.currentAppLanguageCode()
        : normalized;

    if (_settingsService.lyricsTranslationTargetLanguageCode != normalized) {
      _settingsService.lyricsTranslationTargetLanguageCode = normalized;
    }
    if (state.lyricsTranslationLanguageCode == effective) {
      return;
    }
    state = state.copyWith(lyricsTranslationLanguageCode: effective);
  }

  void clearState({bool notify = false, bool preserveTaskState = true}) {
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
    clearLyricsCacheWatch();
  }

  /// 队列里的曲目已经带歌词时直接恢复，不触碰数据库与网络。
  void restoreFromSongLyrics(MusicFile song) {
    _fetchCoordinator.restoreFromQueuedLyrics(song);
  }

  /// 切歌 / 进歌词面板时的快速恢复：只查 SQLite，不依赖 duration。
  Future<bool> tryFastRestoreFromCache(MusicFile song) {
    return _fetchCoordinator.tryFastRestoreFromCache(song);
  }

  /// 进歌词模式的唯一入口：内存 → 本地缓存 → 分层查询，同曲幂等。
  Future<void> ensureLyricsForSong(MusicFile song) {
    return _fetchCoordinator.ensureLyricsForSong(song);
  }

  /// 播放器时长首次就绪时由 AudioService 回调，续跑被挂起的查询。
  void onSongDurationReady(String path) {
    _fetchCoordinator.onSongDurationReady(path);
  }

  void scheduleFetch(MusicFile song, {Duration? preservedTimelineOffset}) {
    _fetchCoordinator.scheduleFetch(
      song,
      preservedTimelineOffset: preservedTimelineOffset,
    );
  }

  Future<void> fetchAndLog(MusicFile song) {
    return _fetchCoordinator.fetchAndLog(song);
  }

  Future<void> watchLyricsCacheForSong(MusicFile song) async {
    // 缓存键只由文件路径决定，不经过 buildLyricsQueryForSong —— 那条路需要
    // duration，时长未就绪时会让本应立即建立的监听直接放弃。
    var cacheKey = _support.lyricsCacheKeyForPath(song.path);
    if (cacheKey.isEmpty) {
      clearLyricsCacheWatch();
      return;
    }

    final cached = await _support.readCachedLyricsRecordByPath(song.path);
    if (cached != null && cached.cacheKey.isNotEmpty) {
      cacheKey = cached.cacheKey;
    }

    final currentPath = _context.currentMusic()?.path;
    if (currentPath != song.path) {
      return;
    }

    if (_watchedLyricsCacheKey == cacheKey &&
        _watchedLyricsSongPath == song.path) {
      return;
    }

    clearLyricsCacheWatch();
    _watchedLyricsCacheKey = cacheKey;
    _watchedLyricsSongPath = song.path;

    _lyricsCacheSubscription = _context.lyricsCacheRepository
        .watchLyricsCaches(cacheKey)
        .listen(
          (_) => unawaited(_syncLyricsCacheWatch(song.path, cacheKey)),
          onError: (error, stackTrace) {
            debugPrint('[LyricsController] lyrics cache watch error: $error');
          },
        );
    _lyricsTranslationCacheSubscription = _context.lyricsCacheRepository
        .watchLyricsTranslationCaches(cacheKey)
        .listen(
          (_) => unawaited(_syncLyricsCacheWatch(song.path, cacheKey)),
          onError: (error, stackTrace) {
            debugPrint(
              '[LyricsController] lyrics translation cache watch error: $error',
            );
          },
        );

    unawaited(_syncLyricsCacheWatch(song.path, cacheKey));
  }

  static const String _activeLyricSourcePrefix = 'selected_lyric_source_';

  Future<({LyricsCacheSource source, String languageCode})?> getSelectedLyricSource(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString('$_activeLyricSourcePrefix$cacheKey');
      if (val != null && val.contains('|')) {
        final parts = val.split('|');
        return (
          source: LyricsCacheSource.fromDbValue(parts[0]),
          languageCode: parts.length > 1 ? parts[1] : '',
        );
      }
    } catch (e) {
      debugPrint('[LyricsController] Error getting selected lyric source: $e');
    }
    return null;
  }

  Future<void> setSelectedLyricSource(String cacheKey, LyricsCacheSource source, {String languageCode = ''}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_activeLyricSourcePrefix$cacheKey';
      await prefs.setString(key, '${source.dbValue}|$languageCode');
      
      final currentSong = _context.currentMusic();
      if (currentSong != null) {
        final currentQuery = await _support.buildLyricsQueryForSong(currentSong);
        final currentKey = currentQuery?.cacheKey ?? cacheKey;
        if (currentKey != cacheKey) {
          await prefs.setString('$_activeLyricSourcePrefix$currentKey', '${source.dbValue}|$languageCode');
        }

        // 切换来源即覆盖旧缓存：将新选中的来源持久化覆盖到数据库中
        final available = await getAvailableLyricRecords(currentSong);
        LyricsCacheRecord? targetRecord;
        for (final r in available) {
          if (r.source == source && r.languageCode == languageCode) {
            targetRecord = r;
            break;
          }
        }
        targetRecord ??= available.where((r) => r.source == source).firstOrNull;

        if (targetRecord != null) {
          await _context.lyricsCacheRepository.saveLyricsCache(
            targetRecord.copyWith(
              cacheKey: currentKey,
              updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        }

        await _syncLyricsCacheWatch(currentSong.path, currentKey);
      }
    } catch (e) {
      debugPrint('[LyricsController] Error setting selected lyric source: $e');
    }
  }

  Future<LyricsQuery?> buildLyricsQueryForSong(MusicFile song) {
    return _support.buildLyricsQueryForSong(song);
  }

  Future<List<LyricsCacheRecord>> getAvailableLyricRecords(MusicFile song) async {
    final query = await _support.buildLyricsQueryForSong(song);
    final cacheKey = query?.cacheKey.trim() ?? '';
    if (query == null || cacheKey.isEmpty) return const [];

    final records = await _context.lyricsService.getOrPopulateAvailableLyricRecords(query);

    debugPrint(
      '[LyricsController] getAvailableLyricRecords for "${song.displayName}": cacheKey="$cacheKey", count=${records.length}, sources=${records.map((r) => r.source.dbValue).toList()}',
    );

    return records;
  }

  void clearLyricsCacheWatch() {
    _lyricsCacheSubscription?.cancel();
    _lyricsCacheSubscription = null;
    _lyricsTranslationCacheSubscription?.cancel();
    _lyricsTranslationCacheSubscription = null;
    _watchedLyricsCacheKey = null;
    _watchedLyricsSongPath = null;
    _lyricsCacheWatchPrimed = false;
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

  MusicLyric? currentLyricsForCurrentSong() {
    final currentSong = _currentMusic();
    if (currentSong == null) return null;

    return _support.songForPath(currentSong.path)?.lyrics;
  }

  /// 统一合成当前应展示的 [MusicLyric] 对象，封装暂态 liveText 与持久化 lyrics 的合并逻辑
  MusicLyric? displayLyricsForCurrentSong() {
    final currentSong = _currentMusic();
    if (currentSong == null) return null;

    final baseLyrics = _support.songForPath(currentSong.path)?.lyrics;
    final liveText = state.currentLyricsText.trim();
    if (liveText.isEmpty) {
      return baseLyrics;
    }

    final effectiveLines = state.currentLyricsLines.isNotEmpty
        ? state.currentLyricsLines
        : (baseLyrics?.syncedLines ?? const []);

    if (baseLyrics == null) {
      return MusicLyric(
        syncedLines: effectiveLines,
        plainText: liveText,
      );
    }

    return baseLyrics.copyWith(
      syncedLines: effectiveLines,
      plainText: liveText,
    );
  }

  Future<String?> generateLyricsForCurrentSong() {
    return _generationCoordinator.generateLyricsForCurrentSong();
  }

  Future<String?> generateTimelineForCurrentSong() {
    return _generationCoordinator.generateTimelineForCurrentSong();
  }

  Future<String?> convertToKaraokeLyricsForCurrentSong() {
    return _generationCoordinator.convertToKaraokeLyricsForCurrentSong();
  }

  Future<String?> regenerateLyricsForCurrentSong() {
    return _generationCoordinator.regenerateLyricsForCurrentSong();
  }

  Future<String?> translateLyricsForCurrentSong({
    String? targetLanguageCode,
    bool force = false,
  }) {
    return _translationCoordinator.translateLyricsForCurrentSong(
      targetLanguageCode: targetLanguageCode,
      force: force,
    );
  }

  /// 切换当前曲目展示的译文语言（空串 = 回落全局默认）。
  Future<void> selectTranslationLanguageForCurrentSong(
    String languageCode,
  ) {
    return _translationCoordinator.selectTranslationLanguageForCurrentSong(
      languageCode,
    );
  }

  /// 当前应当展示的译文语言 —— **展示侧的唯一入口**。
  ///
  /// 优先级（与 `docs/歌词译文语言-现状与改造计划.md` §4.1 一致）：
  /// 1. 这首歌选定的译文语言（`lyrics_cache.selectedTranslationLanguage`）且确有内容；
  /// 2. 全局默认目标语言且确有内容；
  /// 3. `MusicLyric.getEffectiveTranslationLanguage()` 的「最新有内容」兜底
  ///    —— 只在前两级都拿不到内容时生效。
  ///
  /// 中间这一级不能省：`getEffectiveTranslationLanguage` 只看一个入参，会把
  /// 「选定的语言没有内容」直接跳到「最新的一条」，于是设定过的全局默认被绕过。
  ///
  /// 面板行高测量、桌面歌词、竖屏/横屏播控、翻译开关判定都必须走这里，
  /// 不允许各自拼 `getEffectiveTranslationLanguage` + 自选入参。
  String effectiveTranslationLanguageFor(MusicLyric? lyrics) {
    final selected = state.translationDisplayLanguageCode;
    final fallback = state.lyricsTranslationLanguageCode;
    if (lyrics == null) {
      return selected.isNotEmpty ? selected : fallback;
    }
    if (selected.isNotEmpty && _hasTranslatedContent(lyrics, selected)) {
      return selected;
    }
    if (_hasTranslatedContent(lyrics, fallback)) {
      return fallback;
    }
    return lyrics.getEffectiveTranslationLanguage(fallback);
  }

  bool _hasTranslatedContent(MusicLyric lyrics, String languageCode) {
    if (languageCode.isEmpty) return false;
    return lyrics.translationFor(languageCode)?.hasContent ?? false;
  }

  void cancelActiveAiTask() {
    _logDebug('cancelActiveAiTask called');
    if (_context.lyricsAiCancelToken != null) {
      _context.lyricsAiCancelToken!.cancel('User cancelled AI lyrics task');
      _context.lyricsAiCancelToken = null;
    }
  }

  Future<void> flushPendingLyricsTranslationUpdates() {
    return _translationCoordinator.flushPendingLyricsTranslationUpdates();
  }

  Future<void> updateLyricsTimelineOffsetForCurrentSong(
    Duration timelineOffset, {
    bool recordTimeline = true,
  }) {
    return _support.updateLyricsTimelineOffsetForCurrentSong(
      timelineOffset,
      recordTimeline: recordTimeline,
    );
  }

  Future<void> fillLyricsForCurrentSong(
    String lyricsText, {
    LyricsCacheSource source = LyricsCacheSource.manualAdjust,
    bool recordTimeline = true,
  }) {
    return _support.fillLyricsForCurrentSong(
      lyricsText,
      source: source,
      recordTimeline: recordTimeline,
    );
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

  LyricsGenerationDisplayState get activeLyricsGenerationDisplayState {
    return _context.lyricsGenerationDisplayState;
  }

  void _logDebug(String message) {
    if (kReleaseMode) return;
    debugPrint('[LyricsController] $message');
  }

  Future<void> _syncLyricsCacheWatch(String songPath, String cacheKey) async {
    // 由 watch 订阅以 unawaited 方式触发：控制器在等待期间可能已被销毁
    // （切页、provider 重建）。Riverpod 3 对已销毁 notifier 的 state 访问会抛
    // StateError，落到 unawaited 上就是一条无人接的异步异常，所以每个 await 后都复核。
    if (!ref.mounted) return;

    final currentSong = _support.songForPath(songPath);
    if (currentSong == null) {
      debugPrint('[LyricsController] _syncLyricsCacheWatch aborted: song not found in queue for path="$songPath"');
      return;
    }

    final availableCaches = await getAvailableLyricRecords(currentSong);
    if (!ref.mounted) return;
    if (availableCaches.isEmpty) {
      if (!_lyricsCacheWatchPrimed) {
        debugPrint(
          '[LyricsController] lyrics cache watch initial null ignored -> path="$songPath" '
          'cacheKey="$cacheKey"',
        );
        return;
      }
      if (currentSong.lyrics != null) {
        debugPrint(
          '[LyricsController] lyrics cache watch cleared -> path="$songPath" cacheKey="$cacheKey"',
        );
        _support.clearLyricsStateForPath(songPath);
        _context.setLyricsTranslationStatus('');
        _context.bumpRevision();
      }
      return;
    }

    _lyricsCacheWatchPrimed = true;

    final preference = await getSelectedLyricSource(cacheKey);
    if (!ref.mounted) return;
    final selectedRecord = _support.pickPreferredCacheRecord(
      availableCaches,
      preference: preference,
    );
    if (selectedRecord == null) return;

    // 这首歌选定展示哪种译文，必须从**库里那条记录**读，不能从 selectedRecord 读：
    // `getOrPopulateAvailableLyricRecords()` 会为旁挂 .lrc / 内嵌标签**合成**候选记录，
    // 它们的 selectedTranslationLanguage 恒为空，而这类记录恰恰常是默认选中的那条。
    // 拿它当载体就会：用户选了韩语 → 写库 → watch 回灌 → 读到空串 → 回落全局默认
    // （表现为「右键切了语言，面板还是原来的译文，弹窗勾选也没变」）。
    final cacheRecord = await _context.lyricsCacheRepository.getLyricsCache(
      cacheKey,
    );
    if (!ref.mounted) return;
    if (cacheRecord != null) {
      _context.setTranslationDisplayLanguage(
        cacheRecord.selectedTranslationLanguage,
      );
    }

    final translationRecords = await _context.lyricsCacheRepository
        .getLyricsTranslationCaches(cacheKey);
    if (!ref.mounted) return;
    final translations = _support.translationsFromCacheRecords(
      translationRecords,
    );

    if (selectedRecord.source == LyricsCacheSource.embedded ||
        selectedRecord.source == LyricsCacheSource.external) {
      final raw = selectedRecord.syncedLyrics ?? '';
      if (raw.trim().isNotEmpty) {
        unawaited(
          LyricsTimelineService.instance.ensureInitialSnapshot(
            cacheKey: songPath,
            lyrics: raw,
            timelineOffsetMillis: selectedRecord.timelineOffsetMillis,
            description: selectedRecord.source == LyricsCacheSource.embedded
                ? 'Embedded'
                : 'Local LRC',
          ),
        );
      }
    }

    final applied = _support.applyLyricsRecordToCurrent(
      songPath: songPath,
      record: selectedRecord,
      translations: translations,
    );
    if (!applied) return;

    _logDebug(
      'lyrics cache watch applied -> path="$songPath" cacheKey="$cacheKey" '
      'source=${selectedRecord.source.dbValue} lang=${selectedRecord.languageCode} '
      'lines=${selectedRecord.syncedLines.length} '
      'translationsFromDB=${translations.keys.toList()} '
      '(recordsCount=${translationRecords.length})',
    );

    _context.bumpRevision();
    if (translations.isNotEmpty) {
      _context.bumpLyricsLayoutRevision();
    }
  }
}
