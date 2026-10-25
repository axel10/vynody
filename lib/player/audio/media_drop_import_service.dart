import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path/path.dart' as p;
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/clients/remote_media_library_client.dart';
import 'package:vynody/player/remote/clients/smb_client.dart';
import 'package:vynody/player/remote/clients/webdav_client.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/utils/app_log.dart';
import 'package:vynody/utils/localized_text.dart';
import 'package:vynody/utils/remote_context_menu_utils.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';

final mediaDropImportServiceProvider = Provider<MediaDropImportService>((ref) {
  return MediaDropImportService(ref);
});

/// Service responsible for resolving and importing dropped paths (local files,
/// directories, SMB/WebDAV shares, Subsonic/Jellyfin remote libraries)
/// into playback queue or playlists.
class MediaDropImportService {
  final Ref ref;

  MediaDropImportService(this.ref);

  /// Resolves input paths (local file paths, URIs, directory paths, remote identifiers)
  /// into concrete [MusicFile] objects, enriching metadata from local database or cache where available.
  Future<List<MusicFile>> resolvePathsToMusicFiles(List<String> paths) async {
    final uniqueInputPaths = <String>[];
    final seenInput = <String>{};
    for (final p in paths) {
      var clean = p;
      if (clean.startsWith('file://')) {
        try {
          clean = Uri.parse(clean).toFilePath();
        } catch (_) {}
      }
      String decoded = clean;
      try {
        decoded = Uri.decodeFull(clean);
      } catch (_) {}
      if (seenInput.add(decoded)) {
        uniqueInputPaths.add(decoded);
      }
    }

    if (uniqueInputPaths.isEmpty) return const [];
    final db = MetadataDatabase();
    final servers = ref.read(remoteServersProvider).asData?.value ?? [];
    final scanner = ref.read(scannerServiceProvider);

    final passwordCache = <String, String>{};
    Future<String> getPassword(String serverId) async {
      if (passwordCache.containsKey(serverId)) {
        return passwordCache[serverId]!;
      }
      final pass =
          await ref.read(remoteServersProvider.notifier).getPassword(serverId) ??
              '';
      passwordCache[serverId] = pass;
      return pass;
    }

    final clientCache = <String, RemoteMediaLibraryClient>{};

    final resolvedLists = await _parallelMap<String, List<MusicFile>>(
      uniqueInputPaths,
      (path) => _resolveSinglePath(
        path: path,
        db: db,
        servers: servers,
        scanner: scanner,
        getPassword: getPassword,
        clientCache: clientCache,
      ),
      concurrency: 8,
    );

    final songs = <MusicFile>[];
    for (final list in resolvedLists) {
      songs.addAll(list);
    }

    if (songs.isEmpty) {
      AppLog.log('[MediaDropImport] No valid music files found from dropped paths', mirrorToConsole: true);
      debugPrint('[MediaDropImport] No valid music files found from dropped paths');
      return const [];
    }

    try {
      final cachedMap = await db.getSongMetadataByPaths(songs.map((s) => s.path));
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
      AppLog.log('[MediaDropImport] Error enriching metadata for dropped songs: $e');
    }

    return songs;
  }

  /// Handles dropped paths by adding them to the playback queue at [insertIndex] (or end).
  ///
  /// 调用方（drop 回调）不再等待本方法，所以耗时与结果都要自己回报用户：
  /// 远程集合解析失败或读不到曲目时给错误提示，成功时给「已添加 N 首」回执。
  Future<List<MusicFile>> handleDroppedPaths(
    List<String> paths, {
    int? insertIndex,
    bool playNow = false,
  }) async {
    final hasRemoteCollection = _containsRemoteCollection(paths);
    final songs = await resolvePathsToMusicFiles(paths);
    if (songs.isEmpty) {
      if (hasRemoteCollection) _notifyDropResult(addedCount: 0, failed: true);
      return const [];
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

    if (hasRemoteCollection) {
      _notifyDropResult(addedCount: songs.length);
    }

    return songs;
  }

  /// Adds resolved paths to the specified playlist.
  Future<List<MusicFile>> addPathsToPlaylist(String playlistId, List<String> paths) async {
    final hasRemoteCollection = _containsRemoteCollection(paths);
    final songs = await resolvePathsToMusicFiles(paths);
    if (songs.isNotEmpty) {
      await ref.read(playlistServiceProvider).addSongsToPlaylist(playlistId, songs);
      if (hasRemoteCollection) {
        _notifyDropResult(addedCount: songs.length);
      }
    } else if (hasRemoteCollection) {
      _notifyDropResult(addedCount: 0, failed: true);
    }
    return songs;
  }

  /// 拖入的路径里是否包含需要联网展开的远程集合（专辑 / 艺术家 / 播放列表）。
  static bool _containsRemoteCollection(List<String> paths) =>
      paths.any((path) => RemoteCollectionRef.tryParse(path) != null);

  /// 远程集合拖放的完成回执。
  ///
  /// 走 [currentAppL10n] + oktoast，不依赖 BuildContext：drop 回调在松手瞬间
  /// 就返回了，结果回来时原 widget 可能已经重建或失焦。独立队列窗口没有
  /// OKToast 宿主时 `showToast` 会抛异常，这里静默降级。
  void _notifyDropResult({required int addedCount, bool failed = false}) {
    final l10n = currentAppL10n;
    final message = failed
        ? l10n.remoteCollectionDropFailed
        : l10n.dropAddedSongs(addedCount);
    try {
      dismissAllToast();
      showToast(message);
    } catch (_) {}
  }

  Future<List<R>> _parallelMap<T, R>(
    List<T> items,
    Future<R> Function(T item) worker, {
    int concurrency = 8,
  }) async {
    if (items.isEmpty) return [];
    final results = List<R?>.filled(items.length, null);
    var nextIndex = 0;

    Future<void> runWorker() async {
      while (true) {
        final idx = nextIndex++;
        if (idx >= items.length) break;
        results[idx] = await worker(items[idx]);
      }
    }

    final workerCount = concurrency.clamp(1, items.length);
    final workers = List.generate(
      workerCount,
      (_) => runWorker(),
    );
    await Future.wait(workers);
    return results.cast<R>();
  }

  Future<List<MusicFile>> _resolveSinglePath({
    required String path,
    required MetadataDatabase db,
    required List<RemoteServer> servers,
    required dynamic scanner,
    required Future<String> Function(String serverId) getPassword,
    required Map<String, RemoteMediaLibraryClient> clientCache,
  }) async {
    final songs = <MusicFile>[];
    if (FileSystemEntity.isFileSync(path) ||
        scanner.metadataMap.containsKey(path) ||
        MusicFileUtils.isMusicFilePath(path)) {
      if (MusicFileUtils.isMusicFilePath(path)) {
        songs.add(MusicFile(path: path, name: p.basename(path)));
      } else {
        debugPrint('[MediaDropImport] Dropped file is not a supported music file: $path');
      }
    } else if (FileSystemEntity.isDirectorySync(path)) {
      final dir = Directory(path);
      try {
        final dirSongs = <MusicFile>[];
        await for (final item in dir.list(recursive: true, followLinks: false)) {
          if (item is File &&
              !ScannerPathUtils.isHiddenOrExcludedPath(item.path, rootPath: dir.path) &&
              MusicFileUtils.isMusicFilePath(item.path)) {
            dirSongs.add(MusicFile(path: item.path, name: p.basename(item.path)));
          }
        }
        dirSongs.sort((a, b) => a.path.compareTo(b.path));
        debugPrint('[MediaDropImport] Scanned directory $path, found ${dirSongs.length} songs');
        songs.addAll(dirSongs);
      } catch (e) {
        AppLog.log('[MediaDropImport] Error scanning directory $path: $e', mirrorToConsole: true);
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
          final password = await getPassword(server.id);
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
          debugPrint('[MediaDropImport] Fetched ${remoteFolderAudios.length} songs from remote folder $path');
          songs.addAll(remoteFolderAudios);
        } catch (e) {
          AppLog.log('[MediaDropImport] Error fetching remote folder $path: $e', mirrorToConsole: true);
        }
      } else {
        songs.add(MusicFile(
          path: path,
          name: p.basename(targetPath),
        ));
      }
    } else if (RemoteCollectionRef.tryParse(path) case final ref?) {
      songs.addAll(
        await _resolveRemoteCollection(
          ref,
          servers: servers,
          getPassword: getPassword,
          clientCache: clientCache,
        ),
      );
    } else if (path.startsWith('http://') || path.startsWith('https://')) {
      songs.add(MusicFile(path: path, name: p.basename(path)));
    } else {
      debugPrint('[MediaDropImport] Dropped path unrecognized: $path');
    }
    return songs;
  }

  /// Resolves a dragged remote collection (album / artist / playlist) into its
  /// tracks.
  ///
  /// [RemoteCollectionRef] already carries the server type and kind, so this is
  /// the single place that turns a remote drag reference into songs — adding a
  /// new collection kind means extending [RemoteCollectionKind], not adding
  /// another `startsWith` branch.
  Future<List<MusicFile>> _resolveRemoteCollection(
    RemoteCollectionRef ref, {
    required List<RemoteServer> servers,
    required Future<String> Function(String serverId) getPassword,
    required Map<String, RemoteMediaLibraryClient> clientCache,
  }) async {
    final server = servers.firstWhereOrNull((s) => s.id == ref.serverId);
    if (server == null) {
      debugPrint(
          '[MediaDropImport] Remote server ${ref.serverId} not found for $ref');
      return const [];
    }

    try {
      final password = await getPassword(server.id);
      final client = clientCache.putIfAbsent(
        server.id,
        () => RemoteMediaLibraryClient.create(
          server: server,
          password: password,
        ),
      );
      final tracks = switch (ref.kind) {
        RemoteCollectionKind.album =>
          await fetchSubsonicAlbumTracks(client, server, ref.id),
        RemoteCollectionKind.artist =>
          await fetchSubsonicArtistTracks(client, server, ref.id),
        RemoteCollectionKind.playlist =>
          await fetchSubsonicPlaylistTracks(client, server, ref.id),
      };
      debugPrint(
          '[MediaDropImport] Resolved remote ${ref.kind.slug} ${ref.id}, found ${tracks.length} tracks');
      return tracks;
    } catch (e) {
      AppLog.log(
        '[MediaDropImport] Error resolving remote ${ref.kind.slug} $ref: $e',
        mirrorToConsole: true,
      );
      return const [];
    }
  }
}
