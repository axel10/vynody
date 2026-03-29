import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import '../models/music_file.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';
import 'settings_service.dart';
import 'visualizer_options_service.dart';
import 'playback_queue_processor.dart';
import 'waveform_service.dart';
import 'playback_theme_service.dart';
import 'package:path_provider/path_provider.dart';
import 'windows_integration_service.dart';
import 'android_integration_service.dart';

class AudioService extends ChangeNotifier {
  late final AudioVisualizerPlayerController _player;
  bool _isPlaying = false;
  String? _currentFilePath;
  String? _currentFileName;
  String? _currentArtist;
  String? _currentAlbum;
  int? _currentSongId;
  List<double> _currentWaveform = const [];
  Uint8List? _currentArtworkBytes;
  String? _currentArtworkPath;
  int? _artworkWidth;
  int? _artworkHeight;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100.0;
  double _previousVolume = 100.0;
  bool _isMuted = false;
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final MetadataDatabase _db = MetadataDatabase();

  final List<MusicFile> _playlist = [];
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
  final PlaybackThemeService themeService;
  late final VisualizerOptionsService _visualizerOptions;
  late final PlaybackQueueProcessor _queueProcessor;
  late final WaveformService _waveformService;

  // 独立的 FFT 输出流（用于迷你播放器）
  VisualizerOutputStream? _miniPlayerFftStream;

  late final WindowsIntegrationService? _windowsIntegration;
  late final AndroidIntegrationService? _androidIntegration;

  AudioService(this.settingsService, this.themeService) {
    _player = AudioVisualizerPlayerController(
      fadeMode: FadeMode.crossfade,
      fadeDuration: const Duration(milliseconds: 500),
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
    _windowsIntegration = Platform.isWindows
        ? WindowsIntegrationService(this)
        : null;
    _androidIntegration = Platform.isAndroid
        ? AndroidIntegrationService(this)
        : null;
    _player.addListener(_handlePlayerChanges);
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

  Future<void> _refreshCurrentWaveform({bool notify = true}) async {
    final path = _currentFilePath;
    if (path == null) {
      if (_currentWaveform.isNotEmpty) {
        _currentWaveform = const [];
        if (notify) {
          notifyListeners();
        }
      }
      return;
    }

    final waveform = await getWaveform(
      expectedChunks: settingsService.waveformChunks,
      sampleStride: settingsService.sampleStride,
    );
    if (path == _currentFilePath && waveform.isNotEmpty) {
      _currentWaveform = waveform;
      if (notify) {
        notifyListeners();
      }
    }
  }

  Future<void> updateDynamicColors() async {
    // Forward to theme service
    await themeService.updatePalette(
      filePath: _currentFilePath,
      artworkBytes: _currentArtworkBytes,
      artworkPath: _currentArtworkPath,
    );
  }


  Future<List<double>> getWaveform({
    int expectedChunks = 80,
    int sampleStride = 3,
  }) async {
    final path = _currentFilePath;
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
      if (_currentIndex >= 0) {
        _lastActionNext = true; // Auto advance
      }
      _currentIndex = newIndex;
      if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
        final song = _playlist[_currentIndex];
        unawaited(
          _updateCurrentMetadata(song).then((_) {
            _refreshCurrentWaveform();
            _windowsIntegration?.updateMetadata(_playlist[newIndex]);
            _androidIntegration?.updateMetadata(_playlist[newIndex]);
            _startQueueBackgroundProcessing();
          }),
        );
      }
      _windowsIntegration?.updatePlaybackStatus(_isPlaying);
      _androidIntegration?.updatePlaybackStatus(_isPlaying);
      _notifyIfNeeded(force: true);
    } else {
      _windowsIntegration?.updateTimeline(_position, _duration);
      _androidIntegration?.updateTimeline(_position, _duration);
      _windowsIntegration?.updatePlaybackStatus(_isPlaying);
      _androidIntegration?.updatePlaybackStatus(_isPlaying);
      _notifyIfNeeded();
    }
  }

  void _notifyIfNeeded({bool force = false}) {
    final now = DateTime.now();
    final playbackChanged =
        _isPlaying != _lastNotifiedIsPlaying ||
        _duration != _lastNotifiedDuration ||
        _currentIndex != _lastNotifiedIndex ||
        _currentFilePath != _lastNotifiedFilePath;
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
    _lastNotifiedFilePath = _currentFilePath;
    notifyListeners();
  }

  bool? get isLastActionNext => _lastActionNext;
  bool get isTransitioning => _isTransitioning;

  AudioVisualizerPlayerController get player => _player;

  bool get isPlaying => _isPlaying;
  String? get currentFilePath => _currentFilePath;
  String? get currentFileName => _currentFileName;
  String? get currentArtist => _currentArtist;
  String? get currentAlbum => _currentAlbum;
  int? get currentSongId => _currentSongId;
  List<double> get currentWaveform => List.unmodifiable(_currentWaveform);
  Uint8List? get currentArtworkBytes => _currentArtworkBytes;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  int? get artworkWidth => _artworkWidth;
  int? get artworkHeight => _artworkHeight;
  String? get currentArtworkPath => _currentArtworkPath;
  Uint8List? get currentBlurredArtworkBytes => themeService.currentBlurredArtworkBytes;
  Map<String, Color> get currentThemeColorsMap => themeService.currentThemeColorsMap;
  Color? get dynamicStartColor => themeService.dynamicStartColor;
  Color? get dynamicEndColor => themeService.dynamicEndColor;
  List<MusicFile> get playlist => List.unmodifiable(_playlist);
  int get currentIndex => _currentIndex;
  bool get isRandomMode => _player.playlist.randomPolicy != null;

  Uint8List? getCachedArtwork(String? path) =>
      path != null ? _hdArtworkCache[path] : null;

  int get maxHdCacheSize => _maxHdCacheSize;

  bool get isShuffleRandomMode =>
      _player.playlist.randomPolicy?.label == 'shuffleRandom';

  int? get historyCursor => _player.playlist.historyCursor;

  List<MusicFile> get randomHistory {
    final history = _player.playlist.randomHistory;
    return history.map((entry) {
      if (entry.trackIndex >= 0 && entry.trackIndex < _playlist.length) {
        return _playlist[entry.trackIndex];
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
      if (index >= 0 && index < _playlist.length) {
        return _playlist[index];
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


  Future<void> _updateCurrentMetadata(MusicFile song) async {
    final path = song.path;
    final name = song.displayName;
    final id = song.id;

    if (_currentFilePath == path && _currentSongId == id) return;

    // Clear previous high-res bytes to avoid showing wrong artwork during transition
    _currentArtworkBytes = null;
    _currentFilePath = path;
    _currentFileName = name;
    _currentArtist = song.artist;
    _currentAlbum = song.album;
    _currentSongId = id;

    // 1. Try to get metadata from database immediately (fast)
    final songFromDb = await _db.getSongMetadata(path);
    if (songFromDb != null) {
      _currentWaveform = _waveformService.waveformFromBlob(
        songFromDb.waveformBlob,
      );
      _currentArtworkPath = songFromDb.artworkPath;
      _artworkWidth = songFromDb.artworkWidth;
      _artworkHeight = songFromDb.artworkHeight;
      if (songFromDb.title.trim().isNotEmpty && songFromDb.title != 'Unknown') {
        _currentFileName = songFromDb.title;
      }
      _currentArtist = songFromDb.artist;
      _currentAlbum = songFromDb.album;
    } else {
      _currentWaveform = const [];
      _currentArtworkPath = null;
      _artworkWidth = null;
      _artworkHeight = null;
    }

    // Notify listeners immediately so the UI can show the placeholder (thumbnail from DB)
    _windowsIntegration?.updateMetadata(null);
    notifyListeners();

    // 2. Load fresh high-quality metadata and artwork
    Uint8List? newArtworkBytes = _hdArtworkCache[path]; // Try cache first
    String? newArtworkPath = _currentArtworkPath;
    int? newArtworkWidth = _artworkWidth;
    int? newArtworkHeight = _artworkHeight;
    
    // If not in cache, we'll try to load it asynchronously below
    bool wasInCache = newArtworkBytes != null;
    if (wasInCache) {
      // Get dimensions from the cached bytes if possible
      final codec = await ui.instantiateImageCodec(newArtworkBytes);
      final frameInfo = await codec.getNextFrame();
      newArtworkWidth = frameInfo.image.width;
      newArtworkHeight = frameInfo.image.height;
    }

    if (songFromDb == null) {
      // If not in DB, use MetadataHelper to process it (and save to DB for next time)
      final result = await MetadataHelper.processMetadata(path);
      if (result != null) {
        final processed = result.$1;
        final processedBytes = result.$2;
        
        if (processed.title.trim().isNotEmpty && processed.title != 'Unknown') {
          _currentFileName = processed.title;
        }
        _currentArtist = processed.artist;
        _currentAlbum = processed.album;
        _currentArtworkPath = processed.artworkPath;
        _artworkWidth = processed.artworkWidth;
        _artworkHeight = processed.artworkHeight;
        _currentWaveform = _waveformService.waveformFromBlob(processed.waveformBlob);
        
        // REUSE BYTES if they were just read during processing!
        if (processedBytes != null) {
            newArtworkBytes = processedBytes;
            _hdArtworkCache[path] = processedBytes;
            unawaited(themeService.updateCurrentArtwork(path, processedBytes));
            
            final codec = await ui.instantiateImageCodec(processedBytes);
            final frameInfo = await codec.getNextFrame();
            newArtworkWidth = frameInfo.image.width;
            newArtworkHeight = frameInfo.image.height;
            wasInCache = true; // Effectively in cache now
        }
      }
    }

    // 3. 统一全平台高清元数据与原封加载 (Unified HD Metadata & Artwork Loading)
    if (!wasInCache) {
      try {
        final metadata = readMetadata(File(path), getImage: true);
        final bytes = metadata.pictures.isNotEmpty ? metadata.pictures.first.bytes : null;
        if (bytes != null) {
          newArtworkBytes = bytes;
          _hdArtworkCache[path] = bytes;
          
          // Trigger blur in background as soon as we have bytes
          unawaited(themeService.updateCurrentArtwork(path, bytes));

          // Use dart:ui for much faster decoding on native side
          final codec = await ui.instantiateImageCodec(bytes);
          final frameInfo = await codec.getNextFrame();
          newArtworkWidth = frameInfo.image.width;
          newArtworkHeight = frameInfo.image.height;
        } else if (Platform.isAndroid && id != null) {
          // 如果 MetadataGod 未能直接从文件读取到封面，Android 平台尝试从系统 MediaStore 兜底
          try {
            final fallbackBytes = await _audioQuery.queryArtwork(
              id,
              ArtworkType.AUDIO,
              format: ArtworkFormat.JPEG,
              size: 600,
              quality: 100,
            );
            if (fallbackBytes != null) {
              newArtworkBytes = fallbackBytes;
              _hdArtworkCache[path] = fallbackBytes;
              unawaited(themeService.updateCurrentArtwork(path, fallbackBytes));
            }
          } catch (e) {
            debugPrint('Error in Android artwork fallback: $e');
          }
        }
      } catch (e) {
        debugPrint('Error reading high-res metadata (Unified): $e');
        // 如果 audio_metadata_reader 抛出异常且在 Android 上，则尝试兜底
        if (Platform.isAndroid && id != null && newArtworkBytes == null) {
          try {
            final fallbackBytes = await _audioQuery.queryArtwork(
              id,
              ArtworkType.AUDIO,
              format: ArtworkFormat.JPEG,
              size: 600,
              quality: 100,
            );
            if (fallbackBytes != null) {
              newArtworkBytes = fallbackBytes;
              _hdArtworkCache[path] = fallbackBytes;
              unawaited(themeService.updateCurrentArtwork(path, fallbackBytes));
            }
          } catch (_) {}
        }
      }
    }

    // Android 平台的通知栏逻辑 (即使在缓存中也要确保 temp 文件存在)
    if (Platform.isAndroid && newArtworkBytes != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        final artworkSuffix = [
          (id ?? path.hashCode).toString(),
          DateTime.now().microsecondsSinceEpoch.toString(),
        ].join('_');
        final artworkFile = File(
          '${tempDir.path}/current_notification_artwork_$artworkSuffix.jpg',
        );
        await artworkFile.writeAsBytes(newArtworkBytes);
        newArtworkPath = artworkFile.path;
      } catch (e) {
        debugPrint('Error saving notification artwork on Android: $e');
      }
    }

    _currentArtworkBytes = newArtworkBytes;
    
    await themeService.updatePalette(
      filePath: path,
      artworkBytes: newArtworkBytes,
      artworkPath: newArtworkPath,
      metadata: songFromDb,
    );
    await themeService.updateCurrentArtwork(path, newArtworkBytes);

    _currentArtworkPath = newArtworkPath;
    _artworkWidth = newArtworkWidth;
    _artworkHeight = newArtworkHeight;

    _windowsIntegration?.updateMetadata(null);
    _androidIntegration?.updateMetadata(null);
    notifyListeners();
  }

  Future<void> playFile(
    String path,
    String name, {
    int? id,
    bool append = false,
  }) async {
    final song = MusicFile(path: path, name: name, id: id);
    if (!append) {
      _playlist.clear();
      await _player.playlist.clear();
    }

    final int index = _playlist.length;
    _playlist.add(song);
    await _player.playlist.addTracks([
      AudioTrack(id: index.toString(), uri: path),
    ]);

    _startQueueBackgroundProcessing();
    await playAtIndex(index);
  }

  Future<void> playPlaylist(
    List<MusicFile> songs, {
    int initialIndex = 0,
  }) async {
    if (songs.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, songs.length - 1);

    _isTransitioning = true;
    notifyListeners();

    try {
      _playlist.clear();
      _playlist.addAll(songs);
      _currentIndex = safeIndex;
      notifyListeners();

      final tracks = songs.asMap().entries.map((e) {
        return AudioTrack(id: e.key.toString(), uri: e.value.path);
      }).toList();

      // Clear existing playlist and add all tracks
      await _player.playlist.clear();
      await _player.playlist.addTracks(tracks);

      // Play the selected track
      if (_player.playlist.activePlaylistId != null) {
        await _player.playlist.setActivePlaylist(
          _player.playlist.activePlaylistId!,
          startIndex: safeIndex,
          autoPlay: true,
        );
      }

      final current = songs[safeIndex];
      await _updateCurrentMetadata(current);

      await _player.player.setVolume(_volume / 100.0);
      await _refreshCurrentWaveform(notify: false);
      _startQueueBackgroundProcessing();
    } finally {
      _isTransitioning = false;
      notifyListeners();
    }
  }

  Future<void> addToPlaylist(List<MusicFile> songs) async {
    if (songs.isEmpty) return;

    final bool wasEmpty = _playlist.isEmpty;
    _playlist.addAll(songs);

    final startIndex = _player.playlist.items.length;
    final tracks = songs.asMap().entries.map((e) {
      return AudioTrack(id: (startIndex + e.key).toString(), uri: e.value.path);
    }).toList();
    await _player.playlist.addTracks(tracks);

    if (wasEmpty) {
      _currentIndex = 0;
      final current = songs[0];
      await _updateCurrentMetadata(current);
      await _player.player.setVolume(_volume / 100.0);
      await _refreshCurrentWaveform(notify: false);
    }
    _startQueueBackgroundProcessing();
    notifyListeners();
  }

  Future<void> removeFromPlaylist(int index) async {
    if (index >= 0 && index < _playlist.length) {
      _playlist.removeAt(index);
      await _player.playlist.removeTrackAt(index);
      notifyListeners();
    }
  }

  Future<void> clearPlaylist() async {
    _playlist.clear();
    _currentIndex = -1;
    _currentFilePath = null;
    _currentFileName = null;
    _currentArtist = null;
    _currentAlbum = null;
    _currentSongId = null;
    _currentWaveform = const [];
    _currentArtworkBytes = null;
    _currentArtworkPath = null;
    _isPlaying = false;
    themeService.clear();
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
        if (newIndex >= 0 && newIndex < _playlist.length) {
          _currentIndex = newIndex;
          final song = _playlist[_currentIndex];
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
    if (index < 0 || index >= _playlist.length) return;
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
      final song = _playlist[_currentIndex];
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
        if (newIndex >= 0 && newIndex < _playlist.length) {
          _currentIndex = newIndex;
          final song = _playlist[_currentIndex];
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
    if (Platform.isAndroid && !_isPlaying) {
      final session = await AudioSession.instance;
      if (!await session.setActive(true)) {
        return; // Failed to get focus
      }
    }
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
    final existingPaths = _playlist.map((s) => s.path).toSet();
    final newSongs = globalSongs
        .where((s) => !existingPaths.contains(s.path))
        .toList();

    if (newSongs.isEmpty) return;

    final startIndex = _playlist.length;
    _playlist.addAll(newSongs);

    final tracks = newSongs.asMap().entries.map((e) {
      return AudioTrack(id: (startIndex + e.key).toString(), uri: e.value.path);
    }).toList();

    // We don't use await here to keep it synchronous for the toggle
    unawaited(_player.playlist.addTracks(tracks));
    _startQueueBackgroundProcessing();
  }


  final Map<String, Uint8List> _hdArtworkCache = {};
  static const int _maxHdCacheSize = 8;

  void _startQueueBackgroundProcessing() {
    if (_playlist.isEmpty) return;

    unawaited(
      _queueProcessor.processQueue(
        playlist: List.from(_playlist),
        currentFilePath: _currentFilePath,
        onUpdate: (path, updates) {
          if (path == _currentFilePath) {
            if (updates.containsKey('themeColors')) {
              themeService.updateFromThemeColors(updates['themeColors'] as Map<String, Color>);
            }
            if (updates.containsKey('waveform')) {
              _currentWaveform = updates['waveform'] as List<double>;
            }
            notifyListeners();
          }
        },
        onHdArtworkLoaded: (path, bytes) {
          _hdArtworkCache[path] = bytes;
          if (_hdArtworkCache.length > _maxHdCacheSize) {
            _hdArtworkCache.remove(_hdArtworkCache.keys.first);
          }
          // If the song we just loaded HD art for is the current song, update immediately
          if (path == _currentFilePath && _currentArtworkBytes == null) {
            _currentArtworkBytes = bytes;
            unawaited(themeService.updateCurrentArtwork(path, bytes));
            notifyListeners();
          } else {
            // Also blur it and cache it for upcoming songs
            unawaited(themeService.updateCurrentArtwork(path, bytes));
          }
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
