import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:vibe_flow/player/audio/audio_service.dart' as app; // To distinguish from package:audio_service
import 'package:vibe_flow/player/audio/audio_handler.dart';
import 'package:vibe_flow/models/music_file.dart';

class DarwinIntegrationService {
  final app.AudioService audioService;
  late MyAudioHandler _handler;
  bool _initialized = false;
  String? _lastMetadataKey;

  DarwinIntegrationService(this.audioService) {
    if (!Platform.isIOS && !Platform.isMacOS) return;
    _init();
  }

  Future<void> _init() async {
    try {
      if (Platform.isIOS) {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());

        // Listen to interruptions (phone calls, alarms, Siri, etc.)
        session.interruptionEventStream.listen((event) {
          if (event.begin) {
            switch (event.type) {
              case AudioInterruptionType.duck:
                // Lower the volume (ducking)
                audioService.playbackController.player.setVolume(audioService.volume / 200.0);
                break;
              case AudioInterruptionType.pause:
              case AudioInterruptionType.unknown:
                audioService.playbackController.player.pause();
                break;
            }
          } else {
            switch (event.type) {
              case AudioInterruptionType.duck:
                // Restore volume
                audioService.playbackController.player.setVolume(audioService.volume / 100.0);
                break;
              case AudioInterruptionType.pause:
              case AudioInterruptionType.unknown:
                // Do not automatically resume playback unless it's a transient interruption
                break;
            }
          }
        });

        // Listen to headphone unplugged events (becoming noisy)
        session.becomingNoisyEventStream.listen((_) {
          audioService.playbackController.player.pause();
        });
      }

      // Initialize the audio_service background handler
      _handler = await AudioService.init(
        builder: () => MyAudioHandler(audioService),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'app.vibeflow.player.channel.audio',
          androidNotificationChannelName: 'Vibe Flow Playback',
        ),
      );
      _initialized = true;
      _updateInitialState();
    } catch (e, st) {
      debugPrint('Darwin audio service/session init failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  void _updateInitialState() {
    if (!_initialized) return;
    updatePlaybackStatus(audioService.isPlaying);
    updateMetadata(null);
  }

  void updateMetadata(MusicFile? song) {
    if ((!Platform.isIOS && !Platform.isMacOS) || !_initialized) return;

    final metadataKey = [
      song?.path ?? audioService.currentMusic?.path,
      audioService.currentMusic?.displayName,
      audioService.currentMusic?.artist,
      audioService.currentMusic?.album,
      audioService.currentMusic?.artworkPath,
      audioService.duration.inMilliseconds.toString(),
    ].join('|');
    if (_lastMetadataKey == metadataKey) return;
    _lastMetadataKey = metadataKey;

    _handler.onMetadataChanged();
  }

  bool? _lastIsPlaying;

  void updatePlaybackStatus(bool isPlaying) {
    if ((!Platform.isIOS && !Platform.isMacOS) || !_initialized) return;
    if (_lastIsPlaying == isPlaying) return;
    _lastIsPlaying = isPlaying;

    _handler.onPlaybackStatusChanged(isPlaying);

    if (Platform.isIOS) {
      // Activate/deactivate session based on playback state to cooperate with other apps
      AudioSession.instance.then((session) {
        session.setActive(isPlaying);
      }).catchError((Object error) {
        debugPrint('Failed to update iOS audio session active state: $error');
      });
    }
  }

  void updateTimeline(Duration position, Duration duration) {
    if ((!Platform.isIOS && !Platform.isMacOS) || !_initialized) return;
    _handler.onPositionChanged(position, duration);
  }
}
