import 'dart:async';

enum PlayerBackend { mediaKit, audioVisualizer }

abstract class BasePlayer {
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<double> get volumeStream;
  Stream<int> get indexStream;

  Future<void> initialize();
  Future<void> playFile(String path);
  Future<void> playPlaylist(List<String> paths, {int initialIndex = 0});
  Future<void> addToPlaylist(List<String> paths);
  Future<void> removeFromPlaylist(int index);
  Future<void> clearPlaylist();
  Future<void> next();
  Future<void> previous();
  Future<void> togglePlay();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}
