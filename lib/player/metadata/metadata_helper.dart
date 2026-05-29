import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:audio_core/audio_core.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vibe_flow/player/metadata/metadata_database.dart';
import 'package:vibe_flow/player/settings/track_artwork_theme_service.dart';

Future<Uint8List?> _generateThemeColorsBlobFromImage(img.Image image) async {
  return TrackArtworkThemeService.generateThemeColorsBlobFromImage(image);
}

Future<Map<String, dynamic>?> _buildArtworkFiles({
  required String songPath,
  required Uint8List data,
  required String supportDirPath,
  required bool saveLarge,
}) async {
  try {
    final artworkDir = Directory(p.join(supportDirPath, 'artworks'));
    final thumbnailsDir = Directory(p.join(supportDirPath, 'thumbnails'));

    if (!await artworkDir.exists()) {
      await artworkDir.create(recursive: true);
    }
    if (!await thumbnailsDir.exists()) {
      await thumbnailsDir.create(recursive: true);
    }

    final baseName =
        '${DateTime.now().millisecondsSinceEpoch}_${p.basenameWithoutExtension(songPath)}';
    final largePath = p.join(artworkDir.path, '$baseName.jpg');
    final thumbPath = p.join(thumbnailsDir.path, '${baseName}_thumb.jpg');

    final originalImage = img.decodeImage(data);
    if (originalImage == null) {
      return null;
    }

    final cropSize = originalImage.width < originalImage.height
        ? originalImage.width
        : originalImage.height;
    final offsetX = (originalImage.width - cropSize) ~/ 2;
    final offsetY = (originalImage.height - cropSize) ~/ 2;

    final square = img.copyCrop(
      originalImage,
      x: offsetX,
      y: offsetY,
      width: cropSize,
      height: cropSize,
    );

    final resized = img.copyResize(
      square,
      width: generatedArtworkThumbnailSize,
      height: generatedArtworkThumbnailSize,
      interpolation: img.Interpolation.average,
    );

    final thumbnailBytes = Uint8List.fromList(
      img.encodeJpg(resized, quality: 80),
    );
    final themeColorsBlob = await _generateThemeColorsBlobFromImage(resized);

    if (saveLarge) {
      await File(largePath).writeAsBytes(data);
    }

    await File(thumbPath).writeAsBytes(thumbnailBytes);

    return {
      'artworkPath': saveLarge ? largePath : null,
      'thumbnailPath': thumbPath,
      'width': originalImage.width,
      'height': originalImage.height,
      'themeColorsBlob': themeColorsBlob,
    };
  } catch (e) {
    debugPrint('Error saving artwork: $e');
    return null;
  }
}

/// Supported file extensions for writing metadata
const Set<String> writableMetadataExtensions = {
  '.mp3',
  '.m4a',
  '.mp4',
  '.flac',
  '.wav',
};

/// Unsupported file extensions (OGG, Opus, etc.)
const Set<String> unsupportedMetadataExtensions = {'.ogg', '.opus'};

/// Checks if a file extension supports writing metadata
bool isMetadataWritable(String filePath) {
  final ext = p.extension(filePath).toLowerCase();
  return writableMetadataExtensions.contains(ext);
}

/// Result of saving metadata to file
class SaveMetadataResult {
  final bool success;
  final String? error;
  final int unsupportedCount;
  final int savedCount;
  final List<String> unsupportedFiles;

  SaveMetadataResult({
    required this.success,
    this.error,
    this.unsupportedCount = 0,
    this.savedCount = 0,
    this.unsupportedFiles = const [],
  });
}

class MetadataHelper {
  static String _resolveText(String? value, String fallback) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return fallback;
    return trimmed;
  }

  static String _pictureTypeToAndroidLabel(PictureType type) {
    switch (type) {
      case PictureType.coverFront:
        return 'Front Cover';
      case PictureType.coverBack:
        return 'Back Cover';
      case PictureType.leafletPage:
        return 'Leaflet Page';
      case PictureType.mediaLabelCD:
        return 'Media Label CD';
      case PictureType.artistPerformer:
        return 'Artist / Performer';
      case PictureType.bandArtistLogotype:
        return 'Band Logo';
      default:
        return 'Other';
    }
  }

  static Future<bool> _writeSelectionMetadataToFile({
    required String filePath,
    required SongMetadata metadata,
    Uint8List? artworkBytes,
    String? lyrics,
    List<TrackMetadataPicture>? pictures,
  }) async {
    if (!isMetadataWritable(filePath)) {
      return false;
    }

    final controller = AudioCoreController();
    if (!controller.isInitialized) {
      try {
        await controller.initialize();
      } catch (e) {
        debugPrint('Failed to initialize audio core for metadata write: $e');
      }
    }

    final update = TrackMetadataUpdate(
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      trackNumber: metadata.trackNumber,
      genres: metadata.genres ?? const <String>[],
      lyrics: lyrics,
      pictures:
          pictures ??
          (artworkBytes == null || artworkBytes.isEmpty
              ? const <TrackMetadataPicture>[]
              : <TrackMetadataPicture>[
                  TrackMetadataPicture(
                    bytes: artworkBytes,
                    mimeType: 'image/jpeg',
                    pictureType: 'Front Cover',
                  ),
                ]),
    );

    try {
      final results = await controller.updateMetadataBatch([
        TrackMetadataWriteRequest(path: filePath, metadata: update),
      ]);
      return results.isNotEmpty && results.first;
    } catch (e) {
      debugPrint('Failed to write selection metadata to file $filePath: $e');
      return false;
    }
  }

  static Future<(SongMetadata, Uint8List?)?> saveSelectedSongMetadata({
    required String filePath,
    required String title,
    required String artist,
    required String album,
    int? duration,
    int? trackNumber,
    List<String>? genres,
    Uint8List? artworkBytes,
    String? artworkPath,
    String? thumbnailPath,
    int? artworkWidth,
    int? artworkHeight,
    SongMetadata? existingMetadata,
    bool writeToFile = true,
  }) async {
    try {
      final db = MetadataDatabase();
      final existing = existingMetadata ?? await db.getSongMetadata(filePath);
      final now = DateTime.now().millisecondsSinceEpoch;

      var resolvedArtworkPath = artworkPath ?? existing?.artworkPath;
      var resolvedThumbnailPath = thumbnailPath ?? existing?.thumbnailPath;
      var resolvedArtworkWidth = artworkWidth ?? existing?.artworkWidth;
      var resolvedArtworkHeight = artworkHeight ?? existing?.artworkHeight;
      Uint8List? themeColorsBlob = existing?.themeColorsBlob;

      final needsArtworkSave =
          artworkBytes != null &&
          artworkBytes.isNotEmpty &&
          artworkPath == null &&
          thumbnailPath == null &&
          artworkWidth == null &&
          artworkHeight == null;

      if (needsArtworkSave) {
        final supportDir = await getApplicationSupportDirectory();
        final artworkInfo = await _buildArtworkFiles(
          songPath: filePath,
          data: artworkBytes,
          supportDirPath: supportDir.path,
          saveLarge: !Platform.isWindows,
        );

        if (artworkInfo != null) {
          resolvedArtworkPath = artworkInfo['artworkPath'] as String?;
          resolvedThumbnailPath = artworkInfo['thumbnailPath'] as String?;
          resolvedArtworkWidth = artworkInfo['width'] as int?;
          resolvedArtworkHeight = artworkInfo['height'] as int?;
          themeColorsBlob = artworkInfo['themeColorsBlob'] as Uint8List?;
        } else {
          debugPrint('Failed to save artwork for selected metadata $filePath');
        }
      }

      if (artworkBytes != null && artworkBytes.isNotEmpty) {
        try {
          final decodedArtwork = img.decodeImage(artworkBytes);
          if (decodedArtwork != null) {
            themeColorsBlob = await _generateThemeColorsBlobFromImage(
              decodedArtwork,
            );
          }
        } catch (e) {
          debugPrint(
            'Error generating theme color for selected metadata $filePath: $e',
          );
        }
      }

      final base =
          existing ??
          SongMetadata(
            path: filePath,
            title: p.basenameWithoutExtension(filePath),
            album: 'Unknown Album',
            artist: 'Unknown Artist',
          );

      final updated = base.copyWith(
        title: _resolveText(title, base.title),
        artist: _resolveText(artist, base.artist),
        album: _resolveText(album, base.album),
        duration: duration ?? base.duration,
        trackNumber: trackNumber ?? base.trackNumber,
        artworkPath: resolvedArtworkPath,
        thumbnailPath: resolvedThumbnailPath,
        artworkWidth: resolvedArtworkWidth,
        artworkHeight: resolvedArtworkHeight,
        themeColorsBlob: themeColorsBlob,
        lastModifiedTime: now,
        metadataTextScanned: now,
        metadataImgScanned: artworkBytes != null && artworkBytes.isNotEmpty
            ? now
            : base.metadataImgScanned,
        createdAt: base.createdAt ?? now,
        genres: genres ?? base.genres,
      );

      if (writeToFile) {
        final fileUpdated = await _writeSelectionMetadataToFile(
          filePath: filePath,
          metadata: updated,
          artworkBytes: artworkBytes,
        );

        if (!fileUpdated) {
          return null;
        }
      }

      await db.insertOrUpdateSong(updated);
      return (updated, artworkBytes);
    } catch (e) {
      debugPrint('Error saving selected metadata for $filePath: $e');
      return null;
    }
  }

  /// 深度解析音频文件的元数据和封面信息
  ///
  /// 该方法耗时较长，通常在后台线程（Isolate）中执行，结果会存入数据库以便下次秒开。
  static Future<(SongMetadata, Uint8List?)?> processMetadata(
    String filePath, {
    int? songId,
    bool generateThumbnail = true,
  }) async {
    final db = MetadataDatabase();
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('processMetadata skipped, file missing: $filePath');
      return null;
    }
    final lastModified = (await file.lastModified()).millisecondsSinceEpoch;

    // 1. 如果数据库已有记录且修改时间相同，直接返回
    final existing = await db.getSongMetadata(filePath);
    if (existing != null && existing.lastModifiedTime == lastModified) {
      final hasArtwork =
          (existing.artworkPath?.isNotEmpty ?? false) ||
          (existing.thumbnailPath?.isNotEmpty ?? false);
      if (!generateThumbnail || hasArtwork) {
        return (existing, null);
      }
    }

    try {
      final existingArtworkPath = existing?.artworkPath;
      final existingThumbnailPath = existing?.thumbnailPath;
      final existingArtworkWidth = existing?.artworkWidth;
      final existingArtworkHeight = existing?.artworkHeight;
      final existingThemeColorsBlob = existing?.themeColorsBlob;
      Uint8List? artworkData;
      String? title;
      String? album;
      String? artist;
      int? duration;
      int? trackNumber;

      try {
        // 2. 在 Isolate 中读取文件标签；只有需要缩略图时才取封面字节
        final metadata = await compute(
          generateThumbnail
              ? readMetadataWithImageIsolate
              : readMetadataIsolate,
          filePath,
        );
        title = metadata.title;
        album = metadata.album;
        artist = metadata.artist;
        duration = metadata.duration?.inMilliseconds;
        trackNumber = metadata.trackNumber;
        artworkData = metadata.pictures.isNotEmpty
            ? metadata.pictures.first.bytes
            : null;
      } on NoMetadataParserException {
        artworkData = null;
      } catch (e) {
        debugPrint('audio_metadata_reader error for $filePath: $e');
      }

      String? artworkPath;
      String? thumbnailPath;
      int? artworkWidth;
      int? artworkHeight;
      Uint8List? themeColorsBlob;

      if (artworkData != null && generateThumbnail) {
        // 3. 处理封面图：保存原始大图并生成缩略图
        // Windows 下仅生成缩略图，不存大图
        final artworkInfo = await saveArtworkAndThumbnail(
          filePath,
          artworkData,
          saveLarge: !Platform.isWindows,
        );

        artworkPath = artworkInfo?['artworkPath'] as String?;
        thumbnailPath = artworkInfo?['thumbnailPath'] as String?;
        artworkWidth = artworkInfo?['width'] as int?;
        artworkHeight = artworkInfo?['height'] as int?;
        themeColorsBlob = artworkInfo?['themeColorsBlob'] as Uint8List?;
      } else if (!generateThumbnail && existing != null) {
        artworkPath = existingArtworkPath;
        thumbnailPath = existingThumbnailPath;
        artworkWidth = existingArtworkWidth;
        artworkHeight = existingArtworkHeight;
        themeColorsBlob = existingThemeColorsBlob;
      }

      // 如果是更新现有记录，保留原有的 createdAt；否则使用当前时间
      final createdAt =
          existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch;

      final song = SongMetadata(
        path: filePath,
        title: title ?? p.basenameWithoutExtension(filePath),
        album: album ?? 'Unknown Album',
        artist: artist ?? 'Unknown Artist',
        duration: duration,
        artworkPath: artworkPath,
        thumbnailPath: thumbnailPath,
        artworkWidth: artworkWidth,
        artworkHeight: artworkHeight,
        trackNumber: trackNumber,
        themeColorsBlob: themeColorsBlob,
        lastModifiedTime: lastModified,
        metadataTextScanned: lastModified,
        metadataImgScanned: generateThumbnail
            ? lastModified
            : existing?.metadataImgScanned,
        createdAt: createdAt,
      );

      // 5. 将解析结果存入数据库
      await db.insertOrUpdateSong(song);
      return (song, artworkData);
    } catch (e) {
      debugPrint('Error processing metadata for $filePath: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> saveArtworkAndThumbnail(
    String songPath,
    Uint8List data, {
    bool saveLarge = true,
  }) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final artworkDir = Directory(p.join(supportDir.path, 'artworks'));
      final thumbnailsDir = Directory(p.join(supportDir.path, 'thumbnails'));

      if (!await artworkDir.exists()) {
        await artworkDir.create(recursive: true);
      }
      if (!await thumbnailsDir.exists()) {
        await thumbnailsDir.create(recursive: true);
      }

      final baseName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basenameWithoutExtension(songPath)}';
      final largePath = p.join(artworkDir.path, '$baseName.jpg');
      final thumbPath = p.join(thumbnailsDir.path, '${baseName}_thumb.jpg');

      int width = 0;
      int height = 0;
      Uint8List thumbnailData;

      if (Platform.isWindows || Platform.isLinux) {
        final result = await compute(_processImageWindowsIsolate, data);
        if (result == null) return null;
        thumbnailData = result['thumbnail'] as Uint8List;
        width = result['width'] as int;
        height = result['height'] as int;
      } else {
        try {
          final buffer = await ui.ImmutableBuffer.fromUint8List(data);
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          width = descriptor.width;
          height = descriptor.height;
        } catch (_) {}

        thumbnailData = await FlutterImageCompress.compressWithList(
          data,
          minWidth: generatedArtworkThumbnailSize,
          minHeight: generatedArtworkThumbnailSize,
          quality: 80,
          format: CompressFormat.jpeg,
        );
      }

      // Save high-res original if requested
      if (saveLarge) {
        await File(largePath).writeAsBytes(data);
      }

      // Save thumbnail
      await File(thumbPath).writeAsBytes(thumbnailData);

      Uint8List? themeColorsBlob;
      try {
        final decodedThumbnail = img.decodeImage(thumbnailData);
        if (decodedThumbnail != null) {
          themeColorsBlob = await _generateThemeColorsBlobFromImage(
            decodedThumbnail,
          );
        }
      } catch (e) {
        debugPrint('Error generating theme color for $songPath: $e');
      }

      return {
        'artworkPath': saveLarge ? largePath : null,
        'thumbnailPath': thumbPath,
        'width': width,
        'height': height,
        'themeColorsBlob': themeColorsBlob,
      };
    } catch (e) {
      debugPrint('Error saving artwork: $e');
      return null;
    }
  }

  static Map<String, dynamic>? _processImageWindowsIsolate(Uint8List data) {
    try {
      final originalImage = img.decodeImage(data);
      if (originalImage == null) return null;

      final cropSize = originalImage.width < originalImage.height
          ? originalImage.width
          : originalImage.height;
      final offsetX = (originalImage.width - cropSize) ~/ 2;
      final offsetY = (originalImage.height - cropSize) ~/ 2;

      final square = img.copyCrop(
        originalImage,
        x: offsetX,
        y: offsetY,
        width: cropSize,
        height: cropSize,
      );

      final resized = img.copyResize(
        square,
        width: generatedArtworkThumbnailSize,
        height: generatedArtworkThumbnailSize,
        interpolation: img.Interpolation.average,
      );

      return {
        'thumbnail': Uint8List.fromList(img.encodeJpg(resized, quality: 80)),
        'width': originalImage.width,
        'height': originalImage.height,
      };
    } catch (e) {
      return null;
    }
  }

  static Future<void> clearThumbnails() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final thumbnailsDir = Directory(p.join(supportDir.path, 'thumbnails'));
      if (await thumbnailsDir.exists()) {
        await thumbnailsDir.delete(recursive: true);
        await thumbnailsDir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing thumbnails: $e');
    }
  }

  /// 从文件直接读取原始标签，不请求网络，不存入数据库
  static Future<SongMetadata?> readMetadataFromFile(String filePath) async {
    try {
      final metadata = await compute(readMetadataIsolate, filePath);
      return SongMetadata(
        path: filePath,
        title: metadata.title ?? p.basenameWithoutExtension(filePath),
        album: metadata.album ?? 'Unknown Album',
        artist: metadata.artist ?? 'Unknown Artist',
        duration: metadata.duration?.inMilliseconds,
        trackNumber: metadata.trackNumber,
      );
    } catch (e) {
      debugPrint('Error reading metadata from file $filePath: $e');
      return null;
    }
  }

  /// Loads metadata for playback use.
  ///
  /// This first tries the database cache. If no record exists, it falls back to
  /// reading the audio file itself, then persists the parsed metadata back into
  /// the database through [processMetadata].
  ///
  /// The returned artwork bytes are only populated when the fallback file parse
  /// was needed and the file contained embedded artwork.
  static Future<(SongMetadata, Uint8List?)?> loadMetadataForPlayback(
    String filePath, {
    bool generateThumbnail = false,
  }) async {
    final db = MetadataDatabase();
    final cached = await db.getSongMetadata(filePath);
    if (cached != null) {
      return (cached, null);
    }

    return processMetadata(filePath, generateThumbnail: generateThumbnail);
  }

  /// 解码文件内嵌封面，分辨率限制在 [maxWidth] * [maxHeight]
  static Future<Uint8List?> decodeEmbeddedArtwork(String filePath) async {
    try {
      final metadata = await compute(readMetadataWithImageIsolate, filePath);
      if (metadata.pictures.isEmpty) return null;

      return metadata.pictures.first.bytes;
    } catch (e) {
      debugPrint('Error decoding embedded artwork for $filePath: $e');
      return null;
    }
  }

  /// 探测文件内是否存在内嵌封面，不生成任何缓存文件。
  static Future<bool> hasEmbeddedArtwork(String filePath) async {
    try {
      final metadata = readMetadataIsolate(filePath);
      return metadata.hasArtwork;
    } on MetadataParserException catch (_) {
      // Probe-only API: tagless or slightly malformed files should behave like
      // "no artwork" here instead of polluting logs.
      return false;
    } on NoMetadataParserException catch (_) {
      return false;
    } catch (e) {
      debugPrint('Error probing embedded artwork for $filePath: $e');
      return false;
    }
  }

  static AudioMetadata readMetadataIsolate(String path) {
    return readMetadata(File(path), getImage: false);
  }

  static AudioMetadata readMetadataWithImageIsolate(String path) {
    return readMetadata(File(path), getImage: true);
  }

  static Future<List<Map<String, dynamic>>> readMetadataBatch(
    List<String> filePaths, {
    bool getImage = false,
  }) {
    if (filePaths.isEmpty) {
      return SynchronousFuture<List<Map<String, dynamic>>>(const []);
    }

    return compute(_readMetadataBatchIsolate, <String, dynamic>{
      'paths': filePaths,
      'getImage': getImage,
    });
  }

  static List<Map<String, dynamic>> _readMetadataBatchIsolate(
    Map<String, dynamic> args,
  ) {
    final paths = (args['paths'] as List).cast<String>();
    final getImage = args['getImage'] as bool? ?? false;
    return paths
        .map((path) {
          final file = File(path);
          try {
            final metadata = readMetadata(file, getImage: getImage);
            final lastModified = file.lastModifiedSync().millisecondsSinceEpoch;
            return <String, dynamic>{
              'path': path,
              'title': metadata.title,
              'album': metadata.album,
              'artist': metadata.artist,
              'duration': metadata.duration?.inMilliseconds,
              'trackNumber': metadata.trackNumber,
              'lastModifiedTime': lastModified,
              'hasArtwork': metadata.hasArtwork,
              'artworkBytes': getImage && metadata.pictures.isNotEmpty
                  ? metadata.pictures.first.bytes
                  : null,
              'error': null,
            };
          } catch (e) {
            final lastModified = _safeLastModifiedMillis(file);
            return <String, dynamic>{
              'path': path,
              'title': null,
              'album': null,
              'artist': null,
              'duration': null,
              'trackNumber': null,
              'lastModifiedTime': lastModified,
              'hasArtwork': false,
              'artworkBytes': null,
              'error': e.toString(),
            };
          }
        })
        .toList(growable: false);
  }

  static int? _safeLastModifiedMillis(File file) {
    try {
      return file.lastModifiedSync().millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  /// Saves metadata to a single audio file.
  /// Returns true if successful, false if the format is not supported or an error occurred.
  static Future<bool> saveMetadataToFile(
    String filePath, {
    String? title,
    String? artist,
    String? album,
    int? trackNumber,
    List<String>? genres,
    String? o3ics,
    List<Picture>? pictures,
  }) async {
    if (!isMetadataWritable(filePath)) {
      return false;
    }

    try {
      final firstPictureBytes = (pictures?.isNotEmpty ?? false)
          ? pictures!.first.bytes
          : null;
      final success = await _writeSelectionMetadataToFile(
        filePath: filePath,
        metadata: SongMetadata(
          path: filePath,
          title: title ?? p.basenameWithoutExtension(filePath),
          album: album ?? 'Unknown Album',
          artist: artist ?? 'Unknown Artist',
          trackNumber: trackNumber,
          genres: genres,
        ),
        artworkBytes: firstPictureBytes,
        lyrics: o3ics,
        pictures: pictures
            ?.map(
              (picture) => TrackMetadataPicture(
                bytes: picture.bytes,
                mimeType: picture.mimetype,
                pictureType: _pictureTypeToAndroidLabel(picture.pictureType),
              ),
            )
            .toList(),
      );
      return success;
    } catch (e) {
      debugPrint('Error saving metadata to $filePath: $e');
      return false;
    }
  }

  /// Saves metadata for multiple songs.
  /// Returns a result indicating success count, unsupported count, and errors.
  static Future<SaveMetadataResult> saveMetadataToMultipleFiles(
    List<SongMetadata> songs, {
    List<String>? o3icsList,
    List<Uint8List?>? artworkBytesList,
  }) async {
    int savedCount = 0;
    int unsupportedCount = 0;
    final unsupportedFiles = <String>[];

    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];
      final o3ics = o3icsList != null && i < o3icsList.length
          ? o3icsList[i]
          : null;
      final artworkBytes =
          artworkBytesList != null && i < artworkBytesList.length
          ? artworkBytesList[i]
          : null;

      List<Picture>? pictures;
      if (artworkBytes != null) {
        pictures = [
          Picture(artworkBytes, 'image/jpeg', PictureType.coverFront),
        ];
      }

      final success = await saveMetadataToFile(
        song.path,
        title: song.title,
        artist: song.artist,
        album: song.album,
        trackNumber: song.trackNumber,
        genres: song.genres,
        o3ics: o3ics,
        pictures: pictures,
      );

      if (success) {
        savedCount++;
      } else {
        if (isMetadataWritable(song.path)) {
          debugPrint('Failed to save metadata to ${song.path}');
        } else {
          unsupportedCount++;
          unsupportedFiles.add(song.path);
        }
      }
    }

    return SaveMetadataResult(
      success: unsupportedCount == 0,
      unsupportedCount: unsupportedCount,
      savedCount: savedCount,
      unsupportedFiles: unsupportedFiles,
    );
  }
}
