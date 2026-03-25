import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path_provider/path_provider.dart';
import 'metadata_database.dart';
import 'theme_color_helper.dart';

class MetadataHelper {
  static Future<SongMetadata?> processMetadata(
    String filePath, {
    int? songId,
  }) async {
    final db = MetadataDatabase();

    // Check if already in DB
    final existing = await db.getSongMetadata(filePath);
    if (existing != null) return existing;

    try {
      Uint8List? artworkData;
      String? title;
      String? album;
      String? artist;
      int? duration;
      int? trackNumber;

      try {
        final metadata = await MetadataGod.readMetadata(file: filePath);
        title = metadata.title;
        album = metadata.album;
        artist = metadata.artist;
        duration = (metadata.durationMs as num?)?.toInt();
        trackNumber = metadata.trackNumber;
        artworkData = metadata.picture?.data;
      } catch (e) {
        debugPrint('MetadataGod error for $filePath: $e');
        // If MetadataGod fails and we have a songId (Android), we might consider on_audio_query as fallback here, 
        // but let's keep it simple and let the caller decide if it wants to try on_audio_query first.
      }

      String? artworkPath;
      int? artworkWidth;
      int? artworkHeight;
      Uint8List? themeColorsBlob;

      if (artworkData != null) {
        final artworkInfo = await _saveCompressedArtwork(
          filePath,
          artworkData,
        );
        artworkPath = artworkInfo?['path'] as String?;
        artworkWidth = artworkInfo?['width'] as int?;
        artworkHeight = artworkInfo?['height'] as int?;

        if (artworkPath != null) {
          try {
            final imageProvider = FileImage(File(artworkPath));
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
        artworkWidth: artworkWidth,
        artworkHeight: artworkHeight,
        trackNumber: trackNumber,
        themeColorsBlob: themeColorsBlob,
      );

      await db.insertOrUpdateSong(song);
      return song;
    } catch (e) {
      debugPrint('Error processing metadata for $filePath: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _saveCompressedArtwork(
    String songPath,
    Uint8List data,
  ) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final thumbnailsDir = Directory(p.join(supportDir.path, 'thumbnails'));
      if (!await thumbnailsDir.exists()) {
        await thumbnailsDir.create(recursive: true);
      }

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basenameWithoutExtension(songPath)}.jpg';
      final targetPath = p.join(thumbnailsDir.path, fileName);

      final originalImage = img.decodeImage(data);
      if (originalImage == null) return null;

      Uint8List result;

      if (Platform.isWindows || Platform.isLinux) {
        // Use 'image' package on Windows/Linux as flutter_image_compress doesn't support them
        
        // Crop center square first to avoid stretching non-square artwork.
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

        // Resize
        final resized = img.copyResize(
          square,
          width: 200,
          height: 200,
          interpolation: img.Interpolation.average,
        );

        result = Uint8List.fromList(img.encodeJpg(resized, quality: 80));
      } else {
        // Use flutter_image_compress on supported platforms (Android, iOS, macOS)
        result = await FlutterImageCompress.compressWithList(
          data,
          minWidth: 200,
          minHeight: 200,
          quality: 80,
          format: CompressFormat.jpeg,
        );
      }

      final file = File(targetPath);
      await file.writeAsBytes(result);

      return {
        'path': targetPath,
        'width': originalImage.width,
        'height': originalImage.height,
      };
    } catch (e) {
      debugPrint('Error saving artwork: $e');
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

  /// Processes Gaussian blur in an Isolate (using compute)
  static Future<Uint8List?> blurImage(Uint8List bytes) async {
    return compute(_blurImageIsolate, bytes);
  }

  static Uint8List? _blurImageIsolate(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      // 1. Downsample for performance (50x50 is enough for a heavy blur)
      final resized = img.copyResize(image, width: 75, height: 75);

      // 2. Apply Gaussian blur
      // Radius 5 on a 50x50 image is equivalent to a much larger radius on original image
      final blurred = img.gaussianBlur(resized, radius: 3);

      // 3. Encode as JPG (fastest)
      return Uint8List.fromList(img.encodeJpg(blurred, quality: 70));
    } catch (e) {
      debugPrint('Error blurring image in isolate: $e');
      return null;
    }
  }
}
