import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:vynody/player/audio/audio_service.dart' as app; // To distinguish from package:audio_service

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final app.AudioService appAudio;
  MyAudioHandler(this.appAudio);

  void onMetadataChanged() {
    final music = appAudio.currentMusic;
    mediaItem.add(
      MediaItem(
        id: music?.path ?? 'unknown',
        album: music?.album ?? 'Unknown',
        title: music?.displayName ?? music?.name ?? 'Unknown',
        artist: music?.artist ?? 'Unknown',
        duration: appAudio.duration,
        artUri: () {
          final artPath = music?.artworkPath ?? music?.thumbnailPath;
          if (artPath != null && File(artPath).existsSync()) {
            return Uri.file(artPath);
          }
          return null;
        }(),
      ),
    );
  }

  void onPlaybackStatusChanged(bool isPlaying) {
    _lastPositionUpdateTime = DateTime.now();
    _lastPositionValue = appAudio.position;

    playbackState.add(
      playbackState.value.copyWith(
        playing: isPlaying,
        speed: isPlaying ? 1.0 : 0.0,
        updatePosition: _lastPositionValue,
        androidCompactActionIndices: const [0, 1, 2],
        controls: [
          MediaControl.skipToPrevious,
          isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.stop,
        },
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  DateTime _lastPositionUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastPositionValue = Duration.zero;

  void onPositionChanged(Duration position, Duration duration) {
    final now = DateTime.now();
    final timeSinceLastUpdate = now.difference(_lastPositionUpdateTime);

    final expectedPosition =
        _lastPositionValue +
        (appAudio.isPlaying ? timeSinceLastUpdate : Duration.zero);
    final drift = (position - expectedPosition).abs().inMilliseconds;

    if (drift > 1000 || timeSinceLastUpdate.inSeconds > 10) {
      _lastPositionUpdateTime = now;
      _lastPositionValue = position;
      playbackState.add(
        playbackState.value.copyWith(
          updatePosition: position,
          bufferedPosition: position,
        ),
      );
    }
  }

  @override
  Future<void> play() async {
    await appAudio.playbackController.player.play();
  }

  @override
  Future<void> pause() async {
    await appAudio.playbackController.player.pause();
  }

  @override
  Future<void> skipToNext() => appAudio.next();

  @override
  Future<void> skipToPrevious() => appAudio.previous();

  @override
  Future<void> seek(Duration position) => appAudio.seek(position);

  @override
  Future<void> stop() async {
    await appAudio.playbackController.player.pause();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
    return super.stop();
  }
}
