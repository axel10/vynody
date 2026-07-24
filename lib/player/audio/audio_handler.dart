import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:vynody/player/audio/audio_service.dart' as app; // To distinguish from package:audio_service

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final app.AudioService appAudio;
  MyAudioHandler(this.appAudio);

  String? _getOrCacheArtworkPath(String trackPath, Uint8List bytes) {
    try {
      final tempDir = Directory.systemTemp;
      final fileName = 'vynody_art_${trackPath.hashCode}.jpg';
      final file = File('${tempDir.path}/$fileName');
      if (!file.existsSync()) {
        file.writeAsBytesSync(bytes);
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }

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
          if (artPath != null && artPath.isNotEmpty) {
            if (artPath.startsWith('content://')) {
              return Uri.parse(artPath);
            }
            if (File(artPath).existsSync()) {
              return Uri.file(artPath);
            }
          }
          if (music?.artworkBytes != null &&
              music!.artworkBytes!.isNotEmpty &&
              music.path.isNotEmpty) {
            final cachedPath = _getOrCacheArtworkPath(
              music.path,
              music.artworkBytes!,
            );
            if (cachedPath != null && File(cachedPath).existsSync()) {
              return Uri.file(cachedPath);
            }
          }
          return null;
        }(),
      ),
    );
  }

  void onPlaybackStatusChanged(bool isPlaying) {
    playbackState.add(
      playbackState.value.copyWith(
        playing: isPlaying,
        speed: isPlaying ? 1.0 : 0.0,
        updatePosition: appAudio.position,
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

  void onPositionChanged(Duration position, Duration duration) {
    playbackState.add(
      playbackState.value.copyWith(
        updatePosition: position,
        bufferedPosition: position,
        playing: appAudio.isPlaying,
        speed: appAudio.isPlaying ? 1.0 : 0.0,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (!appAudio.isPlaying) {
      await appAudio.togglePlay();
    }
  }

  @override
  Future<void> pause() async {
    if (appAudio.isPlaying) {
      await appAudio.togglePlay();
    }
  }

  @override
  Future<void> skipToNext() => appAudio.next();

  @override
  Future<void> skipToPrevious() => appAudio.previous();

  @override
  Future<void> seek(Duration position) => appAudio.seek(position);

  @override
  Future<void> stop() async {
    if (appAudio.isPlaying) {
      await appAudio.togglePlay();
    }
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
    return super.stop();
  }
}
