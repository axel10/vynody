import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_taglib/flutter_taglib.dart' as taglib;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

import '../clients/smb_client.dart';
import '../proxy/local_stream_proxy.dart';
import '../proxy/remote_media_resolver.dart';
import '../remote_server_models.dart';
import '../../metadata/metadata_database.dart';

/// Helper for asynchronously extracting and caching audio metadata from SMB servers
/// using lightweight HTTP Range requests through [LocalStreamProxy] via [flutter_taglib].
class SmbMetadataHelper {
  /// Fetches audio metadata for a single SMB file via LocalStreamProxy HTTP Range requests.
  static Future<SongMetadata?> fetchSmbSongMetadata({
    required SmbFile file,
    required RemoteServer server,
  }) async {
    if (!file.isAudio) return null;

    final virtualUri = RemoteMediaResolver.buildSmbUri(server.id, file.share, file.path);
    final fullUrl = await LocalStreamProxy.instance.buildSmbStreamUrl(
      serverId: server.id,
      share: file.share,
      relativePath: file.path,
    );

    if (!taglib.TagLibFile.isSupported) {
      debugPrint('[SMB Metadata] flutter_taglib is not supported on this platform.');
      return null;
    }

    try {
      final tagData = await taglib.TagLibFile.readMetadataAsync(
        fullUrl,
        audioPropertiesStyle: taglib.TagLibAudioPropertiesStyle.fast,
        readCover: true,
        timeout: const Duration(seconds: 10),
      );

      if (tagData == null) {
        debugPrint(
          '[SMB Metadata] Skip metadata for "${file.name}": '
          'TagLib returned null (${taglib.TagLibFile.lastError ?? "read failed"}). '
          'Falling back to filename.',
        );
        return null;
      }

      final title = tagData.title.trim();
      final artist = tagData.artist.trim();
      final album = tagData.album.trim();
      final genre = tagData.genre.trim();
      final duration = tagData.duration.inMilliseconds;
      final trackNumber = tagData.track;

      String? savedThumbnailPath;
      try {
        if (tagData.hasCover && tagData.coverData != null && tagData.coverData!.isNotEmpty) {
          final coverBytes = tagData.coverData!;
          final md5Hex = md5.convert(coverBytes).toString();
          final supportDir = await getApplicationSupportDirectory();
          final thumbnailsDir = Directory(p.join(supportDir.path, 'thumbnails'));
          if (!thumbnailsDir.existsSync()) {
            await thumbnailsDir.create(recursive: true);
          }
          final thumbFile = File(p.join(thumbnailsDir.path, '${md5Hex}_thumb.jpg'));
          if (!thumbFile.existsSync()) {
            await thumbFile.writeAsBytes(coverBytes);
          }
          savedThumbnailPath = thumbFile.path;

          final db = MetadataDatabase();
          await db.insertOrUpdateArtworkCache(
            ArtworkCacheRecord(
              md5: md5Hex,
              thumbnailPath: savedThumbnailPath,
              updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        }
      } catch (e) {
        debugPrint('[SMB Metadata] Failed to save cover thumbnail for "${file.name}": $e');
      }

      final songMetadata = SongMetadata(
        path: virtualUri,
        title: title.isNotEmpty ? title : p.basenameWithoutExtension(file.name),
        album: album.isNotEmpty ? album : 'Unknown',
        artist: artist.isNotEmpty ? artist : 'Unknown',
        duration: duration > 0 ? duration : null,
        trackNumber: trackNumber > 0 ? trackNumber : null,
        thumbnailPath: savedThumbnailPath,
        lastModifiedTime: file.lastModified?.millisecondsSinceEpoch ?? 0,
        genres: genre.isNotEmpty ? [genre] : null,
      );

      final db = MetadataDatabase();
      await db.insertOrUpdateSong(songMetadata);

      return songMetadata;
    } catch (e) {
      debugPrint('[SMB Metadata] Error reading metadata for "${file.name}": $e');
      return null;
    }
  }

  /// Concurrently processes a list of SMB audio files with a pool of workers.
  static Future<void> processBatchMetadata({
    required List<SmbFile> files,
    required RemoteServer server,
    required void Function(String virtualUri, SongMetadata metadata) onMetadataLoaded,
    int concurrency = 3,
    bool Function()? isCancelled,
  }) async {
    final audioFiles = files.where((f) => f.isAudio).toList();
    if (audioFiles.isEmpty) return;

    final queue = List<SmbFile>.from(audioFiles);
    final workerCount = concurrency.clamp(1, 4);

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (isCancelled?.call() == true) return;
        final file = queue.removeAt(0);

        final meta = await fetchSmbSongMetadata(
          file: file,
          server: server,
        );

        if (isCancelled?.call() == true) return;

        if (meta != null) {
          final virtualUri = RemoteMediaResolver.buildSmbUri(server.id, file.share, file.path);
          onMetadataLoaded(virtualUri, meta);
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
