import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:windows_taskbar/windows_taskbar.dart';
import 'package:smtc_windows/smtc_windows.dart';
import '../models/music_file.dart';
import 'audio_service.dart';

class WindowsIntegrationService {
  final AudioService audioService;
  SMTCWindows? _smtc;
  StreamSubscription? _smtcSubscription;
  bool _disposed = false;
  bool _taskbarReady = false;
  bool _taskbarInitScheduled = false;
  bool? _lastIsPlaying;
  Duration _lastPosition = Duration.zero;

  WindowsIntegrationService(this.audioService) {
    if (!Platform.isWindows) return;
    _init();
  }

  void _init() {
    _smtc = SMTCWindows();
    
    _smtcSubscription = _smtc?.buttonPressStream.listen((event) {
      switch (event) {
        case PressedButton.play:
          audioService.togglePlay();
          break;
        case PressedButton.pause:
          audioService.togglePlay();
          break;
        case PressedButton.next:
          audioService.next();
          break;
        case PressedButton.previous:
          audioService.previous();
          break;
        case PressedButton.stop:
          if (audioService.isPlaying) audioService.togglePlay();
          break;
        default:
          break;
      }
    });

    _scheduleInitialTaskbarSetup();
  }

  void updateMetadata(MusicFile? song) {
    if (!Platform.isWindows || _smtc == null) return;

    _smtc?.updateMetadata(
      MusicMetadata(
        title: audioService.currentFileName ?? 'Unknown',
        artist: audioService.currentArtist ?? 'Unknown',
        album: audioService.currentAlbum ?? 'Unknown',
        albumArtist: audioService.currentArtist ?? 'Unknown',
        thumbnail: audioService.currentArtworkPath != null && File(audioService.currentArtworkPath!).existsSync()
            ? audioService.currentArtworkPath
            : null,
      ),
    );
  }

  void updatePlaybackStatus(bool isPlaying) {
    if (!Platform.isWindows || _smtc == null || _disposed) return;

    // Only update if the status has actually changed
    if (_lastIsPlaying == isPlaying) return;
    _lastIsPlaying = isPlaying;

    _smtc?.setPlaybackStatus(
      isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused,
    );

    _updateTaskbarButtons();
  }

  void updateTimeline(Duration position, Duration duration) {
    if (!Platform.isWindows || _smtc == null || _disposed) return;

    _smtc?.updateTimeline(
      PlaybackTimeline(
        positionMs: position.inMilliseconds,
        startTimeMs: 0,
        endTimeMs: duration.inMilliseconds,
      ),
    );

    // Throttled taskbar progress update (every 1 second or if it's a significant change like a seek)
    final diff = (position - _lastPosition).abs().inMilliseconds;
    if (diff >= 1000 || diff < 0 || position == Duration.zero) {
      _lastPosition = position;
      if (duration.inMilliseconds > 0) {
        WindowsTaskbar.setProgressMode(TaskbarProgressMode.normal);
        WindowsTaskbar.setProgress(
          position.inMilliseconds,
          duration.inMilliseconds,
        );
      } else {
        WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
      }
    }
  }

  void _updateTaskbarButtons() {
    if (!Platform.isWindows || _disposed) return;

    if (!_taskbarReady) {
      _scheduleInitialTaskbarSetup();
      return;
    }

    unawaited(_setThumbnailToolbar());
  }

  void _scheduleInitialTaskbarSetup() {
    if (!Platform.isWindows || _disposed || _taskbarInitScheduled) return;
    _taskbarInitScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_retrySetThumbnailToolbar());
    });
  }

  Future<void> _retrySetThumbnailToolbar() async {
    const retryDelays = <Duration>[
      Duration(milliseconds: 600),
      Duration(milliseconds: 1200),
      Duration(milliseconds: 2400),
      Duration(milliseconds: 4000),
    ];

    for (var i = 0; i < retryDelays.length; i++) {
      if (_disposed || _taskbarReady) return;

      if (i > 0) {
        await Future.delayed(retryDelays[i]);
        if (_disposed) return;
      }

      final success = await _setThumbnailToolbar(logError: i == retryDelays.length - 1);
      if (success) {
        return;
      }
    }
  }

  Future<bool> _setThumbnailToolbar({bool logError = true}) async {
    if (_disposed) return false;

    try {
      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/icons/skip_previous.ico'),
          'Previous',
          audioService.previous,
        ),
        ThumbnailToolbarButton(
          audioService.isPlaying
              ? ThumbnailToolbarAssetIcon('assets/icons/pause.ico')
              : ThumbnailToolbarAssetIcon('assets/icons/play_arrow.ico'),
          audioService.isPlaying ? 'Pause' : 'Play',
          audioService.togglePlay,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/icons/skip_next.ico'),
          'Next',
          audioService.next,
        ),
      ]);
      _taskbarReady = true;
      return true;
    } catch (e) {
      if (logError) {
        debugPrint('WindowsTaskbar Error: $e');
      }
      return false;
    }
  }

  void dispose() {
    if (!Platform.isWindows) return;
    _disposed = true;
    _smtcSubscription?.cancel();
    _smtc?.dispose();
  }
}
