import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:image/image.dart' as img;
import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import '../models/music_file.dart';
import 'metadata_database.dart';
import 'settings_service.dart';
import 'theme_color_helper.dart';
import 'visualizer_options_service.dart';
import 'playback_queue_processor.dart';
import 'waveform_service.dart';
import 'windows_integration_service.dart';

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
  final SettingsService settingsService;
  late final VisualizerOptionsService _visualizerOptions;
  late final PlaybackQueueProcessor _queueProcessor;
  late final WaveformService _waveformService;

  // 独立的 FFT 输出流（用于迷你播放器）
  VisualizerOutputStream? _miniPlayerFftStream;

  Color? _dynamicStartColor;
  Color? _dynamicEndColor;
  Map<String, Color> _currentThemeColorsMap = const {};
  late final WindowsIntegrationService? _windowsIntegration;

  Color? get dynamicStartColor => _dynamicStartColor;
  Color? get dynamicEndColor => _dynamicEndColor;
  Map<String, Color> get currentThemeColorsMap => _currentThemeColorsMap;

  AudioService(this.settingsService) {
    _player = AudioVisualizerPlayerController();
    _visualizerOptions = VisualizerOptionsService(
      controller: _player,
      settingsService: settingsService,
    );
    _queueProcessor = PlaybackQueueProcessor(
      db: _db,
      player: _player,
      settingsService: settingsService,
    );
    _waveformService = WaveformService(
      db: _db,
      player: _player,
    );
    _windowsIntegration = Platform.isWindows ? WindowsIntegrationService(this) : null;
    _player.addListener(_handlePlayerChanges);
    unawaited(_player.initialize().then((_) {
      _visualizerOptions.loadOptions().then((_) => notifyListeners());
      _initializeMiniPlayerFftStream();
    }));
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
  Stream<FftFrame>? get miniPlayerFftStream =>
      _miniPlayerFftStream?.fftStream;

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
          _updateCurrentMetadata(
            song.path,
            song.displayName,
            id: song.id,
          ).then((_) {
            _refreshCurrentWaveform();
            _windowsIntegration?.updateMetadata(_playlist[newIndex]);
          }),
        );
      }
      _windowsIntegration?.updatePlaybackStatus(_isPlaying);
      notifyListeners();
    } else {
      _windowsIntegration?.updateTimeline(_position, _duration);
      _windowsIntegration?.updatePlaybackStatus(_isPlaying);
      notifyListeners();
    }
  }

  bool? get isLastActionNext => _lastActionNext;

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
  List<MusicFile> get playlist => List.unmodifiable(_playlist);
  int get currentIndex => _currentIndex;
  bool get isRandomMode => _player.playlist.randomPolicy != null;

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

    final waveform = await getWaveform(expectedChunks: settingsService.waveformChunks, sampleStride: settingsService.sampleStride);
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

  Future<void> _updatePalette() async {
    if (!settingsService.isVisualizerDynamicColor &&
        !settingsService.isVisualizerDynamicStartColor &&
        !settingsService.isVisualizerDynamicEndColor &&
        settingsService.playbackBackgroundType != 1) {
      _dynamicStartColor = null;
      _dynamicEndColor = null;
      return;
    }

    if (_currentFilePath != null) {
      final songMetadata = await _db.getSongMetadata(_currentFilePath!);
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

  Future<void> _updateCurrentMetadata(
    String path,
    String name, {
    int? id,
  }) async {
    if (_currentFilePath == path && _currentSongId == id) return;

    // Clear previous high-res bytes to avoid showing wrong artwork during transition
    _currentArtworkBytes = null;
    _currentFilePath = path;
    _currentFileName = name;
    _currentArtist = null;
    _currentAlbum = null;
    _currentSongId = id;

    // 1. Try to get metadata from database immediately (fast)
    final songFromDb = await _db.getSongMetadata(path);
    if (songFromDb != null) {
      _currentWaveform = _waveformService.waveformFromBlob(songFromDb.waveformBlob);
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
    Uint8List? newArtworkBytes;
    String? newArtworkPath = _currentArtworkPath;
    int? newArtworkWidth = _artworkWidth;
    int? newArtworkHeight = _artworkHeight;

    if (Platform.isWindows) {
      try {
        // Playback page should prefer embedded original artwork, not cached thumbnails.
        final metadata = await MetadataGod.readMetadata(file: path);
        if (metadata.title != null && metadata.title!.trim().isNotEmpty) {
          _currentFileName = metadata.title;
        }
        _currentArtist = metadata.artist;
        _currentAlbum = metadata.album;
        final bytes = metadata.picture?.data;
        if (bytes != null) {
          newArtworkBytes = bytes;
          final image = img.decodeImage(bytes);
          if (image != null) {
            newArtworkWidth = image.width;
            newArtworkHeight = image.height;
          }
        }
      } catch (e) {
        debugPrint('Error reading metadata on Windows: $e');
      }
    } else if (Platform.isAndroid && id != null) {
      try {
        newArtworkBytes = await _audioQuery.queryArtwork(
          id,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: 1000, // Query a larger size for high quality
          quality: 100,
        );
      } catch (e) {
        debugPrint('Error querying artwork on Android: $e');
      }
    }

    _currentArtworkBytes = newArtworkBytes;
    _currentArtworkPath = newArtworkPath;
    _artworkWidth = newArtworkWidth;
    _artworkHeight = newArtworkHeight;

    await _updatePalette();
    _windowsIntegration?.updateMetadata(null);
    notifyListeners();
  }

  Future<void> playFile(String path, String name, {int? id, bool append = false}) async {
    final song = MusicFile(path: path, name: name, id: id);
    if (!append) {
      _playlist.clear();
      await _player.playlist.clear();
    }

    final int index = _playlist.length;
    _playlist.add(song);
    await _player.playlist.addTracks([AudioTrack(id: index.toString(), uri: path)]);

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
        await _player.playlist.setActivePlaylist(_player.playlist.activePlaylistId!, startIndex: safeIndex, autoPlay: true);
      }

      final current = songs[safeIndex];
      await _updateCurrentMetadata(current.path, current.displayName, id: current.id);

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
      await _updateCurrentMetadata(current.path, current.displayName, id: current.id);
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
          await _updateCurrentMetadata(song.path, song.displayName, id: song.id);
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
        await _player.playlist.setActivePlaylist(_player.playlist.activePlaylistId!, startIndex: index, autoPlay: true);
      }
      _currentIndex = index;
      final song = _playlist[_currentIndex];
      await _updateCurrentMetadata(song.path, song.displayName, id: song.id);
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
          await _updateCurrentMetadata(song.path, song.displayName, id: song.id);
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

    _player.playlist.setRandomPolicy(RandomPolicy(
      scope: RandomScope.all(),
      strategy: strategy,
      label: method == 0 ? 'completeRandom' : 'shuffleRandom',
    ));
  }

  void _expandPlaylistToGlobal(List<MusicFile> globalSongs) {
    // Merge current playlist with global songs, deduplicate by path
    final existingPaths = _playlist.map((s) => s.path).toSet();
    final newSongs = globalSongs.where((s) => !existingPaths.contains(s.path)).toList();
    
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

  void _startQueueBackgroundProcessing() {
    if (_queueProcessor.isProcessing || _playlist.isEmpty) return;

    unawaited(_queueProcessor.processQueue(
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
    ));
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
