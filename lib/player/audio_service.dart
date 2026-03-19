import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:image/image.dart' as img;
import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import '../models/music_file.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';
import 'settings_service.dart';
import 'theme_color_helper.dart';

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
  bool _isTransitioning = false;
  bool _isProcessingQueue = false;

  // 独立的 FFT 输出流（用于迷你播放器）
  VisualizerOutputStream? _miniPlayerFftStream;

  final SettingsService settingsService;
  Color? _dynamicStartColor;
  Color? _dynamicEndColor;
  Map<String, Color> _currentThemeColorsMap = const {};

  Color? get dynamicStartColor => _dynamicStartColor;
  Color? get dynamicEndColor => _dynamicEndColor;
  Map<String, Color> get currentThemeColorsMap => _currentThemeColorsMap;

  AudioService(this.settingsService) {
    _player = AudioVisualizerPlayerController();
    _player.addListener(_handlePlayerChanges);
    unawaited(_player.initialize().then((_) {
      _loadVisualizerOptions();
      _initializeMiniPlayerFftStream();
    }));
  }

  void _initializeMiniPlayerFftStream() {
    // 创建独立的 FFT 输出流，专用于迷你播放器
    _miniPlayerFftStream = _player.createVisualizerOutput(
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

  static const String _visualizerOptionsKey = 'visualizer_optimization_options';

  Future<void> _loadVisualizerOptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_visualizerOptionsKey);
      if (jsonStr != null) {
        final Map<String, dynamic> map = jsonDecode(jsonStr);
        final options = VisualizerOptimizationOptions(
          frequencyGroups: map['frequencyGroups'] ?? 64,
          smoothingCoefficient: map['smoothingCoefficient']?.toDouble() ?? 0.8,
          gravityCoefficient: map['gravityCoefficient']?.toDouble() ?? 1.5,
          overallMultiplier: map['overallMultiplier']?.toDouble() ?? 1.0,
          logarithmicScale: map['logarithmicScale']?.toDouble() ?? 2.0,
          groupContrastExponent:
              map['groupContrastExponent']?.toDouble() ?? 1.2,
          skipHighFrequencyGroups: map['skipHighFrequencyGroups'] ?? 0,
        );
        _player.updateVisualOptions(options);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading visualizer options: $e');
    }
  }

  Future<void> saveVisualizerOptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final options = _player.visualOptions;
      final map = {
        'frequencyGroups': options.frequencyGroups,
        'smoothingCoefficient': options.smoothingCoefficient,
        'gravityCoefficient': options.gravityCoefficient,
        'overallMultiplier': options.overallMultiplier,
        'logarithmicScale': options.logarithmicScale,
        'groupContrastExponent': options.groupContrastExponent,
        'skipHighFrequencyGroups': options.skipHighFrequencyGroups,
      };
      await prefs.setString(_visualizerOptionsKey, jsonEncode(map));
    } catch (e) {
      debugPrint('Error saving visualizer options: $e');
    }
  }

  Future<List<double>> getWaveform({
    int expectedChunks = 80,
    int sampleStride = 3,
  }) async {
    final path = _currentFilePath;
    if (path == null) return [];

    final songMetadata = await _db.getSongMetadata(path);
    if (songMetadata != null && songMetadata.waveformBlob != null) {
      final list = Float32List.view(songMetadata.waveformBlob!.buffer);
      return list.map((e) => e.toDouble()).toList();
    }

    // No cache, calculate and store
    final waveform = await _player.getWaveform(
      expectedChunks: expectedChunks,
      sampleStride: sampleStride,
    );

    if (waveform.isNotEmpty && songMetadata != null) {
      final float32List = Float32List.fromList(
        waveform.map((e) => e.toDouble()).toList(),
      );
      final blob = float32List.buffer.asUint8List();

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
        themeColorsBlob: songMetadata.themeColorsBlob,
        waveformBlob: blob,
      );
      await _db.insertOrUpdateSong(updated);
    }

    return waveform;
  }

  void _handlePlayerChanges() {
    _isPlaying = _player.isPlaying;
    _position = _player.position;
    _duration = _player.duration;
    _volume = (_player.volume * 100.0).roundToDouble();

    final int newIndex = _player.currentIndex ?? -1;
    if (newIndex != _currentIndex && !_isTransitioning) {
      _currentIndex = newIndex;
      if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
        final song = _playlist[_currentIndex];
        unawaited(
          _updateCurrentMetadata(
            song.path,
            song.displayName,
            id: song.id,
          ).then((_) => _refreshCurrentWaveform()),
        );
      }
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

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

  double get progress => _duration.inMilliseconds > 0
      ? _position.inMilliseconds / _duration.inMilliseconds
      : 0.0;

  Future<void> updateDynamicColors() async {
    await _updatePalette();
    notifyListeners();
  }

  List<double> _waveformFromBlob(Uint8List? blob) {
    if (blob == null || blob.isEmpty) return const [];
    final list = Float32List.view(blob.buffer, blob.offsetInBytes);
    return list.map((e) => e.toDouble()).toList();
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
      _currentWaveform = _waveformFromBlob(songFromDb.waveformBlob);
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
    notifyListeners();
  }

  Future<void> playFile(String path, String name, {int? id, bool append = false}) async {
    final song = MusicFile(path: path, name: name, id: id);
    if (!append) {
      _playlist.clear();
      await _player.clearPlaylist();
    }

    final int index = _playlist.length;
    _playlist.add(song);
    await _player.addTracks([AudioTrack(id: index.toString(), uri: path)]);

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
      await _player.clearPlaylist();
      await _player.addTracks(tracks);

      // Play the selected track
      await _player.playAt(safeIndex);

      final current = songs[safeIndex];
      await _updateCurrentMetadata(current.path, current.displayName, id: current.id);

      await _player.setVolume(_volume / 100.0);
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

    final startIndex = _player.playlist.length;
    final tracks = songs.asMap().entries.map((e) {
      return AudioTrack(id: (startIndex + e.key).toString(), uri: e.value.path);
    }).toList();
    await _player.addTracks(tracks);

    if (wasEmpty) {
      _currentIndex = 0;
      final current = songs[0];
      await _updateCurrentMetadata(current.path, current.displayName, id: current.id);
      await _player.setVolume(_volume / 100.0);
      await _refreshCurrentWaveform(notify: false);
    }
    _startQueueBackgroundProcessing();
    notifyListeners();
  }

  Future<void> removeFromPlaylist(int index) async {
    if (index >= 0 && index < _playlist.length) {
      _playlist.removeAt(index);
      await _player.removeTrackAt(index);
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
    await _player.clearPlaylist();
    _duration = Duration.zero;
    _position = Duration.zero;
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> next() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    try {
      final success = await _player.playNext();
      if (success) {
        final newIndex = _player.currentIndex ?? -1;
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
    try {
      await _player.playAt(index);
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
    try {
      final success = await _player.playPrevious();
      if (success) {
        final newIndex = _player.currentIndex ?? -1;
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
    await _player.togglePlayPause();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 100.0);
    if (_volume > 0) {
      _isMuted = false;
    }
    await _player.setVolume(_volume / 100.0);
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
    _player.updateVisualOptions(options);
    notifyListeners();
  }

  void _startQueueBackgroundProcessing() {
    if (_isProcessingQueue) return;
    unawaited(_processQueueBackground());
  }

  Future<void> _processQueueBackground() async {
    if (_isProcessingQueue || _playlist.isEmpty) return;
    _isProcessingQueue = true;

    try {
      debugPrint('Starting background queue processing');
      // Create a snapshot to avoid concurrent modification issues
      final List<MusicFile> processingList = List.from(_playlist);

      for (final song in processingList) {
        // Re-check if song is still in the playlist
        if (!_playlist.any((s) => s.path == song.path)) continue;

        try {
          final existing = await _db.getSongMetadata(song.path);

          bool needsWaveform = existing == null || existing.waveformBlob == null;
          bool needsThemeColor =
              existing == null || existing.themeColorsBlob == null;

          if (needsWaveform || needsThemeColor) {
            debugPrint('Background processing: ${song.path}');

            // 1. Process basic metadata
            final SongMetadata? initialMetadata =
                await MetadataHelper.processMetadata(song.path);

            if (initialMetadata != null) {
              SongMetadata m = initialMetadata;

              // If theme colors are missing but artwork exists, extract them
              if (m.themeColorsBlob == null && m.artworkPath != null) {
                try {
                  final imageProvider = FileImage(File(m.artworkPath!));
                  final palette = await PaletteGenerator.fromImageProvider(
                    imageProvider,
                    maximumColorCount: 20,
                  );
                  final themeColorsBlob =
                      ThemeColorHelper.paletteToBlob(palette);

                  m = SongMetadata(
                    id: m.id,
                    path: m.path,
                    title: m.title,
                    album: m.album,
                    artist: m.artist,
                    duration: m.duration,
                    artworkPath: m.artworkPath,
                    artworkWidth: m.artworkWidth,
                    artworkHeight: m.artworkHeight,
                    trackNumber: m.trackNumber,
                    themeColorsBlob: themeColorsBlob,
                    waveformBlob: m.waveformBlob,
                  );
                  await _db.insertOrUpdateSong(m);

                  // Update current colors if this is the playing song
                  if (song.path == _currentFilePath) {
                    _applyThemeColors(
                      ThemeColorHelper.blobToColors(themeColorsBlob),
                    );
                    notifyListeners();
                  }
                } catch (e) {
                  debugPrint('Theme color extraction error for ${song.path}: $e');
                }
              }

              // 2. Process waveform if still missing
              if (m.waveformBlob == null) {
                try {
                  final waveform = await _player.getWaveform(
                    expectedChunks: settingsService.waveformChunks,
                    sampleStride: settingsService.sampleStride,
                    filePath: song.path,
                  );

                  if (waveform.isNotEmpty) {
                    final float32List = Float32List.fromList(
                      waveform.map((e) => e.toDouble()).toList(),
                    );
                    final blob = float32List.buffer.asUint8List();

                    final updated = SongMetadata(
                      id: m.id,
                      path: m.path,
                      title: m.title,
                      album: m.album,
                      artist: m.artist,
                      duration: m.duration,
                      artworkPath: m.artworkPath,
                      artworkWidth: m.artworkWidth,
                      artworkHeight: m.artworkHeight,
                      trackNumber: m.trackNumber,
                      themeColorsBlob: m.themeColorsBlob,
                      waveformBlob: blob,
                    );
                    await _db.insertOrUpdateSong(updated);

                    // Also update 'm' in case we add more steps later
                    m = updated;

                    // Update current waveform if this is the playing song
                    if (song.path == _currentFilePath) {
                      _currentWaveform = waveform;
                      notifyListeners();
                    }
                  }
                } catch (e) {
                  debugPrint('Waveform extraction error for ${song.path}: $e');
                }
              }
            }

            // Small delay between songs to avoid heavy load
            await Future.delayed(const Duration(milliseconds: 300));
          }
        } catch (e) {
          debugPrint('Error processing background song ${song.path}: $e');
        }
      }
    } finally {
      _isProcessingQueue = false;
      debugPrint('Background queue processing finished');
    }
  }

  @override
  void dispose() {
    _player.removeListener(_handlePlayerChanges);
    _player.removeVisualizerOutput('mini_player');
    _player.dispose();
    super.dispose();
  }
}
