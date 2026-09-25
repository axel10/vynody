import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/app_log.dart';

final standaloneQueueWindowManagerProvider =
    Provider<StandaloneQueueWindowManager>((ref) {
  final manager = StandaloneQueueWindowManager(ref);
  ref.onDispose(manager.dispose);
  return manager;
});

final isStandaloneQueueWindowOpenProvider =
    StateProvider<bool>((ref) => false);

class StandaloneQueueWindowManager {
  final Ref ref;
  String? _subWindowId;
  WindowController? _subWindowController;
  late final WindowMethodChannel _mainChannel;

  ProviderSubscription<List<MusicFile>>? _queueSub;
  ProviderSubscription<MusicFile?>? _musicSub;
  ProviderSubscription<bool>? _isPlayingSub;
  ProviderSubscription<int>? _currentIndexSub;
  ProviderSubscription<ScannerService>? _scannerSub;
  ProviderSubscription<SettingsService>? _settingsSub;
  Timer? _debounceSyncTimer;

  StandaloneQueueWindowManager(this.ref) {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    _mainChannel = const WindowMethodChannel(
      'vynody/standalone_queue_main',
      mode: ChannelMode.unidirectional,
    );
    _initIpcHandler();
  }

  bool get isWindowOpen => _subWindowId != null;

  void _initIpcHandler() {
    _mainChannel.setMethodCallHandler((call) async {
      AppLog.log(
        '[StandaloneQueue] IPC method received: ${call.method}',
        mirrorToConsole: true,
      );

      final audio = ref.read(audioServiceProvider);

      switch (call.method) {
        case 'request_initial_sync':
          _syncFullStateToSubWindow();
          return true;

        case 'request_thumbnail':
          final path = call.arguments as String?;
          if (path != null && path.isNotEmpty) {
            unawaited(ref.read(scannerServiceProvider).loadThumbnailForPath(path));
          }
          return true;

        case 'play_index':
          final index = call.arguments as int?;
          if (index != null) {
            audio.playAtIndex(index);
          }
          return true;

        case 'play_music':
          final songJson = call.arguments as Map?;
          if (songJson != null) {
            final song = _musicFileFromJson(Map<String, dynamic>.from(songJson));
            audio.playFile(song.path, song.name);
          }
          return true;

        case 'remove_index':
          final index = call.arguments as int?;
          if (index != null) {
            audio.removeFromPlaylist(index);
          }
          return true;

        case 'clear_queue':
          audio.clearPlaylist();
          return true;

        case 'reorder':
          final args = call.arguments as Map?;
          if (args != null) {
            final oldIndex = args['oldIndex'] as int;
            final newIndex = args['newIndex'] as int;
            audio.moveQueueTrack(oldIndex, newIndex);
          }
          return true;

        case 'add_files':
          final args = call.arguments as Map?;
          if (args != null) {
            final paths = List<String>.from(args['paths'] ?? []);
            final insertIndex = args['insertIndex'] as int?;
            final playNow = args['playNow'] as bool? ?? false;
            await _handleDroppedPaths(paths, insertIndex: insertIndex, playNow: playNow);
          }
          return true;

        case 'window_closed':
          _onSubWindowClosed();
          return true;

        default:
          return null;
      }
    });
  }

  Future<void> _handleDroppedPaths(
    List<String> paths, {
    int? insertIndex,
    bool playNow = false,
  }) async {
    if (paths.isEmpty) return;
    final songs = <MusicFile>[];
    for (final path in paths) {
      if (FileSystemEntity.isFileSync(path)) {
        if (MusicFileUtils.isMusicFilePath(path)) {
          songs.add(MusicFile(path: path, name: p.basename(path)));
        }
      } else if (FileSystemEntity.isDirectorySync(path)) {
        final dir = Directory(path);
        try {
          await for (final item in dir.list(recursive: true, followLinks: false)) {
            if (item is File && MusicFileUtils.isMusicFilePath(item.path)) {
              songs.add(MusicFile(path: item.path, name: p.basename(item.path)));
            }
          }
        } catch (e) {
          AppLog.log('[StandaloneQueue] Error scanning directory $path: $e');
        }
      }
    }

    if (songs.isEmpty) return;

    try {
      final db = MetadataDatabase();
      final cachedMap =
          await db.getSongMetadataByPaths(songs.map((s) => s.path));
      for (var i = 0; i < songs.length; i++) {
        final s = songs[i];
        final cached = cachedMap[s.path];
        if (cached != null) {
          songs[i] = songs[i].copyWith(
            title: cached.title,
            artist: cached.artist,
            albumArtist: cached.albumArtist,
            album: cached.album,
            trackNumber: cached.trackNumber,
            durationMillis: cached.duration,
            thumbnailPath: cached.thumbnailPath,
            artworkPath: cached.artworkPath,
            artworkWidth: cached.artworkWidth,
            artworkHeight: cached.artworkHeight,
            themeColorsBlob: cached.themeColorsBlob,
            waveformBlob: cached.waveformBlob,
            lastModifiedTime: cached.lastModifiedTime,
          );
        }
      }
    } catch (e) {
      AppLog.log('[StandaloneQueue] Error enriching metadata for dropped songs: $e');
    }

    final audio = ref.read(audioServiceProvider);
    if (insertIndex != null && insertIndex >= 0) {
      await audio.insertIntoQueueAt(insertIndex, songs);
    } else {
      await audio.appendToQueue(songs);
    }

    if (playNow && songs.isNotEmpty) {
      await audio.playFile(songs.first.path, songs.first.name);
    }
  }

  void _preloadQueueThumbnails(List<MusicFile> queue) {
    if (queue.isEmpty) return;
    final scanner = ref.read(scannerServiceProvider);
    for (final song in queue) {
      final meta = scanner.metadataMap[song.path];
      final hasThumbnail = (song.thumbnailPath != null && song.thumbnailPath!.isNotEmpty) ||
          (meta?.thumbnailPath != null && meta!.thumbnailPath!.isNotEmpty) ||
          (song.artworkPath != null && song.artworkPath!.isNotEmpty) ||
          (meta?.artworkPath != null && meta!.artworkPath!.isNotEmpty);
      if (!hasThumbnail) {
        unawaited(scanner.loadThumbnailForPath(song.path));
      }
    }
  }

  Map<String, dynamic> _buildStatePayload() {
    final queue = ref.read(audioPlaybackQueueProvider);
    final currentMusic = ref.read(audioCurrentMusicProvider);
    final currentIndex = ref.read(audioCurrentIndexProvider);
    final isPlaying = ref.read(audioIsPlayingProvider);
    final settings = ref.read(settingsServiceProvider);

    _preloadQueueThumbnails(queue);

    return {
      'type': 'standalone_queue',
      'title': '播放队列 - Vynody',
      'queue': queue.map(_musicFileToJson).toList(),
      'currentMusic': currentMusic != null ? _musicFileToJson(currentMusic) : null,
      'currentIndex': currentIndex,
      'isPlaying': isPlaying,
      'themeMode': settings.themeMode.index,
      'accentColor': settings.themeColor.toARGB32(),
    };
  }

  Future<void> openOrFocusQueueWindow() async {
    if (_subWindowController != null) {
      try {
        await _subWindowController!.show();
        _syncFullStateToSubWindow();
        return;
      } catch (e) {
        AppLog.log('[StandaloneQueue] Failed to focus existing window: $e, recreating...');
        _subWindowController = null;
        _subWindowId = null;
      }
    }

    try {
      final configPayload = jsonEncode(_buildStatePayload());

      final controller = await WindowController.create(
        WindowConfiguration(
          arguments: configPayload,
        ),
      );
      _subWindowController = controller;
      _subWindowId = controller.windowId;

      final settings = ref.read(settingsServiceProvider);
      final isDark = settings.themeMode == ThemeMode.dark ||
          (settings.themeMode == ThemeMode.system &&
              WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                  Brightness.dark);
      if (Platform.isWindows) {
        try {
          await controller.setDarkMode(isDark);
        } catch (_) {}
      }

      await controller.show();

      ref.read(isStandaloneQueueWindowOpenProvider.notifier).state = true;
      _startStateListening();
      _syncFullStateToSubWindow();
    } catch (e, stack) {
      AppLog.log('[StandaloneQueue] Failed to create standalone queue window: $e', stackTrace: stack);
      _subWindowController = null;
      _subWindowId = null;
      ref.read(isStandaloneQueueWindowOpenProvider.notifier).state = false;
    }
  }

  Future<void> closeQueueWindow() async {
    if (_subWindowController == null) return;
    try {
      await _subWindowController!.hide();
    } catch (e) {
      AppLog.log('[StandaloneQueue] Error closing window: $e');
    } finally {
      _onSubWindowClosed();
    }
  }

  void _onSubWindowClosed() {
    _subWindowController = null;
    _subWindowId = null;
    _stopStateListening();
    ref.read(isStandaloneQueueWindowOpenProvider.notifier).state = false;
  }

  void _startStateListening() {
    _stopStateListening();

    _queueSub = ref.listen<List<MusicFile>>(
      audioPlaybackQueueProvider,
      (prev, next) => _syncFullStateToSubWindow(),
    );

    _musicSub = ref.listen<MusicFile?>(
      audioCurrentMusicProvider,
      (prev, next) => _syncFullStateToSubWindow(),
    );

    _isPlayingSub = ref.listen<bool>(
      audioIsPlayingProvider,
      (prev, next) => _syncPlaybackStateOnly(),
    );

    _currentIndexSub = ref.listen<int>(
      audioCurrentIndexProvider,
      (prev, next) => _syncFullStateToSubWindow(),
    );

    _scannerSub = ref.listen<ScannerService>(
      scannerServiceProvider,
      (prev, next) => _debouncedSyncFullState(),
    );

    _settingsSub = ref.listen<SettingsService>(
      settingsServiceProvider,
      (prev, next) {
        final settings = next;
        final isDark = settings.themeMode == ThemeMode.dark ||
            (settings.themeMode == ThemeMode.system &&
                WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                    Brightness.dark);
        if (Platform.isWindows && _subWindowController != null) {
          try {
            _subWindowController!.setDarkMode(isDark);
          } catch (_) {}
        }
        _syncFullStateToSubWindow();
      },
    );
  }

  void _debouncedSyncFullState() {
    _debounceSyncTimer?.cancel();
    _debounceSyncTimer = Timer(const Duration(milliseconds: 150), () {
      _syncFullStateToSubWindow();
    });
  }

  void _stopStateListening() {
    _debounceSyncTimer?.cancel();
    _debounceSyncTimer = null;
    _queueSub?.close();
    _queueSub = null;
    _musicSub?.close();
    _musicSub = null;
    _isPlayingSub?.close();
    _isPlayingSub = null;
    _currentIndexSub?.close();
    _currentIndexSub = null;
    _scannerSub?.close();
    _scannerSub = null;
    _settingsSub?.close();
    _settingsSub = null;
  }

  void _syncFullStateToSubWindow() {
    if (_subWindowId == null) return;
    try {
      final payload = _buildStatePayload();
      final subChannel = WindowMethodChannel(
        'vynody/standalone_queue_sub_$_subWindowId',
        mode: ChannelMode.unidirectional,
      );
      subChannel.invokeMethod('sync_state', payload);
    } catch (e) {
      AppLog.log('[StandaloneQueue] Failed to sync state to sub window: $e');
    }
  }

  void _syncPlaybackStateOnly() {
    if (_subWindowId == null) return;
    try {
      final isPlaying = ref.read(audioIsPlayingProvider);
      final subChannel = WindowMethodChannel(
        'vynody/standalone_queue_sub_$_subWindowId',
        mode: ChannelMode.unidirectional,
      );
      subChannel.invokeMethod('sync_playback_state', {
        'isPlaying': isPlaying,
      });
    } catch (e) {
      AppLog.log('[StandaloneQueue] Failed to sync playback state: $e');
    }
  }

  Map<String, dynamic> _musicFileToJson(MusicFile file) {
    final scanner = ref.read(scannerServiceProvider);
    final meta = scanner.metadataMap[file.path];
    final thumbnailPath = (file.thumbnailPath != null && file.thumbnailPath!.isNotEmpty)
        ? file.thumbnailPath
        : meta?.thumbnailPath;
    final artworkPath = (file.artworkPath != null && file.artworkPath!.isNotEmpty)
        ? file.artworkPath
        : meta?.artworkPath;

    return {
      'path': file.path,
      'name': file.name,
      'title': file.title ?? meta?.title,
      'artist': file.artist ?? meta?.artist,
      'albumArtist': file.albumArtist ?? meta?.albumArtist,
      'album': file.album ?? meta?.album,
      'trackNumber': file.trackNumber ?? meta?.trackNumber,
      'durationMillis': file.durationMillis ?? meta?.duration,
      'thumbnailPath': thumbnailPath,
      'artworkPath': artworkPath,
      'mediaUri': file.mediaUri,
      'isMissing': file.isMissing,
    };
  }

  MusicFile _musicFileFromJson(Map<String, dynamic> json) {
    return MusicFile(
      path: json['path'] as String,
      name: json['name'] as String? ?? '',
      title: json['title'] as String?,
      artist: json['artist'] as String?,
      albumArtist: json['albumArtist'] as String?,
      album: json['album'] as String?,
      trackNumber: json['trackNumber'] as int?,
      durationMillis: json['durationMillis'] as int?,
      thumbnailPath: json['thumbnailPath'] as String?,
      artworkPath: json['artworkPath'] as String?,
      mediaUri: json['mediaUri'] as String?,
      isMissing: json['isMissing'] as bool? ?? false,
    );
  }

  void dispose() {
    _debounceSyncTimer?.cancel();
    _debounceSyncTimer = null;
    _stopStateListening();
    _mainChannel.setMethodCallHandler(null);
  }

  static bool isStandaloneQueueWindow(List<String> args) {
    if (args.length >= 3 && args.first == 'multi_window') {
      try {
        final json = jsonDecode(args[2]);
        if (json is Map && json['type'] == 'standalone_queue') {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }
}
