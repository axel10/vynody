import 'dart:io';
import 'dart:typed_data';

import 'package:vynody/utils/file_selector_helper.dart';

typedef ArtworkSaveFileFn = Future<String?> Function({
  required String suggestedName,
  String? label,
  List<String>? extensions,
  String? dialogTitle,
  Uint8List? bytes,
});

/// Helpers for resolving, naming, and exporting cover artwork bytes to disk.
class ArtworkExportHelper {
  ArtworkExportHelper._();

  static final RegExp _invalidFileNameChars = RegExp(r'[\\/:*?"<>|]');

  /// Detects the image file extension (`png`, `webp`, or `jpg`) from magic bytes.
  static String detectImageExtension(Uint8List bytes) {
    if (bytes.length >= 8) {
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'png';
      }
      if (bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46) {
        return 'webp';
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return 'jpg';
      }
    }
    return 'jpg';
  }

  /// Builds a sanitized suggested filename for exporting a track's cover art.
  static String buildSuggestedFileName({
    String? artist,
    String? title,
    required String extension,
  }) {
    final trimmedTitle = title?.trim() ?? '';
    final trimmedArtist = artist?.trim() ?? '';
    String baseName = 'cover';
    if (trimmedArtist.isNotEmpty && trimmedTitle.isNotEmpty) {
      baseName = '$trimmedArtist - $trimmedTitle - Cover';
    } else if (trimmedTitle.isNotEmpty) {
      baseName = '$trimmedTitle - Cover';
    }
    final sanitized = baseName.replaceAll(_invalidFileNameChars, '_');
    return '$sanitized.$extension';
  }

  /// Resolves non-empty cover bytes from in-memory [bytes] or an on-disk [filePath].
  static Future<Uint8List?> resolveCoverBytes({
    Uint8List? bytes,
    String? filePath,
  }) async {
    if (bytes != null && bytes.isNotEmpty) {
      return bytes;
    }
    if (filePath != null && filePath.isNotEmpty) {
      final file = File(filePath);
      if (await file.exists()) {
        final fileBytes = await file.readAsBytes();
        if (fileBytes.isNotEmpty) {
          return fileBytes;
        }
      }
    }
    return null;
  }

  /// Saves [bytes] to a user-selected file location.
  ///
  /// Returns the saved path, or `null` if the user cancelled the save dialog.
  static Future<String?> exportCoverBytes({
    required Uint8List bytes,
    String? artist,
    String? title,
    ArtworkSaveFileFn saveFile = FileSelectorHelper.saveFile,
  }) async {
    final ext = detectImageExtension(bytes);
    final suggestedName = buildSuggestedFileName(
      artist: artist,
      title: title,
      extension: ext,
    );
    return saveFile(
      suggestedName: suggestedName,
      label: 'Images',
      extensions: [ext],
      bytes: bytes,
    );
  }
}
