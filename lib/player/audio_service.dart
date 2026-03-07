import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:image/image.dart' as img;
import 'metadata_database.dart';

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

  AudioService() {
    _player = Player();
    _player.stream.playing.listen((playing) {
      _isPlaying = playing;
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
  double get progress => _duration.inMilliseconds > 0
      ? _position.inMilliseconds / _duration.inMilliseconds
      : 0.0;

  Future<void> playFile(String path, String name, {int? id}) async {
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

    await _player.open(Media(path));
    await _player.setVolume(_volume);
    await _player.play();
    notifyListeners();
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
    _player.dispose();
    super.dispose();
  }
}
