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
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:collection/collection.dart';
import 'package:vynody/player/platform/right_queue_drawer_controller.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/clients/webdav_client.dart';
import 'package:vynody/player/remote/clients/smb_client.dart';
import 'package:vynody/player/remote/clients/remote_media_library_client.dart';
import 'package:vynody/utils/remote_context_menu_utils.dart';
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
  ProviderSubscription<PlaylistService>? _playlistSub;
  ProviderSubscription<SettingsService>? _settingsSub;
  StreamSubscription<void>? _windowsChangedSub;
  Timer? _debounceSyncTimer;

  StandaloneQueueWindowManager(this.ref) {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    _mainChannel = const WindowMethodChannel(
      'vynody/standalone_queue_main',
      mode: ChannelMode.unidirectional,
    );
    _initIpcHandler();
    _initWindowsChangedListener();
  }

  bool get isWindowOpen => ref.read(isStandaloneQueueWindowOpenProvider);

  void _initWindowsChangedListener() {
    _windowsChangedSub?.cancel();
    _windowsChangedSub = onWindowsChanged.listen((_) async {
      if (_subWindowId == null) return;
      try {
        final allWindows = await WindowController.getAll();
        final exists = allWindows.any((w) => w.windowId == _subWindowId);
        if (!exists) {
          AppLog.log(
            '[StandaloneQueue] Sub-window $_subWindowId closed natively',
            mirrorToConsole: true,
          );
          _onSubWindowClosed();
        }
      } catch (e) {
        AppLog.log('[StandaloneQueue] Error checking window existence: $e');
      }
    });
  }

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

        case 'remove_indices':
          final rawIndices = call.arguments as List?;
          if (rawIndices != null) {
            final indices = rawIndices.cast<int>();
            await audio.removeTracksAt(indices);
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
          AppLog.log('[StandaloneQueue] IPC add_files received args: $args', mirrorToConsole: true);
          debugPrint('[StandaloneQueue] IPC add_files received args: $args');
          if (args != null) {
            final paths = List<String>.from(args['paths'] ?? []);
            final insertIndex = args['insertIndex'] as int?;
            final playNow = args['playNow'] as bool? ?? false;
            await handleDroppedPaths(paths, insertIndex: insertIndex, playNow: playNow);
          }
          return true;

        case 'add_to_playlist':
          final args = call.arguments as Map?;
          if (args != null) {
            final playlistId = args['playlistId'] as String;
            final paths = List<String>.from(args['paths'] ?? []);
            await addPathsToPlaylist(playlistId, paths);
          }
          return true;

        case 'create_playlist':
          final args = call.arguments as Map?;
          final name = args?['name'] as String?;
          if (name != null && name.trim().isNotEmpty) {
            await ref.read(playlistServiceProvider).createPlaylist(name.trim());
            _syncFullStateToSubWindow();
          }
          return true;

        case 'play_playlist':
          final args = call.arguments as Map?;
          if (args != null) {
            final playlistId = args['playlistId'] as String;
            final initialIndex = args['initialIndex'] as int? ?? 0;
            final playlist = ref
                .read(playlistServiceProvider)
                .playlists
                .firstWhereOrNull((p) => p.id == playlistId);
            if (playlist != null && playlist.songs.isNotEmpty) {
              await audio.playPlaylist(
                playlist.songs,
                initialIndex: initialIndex,
                source: PlaybackSource(
                  type: PlaybackSourceType.playlist,
                  id: playlist.id,
                  name: playlist.name,
                ),
              );
            }
          }
          return true;

        case 'append_playlist_to_queue':
          final args = call.arguments as Map?;
          if (args != null) {
            final playlistId = args['playlistId'] as String;
            final playlist = ref
                .read(playlistServiceProvider)
                .playlists
                .firstWhereOrNull((p) => p.id == playlistId);
            if (playlist != null && playlist.songs.isNotEmpty) {
              await audio.appendToQueue(playlist.songs);
            }
          }
          return true;

        case 'remove_from_playlist':
          final args = call.arguments as Map?;
          if (args != null) {
            final playlistId = args['playlistId'] as String;
            final index = args['index'] as int?;
            final indices = (args['indices'] as List?)?.cast<int>() ??
                (index != null ? [index] : <int>[]);
            final validIndices = indices.where((i) => i >= 0).toList();
            if (validIndices.isNotEmpty) {
              await ref
                  .read(playlistServiceProvider)
                  .removeSongsFromPlaylist(playlistId, validIndices);
              _syncFullStateToSubWindow();
            }
          }
          return true;

        case 'reorder_playlist_songs':
          final args = call.arguments as Map?;
          if (args != null) {
            final playlistId = args['playlistId'] as String;
            final oldIndex = args['oldIndex'] as int;
            final newIndex = args['newIndex'] as int;
            await ref
                .read(playlistServiceProvider)
                .reorderSongsInPlaylist(playlistId, oldIndex, newIndex);
            _syncFullStateToSubWindow();
          }
          return true;

        case 'clear_playlist':
          final args = call.arguments as Map?;
          if (args != null) {
            final playlistId = args['playlistId'] as String;
            await ref.read(playlistServiceProvider).clearPlaylist(playlistId);
            _syncFullStateToSubWindow();
          }
          return true;

        case 'rename_playlist':
          final args = call.arguments as Map?;
          if (args != null) {
            final playlistId = args['playlistId'] as String;
            final name = args['name'] as String?;
            if (name != null && name.trim().isNotEmpty) {
              await ref
                  .read(playlistServiceProvider)
                  .renamePlaylist(playlistId, name.trim());
              _syncFullStateToSubWindow();
            }
          }
          return true;

        case 'delete_playlist':
          final args = call.arguments as Map?;
          if (args != null) {
            final playlistId = args['playlistId'] as String;
            await ref.read(playlistServiceProvider).deletePlaylist(playlistId);
            _syncFullStateToSubWindow();
          }
          return true;

        case 'enqueue_next':
          final songJson = call.arguments as Map?;
          if (songJson != null) {
            final song = _musicFileFromJson(Map<String, dynamic>.from(songJson));
            audio.enqueueNext([song]);
          }
          return true;

        case 'append_to_queue':
          final songJson = call.arguments as Map?;
          if (songJson != null) {
            final song = _musicFileFromJson(Map<String, dynamic>.from(songJson));
            audio.appendToQueue([song]);
          }
          return true;

        case 'dock_to_main':
          await closeQueueWindow();
          ref.read(rightQueueDrawerProvider.notifier).open();
          return true;

        case 'window_closed':
          _onSubWindowClosed();
          return true;

        default:
          return null;
      }
    });
  }

  Future<void> addPathsToPlaylist(String playlistId, List<String> paths) async {
    final songs = await resolvePathsToMusicFiles(paths);
    if (songs.isNotEmpty) {
      await ref
          .read(playlistServiceProvider)
          .addSongsToPlaylist(playlistId, songs);
      _syncFullStateToSubWindow();
    }
  }

  Future<List<MusicFile>> resolvePathsToMusicFiles(List<String> paths) async {
    final uniqueInputPaths = <String>[];
    final seenInput = <String>{};
    for (final p in paths) {
      String decoded = p;
      try {
        decoded = Uri.decodeFull(p);
      } catch (_) {}
      if (seenInput.add(decoded)) {
        uniqueInputPaths.add(decoded);
      }
    }

    if (uniqueInputPaths.isEmpty) return const [];
    final songs = <MusicFile>[];
    final db = MetadataDatabase();
    final servers = ref.read(remoteServersProvider).asData?.value ?? [];

    for (final path in uniqueInputPaths) {
      if (FileSystemEntity.isFileSync(path)) {
        if (MusicFileUtils.isMusicFilePath(path)) {
          songs.add(MusicFile(path: path, name: p.basename(path)));
        } else {
          debugPrint('[StandaloneQueue] Dropped file is not a supported music file: $path');
        }
      } else if (FileSystemEntity.isDirectorySync(path)) {
        final dir = Directory(path);
        try {
          final dirSongs = <MusicFile>[];
          await for (final item in dir.list(recursive: true, followLinks: false)) {
            if (item is File && MusicFileUtils.isMusicFilePath(item.path)) {
              dirSongs.add(MusicFile(path: item.path, name: p.basename(item.path)));
            }
          }
          dirSongs.sort((a, b) => a.path.compareTo(b.path));
          debugPrint('[StandaloneQueue] Scanned directory $path, found ${dirSongs.length} songs');
          songs.addAll(dirSongs);
        } catch (e) {
          AppLog.log('[StandaloneQueue] Error scanning directory $path: $e', mirrorToConsole: true);
        }
      } else if (RemoteMediaResolver.isRemoteUri(path)) {
        final remoteInfo = RemoteMediaResolver.parseUri(path);
        final server = servers.firstWhereOrNull((s) => s.id == remoteInfo?.serverId);
        final targetPath = remoteInfo?.trackIdOrPath ?? path;
        final isAudio = MusicFileUtils.isMusicFilePath(targetPath) ||
            (remoteInfo?.type == RemoteServerType.subsonic) ||
            (remoteInfo?.type == RemoteServerType.jellyfin);

        if (isAudio) {
          final cachedMeta = await db.getRemoteSongMetadata(path);
          if (cachedMeta != null) {
            songs.add(MusicFile(
              path: path,
              name: p.basename(targetPath),
              title: cachedMeta.title,
              artist: cachedMeta.artist,
              albumArtist: cachedMeta.albumArtist,
              album: cachedMeta.album,
              trackNumber: cachedMeta.trackNumber,
              durationMillis: cachedMeta.duration,
              thumbnailPath: cachedMeta.thumbnailPath,
              artworkPath: cachedMeta.artworkPath,
              artworkWidth: cachedMeta.artworkWidth,
              artworkHeight: cachedMeta.artworkHeight,
              themeColorsBlob: cachedMeta.themeColorsBlob,
              waveformBlob: cachedMeta.waveformBlob,
              lastModifiedTime: cachedMeta.lastModifiedTime,
            ));
          } else if (server != null) {
            songs.add(RemoteMediaResolver.buildMusicFile(
              WebDavFile(
                path: targetPath,
                name: p.basename(targetPath),
                isDirectory: false,
                contentLength: 0,
              ),
              server,
            ));
          } else {
            songs.add(MusicFile(
              path: path,
              name: p.basename(targetPath),
            ));
          }
        } else if (server != null && remoteInfo != null) {
          // Remote directory
          try {
            final password = await ref.read(remoteServersProvider.notifier).getPassword(server.id) ?? '';
            final client = server.type == RemoteServerType.smb
                ? SmbClient(server: server, password: password)
                : WebDavClient(server: server, password: password);
            final remoteFiles = await fetchAllWebDavAudioFilesRecursive(client, targetPath);
            final remoteUris = remoteFiles.map((f) => RemoteMediaResolver.buildRemoteUri(server, f.path)).toList();
            final cachedMap = await db.getSongMetadataByPaths(remoteUris);
            final remoteFolderAudios = remoteFiles
                .map((f) {
                  final uri = RemoteMediaResolver.buildRemoteUri(server, f.path);
                  return RemoteMediaResolver.buildMusicFile(f, server, metadata: cachedMap[uri]);
                })
                .toList();
            debugPrint('[StandaloneQueue] Fetched ${remoteFolderAudios.length} songs from remote folder $path');
            songs.addAll(remoteFolderAudios);
          } catch (e) {
            AppLog.log('[StandaloneQueue] Error fetching remote folder $path: $e', mirrorToConsole: true);
          }
        } else {
          songs.add(MusicFile(
            path: path,
            name: p.basename(targetPath),
          ));
        }
      } else if (path.startsWith('subsonic-artist://') ||
          path.startsWith('jellyfin-artist://')) {
        final uri = Uri.tryParse(path);
        final serverId = uri?.host ?? '';
        final artistId = uri != null && uri.pathSegments.isNotEmpty
            ? uri.pathSegments.join('/')
            : '';
        final server = servers.firstWhereOrNull((s) => s.id == serverId);
        if (server != null && artistId.isNotEmpty) {
          try {
            final password = await ref
                    .read(remoteServersProvider.notifier)
                    .getPassword(server.id) ??
                '';
            final client = RemoteMediaLibraryClient.create(
              server: server,
              password: password,
            );
            final tracks =
                await fetchSubsonicArtistTracks(client, server, artistId);
            debugPrint(
                '[StandaloneQueue] Resolved remote artist $artistId, found ${tracks.length} tracks');
            songs.addAll(tracks);
          } catch (e) {
            AppLog.log(
                '[StandaloneQueue] Error resolving remote artist $path: $e',
                mirrorToConsole: true);
          }
        }
      } else if (path.startsWith('subsonic-playlist://') ||
          path.startsWith('jellyfin-playlist://')) {
        final uri = Uri.tryParse(path);
        final serverId = uri?.host ?? '';
        final playlistId = uri != null && uri.pathSegments.isNotEmpty
            ? uri.pathSegments.join('/')
            : '';
        final server = servers.firstWhereOrNull((s) => s.id == serverId);
        if (server != null && playlistId.isNotEmpty) {
          try {
            final password = await ref
                    .read(remoteServersProvider.notifier)
                    .getPassword(server.id) ??
                '';
            final client = RemoteMediaLibraryClient.create(
              server: server,
              password: password,
            );
            final tracks =
                await fetchSubsonicPlaylistTracks(client, server, playlistId);
            debugPrint(
                '[StandaloneQueue] Resolved remote playlist $playlistId, found ${tracks.length} tracks');
            songs.addAll(tracks);
          } catch (e) {
            AppLog.log(
                '[StandaloneQueue] Error resolving remote playlist $path: $e',
                mirrorToConsole: true);
          }
        }
      } else if (path.startsWith('subsonic-album://') ||
          path.startsWith('jellyfin-album://')) {
        final uri = Uri.tryParse(path);
        final serverId = uri?.host ?? '';
        final albumId = uri != null && uri.pathSegments.isNotEmpty
            ? uri.pathSegments.join('/')
            : '';
        final server = servers.firstWhereOrNull((s) => s.id == serverId);
        if (server != null && albumId.isNotEmpty) {
          try {
            final password = await ref
                    .read(remoteServersProvider.notifier)
                    .getPassword(server.id) ??
                '';
            final client = RemoteMediaLibraryClient.create(
              server: server,
              password: password,
            );
            final tracks =
                await fetchSubsonicAlbumTracks(client, server, albumId);
            debugPrint(
                '[StandaloneQueue] Resolved remote album $albumId, found ${tracks.length} tracks');
            songs.addAll(tracks);
          } catch (e) {
            AppLog.log(
                '[StandaloneQueue] Error resolving remote album $path: $e',
                mirrorToConsole: true);
          }
        }
      } else if (path.startsWith('http://') || path.startsWith('https://')) {
        songs.add(MusicFile(path: path, name: p.basename(path)));
      } else {
        debugPrint('[StandaloneQueue] Dropped path unrecognized: $path');
      }
    }

    if (songs.isEmpty) {
      AppLog.log('[StandaloneQueue] No valid music files found from dropped paths', mirrorToConsole: true);
      debugPrint('[StandaloneQueue] No valid music files found from dropped paths');
      return const [];
    }

    final scanner = ref.read(scannerServiceProvider);

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
        } else {
          final meta = scanner.metadataMap[s.path];
          if (meta != null) {
            songs[i] = songs[i].copyWith(
              title: meta.title,
              artist: meta.artist,
              albumArtist: meta.albumArtist,
              album: meta.album,
              trackNumber: meta.trackNumber,
              durationMillis: meta.duration,
              thumbnailPath: meta.thumbnailPath,
              artworkPath: meta.artworkPath,
            );
          }
        }
      }
    } catch (e) {
      AppLog.log('[StandaloneQueue] Error enriching metadata for dropped songs: $e');
    }

    return songs;
  }

  Future<void> handleDroppedPaths(
    List<String> paths, {
    int? insertIndex,
    bool playNow = false,
  }) async {
    final songs = await resolvePathsToMusicFiles(paths);
    if (songs.isEmpty) {
      AppLog.log('[StandaloneQueue] No valid music files found from dropped paths', mirrorToConsole: true);
      debugPrint('[StandaloneQueue] No valid music files found from dropped paths');
      return;
    }

    final audio = ref.read(audioServiceProvider);
    if (insertIndex != null && insertIndex >= 0) {
      await audio.insertIntoQueueAt(insertIndex, songs);
    } else {
      await audio.appendToQueue(songs);
    }

    AppLog.log('[StandaloneQueue] Successfully added ${songs.length} songs to queue, forcing sub-window sync', mirrorToConsole: true);
    debugPrint('[StandaloneQueue] Successfully added ${songs.length} songs to queue, forcing sub-window sync');
    _syncFullStateToSubWindow();

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
    final playlistService = ref.read(playlistServiceProvider);

    _preloadQueueThumbnails(queue);

    return {
      'type': 'standalone_queue',
      'title': '播放队列 - Vynody',
      'queue': queue.map(_musicFileToJson).toList(),
      'playlists': playlistService.playlists.map((p) => {
        'id': p.id,
        'name': p.name,
        'songCount': p.songs.length,
        'isFavorite': p.id == PlaylistService.favoritePlaylistId,
        'isDefault': p.id == 'default',
        'songs': p.songs.map(_musicFileToJson).toList(),
      }).toList(),
      'currentPlaylistId': playlistService.currentPlaylist?.id,
      'currentMusic': currentMusic != null ? _musicFileToJson(currentMusic) : null,
      'currentIndex': currentIndex,
      'isPlaying': isPlaying,
      'themeMode': settings.themeMode.index,
      'accentColor': settings.themeColor.toARGB32(),
    };
  }

  Future<void> openOrFocusQueueWindow() async {
    // If the right queue drawer is currently open in the main window, close it.
    unawaited(ref.read(rightQueueDrawerProvider.notifier).close(restoreWindowSize: false));

    if (_subWindowController != null) {
      try {
        await _subWindowController!.show();
        ref.read(isStandaloneQueueWindowOpenProvider.notifier).state = true;
        _startStateListening();
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
    if (_subWindowId != null) {
      try {
        final subChannel = WindowMethodChannel(
          'vynody/standalone_queue_sub_$_subWindowId',
          mode: ChannelMode.unidirectional,
        );
        unawaited(subChannel.invokeMethod('close_window'));
      } catch (e) {
        AppLog.log('[StandaloneQueue] Error sending close_window IPC: $e');
      }
    }
    if (_subWindowController != null) {
      try {
        await _subWindowController!.hide();
      } catch (e) {
        AppLog.log('[StandaloneQueue] Error closing window: $e');
      }
    }
    _onSubWindowClosed();
  }

  void _onSubWindowClosed() {
    _stopStateListening();
    _subWindowController = null;
    _subWindowId = null;
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

    _playlistSub = ref.listen<PlaylistService>(
      playlistServiceProvider,
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
    _playlistSub?.close();
    _playlistSub = null;
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
    _windowsChangedSub?.cancel();
    _windowsChangedSub = null;
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
