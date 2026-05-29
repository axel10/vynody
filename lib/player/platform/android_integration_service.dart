import 'dart:io';
import 'package:audio_service/audio_service.dart';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibe_flow/player/audio/audio_service.dart' as app; // To distinguish from package:audio_service
import 'package:vibe_flow/player/audio/audio_handler.dart';
import 'package:vibe_flow/models/music_file.dart';

class AndroidIntegrationService {
  final app.AudioService audioService;
  late MyAudioHandler _handler;
  bool _initialized = false;
  String? _lastMetadataKey;
  DateTime _lastTimelineForwardedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastTimelinePosition = Duration.zero;
  Duration _lastTimelineDuration = Duration.zero;
  bool _hasForwardedTimeline = false;
  DateTime _lastDebugLogAt = DateTime.fromMillisecondsSinceEpoch(0);

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
          androidNotificationOngoing: false,
          androidShowNotificationBadge: false,
          // androidStopForegroundOnPause: false,
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

    final shouldForward =
        !_hasForwardedTimeline ||
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

    _logDebug(
      'forward position=${_formatDuration(position)} '
      'duration=${_formatDuration(duration)} '
      'playing=${audioService.isPlaying}',
      throttle: const Duration(seconds: 1),
    );

    if (durationChanged) {
      updateMetadata(null);
    }
    _handler.onPositionChanged(position, duration);
  }

  void dispose() {
    // AudioService handlers usually live for the duration of the app
  }

  void _logDebug(String message, {Duration? throttle}) {
    if (!kDebugMode) return;

    final now = DateTime.now();
    if (throttle != null && now.difference(_lastDebugLogAt) < throttle) {
      return;
    }
    _lastDebugLogAt = now;
    debugPrint('[AndroidIntegration] $message');
  }

  String _formatDuration(Duration duration) {
    final safe = duration < Duration.zero ? Duration.zero : duration;
    final totalMilliseconds = safe.inMilliseconds;
    final minutes = totalMilliseconds ~/ 60000;
    final seconds = (totalMilliseconds % 60000) ~/ 1000;
    final millis = totalMilliseconds % 1000;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
  }
}
