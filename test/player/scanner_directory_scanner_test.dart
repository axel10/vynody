import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_flow/player/scanner_directory_scanner.dart';
import 'package:vibe_flow/player/scanner_scan_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScannerDirectoryScanner', () {
    test(
      'discoverMusicFilesInDirectory only scans the current directory',
      () async {
        final tempDirectory = await Directory.systemTemp.createTemp(
          'scanner_directory_scanner_test_',
        );

        try {
          final rootSong = File('${tempDirectory.path}/root-song.mp3');
          await rootSong.writeAsBytes(List<int>.filled(8, 1));

          final nestedDirectory = Directory('${tempDirectory.path}/nested');
          await nestedDirectory.create();

          final nestedSong = File('${nestedDirectory.path}/nested-song.mp3');
          await nestedSong.writeAsBytes(List<int>.filled(8, 2));

          final scanner = ScannerDirectoryScanner(emitScanProgress: (_, __) {});
          final scanState = ScanProgressState(
            comparePaths: (a, b) => a.compareTo(b),
          );

          final discovered = await scanner.discoverMusicFilesInDirectory(
            tempDirectory.path,
            scanState,
          );

          expect(discovered, contains(rootSong.path));
          expect(discovered, isNot(contains(nestedSong.path)));
        } finally {
          if (await tempDirectory.exists()) {
            await tempDirectory.delete(recursive: true);
          }
        }
      },
    );
  });
}
