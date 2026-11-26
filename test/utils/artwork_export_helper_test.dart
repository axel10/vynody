import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/utils/artwork_export_helper.dart';

void main() {
  group('ArtworkExportHelper', () {
    test('detectImageExtension detects png, webp, and defaults to jpg', () {
      expect(
        ArtworkExportHelper.detectImageExtension(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        'png',
      );
      expect(
        ArtworkExportHelper.detectImageExtension(
          Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00]),
        ),
        'webp',
      );
      expect(
        ArtworkExportHelper.detectImageExtension(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]),
        ),
        'jpg',
      );
      expect(
        ArtworkExportHelper.detectImageExtension(Uint8List.fromList([1, 2, 3])),
        'jpg',
      );
    });

    test('buildSuggestedFileName formats and sanitizes artist and title', () {
      expect(
        ArtworkExportHelper.buildSuggestedFileName(
          artist: 'Artist: A/B',
          title: 'Song? *Title*',
          extension: 'png',
        ),
        'Artist_ A_B - Song_ _Title_ - Cover.png',
      );
      expect(
        ArtworkExportHelper.buildSuggestedFileName(
          artist: '   ',
          title: 'Only Title',
          extension: 'jpg',
        ),
        'Only Title - Cover.jpg',
      );
      expect(
        ArtworkExportHelper.buildSuggestedFileName(
          artist: null,
          title: null,
          extension: 'webp',
        ),
        'cover.webp',
      );
    });

    test('resolveCoverBytes prefers in-memory bytes and falls back to file', () async {
      final memoryBytes = Uint8List.fromList([1, 2, 3, 4]);
      expect(
        await ArtworkExportHelper.resolveCoverBytes(
          bytes: memoryBytes,
          filePath: '/nonexistent/path.jpg',
        ),
        memoryBytes,
      );

      final tempDir = await Directory.systemTemp.createTemp('artwork_export_test_');
      try {
        final file = File('${tempDir.path}/cover.png');
        final fileBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
        await file.writeAsBytes(fileBytes);

        expect(
          await ArtworkExportHelper.resolveCoverBytes(
            bytes: Uint8List(0),
            filePath: file.path,
          ),
          fileBytes,
        );
        expect(
          await ArtworkExportHelper.resolveCoverBytes(
            bytes: null,
            filePath: '${tempDir.path}/missing.png',
          ),
          isNull,
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('exportCoverBytes passes detected extension and sanitized filename to saveFile', () async {
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      String? capturedName;
      List<String>? capturedExtensions;
      Uint8List? capturedBytes;

      final savedPath = await ArtworkExportHelper.exportCoverBytes(
        bytes: pngBytes,
        artist: 'Artist/1',
        title: 'Track:2',
        saveFile: ({
          required suggestedName,
          label,
          extensions,
          dialogTitle,
          bytes,
        }) async {
          capturedName = suggestedName;
          capturedExtensions = extensions;
          capturedBytes = bytes;
          return '/tmp/out.png';
        },
      );

      expect(savedPath, '/tmp/out.png');
      expect(capturedName, 'Artist_1 - Track_2 - Cover.png');
      expect(capturedExtensions, ['png']);
      expect(capturedBytes, pngBytes);
    });
  });
}
