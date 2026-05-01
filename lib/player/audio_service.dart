import 'dart:async';
import 'package:collection/collection.dart';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_core/audio_core.dart';
import 'package:path_provider/path_provider.dart';

import '../models/music_file.dart';
import 'audio_snapshot.dart';
import 'metadata_database.dart';

import 'settings_service.dart';
import 'theme_color_helper.dart';
import 'track_artwork_theme_service.dart';
import 'visualizer_options_service.dart';
import 'playback_queue_processor.dart';
import 'waveform_service.dart';
import 'windows_integration_service.dart';
import 'android_integration_service.dart';
import 'scanner_service.dart';
import 'playlist_service.dart';
import 'metadata_helper.dart';
import 'lyrics_controller.dart';
import 'lyrics_controller_state.dart';
import 'lyrics_controller_dependencies.dart';
import 'audio_riverpod.dart';
import 'library_insights_service.dart';
import 'lyrics_riverpod.dart';

class AudioService extends Notifier<AudioSnapshot> {
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
  late final SettingsService settingsService;
  late final VisualizerOptionsService _visualizerOptions;
  late final PlaybackQueueProcessor _queueProcessor;
  late final WaveformService _waveformService;
  ScannerService? _scannerService;
  PlaylistService? _playlistService;
  void Function({required bool skipped})? _missingSongNoticeHandler;
  bool _isLyricsActive = false;
  Timer? _sleepTimer;
  DateTime? _sleepTimerEndAt;
  Duration? _sleepTimerDuration;
  int _lastWaveformChunks = -1;
  bool _disposed = false;
  late final VoidCallback _settingsListener;
  DateTime _lastPositionDebugLogAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _trackedPlaybackSongPath;
  bool _hasLoggedCurrentPlayback = false;
  Duration _lastPlaybackObservedPosition = Duration.zero;

  // 独立的 FFT 输出流（用于迷你播放器）
  VisualizerOutputStream? _miniPlayerFftStream;

  Color? _dynamicStartColor;
  Color? _dynamicEndColor;
  Map<String, Color> _currentThemeColorsMap = const {};
  late final WindowsIntegrationService? _windowsIntegration;
  late final AndroidIntegrationService? _androidIntegration;
  String? _themePaletteRecomputeInProgressPath;

  Color? get dynamicStartColor => _dynamicStartColor;
  Color? get dynamicEndColor => _dynamicEndColor;
  Map<String, Color> get currentThemeColorsMap => _currentThemeColorsMap;
  bool get isLyricsActive => _isLyricsActive;
  bool get isLyricsLoading => _lyricsState.isLyricsLoading;
  bool get hasLyrics => _lyricsState.hasLyrics;
  bool get lyricsSearchAttempted => _lyricsState.lyricsSearchAttempted;
  Duration? get sleepTimerRemaining {
    final endAt = _sleepTimerEndAt;
    if (endAt == null) return null;

    final remaining = endAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return Duration.zero;
    }
    return remaining;
  }

  Duration? get sleepTimerDuration => _sleepTimerDuration;
  bool get hasSleepTimer => _sleepTimerEndAt != null;

  @override
  AudioSnapshot build() {
    settingsService = ref.read(settingsServiceProvider);
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
    _lastWaveformChunks = settingsService.waveformChunks;

    _windowsIntegration = Platform.isWindows
        ? WindowsIntegrationService(this)
        : null;
    _androidIntegration = Platform.isAndroid
        ? AndroidIntegrationService(this)
        : null;
    _player.addListener(_handlePlayerChanges);
    _settingsListener = () {
      if (_disposed) return;
      final currentWaveformChunks = settingsService.waveformChunks;
      if (_lastWaveformChunks != currentWaveformChunks) {
        _lastWaveformChunks = currentWaveformChunks;
        unawaited(_handleWaveformChunkChange());
        return;
      }

      unawaited(_refreshCurrentWaveform());
    };
    settingsService.addListener(_settingsListener);
    ref.onDispose(_dispose);
    unawaited(
      _player.initialize().then((_) {
        if (_disposed) return;
        _visualizerOptions.loadOptions().then((_) => notifyListeners());
        if (_disposed) return;
        _initializeMiniPlayerFftStream();
      }),
    );
    return snapshot;
  }

  void notifyListeners() {
    if (_disposed) return;
    state = snapshot;
  }

  LyricsControllerDependencies get lyricsControllerDependencies {
    return LyricsControllerDependencies(
      db: _db,
      currentMusic: () => currentMusic,
      queue: () => _queue,
      currentIndex: () => _currentIndex,
      playerDuration: () => _duration,
      isLyricsActive: () => isLyricsActive,
      cacheSongDuration: _cacheSongDuration,
    );
  }

  LyricsController get _lyricsController {
    return ref.read(lyricsControllerProvider.notifier);
  }

  LyricsControllerState get _lyricsState {
    return ref.read(lyricsControllerProvider);
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

  void setScannerService(ScannerService? scanner) {
    _scannerService = scanner;
  }

  void setPlaylistService(PlaylistService? playlistService) {
    _playlistService = playlistService;
  }

  void setSongMissingStateByPath(String path, bool isMissing) {
    var changed = false;
    for (var i = 0; i < _queue.length; i++) {
      final song = _queue[i];
      if (song.path != path || song.isMissing == isMissing) continue;
      _queue[i] = song.copyWith(isMissing: isMissing);
      changed = true;
    }

    if (changed) {
      if (isMissing &&
          currentMusic?.path == path &&
          !_isTransitioning &&
          _queue.isNotEmpty) {
        unawaited(_skipMissingCurrentTrack());
      } else {
        notifyListeners();
      }
    }
  }

  void setMissingSongNoticeHandler(
    void Function({required bool skipped})? handler,
  ) {
    _missingSongNoticeHandler = handler;
  }

  void _showMissingSongNotice({required bool skipped}) {
    _missingSongNoticeHandler?.call(skipped: skipped);
  }

  Future<bool> _songExists(String path) async {
    if (path.trim().isEmpty) return false;
    return File(path).exists();
  }

  Future<void> _skipMissingCurrentTrack() async {
    if (_isTransitioning || _queue.isEmpty || _currentIndex < 0) {
      return;
    }

    _isTransitioning = true;
    try {
      var attempts = 0;
      while (_queue.isNotEmpty && attempts < _queue.length) {
        if (_currentIndex < 0 || _currentIndex >= _queue.length) {
          break;
        }

        final current = _queue[_currentIndex];
        if (await _songExists(current.path)) {
          await _syncCurrentPlaybackSong(current);
          return;
        }

        setSongMissingStateByPath(current.path, true);
        _showMissingSongNotice(skipped: true);

        final success = await _player.playlist.playNext();
        final newIndex = _player.playlist.currentIndex ?? -1;
        if (!success || newIndex < 0 || newIndex >= _queue.length) {
          await _player.player.pause();
          _isPlaying = false;
          _currentIndex = -1;
          _duration = Duration.zero;
          _position = Duration.zero;
          notifyListeners();
          return;
        }

        _currentIndex = newIndex;
        attempts++;
      }
    } finally {
      _isTransitioning = false;
      notifyListeners();
    }
  }

  MusicFile _songFromMetadata(
    MusicFile song,
    SongMetadata metadata, {
    Uint8List? artworkBytes,
  }) {
    return song.copyWith(
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      trackNumber: metadata.trackNumber,
      thumbnailPath: metadata.thumbnailPath,
      artworkPath: metadata.artworkPath,
      artworkWidth: metadata.artworkWidth,
      artworkHeight: metadata.artworkHeight,
      themeColorsBlob: metadata.themeColorsBlob,
      waveformBlob: metadata.waveformBlob,
      artworkBytes: artworkBytes ?? song.artworkBytes,
      lastModifiedTime: metadata.lastModifiedTime,
      lyrics: song.lyrics,
    );
  }

  void _replaceQueueSongsByPath(String path, MusicFile updatedSong) {
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].path == path) {
        _queue[i] = updatedSong.copyWith(
          lyrics: updatedSong.lyrics ?? _queue[i].lyrics,
        );
      }
    }
  }

  bool _hasMeaningfulTrackText(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return false;
    }

    final lower = text.toLowerCase();
    return lower != 'unknown' &&
        lower != 'unknown artist' &&
        lower != 'unknown album';
  }

  bool _needsPlaybackMetadataRefresh(MusicFile song) {
    return !_hasMeaningfulTrackText(song.title) ||
        !_hasMeaningfulTrackText(song.artist) ||
        !_hasMeaningfulTrackText(song.album);
  }

  Future<MusicFile> _resolveMetadataForPlayback(MusicFile song) async {
    if (!_needsPlaybackMetadataRefresh(song)) {
      return song;
    }

    final result = await MetadataHelper.loadMetadataForPlayback(
      song.path,
      generateThumbnail: false,
    );
    if (result == null) {
      return song;
    }

    final metadata = result.$1;
    final artworkBytes = result.$2;
    final updatedSong = _songFromMetadata(
      song,
      metadata,
      artworkBytes: artworkBytes,
    );

    _replaceQueueSongsByPath(song.path, updatedSong);
    _scannerService?.updateMetadataForPath(
      metadata,
      artworkBytes: artworkBytes,
    );
    return updatedSong;
  }

  Future<void> _syncCurrentPlaybackSong(MusicFile song) async {
    if (_trackedPlaybackSongPath != song.path) {
      _resetPlaybackTrackingForSong(song);
    }
    await _updateCurrentMetadata(song);
    await _refreshCurrentWaveform(notify: false);
  }

  void _resetPlaybackTrackingForSong(MusicFile? song) {
    _trackedPlaybackSongPath = song?.path;
    _hasLoggedCurrentPlayback = false;
    _lastPlaybackObservedPosition = Duration.zero;
  }

  void _updatePlaybackTrackingForCurrentSong() {
    final song = currentMusic;
    if (song == null) {
      _resetPlaybackTrackingForSong(null);
      return;
    }

    if (_trackedPlaybackSongPath != song.path) {
      _resetPlaybackTrackingForSong(song);
    } else if (_position <= const Duration(seconds: 2) &&
        _lastPlaybackObservedPosition >= const Duration(seconds: 20)) {
      // Treat a jump back to the beginning after meaningful progress as a new play.
      _resetPlaybackTrackingForSong(song);
    }

    _lastPlaybackObservedPosition = _position;

    if (!_isPlaying || _hasLoggedCurrentPlayback) {
      return;
    }

    final durationMillis = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : (song.durationMillis ?? 0);
    final positionMillis = _position.inMilliseconds;
    final reachedThirtySeconds = positionMillis >= 30000;
    final reachedHalfway =
        durationMillis > 0 && positionMillis * 2 >= durationMillis;

    if (!reachedThirtySeconds && !reachedHalfway) {
      return;
    }

    _hasLoggedCurrentPlayback = true;
    unawaited(
      ref
          .read(libraryInsightsServiceProvider)
          .recordPlayback(
            song: song,
            playedAtMillis: DateTime.now().millisecondsSinceEpoch,
            playedDurationMillis: positionMillis,
            source: 'queue',
          )
          .catchError((Object error, StackTrace stackTrace) {
            _hasLoggedCurrentPlayback = false;
            debugPrint(
              'AudioService: failed to record playback for ${song.path}: $error',
            );
          }),
    );
  }

  Future<void> _prepareCurrentPlaybackArtwork(MusicFile song) async {
    try {
      Uint8List? artworkBytes = song.artworkBytes;
      String? artworkPath = song.artworkPath;
      String? thumbnailPath = song.thumbnailPath;
      Uint8List? themeColorsBlob = song.themeColorsBlob;

      final artworkThemeService = TrackArtworkThemeService(db: _db);
      final dbMetadata = await _db.getSongMetadata(song.path);
      if (dbMetadata != null) {
        artworkPath ??= dbMetadata.artworkPath;
        thumbnailPath ??= dbMetadata.thumbnailPath;
        themeColorsBlob ??= dbMetadata.themeColorsBlob;

        final dbArtworkPath = dbMetadata.artworkPath;
        if (dbArtworkPath != null && dbArtworkPath.trim().isNotEmpty) {
          artworkPath = dbArtworkPath;
          try {
            final file = File(dbArtworkPath);
            if (await file.exists()) {
              artworkBytes = await file.readAsBytes();
            }
          } catch (_) {}
        }
      }

      artworkBytes ??= await MetadataHelper.decodeEmbeddedArtwork(song.path);

      if (artworkPath == null ||
          thumbnailPath == null ||
          themeColorsBlob == null) {
        final supportDir = await getApplicationSupportDirectory();
        final artworkTheme = await artworkThemeService.getTrackArtworkTheme(
          song.path,
          controller: _player,
          cacheRootPath: supportDir.path,
          saveLargeArtwork: !Platform.isWindows,
        );
        if (artworkTheme != null) {
          artworkPath ??=
              artworkTheme.artworkPath ?? artworkTheme.thumbnailPath;
          thumbnailPath ??= artworkTheme.thumbnailPath;
          themeColorsBlob ??= artworkTheme.themeColorsBlob;
        }
      }

      if (artworkBytes != null && artworkBytes.isNotEmpty) {
        if (_currentIndex >= 0 && _currentIndex < _queue.length) {
          final currentSong = _queue[_currentIndex];
          if (currentSong.path == song.path) {
            _queue[_currentIndex] = currentSong.copyWith(
              artworkBytes: artworkBytes,
              artworkPath: artworkPath,
              thumbnailPath: thumbnailPath,
              themeColorsBlob: themeColorsBlob ?? currentSong.themeColorsBlob,
            );
            notifyListeners();
          }
        }

        // Keep the hero destination image sharp without allowing a full-size
        // decode to block the transition.
        // Existing desktop/mobile limits stay in place:
        // 1200px on desktop, 800px on mobile.
        final isPc = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
        final int limit = isPc ? 1200 : 800;
        final provider = ResizeImage(
          MemoryImage(artworkBytes),
          width: limit,
          height: limit,
          allowUpscaling: false,
        );
        provider.resolve(ImageConfiguration.empty);
      }

      if (themeColorsBlob != null && themeColorsBlob.isNotEmpty) {
        _applyThemeColors(ThemeColorHelper.blobToColors(themeColorsBlob));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AudioService: hero artwork prep failed for ${song.path}: $e');
    }
  }

  Future<List<double>> getWaveform({
    int expectedChunks = 80,
    int sampleStride = 8,
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
    _logPositionDebug();

    final int newIndex = _player.playlist.currentIndex ?? -1;
    if (newIndex != _currentIndex && !_isTransitioning) {
      // 检测到歌曲切换
      if (_currentIndex >= 0) {
        _lastActionNext = true; // 记录为自动切歌
      }
      _currentIndex = newIndex;
      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        final song = _queue[_currentIndex];
        _logLyricsDebug(
          'track changed -> index=$_currentIndex title="${song.displayName}" '
          'path="${song.path}" duration=$_duration active=$isLyricsActive',
        );
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

    if (!_isTransitioning &&
        _currentIndex >= 0 &&
        _currentIndex < _queue.length &&
        _queue[_currentIndex].path.isNotEmpty &&
        !(File(_queue[_currentIndex].path).existsSync())) {
      unawaited(_skipMissingCurrentTrack());
      return;
    }

    _windowsIntegration?.updateTimeline(_position, _duration);
    _androidIntegration?.updateTimeline(_position, _duration);
    _windowsIntegration?.updatePlaybackStatus(_isPlaying);
    _androidIntegration?.updatePlaybackStatus(_isPlaying);
    _updatePlaybackTrackingForCurrentSong();

    // 如果当前开启了歌词模式，但因为切歌瞬间加载太快（时长 Duration 还没准备好）
    // 导致 API 没匹配到或尚未开始加载，当时长变为有效正值时，自动触发补抓取。
    if (isLyricsActive &&
        _duration > Duration.zero &&
        !hasLyrics &&
        !isLyricsLoading &&
        !_lyricsController.isLyricsGenerationForSong(currentMusic!.path) &&
        !lyricsSearchAttempted &&
        _currentIndex >= 0 &&
        _currentIndex < _queue.length) {
      final song = _queue[_currentIndex];
      if (song.path == currentMusic?.path) {
        _logLyricsDebug(
          'auto retry trigger -> index=$_currentIndex title="${song.displayName}" '
          'duration=$_duration hasLyrics=$hasLyrics loading=$isLyricsLoading '
          'searched=$lyricsSearchAttempted',
        );
        unawaited(_lyricsController.fetchAndLog(song));
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

  void _logPositionDebug() {
    if (!kDebugMode) return;

    final now = DateTime.now();
    if (now.difference(_lastPositionDebugLogAt) < const Duration(seconds: 1)) {
      return;
    }
    _lastPositionDebugLogAt = now;

    // debugPrint(
    //   '[AudioService][Position] playing=$_isPlaying '
    //   'index=$_currentIndex '
    //   'pos=${_formatDuration(_position)} '
    //   'duration=${_formatDuration(_duration)} '
    //   'volume=${_volume.toStringAsFixed(1)} '
    //   'track=${currentMusic?.displayName ?? 'null'}',
    // );
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
    if (isLyricsActive == active) return;
    _isLyricsActive = active;
    _logLyricsDebug(
      'lyrics mode ${active ? 'enabled' : 'disabled'} -> '
      'currentIndex=$_currentIndex duration=$_duration hasLyrics=$hasLyrics '
      'loading=$isLyricsLoading searched=$lyricsSearchAttempted',
    );

    if (isLyricsActive &&
        currentMusic?.path != null &&
        !hasLyrics &&
        !isLyricsLoading &&
        !_lyricsController.isLyricsGenerationForSong(currentMusic!.path)) {
      final song = (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;
      if (song != null) {
        _logLyricsDebug(
          'lyrics mode immediate fetch -> index=$_currentIndex '
          'title="${song.displayName}" duration=$_duration',
        );
        _lyricsController.scheduleFetch(song);
      }
    }
    notifyListeners();
  }

  void _cancelSleepTimer({bool notify = true}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndAt = null;
    _sleepTimerDuration = null;
    if (notify) {
      notifyListeners();
    }
  }

  void _tickSleepTimer() {
    final endAt = _sleepTimerEndAt;
    if (endAt == null) return;

    if (DateTime.now().isBefore(endAt)) {
      notifyListeners();
      return;
    }

    _cancelSleepTimer(notify: false);
    unawaited(_stopPlaybackForSleepTimer());
    notifyListeners();
  }

  Future<void> _stopPlaybackForSleepTimer() async {
    if (_isPlaying) {
      await _player.player.pause();
    }
  }

  Future<void> startSleepTimer(Duration duration) async {
    final normalized = Duration(
      milliseconds: duration.inMilliseconds < 0 ? 0 : duration.inMilliseconds,
    );
    if (normalized <= Duration.zero) {
      await cancelSleepTimer();
      return;
    }

    _sleepTimer?.cancel();
    _sleepTimerDuration = normalized;
    _sleepTimerEndAt = DateTime.now().add(normalized);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickSleepTimer();
    });
    notifyListeners();
  }

  Future<void> cancelSleepTimer({bool notify = true}) async {
    _cancelSleepTimer(notify: notify);
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
    equalizerConfig: equalizerConfig,
    currentVisualizerOptions: currentVisualizerOptions,
    randomHistory: randomHistory,
    randomQueue: randomQueue,
    historyCursor: historyCursor,
    deckCursor: deckCursor,
    isVisualizerEnabled: isVisualizerEnabled,
    dynamicStartColor: _dynamicStartColor,
    dynamicEndColor: _dynamicEndColor,
    currentThemeColorsMap: _currentThemeColorsMap,
    isLyricsActive: isLyricsActive,
    sleepTimerRemaining: sleepTimerRemaining,
    sleepTimerDuration: sleepTimerDuration,
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

      _queue[i] = _songFromMetadata(song, metadata, artworkBytes: artworkBytes);

      queueChanged = true;
    }

    final isCurrentTrack = currentMusic?.path == metadata.path;

    await _updatePalette();

    if (queueChanged || isCurrentTrack) {
      if (isCurrentTrack &&
          isLyricsActive &&
          !hasLyrics &&
          !isLyricsLoading &&
          !_lyricsController.isLyricsGenerationForSong(metadata.path)) {
        final current = currentMusic;
        if (current != null) {
          unawaited(_lyricsController.fetchAndLog(current));
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

  Future<void> _handleWaveformChunkChange() async {
    await _db.clearWaveformCache();
    _clearInMemoryWaveformCache();

    if (settingsService.isWaveformProgressBarEnabled) {
      await _refreshCurrentWaveform();
    } else {
      notifyListeners();
    }
  }

  void _clearInMemoryWaveformCache() {
    bool changed = false;
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].waveformBlob != null) {
        _queue[i] = _queue[i].copyWith(waveformBlob: null);
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  void _applyThemeColors(Map<String, Color> colors) {
    _currentThemeColorsMap = colors;
    _dynamicStartColor = colors['dominant'] ?? colors['vibrant'];
    _dynamicEndColor =
        (colors['vibrant']?.withValues(alpha: 0.8)) ?? colors['muted'];
  }

  Future<void> saveCurrentSongThemeColors(Map<String, Color> colors) async {
    final current = currentMusic;
    if (current == null) return;
    final existingMetadata = await _db.getSongMetadata(current.path);

    final themeColorsBlob = ThemeColorHelper.colorsMapToBlob(colors);
    final updatedSong = current.copyWith(themeColorsBlob: themeColorsBlob);
    final updatedMetadata = SongMetadata(
      id: updatedSong.id,
      path: updatedSong.path,
      title: updatedSong.title ?? updatedSong.displayName,
      album: updatedSong.album ?? 'Unknown',
      artist: updatedSong.artist ?? 'Unknown',
      duration: updatedSong.durationMillis,
      artworkPath: updatedSong.artworkPath,
      thumbnailPath: updatedSong.thumbnailPath,
      artworkWidth: updatedSong.artworkWidth,
      artworkHeight: updatedSong.artworkHeight,
      trackNumber: updatedSong.trackNumber,
      themeColorsBlob: themeColorsBlob,
      waveformBlob: updatedSong.waveformBlob,
      lastModifiedTime: updatedSong.lastModifiedTime,
      metadataTextScanned:
          existingMetadata?.metadataTextScanned ?? updatedSong.lastModifiedTime,
      metadataImgScanned:
          existingMetadata?.metadataImgScanned ?? updatedSong.lastModifiedTime,
      createdAt: existingMetadata?.createdAt,
      genres: existingMetadata?.genres,
    );

    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue[_currentIndex] = updatedSong;
    }

    _applyThemeColors(colors);
    await _db.insertOrUpdateSong(updatedMetadata);
    _scannerService?.updateMetadataForPath(
      updatedMetadata,
      artworkBytes: updatedSong.artworkBytes,
    );
    await _playlistService?.updateSongMetadataByPath(
      updatedMetadata,
      artworkBytes: updatedSong.artworkBytes,
    );
    notifyListeners();
  }

  Future<void> recomputeThemeColorsWithMaster({
    required String songPath,
  }) async {
    if (_themePaletteRecomputeInProgressPath == songPath) {
      return;
    }

    final current = currentMusic;
    if (current == null || current.path != songPath) {
      return;
    }

    final bytes = current.artworkBytes;
    final sourcePath = current.thumbnailPath ?? current.artworkPath;
    if ((bytes == null || bytes.isEmpty) &&
        (sourcePath == null || sourcePath.isEmpty)) {
      return;
    }

    _themePaletteRecomputeInProgressPath = songPath;
    try {
      final themeColorsBlob =
          await TrackArtworkThemeService.generateThemeColorsBlob(
            bytes: bytes,
            path: sourcePath,
            useMaster: true,
          );

      if (currentMusic?.path != songPath || themeColorsBlob == null) {
        return;
      }

      await saveCurrentSongThemeColors(
        ThemeColorHelper.blobToColors(themeColorsBlob),
      );
    } catch (e) {
      debugPrint('Error recomputing theme colors for $songPath: $e');
    } finally {
      if (_themePaletteRecomputeInProgressPath == songPath) {
        _themePaletteRecomputeInProgressPath = null;
      }
    }
  }

  Future<void> _updatePalette() async {
    final artworkBytes = currentMusic?.artworkBytes;
    final artworkPath =
        currentMusic?.artworkPath ?? currentMusic?.thumbnailPath;
    final themeColorsBlob = currentMusic?.themeColorsBlob;

    if (artworkBytes == null &&
        artworkPath == null &&
        themeColorsBlob == null) {
      _dynamicStartColor = null;
      _dynamicEndColor = null;
      _currentThemeColorsMap = const {};
      notifyListeners();
      return;
    }

    if (themeColorsBlob != null && themeColorsBlob.isNotEmpty) {
      final colorsMap = ThemeColorHelper.blobToColors(themeColorsBlob);
      _applyThemeColors(colorsMap);
      _dynamicStartColor = colorsMap['dominant'] ?? colorsMap['vibrant'];
      _dynamicEndColor =
          (colorsMap['vibrant']?.withValues(alpha: 0.8)) ?? colorsMap['muted'];
      notifyListeners();
      return;
    }

    final paletteBlob = await TrackArtworkThemeService.generateThemeColorsBlob(
      bytes: artworkBytes,
      path: artworkPath,
    );

    if (paletteBlob == null || paletteBlob.isEmpty) {
      _dynamicStartColor = null;
      _dynamicEndColor = null;
      _currentThemeColorsMap = const {};
      notifyListeners();
      return;
    }

    final colorsMap = ThemeColorHelper.blobToColors(paletteBlob);
    _applyThemeColors(colorsMap);
    _dynamicStartColor = colorsMap['dominant'] ?? colorsMap['vibrant'];
    _dynamicEndColor =
        (colorsMap['vibrant']?.withValues(alpha: 0.8)) ?? colorsMap['muted'];
    notifyListeners();
  }

  /// Synchronizes the currently playing song with the in-memory playback state.
  ///
  /// This method does not "scan" the file or rebuild the database. Its job is to:
  /// - make sure the current queue item reflects the newest `MusicFile` data
  /// - preserve any existing lyrics already attached to that song
  /// - hydrate artwork and theme colors if they are already available
  /// - push the current track metadata to Windows / Android integration layers
  /// - kick off lyrics loading when lyric mode is enabled
  ///
  /// In short: this is the "apply current song metadata to the player/UI" step
  /// that runs after a track becomes current.
  Future<void> _updateCurrentMetadata(MusicFile inputSong) async {
    final song = await _resolveMetadataForPlayback(inputSong);
    final path = song.path;
    final isCurrentSong =
        _currentIndex >= 0 &&
        _currentIndex < _queue.length &&
        _queue[_currentIndex].path == path;
    // Guard against async races:
    // if the queue has already moved on to another track, do not let this call
    // overwrite the newer song's state with stale metadata.
    if (isCurrentSong) {
      // Keep any existing lyrics that are already attached to the current item.
      // A normal metadata refresh should not wipe lyrics that were loaded or cached.
      final existingLyrics = _queue[_currentIndex].lyrics;
      _queue[_currentIndex] = song.copyWith(
        lyrics: song.lyrics ?? existingLyrics,
      );
    } else {
      _logLyricsDebug(
        'metadata refresh ignored for stale song -> title="${song.displayName}" '
        'path="$path" currentPath="${currentMusic?.path}"',
      );
      return;
    }

    // Apply cached theme colors immediately so the UI can update without waiting
    // for the slower artwork/palette pipeline.
    final hasCachedThemeColors = song.themeColorsBlob != null;
    if (song.themeColorsBlob != null) {
      final colorsMap = ThemeColorHelper.blobToColors(song.themeColorsBlob!);
      _applyThemeColors(colorsMap);
    }

    // Hydrate artwork bytes asynchronously:
    // prefer the higher-quality file saved in the metadata database, then fall
    // back to embedded artwork inside the audio file.
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
        // If we already have cached theme colors from the database, keep them
        // as the final source of truth to avoid a second visual color change.
        if (!hasCachedThemeColors) {
          // Recompute the palette only after the artwork bytes have been updated.
          await _updatePalette();
        }
      }
    }());

    // Prefer the latest current queue item here rather than the async input
    // snapshot. A lyrics fetch can complete while metadata refresh is still in
    // flight, and the queue entry may already contain the freshly attached
    // lyrics even if `song` was captured earlier without them.
    final latestCurrentSong =
        (_currentIndex >= 0 && _currentIndex < _queue.length)
        ? _queue[_currentIndex]
        : song;

    // If the current song already carries lyrics, restore them directly.
    // Otherwise clear lyric state and let the async lyric fetch pipeline decide
    // whether anything should be loaded.
    final songLyrics = latestCurrentSong.lyrics;
    if (isLyricsActive && songLyrics != null) {
      _lyricsController.restoreFromSongLyrics(latestCurrentSong);
    } else {
      _logLyricsDebug(
        'lyrics state cleared -> title="${song.displayName}" '
        'mode=$isLyricsActive hasCache=${songLyrics != null}',
      );
      _lyricsController.clearState(preserveTaskState: true);
    }

    notifyListeners();

    // Fallback palette refresh:
    // if artwork bytes/path are still missing here, keep the UI color state in
    // sync with whatever is currently available.
    if (!hasCachedThemeColors &&
        currentMusic?.artworkBytes == null &&
        currentMusic?.artworkPath == null) {
      await _updatePalette();
    }

    // Propagate the current track to platform integrations so Windows media
    // controls / Android notification UI stay in sync with playback.
    _windowsIntegration?.updateMetadata(song);
    _androidIntegration?.updateMetadata(song);

    // Trigger lyric loading only when lyric mode is active and we still do not
    // have lyrics for this track.
    if (isLyricsActive && !hasLyrics) {
      if (_lyricsController.isLyricsGenerationForSong(song.path)) {
        _logLyricsDebug(
          'post-metadata fetch skipped because lyrics generation is active '
          '-> title="${song.displayName}"',
        );
      } else {
        _logLyricsDebug(
          'post-metadata fetch -> title="${song.displayName}" '
          'duration=$_duration hasLyrics=$hasLyrics loading=$isLyricsLoading',
        );
        _lyricsController.scheduleFetch(song);
      }
    }

    notifyListeners();
  }

  void _cacheSongDuration(String path, int durationMillis) {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final currentSong = _queue[_currentIndex];
    if (currentSong.path != path) return;
    if (currentSong.durationMillis == durationMillis) return;

    _queue[_currentIndex] = currentSong.copyWith(
      durationMillis: durationMillis,
    );
    notifyListeners();
  }

  void _logLyricsDebug(String message) {
    if (!kDebugMode) return;
    debugPrint('[AudioService][Lyrics] $message');
  }

  Future<MusicFile> _buildMusicFileFromPath(
    String path, {
    required String name,
    int? id,
    String? mediaUri,
  }) async {
    final resolved = await MetadataHelper.loadMetadataForPlayback(
      path,
      generateThumbnail: false,
    );
    final metadata = resolved?.$1;
    final artworkBytes = resolved?.$2;

    return MusicFile(
      path: path,
      name: name,
      title: metadata?.title,
      artist: metadata?.artist,
      album: metadata?.album,
      trackNumber: metadata?.trackNumber,
      durationMillis: metadata?.duration,
      thumbnailPath: metadata?.thumbnailPath,
      artworkPath: metadata?.artworkPath,
      artworkWidth: metadata?.artworkWidth,
      artworkHeight: metadata?.artworkHeight,
      themeColorsBlob: metadata?.themeColorsBlob,
      artworkBytes: artworkBytes,
      lastModifiedTime: metadata?.lastModifiedTime,
      id: id,
      mediaUri: mediaUri,
    );
  }

  Future<void> _playQueueTracks({
    required List<MusicFile> songs,
    required int startIndex,
    required bool clearPlayerQueue,
    bool startBackgroundProcessing = true,
  }) async {
    if (songs.isEmpty) return;

    final safeIndex = startIndex.clamp(0, songs.length - 1);
    final paths = songs.map((song) => song.path).toList(growable: false);

    if (clearPlayerQueue) {
      await _player.playlist.clear();
    }

    await _player.playPaths(paths, autoPlayFirst: false);

    final current = songs[safeIndex];
    await _player.playTrack(
      _audioTrackForSong(current),
      preferredPlaylistId: _player.playlist.queuePlaylistId,
    );

    _currentIndex = safeIndex;
    await _syncCurrentPlaybackSong(current);
    await _player.player.setVolume(_volume / 100.0);
    if (startBackgroundProcessing) {
      _startQueueBackgroundProcessing(priorityPath: current.path);
    }
  }

  Future<void> playFile(
    String path,
    String name, {
    int? id,
    String? mediaUri,
    bool append = false,
  }) async {
    if (!await _songExists(path)) {
      setSongMissingStateByPath(path, true);
      _showMissingSongNotice(skipped: false);
      return;
    }

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
      }

      _queue.add(song);
      await _playQueueTracks(
        songs: _queue,
        startIndex: _queue.length - 1,
        clearPlayerQueue: !append,
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
    if (!await _songExists(songs[safeIndex].path)) {
      setSongMissingStateByPath(songs[safeIndex].path, true);
      _showMissingSongNotice(skipped: false);
      return;
    }

    // 1. 设置正在切换状态并通知 UI
    _isTransitioning = true;
    notifyListeners();
    _queueProcessor.pause();
    _scannerService?.pauseBackgroundTasks();

    // 2. 清除并重新填充本地播放队列
    _queue.clear();
    _queue.addAll(songs);
    _currentIndex = safeIndex;
    notifyListeners();

    final current = _queue[safeIndex];

    unawaited(
      _playQueueTracks(
        songs: _queue,
        startIndex: safeIndex,
        clearPlayerQueue: true,
        startBackgroundProcessing: false,
      ).catchError((e) {
        debugPrint('AudioService: failed to start playlist playback: $e');
      }),
    );

    await _prepareCurrentPlaybackArtwork(current);
  }

  Future<void> addToPlaylist(List<MusicFile> songs) async {
    if (songs.isEmpty) return;

    final bool wasEmpty = _queue.isEmpty;
    _queue.addAll(songs);

    if (wasEmpty) {
      await _playQueueTracks(
        songs: _queue,
        startIndex: 0,
        clearPlayerQueue: false,
      );
      return;
    }

    final tracks = songs.map(_audioTrackForSong).toList(growable: false);
    await _player.playlist.addTracks(tracks);
    _startQueueBackgroundProcessing();
    notifyListeners();
  }

  Future<void> enqueueNext(List<MusicFile> songs) async {
    if (songs.isEmpty) return;

    if (_queue.isEmpty) {
      await playPlaylist(songs);
      return;
    }

    final insertAt = (_currentIndex >= 0 && _currentIndex < _queue.length)
        ? _currentIndex + 1
        : _queue.length;

    for (var i = 0; i < songs.length; i++) {
      final song = songs[i];
      _queue.insert(insertAt + i, song);
      await _player.playlist.insertTrack(
        insertAt + i,
        _audioTrackForSong(song),
      );
    }

    _startQueueBackgroundProcessing(priorityPath: currentMusic?.path);
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
    _resetPlaybackTrackingForSong(null);
  }

  Future<void> clearPlaylist() async {
    _cancelSleepTimer(notify: false);
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
          await _syncCurrentPlaybackSong(song);
        }
      }
    } finally {
      _isTransitioning = false;
      notifyListeners();
    }
  }

  Future<void> playAtIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    if (!await _songExists(_queue[index].path)) {
      setSongMissingStateByPath(_queue[index].path, true);
      _showMissingSongNotice(skipped: false);
      return;
    }
    if (_isTransitioning) return;
    if (index == _currentIndex && _isPlaying) return;

    _isTransitioning = true;
    _lastActionNext = (index > _currentIndex);
    try {
      final song = _queue[index];
      await _player.playTrack(
        _audioTrackForSong(song),
        preferredPlaylistId:
            _player.playlist.activePlaylistId ??
            _player.playlist.queuePlaylistId,
      );
      _currentIndex = index;
      await _syncCurrentPlaybackSong(song);
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
          await _syncCurrentPlaybackSong(song);
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

    _queue.addAll(newSongs);

    final tracks = newSongs.map(_audioTrackForSong).toList(growable: false);

    // We don't use await here to keep it synchronous for the toggle
    unawaited(_player.playlist.addTracks(tracks));
    _startQueueBackgroundProcessing();
  }

  AudioTrack _audioTrackForSong(MusicFile song) {
    return AudioTrack(
      id: song.path,
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

  Future<void> completeHeroTransition({String? priorityPath}) async {
    if (_disposed) return;

    _queueProcessor.resume();
    _scannerService?.resumeBackgroundTasks();

    if (_isTransitioning) {
      _isTransitioning = false;
    }

    if (_queue.isNotEmpty) {
      _startQueueBackgroundProcessing(
        priorityPath: priorityPath ?? currentMusic?.path,
      );
    }

    notifyListeners();
  }

  void _dispose() {
    _disposed = true;
    _sleepTimer?.cancel();
    _player.removeListener(_handlePlayerChanges);
    settingsService.removeListener(_settingsListener);
    _queueProcessor.dispose();
    _player.visualizer.removeOutput('mini_player');
    _windowsIntegration?.dispose();
    _player.dispose();
  }
}
