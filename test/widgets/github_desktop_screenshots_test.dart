// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/macos_screenshot_harness.dart';
import 'helpers/github_demo_data.dart';

void _saveToGithubDir(Uint8List bytes, String filename) {
  final out = File('screenshots/github/$filename');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes);
  print('COPIED_TO_GITHUB_DIR: ${out.path} (${bytes.length} bytes)');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dataset = createGithubLibraryDataset();
  final featuredSong = dataset.songs[0]; // The Weeknd - Starboy

  final snapshot = AudioSnapshot(
    isPlaying: true,
    isTransitioning: false,
    isLastActionNext: null,
    currentMusic: featuredSong,
    position: const Duration(seconds: 45),
    duration: Duration(milliseconds: featuredSong.durationMillis ?? 230453),
    volume: 0.85,
    isMuted: false,
    playbackQueue: dataset.songs,
    currentIndex: 0,
    isRandomMode: false,
    isShuffleRandomMode: false,
    playbackMode: AppPlaybackMode.queue,
    equalizerConfig: EqualizerConfig(
      enabled: false,
      bandCount: 10,
      preampDb: 0.0,
      bassBoostDb: 0.0,
      bassBoostFrequencyHz: 80.0,
      bassBoostQ: 1.0,
      bandGainsDb: Float32List(10),
    ),
    currentVisualizerOptions: const VisualizerOptimizationOptions(
      frequencyGroups: 100,
    ),
    randomHistory: const [],
    randomQueue: const [],
    historyCursor: null,
    deckCursor: null,
    isVisualizerEnabled: true,
    dynamicStartColor: const Color(0xFFE11D48),
    dynamicEndColor: const Color(0xFF0F172A),
    currentThemeColorsMap: const {
      'darkVibrant': Color(0xFFE11D48),
      'vibrant': Color(0xFFF43F5E),
      'dominant': Color(0xFFBE123C),
      'darkMuted': Color(0xFF1E112A),
      'lightVibrant': Color(0xFFFDA4AF),
    },
    isLyricsActive: false,
    sleepTimerRemaining: null,
    sleepTimerDuration: null,
  );

  group('GitHub Covers - Desktop Screenshots', () {
    testWidgets('1. Desktop 目录页 (Directory Page)', (tester) async {
      await loadMacosTestFonts();

      final scannerService = MockScannerService(
        rootFolders: [dataset.rootFolder],
        metadataMap: dataset.metadataMap,
      );
      scannerService.setNavigationState(dataset.rootFolder, []);

      final bytes = await captureMacosWindow(
        tester: tester,
        song: featuredSong,
        snapshot: snapshot,
        initialIndex: 0,
        customBody: const MainLayout(
          args: [],
          initialIndex: 0,
        ),
        scannerService: scannerService,
        saveWindowFileName: ScreenshotPaths.raw('desktop_directory.png'),
        configureSettings: (s) {
          s.visualizerColor = const Color(0xFFE11D48);
        },
      );

      _saveToGithubDir(bytes, 'desktop_directory.png');
      expect(bytes.isNotEmpty, isTrue);
    });

    testWidgets('2. Desktop 专辑页 (Albums Page)', (tester) async {
      await loadMacosTestFonts();

      final scannerService = MockScannerService(
        rootFolders: [dataset.rootFolder],
        metadataMap: dataset.metadataMap,
      );

      final bytes = await captureMacosWindow(
        tester: tester,
        song: featuredSong,
        snapshot: snapshot,
        initialIndex: 2,
        customBody: const MainLayout(
          args: [],
          initialIndex: 2,
          initialLibraryTabIndex: 4,
          initialAlbums3DView: false,
        ),
        scannerService: scannerService,
        extraOverrides: [
          albumLibraryProvider.overrideWith((ref) => Stream.value(dataset.albums)),
        ],
        saveWindowFileName: ScreenshotPaths.raw('desktop_albums.png'),
        configureSettings: (s) {
          s.visualizerColor = const Color(0xFFE11D48);
        },
      );

      _saveToGithubDir(bytes, 'desktop_albums.png');
      expect(bytes.isNotEmpty, isTrue);
    });

    testWidgets('3. Desktop Coverflow页 (3D Cover Flow Page)', (tester) async {
      await loadMacosTestFonts();

      final scannerService = MockScannerService(
        rootFolders: [dataset.rootFolder],
        metadataMap: dataset.metadataMap,
      );

      final bytes = await captureMacosWindow(
        tester: tester,
        song: featuredSong,
        snapshot: snapshot,
        initialIndex: 2,
        customBody: const MainLayout(
          args: [],
          initialIndex: 2,
          initialLibraryTabIndex: 4,
          initialAlbums3DView: true,
          initialAlbums3DIndex: 0,
        ),
        scannerService: scannerService,
        extraOverrides: [
          albumLibraryProvider.overrideWith((ref) => Stream.value(dataset.albums)),
        ],
        saveWindowFileName: ScreenshotPaths.raw('desktop_coverflow.png'),
        configureSettings: (s) {
          s.visualizerColor = const Color(0xFFE11D48);
        },
      );

      _saveToGithubDir(bytes, 'desktop_coverflow.png');
      expect(bytes.isNotEmpty, isTrue);
    });
  });
}
