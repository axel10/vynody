import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:image/image.dart' as img;
import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import '../models/music_file.dart';
import 'metadata_database.dart';

class AudioService extends ChangeNotifier {
  late final AudioVisualizerPlayerController _player;
  bool _isPlaying = false;
  String? _currentFilePath;
  String? _currentFileName;
  int? _currentSongId;
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

  AudioService() {
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

  void _handlePlayerChanges() {
    _isPlaying = _player.isPlaying;
    _position = _player.position;
    _duration = _player.duration;
    _volume = _player.volume * 100.0;

    final int newIndex = _player.currentIndex ?? -1;
    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;
      if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
        final song = _playlist[_currentIndex];
        _updateCurrentMetadata(song.path, song.name, id: song.id);
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

  Future<void> _updateCurrentMetadata(
    String path,
    String name, {
    int? id,
  }) async {
    _currentFilePath = path;
    _currentFileName = name;
    _currentSongId = id;
    _currentArtworkBytes = null;
    _currentArtworkPath = null;
    _artworkWidth = null;
    _artworkHeight = null;

    if (Platform.isWindows) {
      try {
        final songFromDb = await _db.getSongMetadata(path);
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

    // await _player.setPlaylist(tracks, startIndex: safeIndex, autoPlay: true);
    _player.loadFromPath(tracks[safeIndex].uri);

    final current = songs[safeIndex];
    await _updateCurrentMetadata(current.path, current.name, id: current.id);

    await _player.setVolume(_volume / 100.0);
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
    _currentArtworkBytes = null;
    _currentArtworkPath = null;
    await _player.clearPlaylist();
    _duration = Duration.zero;
    _position = Duration.zero;
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> next() async {
    await _player.playNext();
  }

  Future<void> previous() async {
    await _player.playPrevious();
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
