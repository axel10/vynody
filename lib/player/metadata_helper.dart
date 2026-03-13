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
  static Future<SongMetadata?> processMetadata(String filePath) async {
    final db = MetadataDatabase();

    // Check if already in DB
    final existing = await db.getSongMetadata(filePath);
    if (existing != null) return existing;

    try {
      final metadata = await MetadataGod.readMetadata(file: filePath);

      String? artworkPath;
      int? artworkWidth;
      int? artworkHeight;
      Uint8List? themeColorsBlob;

      if (metadata.picture != null) {
        final artworkInfo = await _saveCompressedArtwork(
          filePath,
          metadata.picture!.data,
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
        title: metadata.title ?? p.basenameWithoutExtension(filePath),
        album: metadata.album ?? 'Unknown Album',
        artist: metadata.artist ?? 'Unknown Artist',
        duration: (metadata.durationMs as num?)?.toInt(),
        artworkPath: artworkPath,
        artworkWidth: artworkWidth,
        artworkHeight: artworkHeight,
        trackNumber: metadata.trackNumber,
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

      final extension = (Platform.isWindows || Platform.isLinux)
          ? 'jpg'
          : 'webp';
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basenameWithoutExtension(songPath)}.$extension';
      final targetPath = p.join(thumbnailsDir.path, fileName);

      Uint8List result;

      if (Platform.isWindows || Platform.isLinux) {
        // Use 'image' package on Windows/Linux as flutter_image_compress doesn't support them
        final image = img.decodeImage(data);
        if (image == null) return null;

        // Crop center square first to avoid stretching non-square artwork.
        final cropSize = image.width < image.height
            ? image.width
            : image.height;
        final offsetX = (image.width - cropSize) ~/ 2;
        final offsetY = (image.height - cropSize) ~/ 2;
        final square = img.copyCrop(
          image,
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

        // Encode to JPEG (WebP encoding not supported on Windows by current libs)
        result = Uint8List.fromList(img.encodeJpg(resized, quality: 80));
      } else {
        // Use flutter_image_compress on supported platforms (Android, iOS, macOS)
        result = await FlutterImageCompress.compressWithList(
          data,
          minWidth: 200,
          minHeight: 200,
          quality: 80,
          format: CompressFormat.webp,
        );
      }

      final file = File(targetPath);
      await file.writeAsBytes(result);

      // Also get original dimensions to return
      final originalImage = img.decodeImage(data);
      return {
        'path': targetPath,
        'width': originalImage?.width,
        'height': originalImage?.height,
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
}
