import 'dart:async';
import 'dart:io';
import 'dart:convert';

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
import 'settings_service.dart';
import 'theme_color_helper.dart';

class AudioService extends ChangeNotifier {
  late final AudioVisualizerPlayerController _player;
  bool _isPlaying = false;
  String? _currentFilePath;
  String? _currentFileName;
  int? _currentSongId;
  List<double> _currentWaveform = const [];
  Uint8List? _currentArtworkBytes;
  String? _currentArtworkPath;
  int? _artworkWidth;
  int? _artworkHeight;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100.0;
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final MetadataDatabase _db = MetadataDatabase();

  final List<MusicFile> _playlist = [];
  int _currentIndex = -1;
  bool _isTransitioning = false;

  final SettingsService settingsService;
  Color? _dynamicStartColor;
  Color? _dynamicEndColor;

  Color? get dynamicStartColor => _dynamicStartColor;
  Color? get dynamicEndColor => _dynamicEndColor;

  AudioService(this.settingsService) {
    _player = AudioVisualizerPlayerController();
    _player.addListener(_handlePlayerChanges);
    unawaited(_player.initialize().then((_) => _loadVisualizerOptions()));
  }

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
    _volume = _player.volume * 100.0;

    final int newIndex = _player.currentIndex ?? -1;
    if (newIndex != _currentIndex && !_isTransitioning) {
      _currentIndex = newIndex;
      if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
        final song = _playlist[_currentIndex];
        unawaited(
          _updateCurrentMetadata(
            song.path,
            song.name,
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
  int? get currentSongId => _currentSongId;
  List<double> get currentWaveform => List.unmodifiable(_currentWaveform);
  Uint8List? get currentArtworkBytes => _currentArtworkBytes;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
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

    final waveform = await getWaveform(expectedChunks: 80, sampleStride: 3);
    if (path == _currentFilePath && waveform.isNotEmpty) {
      _currentWaveform = waveform;
      if (notify) {
        notifyListeners();
      }
    }
  }

  void _applyThemeColors(Map<String, Color> colors) {
    _dynamicStartColor = colors['dominant'] ?? colors['vibrant'];
    // In some older Flutter versions withValues might not exist, but lint says to use it or withAlpha. Let's use withOpacity still, it's just an info warning, or withAlpha(128). The lint says "Use .withValues()":
    _dynamicEndColor =
        (colors['vibrant']?.withValues(alpha: 0.5)) ?? colors['muted'];
  }

  Future<void> _updatePalette() async {
    if (!settingsService.isVisualizerDynamicColor &&
        !settingsService.isVisualizerDynamicStartColor &&
        !settingsService.isVisualizerDynamicEndColor) {
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
      _dynamicStartColor = Colors.black;
      _dynamicEndColor = Colors.white;
    }
  }

  Future<void> _updateCurrentMetadata(
    String path,
    String name, {
    int? id,
  }) async {
    if (_currentFilePath == path && _currentSongId == id) return;

    _currentFilePath = path;
    _currentFileName = name;
    _currentSongId = id;
    final songFromDb = await _db.getSongMetadata(path);
    _currentWaveform = _waveformFromBlob(songFromDb?.waveformBlob);
    _currentArtworkBytes = null;
    _currentArtworkPath = null;
    _artworkWidth = null;
    _artworkHeight = null;

    if (Platform.isWindows) {
      try {
        _currentArtworkPath = songFromDb?.artworkPath;
        _artworkWidth = songFromDb?.artworkWidth;
        _artworkHeight = songFromDb?.artworkHeight;

        // Playback page should prefer embedded original artwork, not cached thumbnails.
        final metadata = await MetadataGod.readMetadata(file: path);
        final bytes = metadata.picture?.data;
        if (bytes != null) {
          _currentArtworkBytes = bytes;
          final image = img.decodeImage(bytes);
          if (image != null) {
            _artworkWidth = image.width;
            _artworkHeight = image.height;
          }
        }
      } catch (e) {
        debugPrint('Error reading metadata on Windows: $e');
      }
    } else if (Platform.isAndroid && id != null) {
      try {
        _currentArtworkBytes = await _audioQuery.queryArtwork(
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

    await _updatePalette();
    notifyListeners();
  }

  Future<void> playFile(String path, String name, {int? id}) async {
    final song = MusicFile(path: path, name: name, id: id);
    _playlist.clear();
    _playlist.add(song);
    _currentIndex = 0;

    await _updateCurrentMetadata(path, name, id: id);
    await _player.setVolume(_volume / 100.0);
    await _player.loadFromPath(path);
    await _refreshCurrentWaveform(notify: false);
    await _player.play();
    notifyListeners();
  }

  Future<void> playPlaylist(
    List<MusicFile> songs, {
    int initialIndex = 0,
  }) async {
    if (songs.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, songs.length - 1);

    _playlist.clear();
    _playlist.addAll(songs);
    _currentIndex = safeIndex;

    final tracks = songs.asMap().entries.map((e) {
      return AudioTrack(id: e.key.toString(), uri: e.value.path);
    }).toList();

    // Clear existing playlist and add all tracks
    await _player.clearPlaylist();
    await _player.addTracks(tracks);

    // Play the selected track
    await _player.playAt(safeIndex);

    final current = songs[safeIndex];
    await _updateCurrentMetadata(current.path, current.name, id: current.id);

    await _player.setVolume(_volume / 100.0);
    await _refreshCurrentWaveform(notify: false);
    notifyListeners();
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
      await _updateCurrentMetadata(current.path, current.name, id: current.id);
      await _player.setVolume(_volume / 100.0);
      await _refreshCurrentWaveform(notify: false);
    }
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
          await _updateCurrentMetadata(song.path, song.name, id: song.id);
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
      await _updateCurrentMetadata(song.path, song.name, id: song.id);
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
          await _updateCurrentMetadata(song.path, song.name, id: song.id);
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
    await _player.setVolume(_volume / 100.0);
    notifyListeners();
  }

  void updateVisualOptions(VisualizerOptimizationOptions options) {
    _player.updateVisualOptions(options);
    notifyListeners();
  }

  @override
  void dispose() {
    _player.removeListener(_handlePlayerChanges);
    _player.dispose();
    super.dispose();
  }
}
