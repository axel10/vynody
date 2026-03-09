import 'dart:async';
import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import 'base_player.dart';

class AudioVisualizerPlayer extends BasePlayer {
  late final AudioVisualizerPlayerController _controller;

  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  final StreamController<int> _indexController =
      StreamController<int>.broadcast();

  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration> get durationStream => _durationController.stream;
  @override
  Stream<double> get volumeStream => _volumeController.stream;
  @override
  Stream<int> get indexStream => _indexController.stream;

  AudioVisualizerPlayer() {
    _controller = AudioVisualizerPlayerController();
    _controller.addListener(_handleControllerChanges);
  }

  void _handleControllerChanges() {
    _playingController.add(_controller.isPlaying);
    _positionController.add(_controller.position);
    _durationController.add(_controller.duration);
    _volumeController.add(_controller.volume * 100.0);
    if (_controller.currentIndex != null) {
      _indexController.add(_controller.currentIndex!);
    }
  }

  @override
  Future<void> initialize() async {
    await _controller.initialize();
  }

  @override
  Future<void> playFile(String path) async {
    await _controller.loadFromPath(path);
    await _controller.play();
  }

  @override
  Future<void> playPlaylist(List<String> paths, {int initialIndex = 0}) async {
    final tracks = paths.asMap().entries.map((e) {
      return AudioTrack(id: e.key.toString(), uri: e.value);
    }).toList();

    await _controller.setPlaylist(
      tracks,
      startIndex: initialIndex,
      autoPlay: true,
    );
  }

  @override
  Future<void> addToPlaylist(List<String> paths) async {
    final startIndex = _controller.playlist.length;
    final tracks = paths.asMap().entries.map((e) {
      return AudioTrack(id: (startIndex + e.key).toString(), uri: e.value);
    }).toList();
    await _controller.addTracks(tracks);
  }

  @override
  Future<void> removeFromPlaylist(int index) async {
    await _controller.removeTrackAt(index);
  }

  @override
  Future<void> clearPlaylist() async {
    await _controller.clearPlaylist();
  }

  @override
  Future<void> next() async {
    await _controller.playNext();
  }

  @override
  Future<void> previous() async {
    await _controller.playPrevious();
  }

  @override
  Future<void> togglePlay() async {
    await _controller.togglePlayPause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _controller.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _controller.setVolume(volume / 100.0);
  }

  @override
  Future<void> dispose() async {
    _controller.removeListener(_handleControllerChanges);
    _controller.dispose();
    await _playingController.close();
    await _positionController.close();
    await _durationController.close();
    await _volumeController.close();
    await _indexController.close();
  }

  /// Exposed for UI visualization
  AudioVisualizerPlayerController get controller => _controller;
}
