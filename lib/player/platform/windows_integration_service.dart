import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:windows_taskbar/windows_taskbar.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_service.dart';

class WindowsIntegrationService {
  final AudioService audioService;
  SMTCWindows? _smtc;
  StreamSubscription? _smtcSubscription;
  bool _disposed = false;
  bool _taskbarReady = false;
  bool _taskbarInitScheduled = false;
  bool? _lastIsPlaying;
  Duration _lastPosition = Duration.zero;

  HttpServer? _artworkServer;
  int? _artworkServerPort;

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
    _startArtworkServer();

    // TEST: Deliberate early call to verify the new error message reporting.
    // This is expected to fail with "SetProgressMode failed: Window is not visible."
    unawaited(() async {
      try {
        await WindowsTaskbar.setProgressMode(TaskbarProgressMode.normal);
      } catch (e) {
        debugPrint('TEST: Expected startup error: $e');
      }
    }());
  }

  Future<void> _startArtworkServer() async {
    try {
      _artworkServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _artworkServerPort = _artworkServer!.port;
      _artworkServer!.listen((HttpRequest request) async {
        try {
          final path = request.uri.queryParameters['path'];
          if (path == null) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }
          final decodedPath = Uri.decodeComponent(path);
          final file = File(decodedPath);
          if (await file.exists()) {
            request.response.headers.contentType = ContentType('image', '*');
            await file.openRead().pipe(request.response);
          } else {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          }
        } catch (e) {
          debugPrint('Error serving artwork: $e');
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
      });
      // Trigger update if there's already metadata loaded
      if (audioService.currentMusic != null) {
        updateMetadata(audioService.currentMusic);
      }
    } catch (e) {
      debugPrint('Failed to start artwork server: $e');
    }
  }

  void updateMetadata(MusicFile? song) {
    if (!Platform.isWindows || _smtc == null) return;

    _smtc?.updateMetadata(
      MusicMetadata(
        title: audioService.currentMusic?.displayName ?? 'Unknown',
        artist: audioService.currentMusic?.artist ?? 'Unknown',
        album: audioService.currentMusic?.album ?? 'Unknown',
        albumArtist: audioService.currentMusic?.artist ?? 'Unknown',
        thumbnail: () {
          final artPath = audioService.currentMusic?.artworkPath ??
              audioService.currentMusic?.thumbnailPath;
          if (artPath != null && File(artPath).existsSync()) {
            if (_artworkServerPort != null) {
              return 'http://127.0.0.1:$_artworkServerPort/cover?path=${Uri.encodeComponent(artPath)}';
            }
            return Uri.file(artPath).toString();
          }
          return null;
        }(),
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

    if (!_taskbarReady) return;

    // Throttled taskbar progress update (every 1 second or if it's a significant change like a seek)
    final diff = (position - _lastPosition).abs().inMilliseconds;
    if (diff >= 1000 || diff < 0 || position == Duration.zero) {
      _lastPosition = position;
      try {
        if (duration.inMilliseconds > 0) {
          WindowsTaskbar.setProgressMode(TaskbarProgressMode.normal);
          WindowsTaskbar.setProgress(
            position.inMilliseconds,
            duration.inMilliseconds,
          );
        } else {
          WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
        }
      } catch (e) {
        // Log only if it's not a 'Window is not visible' error or if we really want to see it
        // At this point _taskbarReady is true, so this is unexpected.
        debugPrint('WindowsTaskbar progress error: $e');
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_disposed) {
        _taskbarInitScheduled = false;
        return;
      }
      await _retrySetThumbnailToolbar();
      if (_disposed) return;
      // 无论成功与否，都重置标志以便下次可以重新尝试
      // （例如窗口重新显示时）
      _taskbarInitScheduled = false;
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
    _artworkServer?.close(force: true);
  }
}
