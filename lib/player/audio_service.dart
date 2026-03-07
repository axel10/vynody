import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

class AudioService extends ChangeNotifier {
  late final Player _player;
  bool _isPlaying = false;
  String? _currentFilePath;
  String? _currentFileName;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100.0;

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
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  double get progress => _duration.inMilliseconds > 0
      ? _position.inMilliseconds / _duration.inMilliseconds
      : 0.0;

  Future<void> playFile(String path, String name) async {
    _currentFilePath = path;
    _currentFileName = name;
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
