import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path_provider/path_provider.dart';
import 'metadata_database.dart';
import 'theme_color_helper.dart';

class MetadataHelper {
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
    final lastModified = (await file.lastModified()).millisecondsSinceEpoch;

    // 1. 如果数据库已有记录且修改时间相同，直接返回
    final existing = await db.getSongMetadata(filePath);
    if (existing != null && existing.lastModifiedTime == lastModified) {
      return (existing, null);
    }

    try {
      Uint8List? artworkData;
      String? title;
      String? album;
      String? artist;
      int? duration;
      int? trackNumber;

      try {
        // 2. 在 Isolate 中读取文件 ID3 标签 and 原始封面字节，避免 UI 卡顿
        final metadata = await compute(readMetadataIsolate, filePath);
        title = metadata.title;
        album = metadata.album;
        artist = metadata.artist;
        duration = metadata.duration?.inMilliseconds;
        trackNumber = metadata.trackNumber;
        artworkData = metadata.pictures.isNotEmpty
            ? metadata.pictures.first.bytes
            : null;
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

        if (thumbnailPath != null) {
          try {
            // 4. 基于缩略图生成预置的主题颜色，存入数据库以备后用
            final imageProvider = FileImage(File(thumbnailPath));
            final palette = await PaletteGenerator.fromImageProvider(
              imageProvider,
              maximumColorCount: 20,
            );
            themeColorsBlob = ThemeColorHelper.paletteToBlob(palette);
          } catch (e) {
            debugPrint('Error generating theme color for $filePath: $e');
          }
        }
      }

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
      
      if (!await artworkDir.exists()) await artworkDir.create(recursive: true);
      if (!await thumbnailsDir.exists()) await thumbnailsDir.create(recursive: true);

      final baseName = '${DateTime.now().millisecondsSinceEpoch}_${p.basenameWithoutExtension(songPath)}';
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
          minWidth: 200,
          minHeight: 200,
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

      return {
        'artworkPath': saveLarge ? largePath : null,
        'thumbnailPath': thumbPath,
        'width': width,
        'height': height,
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
        width: 200,
        height: 200,
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

  /// 解码文件内嵌封面，分辨率限制在 [maxWidth] * [maxHeight]
  static Future<Uint8List?> decodeEmbeddedArtwork(
    String filePath, {
    int maxWidth = 1000,
    int maxHeight = 1000,
  }) async {
    try {
      final metadata = await compute(readMetadataIsolate, filePath);
      if (metadata.pictures.isEmpty) return null;

      final rawData = metadata.pictures.first.bytes;
      
      // 使用 Isolate 进行解码和缩放，避免 UI 卡顿
      return await compute(processAndResizeImageIsolate, {
        'data': rawData,
        'maxWidth': maxWidth,
        'maxHeight': maxHeight,
      });
    } catch (e) {
      debugPrint('Error decoding embedded artwork for $filePath: $e');
      return null;
    }
  }

  static Uint8List? processAndResizeImageIsolate(Map<String, dynamic> params) {
    try {
      final data = params['data'] as Uint8List;
      final maxWidth = params['maxWidth'] as int;
      final maxHeight = params['maxHeight'] as int;

      final originalImage = img.decodeImage(data);
      if (originalImage == null) return null;

      if (originalImage.width <= maxWidth && originalImage.height <= maxHeight) {
        return data; // 不需要缩放
      }

      final resized = img.copyResize(
        originalImage,
        width: originalImage.width > originalImage.height ? maxWidth : null,
        height: originalImage.width <= originalImage.height ? maxHeight : null,
        interpolation: img.Interpolation.average,
      );

      return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
    } catch (e) {
      return null;
    }
  }

  static AudioMetadata readMetadataIsolate(String path) {
    return readMetadata(File(path), getImage: true);
  }

  /// 生成高清封面的低清版本 (200*200) 用于背景模糊 (UI 层 ImageFiltered 处理)
  static Future<Uint8List?> generateLowResArtwork(Uint8List artworkData) async {
    return await compute(_generateLowResArtworkIsolate, artworkData);
  }

  static Uint8List? _generateLowResArtworkIsolate(Uint8List data) {
    try {
      final image = img.decodeImage(data);
      if (image == null) return null;

      // 缩放到 200*200
      final resized = img.copyResize(
        image,
        width: 200,
        height: 200,
        interpolation: img.Interpolation.average,
      );

      return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
    } catch (e) {
      return null;
    }
  }
}
