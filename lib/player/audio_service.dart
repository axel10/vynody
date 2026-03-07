import 'dart:io';
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:image/image.dart' as img;
import 'metadata_database.dart';
import 'scanner_service.dart';

class AudioService extends ChangeNotifier {
  late final Player _player;
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
  bool _showSpectrum = false;
  late final Stream<List<double>> _fftStream;
  late final bool _nativeSpectrumSupported;
  final StreamController<List<double>> _emulatedFftController =
      StreamController<List<double>>.broadcast();
  Timer? _emulatedFftTimer;
  static const int _emulatedBarCount = 56;
  List<double> _lastEmulatedFft = List<double>.filled(_emulatedBarCount, 0.0);

  AudioService() {
    _player = Player();
    try {
      final rawStream = (_player.stream as dynamic).fft as Stream<dynamic>;
      _fftStream = rawStream.map((event) {
        if (event is List) {
          return event
              .map((value) => (value as num).toDouble())
              .toList(growable: false);
        }
        return const <double>[];
      });
      _nativeSpectrumSupported = true;
    } catch (_) {
      _fftStream = const Stream.empty();
      _nativeSpectrumSupported = false;
    }
    _player.stream.playing.listen((playing) {
      _isPlaying = playing;
      if (!_nativeSpectrumSupported) {
        if (playing) {
          _startEmulatedSpectrum();
        } else {
          _stopEmulatedSpectrum(reset: false);
        }
      }
      notifyListeners();
    });
    _player.stream.position.listen((position) {
      _position = position;
      notifyListeners();
    });
    _player.stream.duration.listen((duration) {
      _duration = duration;
      notifyListeners();
    });
    _player.stream.volume.listen((volume) {
      _volume = volume;
      notifyListeners();
    });
    _player.stream.playlist.listen((playlist) {
      if (playlist.index != _currentIndex) {
        _currentIndex = playlist.index;
        if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
          final song = _playlist[_currentIndex];
          _updateCurrentMetadata(song.path, song.name, id: song.id);
        }
        notifyListeners();
      }
    });
  }

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
  bool get showSpectrum => _showSpectrum;
  bool get spectrumSupported => true;
  bool get nativeSpectrumSupported => _nativeSpectrumSupported;

  Stream<List<double>> get fftStream => _nativeSpectrumSupported
      ? _fftStream
      : _emulatedFftController.stream;

  void toggleSpectrum() {
    _showSpectrum = !_showSpectrum;
    if (!_nativeSpectrumSupported) {
      if (_showSpectrum && _isPlaying) {
        _startEmulatedSpectrum();
      }
      if (!_showSpectrum) {
        _stopEmulatedSpectrum();
      }
    }
    notifyListeners();
  }

  void _startEmulatedSpectrum() {
    if (_emulatedFftTimer != null) return;
    _emulatedFftTimer = Timer.periodic(const Duration(milliseconds: 45), (_) {
      if (!_showSpectrum) return;

      if (!_isPlaying || _currentFilePath == null) {
        _lastEmulatedFft = _lastEmulatedFft
            .map((v) => (v * 0.86).clamp(0.0, 1.0))
            .toList(growable: false);
        _emulatedFftController.add(_lastEmulatedFft);
        return;
      }

      final t = _position.inMilliseconds / 1000.0;
      final v = (_volume / 100.0).clamp(0.08, 1.0);
      final bars = List<double>.generate(_emulatedBarCount, (i) {
        final p = i / _emulatedBarCount;
        final lane = 1.0 - p * 0.6;
        final a = math.sin(t * 4.2 + i * 0.19);
        final b = math.sin(t * 7.8 + i * 0.43 + 1.2);
        final c = math.sin(t * 2.1 + i * 0.11 + 2.4);
        final mixed = ((a * 0.5 + b * 0.35 + c * 0.15) + 1.0) * 0.5;
        final shaped = math.pow(mixed, 1.7).toDouble();
        return (0.03 + shaped * v * lane).clamp(0.0, 1.0);
      }, growable: false);

      _lastEmulatedFft = bars;
      _emulatedFftController.add(bars);
    });
  }

  void _stopEmulatedSpectrum({bool reset = true}) {
    _emulatedFftTimer?.cancel();
    _emulatedFftTimer = null;
    if (reset) {
      _lastEmulatedFft = List<double>.filled(_emulatedBarCount, 0.0);
      _emulatedFftController.add(_lastEmulatedFft);
    }
  }

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

        // Always try to load original artwork for the playback page to ensure "original" quality
        final bool noThumb = _currentArtworkPath == null;
        final bool unknownDimensions = _artworkWidth == null;

        if (noThumb || unknownDimensions || true) {
          // Force fetch original for best quality
          final metadata = await MetadataGod.readMetadata(file: path);
          final bytes = metadata.picture?.data;
          if (bytes != null) {
            if (unknownDimensions) {
              final image = img.decodeImage(bytes);
              if (image != null) {
                _artworkWidth = image.width;
                _artworkHeight = image.height;
              }
            }
            _currentArtworkBytes = bytes;
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
    await _player.open(Media(path));
    await _player.setVolume(_volume);
    await _player.play();
    notifyListeners();
  }

  Future<void> playPlaylist(
    List<MusicFile> songs, {
    int initialIndex = 0,
  }) async {
    if (songs.isEmpty) return;

    _playlist.clear();
    _playlist.addAll(songs);
    _currentIndex = initialIndex;

    final mediaList = songs.map((s) => Media(s.path)).toList();
    await _player.open(Playlist(mediaList, index: initialIndex));

    final current = songs[initialIndex];
    await _updateCurrentMetadata(current.path, current.name, id: current.id);

    await _player.setVolume(_volume);
    await _player.play();
    notifyListeners();
  }

  Future<void> addToPlaylist(List<MusicFile> songs) async {
    if (songs.isEmpty) return;

    final bool wasEmpty = _playlist.isEmpty;
    _playlist.addAll(songs);

    for (var song in songs) {
      await _player.add(Media(song.path));
    }

    if (wasEmpty) {
      _currentIndex = 0;
      final current = songs[0];
      await _updateCurrentMetadata(current.path, current.name, id: current.id);
      await _player.setVolume(_volume);
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> removeFromPlaylist(int index) async {
    if (index >= 0 && index < _playlist.length) {
      _playlist.removeAt(index);
      await _player.remove(index);
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
    await _player.stop();
    // Re-open empty playlist or just stop
    notifyListeners();
  }

  Future<void> next() async {
    await _player.next();
  }

  Future<void> previous() async {
    await _player.previous();
  }

  Future<void> togglePlay() async {
    await _player.playOrPause();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 100.0);
    await _player.setVolume(_volume);
    notifyListeners();
  }

  @override
  void dispose() {
    _stopEmulatedSpectrum();
    _emulatedFftController.close();
    _player.dispose();
    super.dispose();
  }
}
