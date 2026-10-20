import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../../models/music_file.dart';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path_provider/path_provider.dart';

import 'package:audio_core/audio_core.dart';
import '../remote_server_models.dart';
import '../remote_server_storage.dart';
import '../clients/subsonic_client.dart';
import '../clients/webdav_client.dart';
import '../clients/smb_client.dart';
import '../clients/jellyfin_client.dart';
import '../services/remote_payload_guard.dart';
import 'local_stream_proxy.dart';
import '../../metadata/metadata_database.dart';

class RemoteUriInfo {
  final RemoteServerType type;
  final String serverId;
  final String trackIdOrPath;
  final Map<String, String> queryParameters;

  const RemoteUriInfo({
    required this.type,
    required this.serverId,
    required this.trackIdOrPath,
    this.queryParameters = const {},
  });
}

class RemoteMediaResolver {
  final RemoteServerStorage storage;
  final AudioStreamCacheManager cacheManager;

  RemoteMediaResolver({
    required this.storage,
    AudioStreamCacheManager? cacheManager,
  }) : cacheManager = cacheManager ?? AudioStreamCacheManager();

  /// Checks if a file path is a remote virtual URI.
  static bool isRemoteUri(String path) {
    return path.startsWith('subsonic://') ||
        path.startsWith('webdav://') ||
        path.startsWith('smb://') ||
        path.startsWith('jellyfin://');
  }

  /// Parses a remote virtual URI.
  static RemoteUriInfo? parseUri(String uriString) {
    if (!isRemoteUri(uriString)) return null;
    try {
      final schemeEnd = uriString.indexOf('://');
      if (schemeEnd > 0) {
        final scheme = uriString.substring(0, schemeEnd).toLowerCase();
        final rest = uriString.substring(schemeEnd + 3);
        final slashIdx = rest.indexOf('/');
        final queryIdx = rest.indexOf('?');

        final serverId = slashIdx >= 0
            ? rest.substring(0, slashIdx)
            : (queryIdx >= 0 ? rest.substring(0, queryIdx) : rest);

        String rawPath = slashIdx >= 0
            ? (queryIdx >= 0
                ? rest.substring(slashIdx, queryIdx)
                : rest.substring(slashIdx))
            : '';

        Map<String, String> queryParams = const {};
        if (queryIdx >= 0) {
          final queryStr = rest.substring(queryIdx + 1);
          try {
            queryParams = Uri.splitQueryString(queryStr);
          } catch (_) {}
        }

        if (scheme == 'subsonic') {
          var trackId = rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
          try {
            trackId = Uri.decodeFull(trackId);
          } catch (_) {}
          return RemoteUriInfo(
            type: RemoteServerType.subsonic,
            serverId: serverId,
            trackIdOrPath: trackId,
            queryParameters: queryParams,
          );
        } else if (scheme == 'jellyfin') {
          var trackId = rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
          try {
            trackId = Uri.decodeFull(trackId);
          } catch (_) {}
          return RemoteUriInfo(
            type: RemoteServerType.jellyfin,
            serverId: serverId,
            trackIdOrPath: trackId,
            queryParameters: queryParams,
          );
        } else if (scheme == 'webdav') {
          var cleanPath = rawPath.isNotEmpty ? rawPath : '/';
          if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';
          try {
            cleanPath = Uri.decodeFull(cleanPath);
          } catch (_) {}
          return RemoteUriInfo(
            type: RemoteServerType.webdav,
            serverId: serverId,
            trackIdOrPath: cleanPath,
            queryParameters: queryParams,
          );
        } else if (scheme == 'smb') {
          var cleanPath = rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
          try {
            cleanPath = Uri.decodeFull(cleanPath);
          } catch (_) {}
          return RemoteUriInfo(
            type: RemoteServerType.smb,
            serverId: serverId,
            trackIdOrPath: cleanPath,
            queryParameters: queryParams,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Builds a Subsonic virtual URI.
  static String buildSubsonicUri(String serverId, String trackId) {
    return 'subsonic://$serverId/$trackId';
  }

  /// Builds a Jellyfin virtual URI.
  static String buildJellyfinUri(String serverId, String trackId) {
    return 'jellyfin://$serverId/$trackId';
  }

  /// Extracts remote track ID from a [MusicFile] or URI path for any remote server.
  static String? extractTrackId(MusicFile song) {
    final info = parseUri(song.path);
    if (info != null && info.trackIdOrPath.isNotEmpty) {
      return info.trackIdOrPath;
    }
    return extractSubsonicTrackId(song);
  }

  /// Extracts Subsonic track ID from a [MusicFile] or URI path.
  static String? extractSubsonicTrackId(MusicFile song) {
    final info = parseUri(song.path);
    if (info != null &&
        info.type == RemoteServerType.subsonic &&
        info.trackIdOrPath.isNotEmpty) {
      return info.trackIdOrPath;
    }
    if (song.path.startsWith('subsonic://')) {
      final uri = Uri.tryParse(song.path) ?? Uri.tryParse(Uri.encodeFull(song.path));
      if (uri != null && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.join('/');
      }
    }
    if (song.path.contains('/track_')) {
      return song.path.split('/track_').last;
    }
    if (song.id != null && song.id! > 0) {
      return song.id.toString();
    }
    return null;
  }

  /// Builds a WebDAV virtual URI.
  static String buildWebDavUri(String serverId, String relativePath) {
    var clean = relativePath.trim();
    if (!clean.startsWith('/')) clean = '/$clean';
    return 'webdav://$serverId$clean';
  }

  /// Builds a virtual URI for either WebDAV or SMB remote servers.
  static String buildRemoteUri(RemoteServer server, String relativePath) {
    var clean = relativePath.trim();
    if (!clean.startsWith('/')) clean = '/$clean';
    if (server.type == RemoteServerType.smb) {
      return 'smb://${server.id}$clean';
    }
    return 'webdav://${server.id}$clean';
  }

  /// Builds an SMB virtual URI.
  static String buildSmbUri(String serverId, String share, String relativePath) {
    var cleanShare = share.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    var cleanPath = relativePath.trim();
    if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);
    return 'smb://$serverId/$cleanShare/$cleanPath';
  }

  /// Parses SMB path segments (share, relativePath) from trackIdOrPath.
  static (String share, String relativePath) parseSmbParts(String trackIdOrPath) {
    var clean = trackIdOrPath.startsWith('/') ? trackIdOrPath.substring(1) : trackIdOrPath;
    final slashIdx = clean.indexOf('/');
    if (slashIdx >= 0) {
      final share = clean.substring(0, slashIdx);
      final path = clean.substring(slashIdx + 1);
      return (share, path);
    }
    return (clean, '');
  }

  /// Converts a cacheKey (e.g. `serverId:path`) back to its virtual URI (`webdav://...` or `subsonic://...` or `smb://...` or `jellyfin://...`).
  static String? uriFromCacheKey(String cacheKey, [RemoteServerStorage? storage]) {
    final idx = cacheKey.indexOf(':');
    if (idx <= 0) return null;
    final serverId = cacheKey.substring(0, idx);
    var trackIdOrPath = cacheKey.substring(idx + 1);
    try {
      trackIdOrPath = Uri.decodeFull(trackIdOrPath);
    } catch (_) {}

    if (storage != null) {
      final servers = storage.loadServers();
      final server = servers.cast<RemoteServer?>().firstWhere(
            (s) => s?.id == serverId,
            orElse: () => null,
          );
      if (server != null) {
        if (server.type == RemoteServerType.smb) {
          final clean = trackIdOrPath.startsWith('/') ? trackIdOrPath.substring(1) : trackIdOrPath;
          return 'smb://$serverId/$clean';
        } else if (server.type == RemoteServerType.webdav) {
          return buildWebDavUri(serverId, trackIdOrPath);
        } else if (server.type == RemoteServerType.jellyfin) {
          return buildJellyfinUri(serverId, trackIdOrPath);
        } else {
          return buildSubsonicUri(serverId, trackIdOrPath);
        }
      }
    }

    if (trackIdOrPath.startsWith('/')) {
      return buildWebDavUri(serverId, trackIdOrPath);
    } else if (trackIdOrPath.contains('/')) {
      return 'smb://$serverId/$trackIdOrPath';
    } else {
      return buildSubsonicUri(serverId, trackIdOrPath);
    }
  }

  /// Resolves a remote virtual URI into a [ResolvedAudioUri] with URL, headers, and cacheKey for [AudioCoreController].
  Future<ResolvedAudioUri> resolvePlayableSource(String remoteUri, {int? maxBitRate}) async {
    final info = parseUri(remoteUri);
    if (info == null) {
      return ResolvedAudioUri(uri: remoteUri);
    }

    final cacheKey = '${info.serverId}:${info.trackIdOrPath}';
    if (await cacheManager.isTrackCached(cacheKey)) {
      final cachedFile = await cacheManager.getCacheFile(cacheKey);
      if (await cachedFile.exists() && await cachedFile.length() > 0) {
        await cacheManager.touchCacheFile(cachedFile);
        return ResolvedAudioUri(
          uri: cachedFile.path,
          cacheKey: cacheKey,
        );
      }
    }

    final servers = storage.loadServers();
    final server = servers.firstWhere(
      (s) => s.id == info.serverId,
      orElse: () => throw StateError('Server with ID ${info.serverId} not found'),
    );

    final password = await storage.getPassword(server.id) ?? '';

    if (info.type == RemoteServerType.subsonic) {
      final client = SubsonicClient(server: server, password: password);
      final streamUrl = client.buildStreamUrl(
        info.trackIdOrPath,
        maxBitRate: maxBitRate ?? server.maxBitRate,
      );

      return ResolvedAudioUri(
        uri: streamUrl,
        cacheKey: '${server.id}:${info.trackIdOrPath}',
      );
    } else if (info.type == RemoteServerType.jellyfin) {
      final client = JellyfinClient(server: server, password: password);
      await client.authenticate();
      final streamUrl = client.buildStreamUrl(
        info.trackIdOrPath,
        maxBitRate: maxBitRate ?? server.maxBitRate,
      );

      return ResolvedAudioUri(
        uri: streamUrl,
        cacheKey: '${server.id}:${info.trackIdOrPath}',
      );
    } else if (info.type == RemoteServerType.smb) {
      final parts = parseSmbParts(info.trackIdOrPath);
      final streamUrl = await LocalStreamProxy.instance.buildSmbStreamUrl(
        serverId: server.id,
        share: parts.$1,
        relativePath: parts.$2,
      );

      return ResolvedAudioUri(
        uri: streamUrl,
        cacheKey: '${server.id}:${info.trackIdOrPath}',
      );
    } else {
      final client = WebDavClient(server: server, password: password);
      final streamUrl = client.buildStreamUrl(info.trackIdOrPath);

      return ResolvedAudioUri(
        uri: streamUrl,
        headers: client.authHeaders,
        cacheKey: '${server.id}:${info.trackIdOrPath}',
      );
    }
  }

  /// Resolves a remote virtual URI into a local cached audio file path (downloading if necessary).
  Future<String> resolvePlayableLocalPath(String remoteUri, {int? maxBitRate}) async {
    final info = parseUri(remoteUri);
    if (info == null) {
      return remoteUri;
    }

    final resolved = await resolvePlayableSource(remoteUri, maxBitRate: maxBitRate);
    final cacheKey = resolved.cacheKey ?? remoteUri;

    final cached = await cacheManager.ensureTrackCached(
      cacheKey: cacheKey,
      remoteUrl: resolved.uri,
      headers: resolved.headers,
    );
    return cached.path;
  }

  /// Synchronously returns the deterministic local cache file path for a remote URI.
  String resolvePlayableLocalPathSync(String remoteUri) {
    final info = parseUri(remoteUri);
    if (info == null) return remoteUri;

    final dir = cacheManager.cacheDirectorySync;
    final hash = md5.convert(utf8.encode('${info.serverId}:${info.trackIdOrPath}')).toString();
    var ext = p.extension(info.trackIdOrPath);
    if (ext.contains('?')) {
      ext = ext.split('?').first;
    }
    if (ext.isEmpty || ext.length > 6 || !ext.startsWith('.')) {
      ext = '.cache';
    }
    final primaryPath = p.join(dir.path, '$hash$ext');
    if (ext != '.cache' && !File(primaryPath).existsSync()) {
      final legacyPath = p.join(dir.path, '$hash.cache');
      if (File(legacyPath).existsSync()) {
        return legacyPath;
      }
    }
    return primaryPath;
  }

  /// Constructs a [MusicFile] model from a Subsonic track JSON object.
  static MusicFile buildMusicFileFromSubsonic(
    Map<String, dynamic> trackJson,
    RemoteServer server,
  ) {
    final trackId = trackJson['id'] as String? ?? '';
    final title = trackJson['title'] as String? ?? '';
    final artist = trackJson['artist'] as String?;
    final albumArtist = extractAlbumArtist(trackJson);
    final album = trackJson['album'] as String?;
    final trackNumber = trackJson['track'] as int?;
    final durationSeconds = trackJson['duration'] as int? ?? 0;
    final coverArt = trackJson['coverArt'] as String?;
    final suffix = trackJson['suffix'] as String? ?? 'mp3';

    final effectiveCoverArt = (coverArt != null && coverArt.isNotEmpty)
        ? coverArt
        : (trackId.isNotEmpty ? trackId : null);

    final uri = buildSubsonicUri(server.id, trackId);
    final year = trackJson['year'] as int?;
    final genre = trackJson['genre'] as String?;
    final genres = (genre != null && genre.trim().isNotEmpty)
        ? genre
            .split(RegExp(r'[;,/、\\|]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
        : null;

    return MusicFile(
      path: uri,
      name: '$title.$suffix',
      title: title,
      artist: artist,
      albumArtist: albumArtist,
      album: album,
      trackNumber: trackNumber,
      durationMillis: durationSeconds * 1000,
      artworkPath: effectiveCoverArt != null
          ? 'subsonic-cover://${server.id}/$effectiveCoverArt'
          : null,
      isMissing: false,
      year: year != null && year > 0 ? year : null,
      genres: genres,
    );
  }

  /// Resolves the album-level artist of a Subsonic / OpenSubsonic song json.
  ///
  /// 合辑（Various Artists）里每首歌的 `artist` 都不同，只有专辑艺术家是统一的，
  /// 下载时按它分层才不会把一张专辑拆成一堆目录。
  /// 优先级：`displayAlbumArtist`（OpenSubsonic）→ `albumArtists[0].name` → `albumArtist`（旧字段）。
  static String? extractAlbumArtist(Map<String, dynamic> trackJson) {
    final display = trackJson['displayAlbumArtist'];
    if (display is String && display.trim().isNotEmpty) {
      return display.trim();
    }

    final albumArtists = trackJson['albumArtists'];
    if (albumArtists is List && albumArtists.isNotEmpty) {
      final first = albumArtists.first;
      if (first is Map) {
        final name = first['name'];
        if (name is String && name.trim().isNotEmpty) return name.trim();
      }
    }

    final legacy = trackJson['albumArtist'] ?? trackJson['AlbumArtist'];
    if (legacy is String && legacy.trim().isNotEmpty) return legacy.trim();

    return null;
  }

  /// Constructs a [MusicFile] model from a Jellyfin track JSON object.
  static MusicFile buildMusicFileFromJellyfin(
    Map<String, dynamic> trackJson,
    RemoteServer server,
  ) {
    final trackId = trackJson['id'] as String? ?? '';
    final title = trackJson['title'] as String? ?? trackJson['name'] as String? ?? '';
    final artist = trackJson['artist'] as String?;
    final albumArtist = extractAlbumArtist(trackJson);
    final album = trackJson['album'] as String?;
    final trackNumber = trackJson['track'] as int?;
    final durationSeconds = trackJson['duration'] as int? ?? 0;
    final coverArt = trackJson['coverArt'] as String?;
    final suffix = trackJson['suffix'] as String? ?? 'mp3';

    final effectiveCoverArt = (coverArt != null && coverArt.isNotEmpty)
        ? coverArt
        : (trackId.isNotEmpty ? trackId : null);

    final uri = buildJellyfinUri(server.id, trackId);
    final year = trackJson['ProductionYear'] as int? ?? trackJson['year'] as int?;
    List<String>? genres;
    if (trackJson['Genres'] is List) {
      genres = (trackJson['Genres'] as List)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    } else if (trackJson['genre'] is String && (trackJson['genre'] as String).trim().isNotEmpty) {
      genres = (trackJson['genre'] as String)
          .split(RegExp(r'[;,/、\\|]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    }

    return MusicFile(
      path: uri,
      name: '$title.$suffix',
      title: title,
      artist: artist,
      albumArtist: albumArtist,
      album: album,
      trackNumber: trackNumber,
      durationMillis: durationSeconds * 1000,
      artworkPath: effectiveCoverArt != null
          ? 'jellyfin-cover://${server.id}/$effectiveCoverArt'
          : null,
      isMissing: false,
      year: year != null && year > 0 ? year : null,
      genres: genres,
    );
  }

  /// Constructs a [MusicFile] model from a [WebDavFile] for any remote server (WebDAV / SMB).
  static MusicFile buildMusicFile(
    WebDavFile file,
    RemoteServer server, {
    SongMetadata? metadata,
  }) {
    final uri = buildRemoteUri(server, file.path);
    final fallbackTitle = p.basenameWithoutExtension(file.name);

    return MusicFile(
      path: uri,
      name: file.name,
      title: metadata != null && metadata.title.isNotEmpty ? metadata.title : fallbackTitle,
      artist: metadata != null && metadata.artist.isNotEmpty && metadata.artist != 'Unknown' ? metadata.artist : null,
      album: metadata != null && metadata.album.isNotEmpty && metadata.album != 'Unknown' ? metadata.album : null,
      trackNumber: metadata?.trackNumber,
      durationMillis: metadata?.duration,
      thumbnailPath: metadata?.thumbnailPath,
      artworkPath: metadata?.artworkPath,
      isMissing: false,
      year: metadata?.year,
      genres: metadata?.genres,
    );
  }

  /// Constructs a [MusicFile] model from a [WebDavFile].
  static MusicFile buildMusicFileFromWebDav(
    WebDavFile file,
    RemoteServer server, {
    SongMetadata? metadata,
  }) => buildMusicFile(file, server, metadata: metadata);

  /// Constructs a [MusicFile] model from an [SmbFile].
  static MusicFile buildMusicFileFromSmb(
    SmbFile file,
    RemoteServer server, {
    SongMetadata? metadata,
  }) {
    final uri = buildSmbUri(server.id, file.share, file.path);
    final fallbackTitle = p.basenameWithoutExtension(file.name);

    return MusicFile(
      path: uri,
      name: file.name,
      title: metadata != null && metadata.title.isNotEmpty ? metadata.title : fallbackTitle,
      artist: metadata != null && metadata.artist.isNotEmpty && metadata.artist != 'Unknown' ? metadata.artist : null,
      album: metadata != null && metadata.album.isNotEmpty && metadata.album != 'Unknown' ? metadata.album : null,
      trackNumber: metadata?.trackNumber,
      durationMillis: metadata?.duration,
      thumbnailPath: metadata?.thumbnailPath,
      artworkPath: metadata?.artworkPath,
      isMissing: false,
    );
  }

  /// Returns the artwork image URL if available for the given remote song.
  Future<String?> getArtworkUrl(MusicFile song, {int size = 400}) async {
    return getArtworkUrlFromUri(song.path, coverArtId: song.artworkPath, size: size);
  }

  /// Returns the artwork image URL if available for the given remote URI or cover art ID.
  Future<String?> getArtworkUrlFromUri(String remotePath, {String? coverArtId, int size = 400}) async {
    final info = parseUri(remotePath);
    if (info == null) return null;

    final servers = storage.loadServers();
    final server = servers.firstWhereOrNull((s) => s.id == info.serverId);
    if (server == null) return null;
    final password = await storage.getPassword(server.id) ?? '';

    if (info.type == RemoteServerType.subsonic) {
      var coverId = (coverArtId != null && coverArtId.isNotEmpty)
          ? coverArtId.replaceFirst('subsonic-cover://', '')
          : info.trackIdOrPath;
      if (coverId.startsWith('${server.id}/')) {
        coverId = coverId.substring('${server.id}/'.length);
      }
      final client = SubsonicClient(server: server, password: password);
      return client.buildCoverArtUrl(coverId, size: size);
    } else if (info.type == RemoteServerType.jellyfin) {
      var coverId = (coverArtId != null && coverArtId.isNotEmpty)
          ? coverArtId.replaceFirst('jellyfin-cover://', '')
          : info.trackIdOrPath;
      if (coverId.startsWith('${server.id}/')) {
        coverId = coverId.substring('${server.id}/'.length);
      }
      final client = JellyfinClient(server: server, password: password);
      return client.buildCoverArtUrl(coverId, size: size);
    }
    return null;
  }

  /// Fetches raw artwork bytes for the given remote URI or cover art ID.
  Future<Uint8List?> getArtworkBytes(String remotePath, {String? coverArtId, int size = 500}) async {
    final info = parseUri(remotePath);
    if (info == null) return null;

    final servers = storage.loadServers();
    final server = servers.firstWhereOrNull((s) => s.id == info.serverId);
    if (server == null) return null;
    final password = await storage.getPassword(server.id) ?? '';

    if (info.type == RemoteServerType.subsonic) {
      var resolvedCoverId = (coverArtId != null && coverArtId.isNotEmpty)
          ? coverArtId.replaceFirst('subsonic-cover://', '')
          : info.trackIdOrPath;
      if (resolvedCoverId.startsWith('${server.id}/')) {
        resolvedCoverId = resolvedCoverId.substring('${server.id}/'.length);
      }
      final client = SubsonicClient(server: server, password: password);
      return client.getCoverArtBytes(resolvedCoverId, size: size);
    } else if (info.type == RemoteServerType.jellyfin) {
      var resolvedCoverId = (coverArtId != null && coverArtId.isNotEmpty)
          ? coverArtId.replaceFirst('jellyfin-cover://', '')
          : info.trackIdOrPath;
      if (resolvedCoverId.startsWith('${server.id}/')) {
        resolvedCoverId = resolvedCoverId.substring('${server.id}/'.length);
      }
      final client = JellyfinClient(server: server, password: password);
      return client.getCoverArtBytes(resolvedCoverId, size: size);
    }
    return null;
  }

  /// Fetches lyrics for the given remote song.
  Future<String?> fetchLyrics(MusicFile song) async {
    final info = parseUri(song.path);
    if (info == null) return null;

    final servers = storage.loadServers();
    final server = servers.firstWhere(
      (s) => s.id == info.serverId,
      orElse: () => throw StateError('Server not found'),
    );
    final password = await storage.getPassword(server.id) ?? '';

    if (info.type == RemoteServerType.subsonic) {
      final client = SubsonicClient(server: server, password: password);
      return client.getLyrics(
        id: info.trackIdOrPath,
        artist: song.artist,
        title: song.title ?? song.name,
      );
    } else if (info.type == RemoteServerType.jellyfin) {
      final client = JellyfinClient(server: server, password: password);
      return client.getLyrics(info.trackIdOrPath);
    } else if (info.type == RemoteServerType.webdav) {
      final client = WebDavClient(server: server, password: password);
      // Attempt to find companion .lrc file in the same directory
      final audioPath = info.trackIdOrPath;
      final lrcPath = '${p.withoutExtension(audioPath)}.lrc';
      return client.getFileContent(lrcPath);
    }
    return null;
  }

  /// Downloads or copies a cached remote track to a temporary file for local operations (e.g. transcoding).
  /// Returns the temporary [File].
  Future<File> downloadRemoteTrackToTempFile(
    MusicFile song, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final info = parseUri(song.path);
    if (info == null) {
      throw ArgumentError('Not a remote track: ${song.path}');
    }

    final servers = storage.loadServers();
    final server = servers.firstWhere(
      (s) => s.id == info.serverId,
      orElse: () => throw StateError('Server with ID ${info.serverId} not found'),
    );

    final cacheKey = '${server.id}:${info.trackIdOrPath}';

    final tempDir = await getTemporaryDirectory();
    final uniqueId = '${DateTime.now().microsecondsSinceEpoch}_${song.hashCode.abs()}';
    final taskTempDir = Directory(p.join(tempDir.path, 'transcode_temp', uniqueId));
    if (!await taskTempDir.exists()) {
      await taskTempDir.create(recursive: true);
    }

    // Determine extension
    String ext = p.extension(song.name);
    if (ext.isEmpty && info.trackIdOrPath.contains('.')) {
      ext = p.extension(info.trackIdOrPath);
    }
    if (ext.isEmpty) {
      ext = '.tmp';
    }

    final baseName = p.basenameWithoutExtension(song.name.isNotEmpty ? song.name : song.displayName);
    final sanitizedBaseName = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final tempFilePath = p.join(taskTempDir.path, '$sanitizedBaseName$ext');
    final tempFile = File(tempFilePath);

    // 1. Check if audio is already cached in AudioStreamCacheManager
    if (await cacheManager.isTrackCached(cacheKey)) {
      final cachedFile = await cacheManager.getCacheFile(cacheKey);
      if (await cachedFile.exists() && await cachedFile.length() > 0) {
        await cachedFile.copy(tempFile.path);
        onProgress?.call(await tempFile.length(), await tempFile.length());
        return tempFile;
      }
    }

    // 2. Download from remote server
    final password = await storage.getPassword(server.id) ?? '';
    String downloadUrl;
    Map<String, String>? headers;

    // 每种协议必须用各自的客户端：Jellyfin 的曲目 id 不是路径，SMB 也不是
    // HTTP 资源，落到 WebDavClient 只会拼出一个必然 404 的 URL。
    if (info.type == RemoteServerType.subsonic) {
      final client = SubsonicClient(server: server, password: password);
      downloadUrl = client.buildDownloadUrl(info.trackIdOrPath);
    } else if (info.type == RemoteServerType.jellyfin) {
      final client = JellyfinClient(server: server, password: password);
      await client.authenticate();
      // maxBitRate: 0 → static=true，取原文件。转码 / AI 分析要的是源音频，
      // 拿服务端转码后的副本既降质又要多转一次。
      downloadUrl = client.buildStreamUrl(info.trackIdOrPath, maxBitRate: 0);
    } else if (info.type == RemoteServerType.smb) {
      final parts = parseSmbParts(info.trackIdOrPath);
      downloadUrl = await LocalStreamProxy.instance.buildSmbStreamUrl(
        serverId: server.id,
        share: parts.$1,
        relativePath: parts.$2,
      );
    } else {
      final client = WebDavClient(server: server, password: password);
      downloadUrl = client.buildStreamUrl(info.trackIdOrPath);
      headers = client.authHeaders;
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 10),
        headers: headers,
      ),
    );

    if (server.ignoreSsl) {
      final adapter = dio.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      }
    }

    final response = await dio.download(
      downloadUrl,
      tempFile.path,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );

    // 服务端失败同样是 200，只是响应体换成失败 JSON；反向代理出错时更可能是
    // 一张 HTML 错误页。不识别的话，转码/AI 分析拿到的是一个网页，报错会指向
    // ffmpeg / 音频解析器，掩盖真实原因。
    final payloadError = RemotePayloadGuard.inspect(
      tempFile,
      contentType: response.headers.value(HttpHeaders.contentTypeHeader),
      parseSubsonicError: info.type == RemoteServerType.subsonic,
    );
    if (payloadError != null) {
      try {
        await taskTempDir.delete(recursive: true);
      } catch (_) {}
      throw payloadError;
    }

    return tempFile;
  }
}

