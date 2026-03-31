import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:audio_core/audio_core.dart';
import '../models/music_file.dart';
import 'audio_snapshot.dart';
import 'current_track_asset_resolver.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';
import 'lyrics_service.dart';
import 'settings_service.dart';
import 'theme_color_helper.dart';
import 'visualizer_options_service.dart';
import 'playback_queue_processor.dart';
import 'waveform_service.dart';
import 'windows_integration_service.dart';
import 'android_integration_service.dart';

class AudioService extends ChangeNotifier {
  late final AudioCoreController _player;
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
  late final VisualizerOptionsService _visualizerOptions;
  late final PlaybackQueueProcessor _queueProcessor;
  late final WaveformService _waveformService;
  late final CurrentTrackAssetResolver _trackAssetResolver;
  late final LyricsService _lyricsService;
  int _lyricsRequestSerial = 0;

  // 独立的 FFT 输出流（用于迷你播放器）
  VisualizerOutputStream? _miniPlayerFftStream;

  Uint8List? _currentBlurredArtworkBytes;
  final Map<String, Uint8List> _blurredArtworkCache = {};
  static const int _maxBlurredCacheSize = 20;

  Color? _dynamicStartColor;
  Color? _dynamicEndColor;
  Map<String, Color> _currentThemeColorsMap = const {};
  late final WindowsIntegrationService? _windowsIntegration;
  late final AndroidIntegrationService? _androidIntegration;

  Color? get dynamicStartColor => _dynamicStartColor;
  Color? get dynamicEndColor => _dynamicEndColor;
  Map<String, Color> get currentThemeColorsMap => _currentThemeColorsMap;

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
    _trackAssetResolver = CurrentTrackAssetResolver(db: _db);
    _lyricsService = LyricsService();
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

  void moveQueueTrack(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _playlist.length ||
        newIndex < 0 ||
        newIndex >= _playlist.length ||
        oldIndex == newIndex) {
      return;
    }

    final movedSong = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, movedSong);
    _player.playlist.moveTrack(oldIndex, newIndex);

    if (_currentFilePath != null) {
      final updatedIndex = _playlist.indexWhere(
        (song) => song.path == _currentFilePath,
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
  Uint8List? get currentBlurredArtworkBytes => _currentBlurredArtworkBytes;
  List<MusicFile> get playbackQueue => List.unmodifiable(_playlist);
  List<MusicFile> get playlist => playbackQueue;
  int get currentIndex => _currentIndex;
  bool get isRandomMode => _player.playlist.randomPolicy != null;
  AudioSnapshot get snapshot => AudioSnapshot(
    isPlaying: _isPlaying,
    isTransitioning: _isTransitioning,
    isLastActionNext: _lastActionNext,
    currentFilePath: _currentFilePath,
    currentFileName: _currentFileName,
    currentArtist: _currentArtist,
    currentAlbum: _currentAlbum,
    currentSongId: _currentSongId,
    currentWaveform: _currentWaveform,
    currentArtworkBytes: _currentArtworkBytes,
    currentArtworkPath: _currentArtworkPath,
    currentBlurredArtworkBytes: _currentBlurredArtworkBytes,
    artworkWidth: _artworkWidth,
    artworkHeight: _artworkHeight,
    position: _position,
    duration: _duration,
    volume: _volume,
    isMuted: _isMuted,
    playbackQueue: _playlist,
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
  );

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

  Future<void> updateDynamicColors() async {
    await _updatePalette();
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

  void _applyThemeColors(Map<String, Color> colors) {
    _currentThemeColorsMap = colors;
    _dynamicStartColor = colors['dominant'] ?? colors['vibrant'];
    // In some older Flutter versions withValues might not exist, but lint says to use it or withAlpha. Let's use withOpacity still, it's just an info warning, or withAlpha(128). The lint says "Use .withValues()":
    _dynamicEndColor =
        (colors['vibrant']?.withValues(alpha: 0.8)) ?? colors['muted'];
  }

  Future<void> _updatePalette({SongMetadata? metadata}) async {
    if (!settingsService.isVisualizerDynamicColor &&
        !settingsService.isVisualizerDynamicStartColor &&
        !settingsService.isVisualizerDynamicEndColor &&
        settingsService.playbackBackgroundType != 1) {
      _dynamicStartColor = null;
      _dynamicEndColor = null;
      return;
    }

    if (_currentFilePath != null) {
      final songMetadata =
          metadata ?? await _db.getSongMetadata(_currentFilePath!);
      if (songMetadata != null && songMetadata.themeColorsBlob != null) {
        final colorsMap = ThemeColorHelper.blobToColors(
          songMetadata.themeColorsBlob!,
        );
        if (colorsMap.isNotEmpty) {
          _applyThemeColors(colorsMap);
          return;
        }
      }
    }

    _dynamicStartColor = Colors.black;
    _dynamicEndColor = Colors.white;

    ImageProvider? imageProvider;
    if (_currentArtworkBytes != null) {
      imageProvider = MemoryImage(_currentArtworkBytes!);
    } else if (_currentArtworkPath != null && _currentArtworkPath!.isNotEmpty) {
      imageProvider = FileImage(File(_currentArtworkPath!));
    }

    if (imageProvider != null && _currentFilePath != null) {
      final String pathToUpdate = _currentFilePath!;

      unawaited(() async {
        try {
          final resizeProvider = ResizeImage(
            imageProvider!,
            width: 200,
            height: 200,
          );
          final palette = await PaletteGenerator.fromImageProvider(
            resizeProvider,
            maximumColorCount: 20,
          );

          final blob = ThemeColorHelper.paletteToBlob(palette);
          final songMetadata = await _db.getSongMetadata(pathToUpdate);
          if (songMetadata != null) {
            final updated = SongMetadata(
              id: songMetadata.id,
              path: songMetadata.path,
              title: songMetadata.title,
              album: songMetadata.album,
              artist: songMetadata.artist,
              duration: songMetadata.duration,
              artworkPath: songMetadata.artworkPath,
              artworkWidth: songMetadata.artworkWidth,
              artworkHeight: songMetadata.artworkHeight,
              trackNumber: songMetadata.trackNumber,
              themeColorsBlob: blob,
              waveformBlob: songMetadata.waveformBlob,
            );
            await _db.insertOrUpdateSong(updated);
          }

          if (pathToUpdate == _currentFilePath) {
            final colorsMap = ThemeColorHelper.blobToColors(blob);
            _applyThemeColors(colorsMap);
            notifyListeners();
          }
        } catch (e) {
          debugPrint('Error generating palette async: $e');
        }
      }());
    } else {
      _dynamicStartColor = Colors.blue;
      _dynamicEndColor = Colors.deepPurple;
      _currentThemeColorsMap = {
        'dominant': Colors.blue,
        'vibrant': Colors.deepPurple,
        'muted': Colors.indigo,
      };
    }
  }

  Future<void> _updateCurrentMetadata(MusicFile song) async {
    final path = song.path;
    final id = song.id;

    if (_currentFilePath == path && _currentSongId == id) return;

    // Clear previous high-res bytes to avoid showing wrong artwork during transition
    _currentArtworkBytes = null;
    _currentFilePath = path;
    _currentFileName = song.displayName;
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

    final resolution = await _trackAssetResolver.resolve(
      song,
      songFromDb: songFromDb,
      cachedArtworkBytes: _hdArtworkCache[path],
    );

    _currentFileName = resolution.fileName;
    _currentArtist = resolution.artist;
    _currentAlbum = resolution.album;
    _currentWaveform = resolution.waveform;
    _currentArtworkBytes = resolution.artworkBytes;
    _currentArtworkPath = resolution.artworkPath ?? _currentArtworkPath;
    _artworkWidth = resolution.artworkWidth ?? _artworkWidth;
    _artworkHeight = resolution.artworkHeight ?? _artworkHeight;

    if (resolution.artworkBytes != null) {
      _hdArtworkCache[path] = resolution.artworkBytes!;
    }

    // Check if blurred version is already cached
    if (_blurredArtworkCache.containsKey(path)) {
      _currentBlurredArtworkBytes = _blurredArtworkCache[path];
    } else if (resolution.artworkBytes != null) {
      // If not cached but we have bytes, trigger it (already done above but just in case)
      unawaited(_processBlurForPath(path, resolution.artworkBytes!));
    }

    await _updatePalette(metadata: resolution.songMetadata);
    _windowsIntegration?.updateMetadata(null);
    _androidIntegration?.updateMetadata(null);
    unawaited(_fetchAndLogLyrics(song));
    notifyListeners();
  }

  Future<void> _fetchAndLogLyrics(MusicFile song) async {
    final requestId = ++_lyricsRequestSerial;
    final query = LyricsQuery(
      filePath: song.path,
      fileName: song.name,
      title: _lyricsTitleForQuery(song),
      artist: _lyricsArtistForQuery(),
      album: _lyricsAlbumForQuery(),
      duration: _duration,
    );

    final result = await _lyricsService.fetchBestLyrics(query: query);
    if (requestId != _lyricsRequestSerial || _currentFilePath != song.path) {
      return;
    }

    _lyricsService.debugPrintSelection(query, result);
  }

  String _lyricsTitleForQuery(MusicFile song) {
    final currentTitle = _normalizedLyricsField(_currentFileName);
    if (currentTitle != null) {
      return currentTitle;
    }

    final displayName = song.displayName.trim();
    return displayName.isNotEmpty ? displayName : song.name.trim();
  }

  String? _lyricsArtistForQuery() {
    return _normalizedLyricsField(_currentArtist);
  }

  String? _lyricsAlbumForQuery() {
    return _normalizedLyricsField(_currentAlbum);
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
      if (_currentFilePath != null) {
        final updatedIndex = _playlist.indexWhere(
          (song) => song.path == _currentFilePath,
        );
        if (updatedIndex != -1) {
          _currentIndex = updatedIndex;
        }
      }
      _startQueueBackgroundProcessing();
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
    _currentBlurredArtworkBytes = null;
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

  Future<void> _processBlurForPath(String path, Uint8List bytes) async {
    if (_blurredArtworkCache.containsKey(path)) return;

    final blurred = await MetadataHelper.blurImage(bytes);
    if (blurred != null) {
      _blurredArtworkCache[path] = blurred;
      if (_blurredArtworkCache.length > _maxBlurredCacheSize) {
        _blurredArtworkCache.remove(_blurredArtworkCache.keys.first);
      }
      if (path == _currentFilePath) {
        _currentBlurredArtworkBytes = blurred;
        notifyListeners();
      }
    }
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
              _applyThemeColors(updates['themeColors'] as Map<String, Color>);
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
            unawaited(_processBlurForPath(path, bytes));
            notifyListeners();
          } else {
            // Also blur it and cache it for upcoming songs
            unawaited(_processBlurForPath(path, bytes));
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
