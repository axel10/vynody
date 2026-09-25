import 'package:flutter/foundation.dart';
import 'package:flutter_taglib/flutter_taglib.dart' as taglib;
import 'package:path/path.dart' as p;

import '../clients/webdav_client.dart';
import '../proxy/local_stream_proxy.dart';
import '../proxy/remote_media_resolver.dart';
import '../remote_server_models.dart';
import '../../metadata/metadata_database.dart';
import '../../metadata/metadata_helper.dart';
import '../../metadata/artwork_constants.dart';

/// Helper for asynchronously extracting and caching audio metadata from WebDAV and SMB servers
/// using lightweight HTTP Range requests via flutter_taglib.
class RemoteMetadataHelper {
  /// Fetches audio metadata for a single remote file (WebDAV or SMB) via HTTP Range requests.
  static Future<SongMetadata?> fetchSongMetadata({
    required WebDavFile file,
    required RemoteServer server,
    required String password,
    int? sourceFlags,
  }) async {
    if (!file.isAudio) return null;

    if (!taglib.TagLibFile.isSupported) {
      debugPrint('[Remote Metadata] flutter_taglib is not supported on this platform.');
      return null;
    }

    final String virtualUri;
    final String fullUrl;
    final Map<String, String>? headers;

    if (server.type == RemoteServerType.smb) {
      virtualUri = RemoteMediaResolver.buildRemoteUri(server, file.path);
      final (share, relPath) = RemoteMediaResolver.parseSmbParts(file.path);
      fullUrl = await LocalStreamProxy.instance.buildSmbStreamUrl(
        serverId: server.id,
        share: share,
        relativePath: relPath,
      );
      headers = null;
    } else {
      final client = WebDavClient(server: server, password: password);
      virtualUri = RemoteMediaResolver.buildWebDavUri(server.id, file.path);
      fullUrl = client.buildFullUrl(file.path);
      headers = client.authHeaders;
    }

    try {
      final tagData = await taglib.TagLibFile.readMetadataAsync(
        fullUrl,
        headers: headers,
        audioPropertiesStyle: taglib.TagLibAudioPropertiesStyle.fast,
        readCover: true,
        timeout: const Duration(seconds: 10),
      );

      if (tagData == null) {
        debugPrint(
          '[Remote Metadata] Skip TagLib metadata for "${file.name}": '
          'TagLib returned null (${taglib.TagLibFile.lastError ?? "read failed"}). '
          'Falling back to filename.',
        );
        final fallbackTitle = p.basenameWithoutExtension(file.name);
        final fallbackMetadata = SongMetadata(
          path: virtualUri,
          title: fallbackTitle.isNotEmpty ? fallbackTitle : file.name,
          album: 'Unknown',
          artist: 'Unknown',
          duration: null,
          trackNumber: null,
          thumbnailPath: null,
          lastModifiedTime: file.lastModified?.millisecondsSinceEpoch ?? 0,
          sourceFlags: sourceFlags ?? SongSourceFlags.remote,
        );
        final db = MetadataDatabase();
        await db.insertOrUpdateSong(fallbackMetadata);
        return fallbackMetadata;
      }

      final title = tagData.title.trim();
      final artist = tagData.artist.trim();
      final album = tagData.album.trim();
      final genre = tagData.genre.trim();
      final duration = tagData.duration.inMilliseconds;
      final trackNumber = tagData.track;

      String? savedThumbnailPath;
      String? savedArtworkPath;
      int? artworkWidth;
      int? artworkHeight;
      Uint8List? themeColorsBlob;
      try {
        if (tagData.hasCover && tagData.coverData != null && tagData.coverData!.isNotEmpty) {
          final coverBytes = tagData.coverData!;
          final artInfo = await MetadataHelper.saveArtworkAndThumbnail(
            virtualUri,
            coverBytes,
            saveLarge: false,
            thumbnailSize: vynodyArtworkThumbnailSize,
          );
          if (artInfo != null) {
            savedThumbnailPath = artInfo['thumbnailPath'] as String?;
            savedArtworkPath = artInfo['artworkPath'] as String?;
            artworkWidth = artInfo['width'] as int?;
            artworkHeight = artInfo['height'] as int?;
            themeColorsBlob = artInfo['themeColorsBlob'] as Uint8List?;
          }
        }
      } catch (e) {
        debugPrint('[Remote Metadata] Failed to save cover thumbnail for "${file.name}": $e');
      }

      final songMetadata = SongMetadata(
        path: virtualUri,
        title: title.isNotEmpty ? title : p.basenameWithoutExtension(file.name),
        album: album.isNotEmpty ? album : 'Unknown',
        artist: artist.isNotEmpty ? artist : 'Unknown',
        duration: duration > 0 ? duration : null,
        trackNumber: trackNumber > 0 ? trackNumber : null,
        thumbnailPath: savedThumbnailPath,
        artworkPath: savedArtworkPath,
        artworkWidth: artworkWidth,
        artworkHeight: artworkHeight,
        themeColorsBlob: themeColorsBlob,
        lastModifiedTime: file.lastModified?.millisecondsSinceEpoch ?? 0,
        metadataImgScanned: file.lastModified?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
        sourceFlags: sourceFlags ?? SongSourceFlags.remote,
        genres: genre.isNotEmpty ? [genre] : null,
      );

      final db = MetadataDatabase();
      await db.insertOrUpdateSong(songMetadata);

      return songMetadata;
    } catch (e) {
      debugPrint('[Remote Metadata] Error reading metadata for "${file.name}": $e. Falling back to filename.');
      final fallbackTitle = p.basenameWithoutExtension(file.name);
      final fallbackMetadata = SongMetadata(
        path: virtualUri,
        title: fallbackTitle.isNotEmpty ? fallbackTitle : file.name,
        album: 'Unknown',
        artist: 'Unknown',
        duration: null,
        trackNumber: null,
        thumbnailPath: null,
        lastModifiedTime: file.lastModified?.millisecondsSinceEpoch ?? 0,
        sourceFlags: sourceFlags ?? SongSourceFlags.remote,
      );
      try {
        final db = MetadataDatabase();
        await db.insertOrUpdateSong(fallbackMetadata);
      } catch (_) {}
      return fallbackMetadata;
    }
  }

  /// Concurrently processes a list of remote audio files (WebDAV or SMB) with a pool of workers.
  static Future<void> processBatchMetadata({
    required List<WebDavFile> files,
    required RemoteServer server,
    required String password,
    required void Function(String virtualUri, SongMetadata metadata, WebDavFile file) onMetadataLoaded,
    void Function(WebDavFile file)? onFileStart,
    int concurrency = 3,
    bool Function()? isCancelled,
  }) async {
    final audioFiles = files.where((f) => f.isAudio).toList();
    if (audioFiles.isEmpty) return;

    final queue = List<WebDavFile>.from(audioFiles);
    final workerCount = concurrency.clamp(1, 4);

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (isCancelled?.call() == true) return;
        final file = queue.removeAt(0);
        onFileStart?.call(file);

        final meta = await fetchSongMetadata(
          file: file,
          server: server,
          password: password,
        );

        if (isCancelled?.call() == true) return;

        if (meta != null) {
          final virtualUri = RemoteMediaResolver.buildRemoteUri(server, file.path);
          onMetadataLoaded(virtualUri, meta, file);
        }
      }
    }

    final workers = List.generate(
      workerCount.clamp(1, queue.length),
      (_) => worker(),
    );
    await Future.wait(workers);
  }
}

/// Backwards compatibility alias for WebDavMetadataHelper
typedef WebDavMetadataHelper = RemoteMetadataHelper;

