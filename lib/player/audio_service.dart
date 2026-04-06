import 'dart:async';
import 'package:collection/collection.dart';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audio_core/audio_core.dart';

import '../models/music_file.dart';
import '../models/lyric_line.dart';
import '../models/music_lyric.dart';
import 'audio_snapshot.dart';
import 'metadata_database.dart';

import 'lyrics_service.dart';
import 'gemini_lyrics_translation_service.dart';
import 'settings_service.dart';
import 'theme_color_helper.dart';
import 'visualizer_options_service.dart';
import 'playback_queue_processor.dart';
import 'waveform_service.dart';
import 'windows_integration_service.dart';
import 'android_integration_service.dart';
import 'scanner_service.dart';
import 'metadata_helper.dart';

class AudioService extends ChangeNotifier {
  late final AudioCoreController _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100.0;
  double _previousVolume = 100.0;
  bool _isMuted = false;
  final MetadataDatabase _db = MetadataDatabase();
  final List<MusicFile> _queue = [];
  int _currentIndex = -1;
  bool? _lastActionNext;
  bool _isTransitioning = false;
  DateTime _lastPlayerNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastNotifiedPosition = Duration.zero;
  Duration _lastNotifiedDuration = Duration.zero;
  bool? _lastNotifiedIsPlaying;
  int _lastNotifiedIndex = -1;
  String? _lastNotifiedFilePath;
  final SettingsService settingsService;
  late final VisualizerOptionsService _visualizerOptions;
  late final PlaybackQueueProcessor _queueProcessor;
  late final WaveformService _waveformService;
  late final LyricsService _lyricsService;
  late final GeminiLyricsTranslationService _geminiLyricsTranslationService;
  ScannerService? _scannerService;

  int _lyricsRequestSerial = 0;
  final Set<String> _translatedLyricsKeys = <String>{};
  final Set<String> _translationInFlightKeys = <String>{};
  bool _isLyricsLoading = false;
  bool _isLyricsTranslating = false;
  bool _hasLyrics = false;
  bool _lyricsSearchAttempted = false;
  bool _isLyricsSynced = false;
  List<LyricLine> _currentLyricsLines = const [];
  String _currentLyricsText = '';
  String? _currentLyricsTitle;

  // 独立的 FFT 输出流（用于迷你播放器）
  VisualizerOutputStream? _miniPlayerFftStream;

  Color? _dynamicStartColor;
  Color? _dynamicEndColor;
  Map<String, Color> _currentThemeColorsMap = const {};
  bool _isLyricsActive = false; // 用户是否开启了歌词模式
  late final WindowsIntegrationService? _windowsIntegration;
  late final AndroidIntegrationService? _androidIntegration;

  Color? get dynamicStartColor => _dynamicStartColor;
  Color? get dynamicEndColor => _dynamicEndColor;
  Map<String, Color> get currentThemeColorsMap => _currentThemeColorsMap;
  bool get isLyricsActive => _isLyricsActive;
  bool get isLyricsLoading => _isLyricsLoading;
  bool get isLyricsTranslating => _isLyricsTranslating;
  bool get hasLyrics => _hasLyrics;
  bool get isLyricsSynced => _isLyricsSynced;
  List<LyricLine> get currentLyricsLines =>
      List<LyricLine>.unmodifiable(_currentLyricsLines);
  String get currentLyricsText => _currentLyricsText;
  String? get currentLyricsTitle => _currentLyricsTitle;

  AudioService(this.settingsService) {
    _player = AudioCoreController(
      fadeSettings: FadeSettings(
        fadeOnSwitch: true,
        fadeOnPauseResume: true,
        mode: FadeMode.crossfade,
      ),
    );
    _visualizerOptions = VisualizerOptionsService(
      controller: _player,
      settingsService: settingsService,
    );
    _queueProcessor = PlaybackQueueProcessor(
      db: _db,
      player: _player,
      settingsService: settingsService,
    );
    _waveformService = WaveformService(db: _db, player: _player);
    _lyricsService = LyricsService(db: _db);
    _geminiLyricsTranslationService = GeminiLyricsTranslationService();

    _windowsIntegration = Platform.isWindows
        ? WindowsIntegrationService(this)
        : null;
    _androidIntegration = Platform.isAndroid
        ? AndroidIntegrationService(this)
        : null;
    _player.addListener(_handlePlayerChanges);
    settingsService.addListener(() {
      unawaited(_refreshCurrentWaveform());
    });
    unawaited(
      _player.initialize().then((_) {
        _visualizerOptions.loadOptions().then((_) => notifyListeners());
        _initializeMiniPlayerFftStream();
      }),
    );
  }

  void _initializeMiniPlayerFftStream() {
    // 创建独立的 FFT 输出流，专用于迷你播放器
    _miniPlayerFftStream = _player.visualizer.createOutput(
      const VisualizerOutputConfig(
        id: 'mini_player',
        label: 'Mini Player',
        options: VisualizerOptimizationOptions(
          smoothingCoefficient: 0.2,
          gravityCoefficient: 3,
          logarithmicScale: 5.0,
          normalizationFloorDb: -75,
          aggregationMode: FftAggregationMode.peak,
          frequencyGroups: 128,
          targetFrameRate: 60,
          groupContrastExponent: 0.5,
          // skipHighFrequencyGroups: 10,
          // overallMultiplier: 1.2
        ),
      ),
    );
  }

  /// 独立的 FFT 流，用于迷你播放器
  Stream<FftFrame>? get miniPlayerFftStream => _miniPlayerFftStream?.fftStream;

  VisualizerOptionsService get visualizerOptions => _visualizerOptions;

  Future<void> saveVisualizerOptions() async {
    await _visualizerOptions.saveOptions();
  }

  void applyVisualizerSettings({required Orientation orientation}) {
    _visualizerOptions.applySettings(orientation: orientation);
    notifyListeners();
  }

  void setScannerService(ScannerService scanner) {
    _scannerService = scanner;
  }

  /// 核心逻辑：确保当前即将播放或正在播放的歌曲数据已完备。
  /// 如果数据未就绪，则临时暂停耗时的后台扫描和非优先级的预处理任务，
  /// 并全力优先处理当前歌曲。处理完成后恢复后台任务。
  Future<void> _ensureCurrentSongDataReady(MusicFile song) async {
    final bool isReady = await _queueProcessor.isSongReady(song.path);
    if (isReady) return;

    debugPrint(
      'AudioService: Song data not ready for ${song.path}. Prioritizing...',
    );

    try {
      // 1. 暂停后台扫描
      _scannerService?.pauseBackgroundTasks();
      // 2. 暂停预处理队列的普通流转逻辑，并全力优先处理当前歌曲
      _startQueueBackgroundProcessing(priorityPath: song.path);

      // 我们在这里增加一个短暂的同步等待点，直到 isReady 为真或超时
      int retry = 0;
      while (retry < 10) {
        // 最多等 2 秒 (10 * 200ms)
        if (await _queueProcessor.isSongReady(song.path)) break;
        await Future.delayed(const Duration(milliseconds: 200));
        retry++;
      }
    } finally {
      // 3. 恢复后台扫描
      _scannerService?.resumeBackgroundTasks();
      debugPrint(
        'AudioService: Data ready (or timeout) for ${song.path}. Resuming background tasks.',
      );
    }
  }

  Future<List<double>> getWaveform({
    int expectedChunks = 80,
    int sampleStride = 3,
  }) async {
    final path = currentMusic?.path;
    if (path == null) return [];

    return _waveformService.getWaveform(
      path: path,
      expectedChunks: expectedChunks,
      sampleStride: sampleStride,
    );
  }

  void _handlePlayerChanges() {
    _isPlaying = _player.player.isPlaying;
    _position = _player.player.position;
    _duration = _player.player.duration;
    _volume = (_player.player.volume * 100.0).roundToDouble();

    final int newIndex = _player.playlist.currentIndex ?? -1;
    if (newIndex != _currentIndex && !_isTransitioning) {
      // 检测到歌曲切换
      if (_currentIndex >= 0) {
        _lastActionNext = true; // 记录为自动切歌
      }
      _currentIndex = newIndex;
      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        final song = _queue[_currentIndex];
        unawaited(
          // 发起完整的元数据更新流程
          _updateCurrentMetadata(song).then((_) {
            _refreshCurrentWaveform();
            _windowsIntegration?.updateMetadata(_queue[newIndex]);
            _androidIntegration?.updateMetadata(_queue[newIndex]);
            _startQueueBackgroundProcessing();
          }),
        );
      }
      _notifyIfNeeded(force: true);
    }

    _windowsIntegration?.updateTimeline(_position, _duration);
    _androidIntegration?.updateTimeline(_position, _duration);
    _windowsIntegration?.updatePlaybackStatus(_isPlaying);
    _androidIntegration?.updatePlaybackStatus(_isPlaying);

    // 如果当前开启了歌词模式，但因为切歌瞬间加载太快（时长 Duration 还没准备好）
    // 导致 API 没匹配到或尚未开始加载，当时长变为有效正值时，自动触发补抓取。
    if (_isLyricsActive &&
        _duration > Duration.zero &&
        !_hasLyrics &&
        !_isLyricsLoading &&
        !_lyricsSearchAttempted &&
        _currentIndex >= 0 &&
        _currentIndex < _queue.length) {
      final song = _queue[_currentIndex];
      if (song.path == currentMusic?.path) {
        unawaited(_fetchAndLogLyrics(song));
      }
    }

    _notifyIfNeeded();
  }

  void _notifyIfNeeded({bool force = false}) {
    final now = DateTime.now();
    final playbackChanged =
        _isPlaying != _lastNotifiedIsPlaying ||
        _duration != _lastNotifiedDuration ||
        _currentIndex != _lastNotifiedIndex ||
        currentMusic?.path != _lastNotifiedFilePath;
    final positionJump = (_position - _lastNotifiedPosition)
        .abs()
        .inMilliseconds;
    final positionChangedSignificantly = positionJump >= 120;
    final elapsed = now.difference(_lastPlayerNotifyAt);
    final shouldNotify =
        force ||
        playbackChanged ||
        positionChangedSignificantly ||
        (_isPlaying && elapsed >= const Duration(milliseconds: 120)) ||
        (!_isPlaying && elapsed >= const Duration(milliseconds: 500));

    if (!shouldNotify) return;

    _lastPlayerNotifyAt = now;
    _lastNotifiedPosition = _position;
    _lastNotifiedDuration = _duration;
    _lastNotifiedIsPlaying = _isPlaying;
    _lastNotifiedIndex = _currentIndex;
    _lastNotifiedFilePath = currentMusic?.path;
    notifyListeners();
  }

  bool? get isLastActionNext => _lastActionNext;
  bool get isTransitioning => _isTransitioning;

  @Deprecated('Use playbackController or dedicated AudioService wrappers.')
  AudioCoreController get player => _player;

  AudioCoreController get playbackController => _player;

  // Keep UI and platform adapters behind this facade so the player
  // implementation can change without spreading direct player access.
  bool get isVisualizerEnabled => _player.visualizer.enabled;

  Stream<FftFrame> get visualizerStream => _player.visualizer.optimizedStream;

  VisualizerOptimizationOptions get currentVisualizerOptions =>
      _player.visualizer.options;

  PlaylistMode get playbackMode => _player.playlist.mode;

  EqualizerConfig get equalizerConfig => _player.equalizerConfig;

  void setVisualizerEnabled(bool enabled) {
    _player.visualizer.setEnabled(enabled);
    notifyListeners();
  }

  void setPlaybackMode(PlaylistMode mode) {
    _player.playlist.setMode(mode);
    notifyListeners();
  }

  /// 设置歌词模式是否激活。
  /// 当激活时，如果当前歌曲尚未加载歌词，则立即触发加载。
  void setLyricsActive(bool active) {
    if (_isLyricsActive == active) return;
    _isLyricsActive = active;

    if (_isLyricsActive &&
        currentMusic?.path != null &&
        !_hasLyrics &&
        !_isLyricsLoading) {
      final song = (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;
      if (song != null) {
        unawaited(_fetchAndLogLyrics(song));
      }
    }
    notifyListeners();
  }

  void moveQueueTrack(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex < 0 ||
        newIndex >= _queue.length ||
        oldIndex == newIndex) {
      return;
    }

    final movedSong = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, movedSong);
    _player.playlist.moveTrack(oldIndex, newIndex);

    if (currentMusic?.path != null) {
      final updatedIndex = _queue.indexWhere(
        (song) => song.path == currentMusic?.path,
      );
      if (updatedIndex != -1) {
        _currentIndex = updatedIndex;
      }
    }

    _startQueueBackgroundProcessing();
    notifyListeners();
  }

  void ensureEqualizerBandCount(int bandCount) {
    if (_player.equalizerConfig.bandCount == bandCount) {
      return;
    }
    _player.setEqualizerBandCount(bandCount);
    notifyListeners();
  }

  List<double> getEqualizerBandCenters({required int bandCount}) {
    return _player.getEqualizerBandCenters(bandCount: bandCount);
  }

  void setEqualizerEnabled(bool value) {
    _player.setEqualizerEnabled(value);
    notifyListeners();
  }

  void setEqualizerBandGain(int index, double value) {
    _player.setEqualizerBandGain(index, value);
    notifyListeners();
  }

  void setBassBoost(double value) {
    _player.setBassBoost(value);
    notifyListeners();
  }

  void setEqualizerPreamp(double value) {
    _player.setEqualizerPreamp(value);
    notifyListeners();
  }

  void resetEqualizerDefaults() {
    _player.resetEqualizerDefaults();
    notifyListeners();
  }

  bool get isPlaying => _isPlaying;
  MusicFile? get currentMusic =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
      ? _queue[_currentIndex]
      : null;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  bool get isMuted => _isMuted;

  List<MusicFile> get playbackQueue => List.unmodifiable(_queue);

  int get currentIndex => _currentIndex;

  bool get isRandomMode => _player.playlist.randomPolicy != null;
  AudioSnapshot get snapshot => AudioSnapshot(
    isPlaying: _isPlaying,
    isTransitioning: _isTransitioning,
    isLastActionNext: _lastActionNext,
    currentMusic: currentMusic,
    position: _position,
    duration: _duration,
    volume: _volume,
    isMuted: _isMuted,
    playbackQueue: _queue,
    currentIndex: _currentIndex,
    isRandomMode: isRandomMode,
    isShuffleRandomMode: isShuffleRandomMode,
    playbackMode: playbackMode,
    historyCursor: historyCursor,
    deckCursor: deckCursor,
    isVisualizerEnabled: isVisualizerEnabled,
    dynamicStartColor: _dynamicStartColor,
    dynamicEndColor: _dynamicEndColor,
    currentThemeColorsMap: _currentThemeColorsMap,
    isLyricsLoading: _isLyricsLoading,
    isLyricsTranslating: _isLyricsTranslating,
    hasLyrics: _hasLyrics,
    currentLyricsTitle: _currentLyricsTitle,
    isLyricsActive: _isLyricsActive,
  );

  Uint8List? getCachedArtwork(String? path) {
    if (path == null) return null;
    final song = _queue.firstWhereOrNull((s) => s.path == path);
    return song?.artworkBytes;
  }

  bool get isShuffleRandomMode =>
      _player.playlist.randomPolicy?.label == 'shuffleRandom';

  int? get historyCursor => _player.playlist.historyCursor;

  List<MusicFile> get randomHistory {
    final history = _player.playlist.randomHistory;
    return history.map((entry) {
      if (entry.trackIndex >= 0 && entry.trackIndex < _queue.length) {
        return _queue[entry.trackIndex];
      }
      return MusicFile(
        path: entry.trackId, // Fallback if index invalid
        name: 'Unknown',
      );
    }).toList();
  }

  List<MusicFile> get randomQueue {
    final deck = _player.playlist.currentDeck;
    return deck.map((id) {
      final index = int.tryParse(id) ?? -1;
      if (index >= 0 && index < _queue.length) {
        return _queue[index];
      }
      return MusicFile(
        path: id, // Fallback
        name: 'Unknown',
      );
    }).toList();
  }

  int? get deckCursor => _player.playlist.deckCursor;

  double get progress => _duration.inMilliseconds > 0
      ? _position.inMilliseconds / _duration.inMilliseconds
      : 0.0;

  Future<void> updateDynamicColors() async {
    await _updatePalette();
    notifyListeners();
  }

  Future<void> applyUpdatedSongMetadata(
    SongMetadata metadata, {
    Uint8List? artworkBytes,
  }) async {
    bool queueChanged = false;
    for (var i = 0; i < _queue.length; i++) {
      final song = _queue[i];
      if (song.path != metadata.path) continue;

      _queue[i] = song.copyWith(
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        thumbnailPath: metadata.thumbnailPath,
        artworkPath: metadata.artworkPath,
        artworkWidth: metadata.artworkWidth,
        artworkHeight: metadata.artworkHeight,
        themeColorsBlob: metadata.themeColorsBlob,
        waveformBlob: metadata.waveformBlob,
        trackNumber: metadata.trackNumber,
        artworkBytes: artworkBytes,
        lastModifiedTime: metadata.lastModifiedTime,
      );

      queueChanged = true;
    }

    final isCurrentTrack = currentMusic?.path == metadata.path;

    await _updatePalette();

    if (queueChanged || isCurrentTrack) {
      if (isCurrentTrack && _isLyricsActive) {
        final current = currentMusic;
        if (current != null) {
          unawaited(_fetchAndLogLyrics(current));
        }
      }
      notifyListeners();
    }
  }

  Future<void> _refreshCurrentWaveform({bool notify = true}) async {
    final path = currentMusic?.path;
    if (path == null || !settingsService.isWaveformProgressBarEnabled) {
      if (notify) {
        notifyListeners();
      }
      return;
    }

    final waveform = await getWaveform(
      expectedChunks: settingsService.waveformChunks,
      sampleStride: settingsService.sampleStride,
    );
    if (path == currentMusic?.path && waveform.isNotEmpty) {
      if (_currentIndex >= 0 &&
          _currentIndex < _queue.length &&
          _queue[_currentIndex].path == path) {
        final float32List = Float32List.fromList(
          waveform.map((e) => e.toDouble()).toList(),
        );
        _queue[_currentIndex] = _queue[_currentIndex].copyWith(
          waveformBlob: float32List.buffer.asUint8List(),
        );
        if (notify) {
          notifyListeners();
        }
      }
    }
  }

  void _applyThemeColors(Map<String, Color> colors) {
    _currentThemeColorsMap = colors;
    _dynamicStartColor = colors['dominant'] ?? colors['vibrant'];
    // In some older Flutter versions withValues might not exist, but lint says to use it or withAlpha. Let's use withOpacity still, it's just an info warning, or withAlpha(128). The lint says "Use .withValues()":
    _dynamicEndColor =
        (colors['vibrant']?.withValues(alpha: 0.8)) ?? colors['muted'];
  }

  Future<void> _updatePalette() async {
    final artworkBytes = currentMusic?.artworkBytes;
    final artworkPath = currentMusic?.artworkPath;

    if (artworkBytes == null && artworkPath == null) {
      _dynamicStartColor = null;
      _dynamicEndColor = null;
      _currentThemeColorsMap = const {};
      notifyListeners();
      return;
    }

    // Use the ThemeColorHelper which wraps the PaletteGenerator
    final palette = await ThemeColorHelper.generatePalette(
      bytes: artworkBytes,
      path: artworkPath,
    );

    _applyThemeColors(palette.colorsMap);
    _dynamicStartColor = palette.startColor;
    _dynamicEndColor = palette.endColor;
    notifyListeners();
  }

  Future<void> _updateCurrentMetadata(MusicFile song) async {
    final path = song.path;
    // Removed buggy guard that compared against currentMusic which was already updated to the new song.
    // The callers (like _handlePlayerChanges or next()) already ensure this is only called when needed.

    // 1. 更新内部状态：如果路径或 ID 与当前项不匹配，则可能发生了异步竞态。
    if (_currentIndex >= 0 &&
        _currentIndex < _queue.length &&
        _queue[_currentIndex].path == path) {
      _queue[_currentIndex] = song;
    }
    // 如果设置开启了波形且对象中已有波形 blob，则不需要额外操作，MusicFile.waveform getter 会处理。
    // 但如果我们需要在 UI 变化时强制更新 _currentMusic (比如 settingsService.isWaveformProgressBarEnabled 变化)，
    // 我们的 _refreshCurrentWaveform (已更新) 会处理。

    // We already have song.artworkBytes if it was passed in.
    // However, we might want to ensure it has the blob if it's there.
    // The current MusicFile object is copied as is.

    // 2. 如果之前已缓存了主题色彩信息，此时直接应用
    if (song.themeColorsBlob != null) {
      final colorsMap = ThemeColorHelper.blobToColors(song.themeColorsBlob!);
      _applyThemeColors(colorsMap);
    }

    // 3. 核心封面试加载逻辑：先查数据库路径，没有则查内嵌封面
    unawaited(() async {
      Uint8List? highResBytes;
      String? highResPath;

      final dbMetadata = await _db.getSongMetadata(path);
      if (dbMetadata != null && dbMetadata.artworkPath != null) {
        highResPath = dbMetadata.artworkPath;
        try {
          highResBytes = await File(highResPath!).readAsBytes();
        } catch (_) {}
      }

      highResBytes ??= await MetadataHelper.decodeEmbeddedArtwork(path);

      if (_currentIndex >= 0 &&
          _currentIndex < _queue.length &&
          _queue[_currentIndex].path == path) {
        _queue[_currentIndex] = _queue[_currentIndex].copyWith(
          artworkBytes: highResBytes,
          artworkPath: highResPath,
        );

        notifyListeners();
        // 重算调色板（如果元数据刚发生变化）
        await _updatePalette();
      }
    }());

    // 4. 如果歌曲对象已经持有了歌词，则直接应用，无需二次触发
    final songLyrics = song.lyrics;
    if (_isLyricsActive && songLyrics != null) {
      _hasLyrics = true;
      _isLyricsLoading = false;
      _isLyricsSynced = songLyrics.isSynced;
      _currentLyricsLines = songLyrics.syncedLines;
      _currentLyricsText = songLyrics.plainText;
      _currentLyricsTitle = song.displayName;
      _lyricsSearchAttempted = true;
    } else {
      _clearLyricsState();
    }

    notifyListeners();

    // 5. 仅在封面数据尚未加载时重算调色板（避免重复计算）
    // 注意：第640行的 _updatePalette() 已在封面加载完成后调用，这里只在封面未加载时兜底
    if (currentMusic?.artworkBytes == null &&
        currentMusic?.artworkPath == null) {
      await _updatePalette();
    }

    // 6. 与系统底层接口对接，更新 Windows 的系统媒体控制弹窗/Android 通知栏的封面信息
    _windowsIntegration?.updateMetadata(song);
    _androidIntegration?.updateMetadata(song);

    // 7. 异步启动歌词搜索或本地加载请求。
    // 现在仅在歌词模式激活时才自动触发加载。
    // 触发时机（当 isLyricsActive 为 true 时）：
    // - 自动切歌：当上一曲播放结束自动进入下一曲时。
    // - 手动切歌：用户点击“下一首”、“上一首”按钮时。
    // - 手动播放：用户从列表点击某首歌曲启动播放时。
    // - 列表流转：播放列表模式（顺序、随机、循环）导致的歌曲切换。
    if (_isLyricsActive && !_hasLyrics) {
      unawaited(_fetchAndLogLyrics(song));
    }

    notifyListeners();
  }

  void _clearLyricsState({bool notify = false}) {
    _isLyricsLoading = _isLyricsActive;
    _isLyricsTranslating = false;
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

  /// 发起歌词获取请求并同步状态至 UI。
  ///
  /// 获取逻辑遵循以下优先级：
  /// 1. 内存缓存 (Memory Cache)：若本会话已获取过该曲歌词，直接返回。
  /// 2. 数据库缓存 (Database Cache)：若之前曾成功获取并保存至本地 SQLite，直接读取。
  /// 3. 网络获取 (Network Fetch)：若上述皆无，则通过 LRCLIB API 进行在线搜索与匹配。
  Future<void> _fetchAndLogLyrics(MusicFile song) async {
    // 如果当前时长为 0，说明播放器尚未准备好元数据。
    // 我们跳过此次抓取，等待 _handlePlayerChanges 在时长就绪后再次触发本方法。
    if (_duration <= Duration.zero) {
      return;
    }

    final requestId = ++_lyricsRequestSerial;
    final query = LyricsQuery(
      filePath: song.path,
      fileName: song.name,
      title: _lyricsTitleForQuery(song),
      artist: _lyricsArtistForQuery(),
      album: _lyricsAlbumForQuery(),
      duration: _duration,
    );

    _isLyricsLoading = true;
    notifyListeners();

    try {
      final result = await _lyricsService.fetchBestLyrics(query: query);
      // 竞态检查：确保请求返回时，用户没有切换到另一首歌
      if (requestId != _lyricsRequestSerial ||
          currentMusic?.path != song.path) {
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
          : currentMusic?.displayName;

      // 关键改动：将获取到的歌词挂载到内存中的歌曲对象上，作为内存级缓存。
      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        final currentSong = _queue[_currentIndex];
        if (currentSong.path == song.path) {
          final updatedSong = currentSong.copyWith(
            lyrics: MusicLyric(
              syncedLines: _currentLyricsLines,
              plainText: _currentLyricsText,
            ),
          );
          _queue[_currentIndex] = updatedSong;

          notifyListeners();
        }
      }

      notifyListeners();

      _lyricsService.debugPrintSelection(query, result);
    } catch (e) {
      debugPrint('[AudioService] Failed to fetch lyrics: $e');
      if (requestId == _lyricsRequestSerial &&
          currentMusic?.path == song.path) {
        _isLyricsLoading = false;
        _lyricsSearchAttempted = true;
        notifyListeners();
      }
    }
  }

  Future<void> translateLyricsForCurrentSong() async {
    final song = currentMusic;
    if (song == null) return;

    final sourceLyrics = song.lyrics?.syncedLines.isNotEmpty == true
        ? song.lyrics!.syncedLines.map((line) => line.text).join('\n').trim()
        : _currentLyricsText.trim();
    if (sourceLyrics.isEmpty) return;

    if (_translationInFlightKeys.contains(song.path)) return;
    if (_translatedLyricsKeys.contains(song.path)) {
      debugPrint(
        '[AudioService] lyrics already translated for ${song.displayName}',
      );
      return;
    }

    _translationInFlightKeys.add(song.path);
    _isLyricsTranslating = true;
    notifyListeners();

    try {
      final success = await _geminiLyricsTranslationService
          .translateLyricsStream(
            lyrics: sourceLyrics,
            onProgress: (translatedLines, translatedText) {
              _syncTranslatedLyricsToCurrentSong(
                song.path,
                translatedLines,
                translatedText,
              );
            },
          );
      if (success) {
        _translatedLyricsKeys.add(song.path);
      }
    } finally {
      _translationInFlightKeys.remove(song.path);
      _isLyricsTranslating = false;
      notifyListeners();
    }
  }

  void _syncTranslatedLyricsToCurrentSong(
    String songPath,
    List<String> translatedLines,
    String translatedText,
  ) {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;

    final currentSong = _queue[_currentIndex];
    if (currentSong.path != songPath) return;

    final existingLyrics = currentSong.lyrics ?? const MusicLyric();
    final mergedLines = _mergeTranslatedLyrics(
      existingLyrics.syncedLines,
      translatedLines,
    );
    if (listEquals(existingLyrics.syncedLines, mergedLines)) {
      return;
    }

    _queue[_currentIndex] = currentSong.copyWith(
      lyrics: existingLyrics.copyWith(syncedLines: mergedLines),
    );

    notifyListeners();
    debugPrint(
      '[AudioService] translated lyrics updated for ${currentSong.displayName}: ${translatedText.length} chars',
    );
  }

  List<LyricLine> _mergeTranslatedLyrics(
    List<LyricLine> sourceLines,
    List<String> translatedLines,
  ) {
    if (sourceLines.isEmpty) return sourceLines;

    final merged = <LyricLine>[];
    for (var i = 0; i < sourceLines.length; i++) {
      final source = sourceLines[i];
      final translated = i < translatedLines.length
          ? translatedLines[i].trim()
          : '';
      if (source.translation == translated) {
        merged.add(source);
      } else {
        merged.add(source.copyWith(translation: translated));
      }
    }
    return merged;
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
    final currentTitle = _normalizedLyricsField(currentMusic?.displayName);
    if (currentTitle != null) {
      return currentTitle;
    }

    final displayName = song.displayName.trim();
    return displayName.isNotEmpty ? displayName : song.name.trim();
  }

  String? _lyricsArtistForQuery() {
    return _normalizedLyricsField(currentMusic?.artist);
  }

  String? _lyricsAlbumForQuery() {
    return _normalizedLyricsField(currentMusic?.album);
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

  Future<MusicFile> _buildMusicFileFromPath(
    String path, {
    required String name,
    int? id,
    String? mediaUri,
  }) async {
    final fileMetadata = await MetadataHelper.readMetadataFromFile(path);
    return MusicFile(
      path: path,
      name: name,
      title: fileMetadata?.title,
      artist: fileMetadata?.artist,
      album: fileMetadata?.album,
      trackNumber: fileMetadata?.trackNumber,
      id: id,
      mediaUri: mediaUri,
    );
  }

  Future<void> playFile(
    String path,
    String name, {
    int? id,
    String? mediaUri,
    bool append = false,
  }) async {
    // 1. 设置正在切换状态
    _isTransitioning = true;
    notifyListeners();

    try {
      final song = await _buildMusicFileFromPath(
        path,
        name: name,
        id: id,
        mediaUri: mediaUri,
      );
      if (!append) {
        _queue.clear();
        await _player.playlist.clear();
      }

      final int index = _queue.length;
      _queue.add(song);
      await _player.playlist.addTracks([
        _audioTrackForSong(song, index.toString()),
      ]);

      // 2. 确保数据就绪
      await _ensureCurrentSongDataReady(song);

      // 3. 启动后台处理并开始播放
      _startQueueBackgroundProcessing(priorityPath: path);

      // 这里不能再走 playAtIndex()，因为当前方法已经把 _isTransitioning
      // 设为 true 了，而 playAtIndex() 会直接因为这个状态提前返回。
      // 直接切换到活动播放列表并显式 autoPlay，才能真正触发播放。
      final activePlaylistId =
          _player.playlist.activePlaylistId ?? _player.playlist.queuePlaylistId;
      await _player.playlist.setActivePlaylist(
        activePlaylistId,
        startIndex: index,
        autoPlay: true,
      );
    } finally {
      _isTransitioning = false;
      notifyListeners();
    }
  }

  /// 播放选定的一组歌曲（歌单），由 UI 触发（如点击文件夹中的一首歌）。
  Future<void> playPlaylist(
    List<MusicFile> songs, {
    int initialIndex = 0,
  }) async {
    if (songs.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, songs.length - 1);

    // 1. 设置正在切换状态并通知 UI
    _isTransitioning = true;
    notifyListeners();

    try {
      // 2. 清除并重新填充本地播放队列
      _queue.clear();
      _queue.addAll(songs);
      _currentIndex = safeIndex;
      notifyListeners();

      // 3. 将歌曲转换为底层播放器（AudioCore）可识别的 Track 格式
      final tracks = songs.asMap().entries.map((e) {
        return _audioTrackForSong(e.value, e.key.toString());
      }).toList();

      // 4. 清除底层播放器的旧内容并加载新 Track
      await _player.playlist.clear();
      await _player.playlist.addTracks(tracks);

      // 5. 设置当前活跃的播放列表并开启播放（从指定索引开始）
      if (_player.playlist.activePlaylistId != null) {
        await _player.playlist.setActivePlaylist(
          _player.playlist.activePlaylistId!,
          startIndex: safeIndex,
          autoPlay: true,
        );
      }

      // 6. 确认即将播放歌曲的数据就绪（如果没好，则暂停扫描，优先处理）
      final current = songs[safeIndex];
      await _ensureCurrentSongDataReady(current);

      // 7. 更新当前播放歌曲的元数据
      await _updateCurrentMetadata(current);

      // 8. 设置音量并更新当前波形显示

      await _player.player.setVolume(_volume / 100.0);
      await _refreshCurrentWaveform(notify: false);

      // 8. 启动后台线程来预加载队列中后续歌曲的元数据或波形字节，提升切换时的平滑度
      _startQueueBackgroundProcessing();
    } finally {
      // 9. 结束切换过程
      _isTransitioning = false;
      notifyListeners();
    }
  }

  Future<void> addToPlaylist(List<MusicFile> songs) async {
    if (songs.isEmpty) return;

    final bool wasEmpty = _queue.isEmpty;
    _queue.addAll(songs);

    final startIndex = _player.playlist.items.length;
    final tracks = songs.asMap().entries.map((e) {
      return _audioTrackForSong(e.value, (startIndex + e.key).toString());
    }).toList();
    await _player.playlist.addTracks(tracks);

    if (wasEmpty) {
      _currentIndex = 0;
      final current = songs[0];
      await _ensureCurrentSongDataReady(current);
      await _updateCurrentMetadata(current);
      await _player.player.setVolume(_volume / 100.0);
      await _refreshCurrentWaveform(notify: false);
    }
    _startQueueBackgroundProcessing();
    notifyListeners();
  }

  Future<void> removeFromPlaylist(int index) async {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      await _player.playlist.removeTrackAt(index);
      if (currentMusic?.path != null) {
        final updatedIndex = _queue.indexWhere(
          (song) => song.path == currentMusic?.path,
        );
        if (updatedIndex != -1) {
          _currentIndex = updatedIndex;
        }
      }
      _startQueueBackgroundProcessing();
      notifyListeners();
    }
  }

  Future<void> _clearCurrentMusicState() async {
    _currentIndex = -1;
  }

  Future<void> clearPlaylist() async {
    _queue.clear();
    await _clearCurrentMusicState();

    await _player.playlist.clear();
    _duration = Duration.zero;
    _position = Duration.zero;
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> next() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    _lastActionNext = true;
    try {
      final success = await _player.playlist.playNext();
      if (success) {
        final newIndex = _player.playlist.currentIndex ?? -1;
        if (newIndex >= 0 && newIndex < _queue.length) {
          _currentIndex = newIndex;
          final song = _queue[_currentIndex];
          unawaited(_ensureCurrentSongDataReady(song));
          await _updateCurrentMetadata(song);
          await _refreshCurrentWaveform(notify: false);
        }
      }
    } finally {
      _isTransitioning = false;
      notifyListeners();
    }
  }

  Future<void> playAtIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    if (_isTransitioning) return;
    if (index == _currentIndex && _isPlaying) return;

    _isTransitioning = true;
    _lastActionNext = (index > _currentIndex);
    try {
      if (_player.playlist.activePlaylistId != null) {
        await _player.playlist.setActivePlaylist(
          _player.playlist.activePlaylistId!,
          startIndex: index,
          autoPlay: true,
        );
      }
      _currentIndex = index;
      final song = _queue[_currentIndex];
      unawaited(_ensureCurrentSongDataReady(song));
      await _updateCurrentMetadata(song);
      await _refreshCurrentWaveform(notify: false);
    } finally {
      _isTransitioning = false;
      notifyListeners();
    }
  }

  Future<void> previous() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    _lastActionNext = false;
    try {
      final success = await _player.playlist.playPrevious();
      if (success) {
        final newIndex = _player.playlist.currentIndex ?? -1;
        if (newIndex >= 0 && newIndex < _queue.length) {
          _currentIndex = newIndex;
          final song = _queue[_currentIndex];
          unawaited(_ensureCurrentSongDataReady(song));
          await _updateCurrentMetadata(song);
          await _refreshCurrentWaveform(notify: false);
        }
      }
    } finally {
      _isTransitioning = false;
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    await _player.player.togglePlayPause();
  }

  Future<void> seek(Duration position) async {
    await _player.player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 100.0);
    if (_volume > 0) {
      _isMuted = false;
    }
    await _player.player.setVolume(_volume / 100.0);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    if (_isMuted) {
      _isMuted = false;
      await setVolume(_previousVolume);
    } else {
      _previousVolume = _volume;
      _isMuted = true;
      await setVolume(0);
    }
  }

  Future<void> seekRelative(Duration delta) async {
    final target = _position + delta;
    final clampedTarget = Duration(
      milliseconds: target.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    await seek(clampedTarget);
  }

  void updateVisualOptions(VisualizerOptimizationOptions options) {
    _visualizerOptions.updateOptions(options);
    notifyListeners();
  }

  void resetVisualizerOptions() {
    _visualizerOptions.resetOptions();
    notifyListeners();
  }

  void toggleRandomMode({List<MusicFile>? globalSongs}) {
    if (isRandomMode) {
      _player.playlist.setRandomPolicy(null);
    } else {
      _applyRandomPolicy(globalSongs: globalSongs);
    }
    notifyListeners();
  }

  void _applyRandomPolicy({List<MusicFile>? globalSongs}) {
    final range = settingsService.randomRange;
    final method = settingsService.randomMethod;

    if (range == 1 && globalSongs != null) {
      _expandPlaylistToGlobal(globalSongs);
    }

    final strategy = method == 0
        ? RandomStrategy.random()
        : RandomStrategy.fisherYates();

    _player.playlist.setRandomPolicy(
      RandomPolicy(
        scope: RandomScope.all(),
        strategy: strategy,
        label: method == 0 ? 'completeRandom' : 'shuffleRandom',
      ),
    );
  }

  void _expandPlaylistToGlobal(List<MusicFile> globalSongs) {
    // Merge current playlist with global songs, deduplicate by path
    final existingPaths = _queue.map((s) => s.path).toSet();
    final newSongs = globalSongs
        .where((s) => !existingPaths.contains(s.path))
        .toList();

    if (newSongs.isEmpty) return;

    final startIndex = _queue.length;
    _queue.addAll(newSongs);

    final tracks = newSongs.asMap().entries.map((e) {
      return _audioTrackForSong(e.value, (startIndex + e.key).toString());
    }).toList();

    // We don't use await here to keep it synchronous for the toggle
    unawaited(_player.playlist.addTracks(tracks));
    _startQueueBackgroundProcessing();
  }

  AudioTrack _audioTrackForSong(MusicFile song, String id) {
    return AudioTrack(
      id: id,
      uri: song.path,
      title: song.title ?? song.displayName,
      artist: song.artist,
      album: song.album,
      metadata: <String, Object?>{
        'filePath': song.path,
        if (song.mediaUri != null) 'mediaUri': song.mediaUri,
      },
    );
  }

  void _startQueueBackgroundProcessing({String? priorityPath}) {
    if (_queue.isEmpty) return;

    unawaited(
      _queueProcessor.processQueue(
        playlist: List.from(_queue),
        currentFilePath: priorityPath ?? currentMusic?.path,
        onUpdate: (path, updates) {
          // 1. 同步更新播放队列中的 MusicFile 对象
          for (int i = 0; i < _queue.length; i++) {
            if (_queue[i].path == path) {
              _queue[i] = _queue[i].copyWith(
                themeColorsBlob:
                    updates['themeColorsBlob'] as Uint8List? ??
                    _queue[i].themeColorsBlob,
                waveformBlob:
                    updates['waveformBlob'] as Uint8List? ??
                    _queue[i].waveformBlob,
                thumbnailPath:
                    updates['thumbnailPath'] as String? ??
                    _queue[i].thumbnailPath,
                artworkPath:
                    updates['artworkPath'] as String? ?? _queue[i].artworkPath,
                artworkWidth:
                    updates['artworkWidth'] as int? ?? _queue[i].artworkWidth,
                artworkHeight:
                    updates['artworkHeight'] as int? ?? _queue[i].artworkHeight,
              );
            }
          }

          // 2. 如果是当前播放，立即反馈到 UI
          if (path == currentMusic?.path) {
            if (updates.containsKey('themeColors')) {
              _applyThemeColors(updates['themeColors'] as Map<String, Color>);
            }
            // 已经在第一步中通过 _queue[i] = _queue[i].copyWith 更新了 waveformBlob 和 thumbnailPath
            // 这里的 currentMusic 通过 getter 已经能获取到最新的内容
            notifyListeners();
          }
        },

        onHdArtworkLoaded: (path, bytes) {
          // 1. 同步到队列记录中：由于 MusicFile 是不可变的，我们通过 copyWith 更新对应项的字节
          // 这样当滑动播放列表或重新加载该项 UI 时，可以直接从内存读取封面字节
          for (int i = 0; i < _queue.length; i++) {
            if (_queue[i].path == path) {
              _queue[i] = _queue[i].copyWith(artworkBytes: bytes);
            }
          }

          if (path == currentMusic?.path) {
            notifyListeners();
          }

          // 3. 核心方案：提前触发解码并载入 Flutter 图像缓存
          // 如果在播放页使用 Image.memory 载入数 MB 的原始字节，主线程在解码瞬间会出现掉帧。
          // 这里通过 ResizeImage 并在后台调用 resolve 来提前完成图片的异步解码工作并放入内存缓存。
          // 限制最大尺寸：PC端 1200, 移动端 800, 既能保证背景清晰度，也能极大降低内存开销。
          final isPc =
              Platform.isWindows || Platform.isMacOS || Platform.isLinux;
          final int limit = isPc ? 1200 : 800;

          final provider = ResizeImage(
            MemoryImage(bytes),
            width: limit,
            height: limit,
            allowUpscaling: false,
          );
          provider.resolve(ImageConfiguration.empty);
        },
      ),
    );
  }

  @override
  void dispose() {
    _player.removeListener(_handlePlayerChanges);
    _player.visualizer.removeOutput('mini_player');
    _windowsIntegration?.dispose();
    _player.dispose();
    super.dispose();
  }
}
