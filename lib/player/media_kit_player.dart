import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'base_player.dart';

class MediaKitPlayer implements BasePlayer {
  final Player _player = Player();

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<double> get volumeStream => _player.stream.volume;

  @override
  Stream<int> get indexStream => _player.stream.playlist.map((p) => p.index);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> playFile(String path) async {
    await _player.open(Media(path));
    await _player.play();
  }

  @override
  Future<void> playPlaylist(List<String> paths, {int initialIndex = 0}) async {
    final mediaList = paths.map((p) => Media(p)).toList();
    await _player.open(Playlist(mediaList, index: initialIndex));
    await _player.play();
  }

  @override
  Future<void> addToPlaylist(List<String> paths) async {
    for (final path in paths) {
      await _player.add(Media(path));
    }
  }

  @override
  Future<void> removeFromPlaylist(int index) async {
    await _player.remove(index);
  }

  @override
  Future<void> clearPlaylist() async {
    await _player.stop();
  }

  @override
  Future<void> next() async {
    await _player.next();
  }

  @override
  Future<void> previous() async {
    await _player.previous();
  }

  @override
  Future<void> togglePlay() async {
    await _player.playOrPause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 100.0));
  }

  @override
  Future<void> dispose() async {
    _player.dispose();
  }
}
