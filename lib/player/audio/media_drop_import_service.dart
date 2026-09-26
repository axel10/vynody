import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/clients/remote_media_library_client.dart';
import 'package:vynody/player/remote/clients/smb_client.dart';
import 'package:vynody/player/remote/clients/webdav_client.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/utils/app_log.dart';
import 'package:vynody/utils/remote_context_menu_utils.dart';

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
    final songs = <MusicFile>[];
    final db = MetadataDatabase();
    final servers = ref.read(remoteServersProvider).asData?.value ?? [];
    final scanner = ref.read(scannerServiceProvider);

    for (final path in uniqueInputPaths) {
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
            if (item is File && MusicFileUtils.isMusicFilePath(item.path)) {
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
                '[MediaDropImport] Resolved remote artist $artistId, found ${tracks.length} tracks');
            songs.addAll(tracks);
          } catch (e) {
            AppLog.log(
                '[MediaDropImport] Error resolving remote artist $path: $e',
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
                '[MediaDropImport] Resolved remote playlist $playlistId, found ${tracks.length} tracks');
            songs.addAll(tracks);
          } catch (e) {
            AppLog.log(
                '[MediaDropImport] Error resolving remote playlist $path: $e',
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
                '[MediaDropImport] Resolved remote album $albumId, found ${tracks.length} tracks');
            songs.addAll(tracks);
          } catch (e) {
            AppLog.log(
                '[MediaDropImport] Error resolving remote album $path: $e',
                mirrorToConsole: true);
          }
        }
      } else if (path.startsWith('http://') || path.startsWith('https://')) {
        songs.add(MusicFile(path: path, name: p.basename(path)));
      } else {
        debugPrint('[MediaDropImport] Dropped path unrecognized: $path');
      }
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
  Future<List<MusicFile>> handleDroppedPaths(
    List<String> paths, {
    int? insertIndex,
    bool playNow = false,
  }) async {
    final songs = await resolvePathsToMusicFiles(paths);
    if (songs.isEmpty) {
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

    return songs;
  }

  /// Adds resolved paths to the specified playlist.
  Future<List<MusicFile>> addPathsToPlaylist(String playlistId, List<String> paths) async {
    final songs = await resolvePathsToMusicFiles(paths);
    if (songs.isNotEmpty) {
      await ref.read(playlistServiceProvider).addSongsToPlaylist(playlistId, songs);
    }
    return songs;
  }
}
