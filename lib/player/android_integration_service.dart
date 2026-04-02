import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'audio_service.dart' as app; // To distinguish from package:audio_service
import '../models/music_file.dart';

class AndroidIntegrationService {
  final app.AudioService audioService;
  late MyAudioHandler _handler;
  bool _initialized = false;
  String? _lastMetadataKey;
  DateTime _lastTimelineForwardedAt =
      DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastTimelinePosition = Duration.zero;
  Duration _lastTimelineDuration = Duration.zero;
  bool _hasForwardedTimeline = false;

  AndroidIntegrationService(this.audioService) {
    if (!Platform.isAndroid) return;
    _init();
  }

  Future<void> _init() async {
    try {
      await _ensureNotificationPermission();

      _handler = await AudioService.init(
        builder: () => MyAudioHandler(audioService),
        config: AudioServiceConfig(
          androidNotificationChannelId:
              'com.pure_player.vibe_flow.channel.audio',
          androidNotificationChannelName: 'Vibe Flow Playback',
          androidNotificationOngoing: true,
          androidShowNotificationBadge: true,
          androidStopForegroundOnPause: false,
        ),
      );
      _initialized = true;
      _updateInitialState();
    } catch (e, st) {
      debugPrint('Android audio service init failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> _ensureNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted) return;

    final result = await Permission.notification.request();
    if (!result.isGranted) {
      debugPrint(
        'Notification permission not granted; Android media notification may not appear.',
      );
    }
  }

  void _updateInitialState() {
    if (!_initialized) return;
    // Sync current state if something is already playing
    updatePlaybackStatus(audioService.isPlaying);
    updateMetadata(null); // Will pull from audioService
  }

  void updateMetadata(MusicFile? song) {
    if (!Platform.isAndroid || !_initialized) return;

    final metadataKey = [
      song?.path ?? audioService.currentFilePath,
      audioService.currentFileName,
      audioService.currentArtist,
      audioService.currentAlbum,
      audioService.currentArtworkPath,
      audioService.duration.inMilliseconds.toString(),
    ].join('|');
    if (_lastMetadataKey == metadataKey) return;
    _lastMetadataKey = metadataKey;

    _handler.onMetadataChanged();
  }

  bool? _lastIsPlaying;

  void updatePlaybackStatus(bool isPlaying) {
    if (!Platform.isAndroid || !_initialized) return;
    if (_lastIsPlaying == isPlaying) return;
    _lastIsPlaying = isPlaying;

    _handler.onPlaybackStatusChanged(isPlaying);
  }

  void updateTimeline(Duration position, Duration duration) {
    if (!Platform.isAndroid || !_initialized) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastTimelineForwardedAt);
    final positionJump = (position - _lastTimelinePosition).abs();
    final durationChanged = duration != _lastTimelineDuration;

    final shouldForward = !_hasForwardedTimeline ||
        durationChanged ||
        position == Duration.zero ||
        positionJump >= const Duration(milliseconds: 500) ||
        elapsed >= const Duration(milliseconds: 250) ||
        (!audioService.isPlaying &&
            elapsed >= const Duration(milliseconds: 1000));

    if (!shouldForward) return;

    _hasForwardedTimeline = true;
    _lastTimelineForwardedAt = now;
    _lastTimelinePosition = position;
    _lastTimelineDuration = duration;

    _handler.onPositionChanged(position, duration);
  }

  void dispose() {
    // AudioService handlers usually live for the duration of the app
  }
}

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final app.AudioService appAudio;
  double? _preDuckingVolume;

  MyAudioHandler(this.appAudio) {
    _initSession();
  }

  Future<void> _initSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Handle interruptions (like calls)
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            // Optional: Lower volume
            if (appAudio.isPlaying) {
              _preDuckingVolume = appAudio.volume;
              appAudio.setVolume(_preDuckingVolume! * 0.3);
            }
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (appAudio.isPlaying) {
              pause();
            }
            break;
        }
      } else {
        // Interruption ended
        switch (event.type) {
          case AudioInterruptionType.duck:
            // Restore volume
            if (_preDuckingVolume != null) {
              appAudio.setVolume(_preDuckingVolume!);
              _preDuckingVolume = null;
            }
            break;
          case AudioInterruptionType.pause:
            // Option: resume if it was interrupted
            // We can decide whether to resume or not.
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    // Handle being "Becoming Noisy" (headphones unplugged)
    session.becomingNoisyEventStream.listen((_) {
      if (appAudio.isPlaying) {
        pause();
      }
    });
  }

  void onMetadataChanged() {
    mediaItem.add(
      MediaItem(
        id: appAudio.currentFilePath ?? 'unknown',
        album: appAudio.currentAlbum ?? 'Unknown',
        title: appAudio.currentFileName ?? 'Unknown',
        artist: appAudio.currentArtist ?? 'Unknown',
        duration: appAudio.duration,
        artUri: appAudio.currentArtworkPath != null &&
                File(appAudio.currentArtworkPath!).existsSync()
            ? Uri.file(appAudio.currentArtworkPath!)
          : null,
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
        },
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  DateTime _lastPositionUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastPositionValue = Duration.zero;

  void onPositionChanged(Duration position, Duration duration) {
    // Only update if there is a significant jump (seek) or if it's been a while (e.g. 10 seconds)
    // to keep the clocks in sync, though usually interpolation is enough.
    final now = DateTime.now();
    final timeSinceLastUpdate = now.difference(_lastPositionUpdateTime);

    // If it's a seek (difference between actual and expected > 1s)
    final expectedPosition = _lastPositionValue +
        (appAudio.isPlaying
            ? timeSinceLastUpdate
            : Duration.zero);
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
    final session = await AudioSession.instance;
    if (await session.setActive(true)) {
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
    if (appAudio.isPlaying) await appAudio.togglePlay();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
    return super.stop();
  }
}
