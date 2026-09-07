// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/pages/folder_page.dart';
import 'package:vynody/pages/playback_page.dart';
import 'package:vynody/pages/recently_played_tab.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/player/pro/pro_license_service.dart';

import 'helpers/mobile_screenshot_harness.dart';
import 'helpers/github_demo_data.dart';

void _saveToGithubDir(Uint8List bytes, String filename) {
  final out = File('screenshots/github/$filename');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes);
  print('COPIED_TO_GITHUB_DIR: ${out.path} (${bytes.length} bytes)');
}

Future<void> _setupMocks() async {
  await loadMobileTestFonts();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'isFullScreen':
          return false;
        case 'isMaximized':
          return false;
        case 'getSize':
          return {'width': 430.0, 'height': 932.0};
        default:
          return null;
      }
    },
  );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const demoLrc = '''
[00:00.00]Starboy - The Weeknd (feat. Daft Punk)
[00:15.00]I'm tryna put you in the worst mood, ah
[00:20.00]P1 cleaner than your church shoes, ah
[00:25.00]Milli point two just to hurt you, ah
[00:30.00]All red Lamb' just to tease you, ah
[00:35.00]None of these toys on lease too, ah
[00:40.00]Made your whole year in a week too, yah
[00:45.00]Look what you've done
[00:48.00]I'm a motherfuckin' starboy
''';

  group('GitHub Covers - Mobile Portrait Screenshots', () {
    testWidgets('1. Mobile 播放页 (Playback Page)', (tester) async {
      await _setupMocks();

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settingsService = TestSettingsService(prefs);

      settingsService.hasShownOnboarding = true;
      settingsService.hasShownCoverTapLyricTip = true;
      settingsService.isWaveformProgressBarEnabled = true;
      settingsService.portraitFrequencyGroups = 100;
      settingsService.visualizerStyle = VisualizerStyle.bars;
      settingsService.visualizerOpacity = 0.85;
      settingsService.isVisualizerDynamicColor = true;

      final dataset = createGithubLibraryDataset();
      final activeSong = dataset.songs[0]; // Starboy

      final lyrics = parseLrc(demoLrc);
      final waveformBlob = generateRealisticWaveform(128, seed: 2.1);

      final songWithMedia = activeSong.copyWith(
        lyrics: lyrics,
        waveformBlob: waveformBlob,
      );

      final fftValues = generateFftBandsDefault(count: 100, energy: 0.88);
      final fftFrame = FftFrame(
        position: const Duration(seconds: 45),
        values: fftValues,
        isPlaying: true,
      );

      final snapshot = AudioSnapshot(
        isPlaying: true,
        isTransitioning: false,
        isLastActionNext: null,
        currentMusic: songWithMedia,
        position: const Duration(seconds: 45),
        duration: Duration(milliseconds: songWithMedia.durationMillis ?? 230453),
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

      final visualizerStreamController = StreamController<FftFrame>.broadcast();
      final audioService = MockAudioService(
        snapshot: snapshot,
        artworkBytes: songWithMedia.artworkBytes,
        visualizerStream: visualizerStreamController.stream,
      );

      final scannerService = MockScannerService(
        rootFolders: [dataset.rootFolder],
        metadataMap: dataset.metadataMap,
      );

      final screenBytes = await captureMobileScreen(
        tester: tester,
        screenChild: const PlaybackPage(),
        initialFftFrame: fftFrame,
        visualizerStreamController: visualizerStreamController,
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settingsService),
          audioServiceProvider.overrideWith((ref) => audioService),
          audioSnapshotProvider.overrideWith((ref) => snapshot),
          audioCurrentMusicProvider.overrideWith((ref) => songWithMedia),
          scannerServiceProvider.overrideWith((ref) => scannerService),
          isEffectiveWaveformEnabledProvider.overrideWith((ref) => true),
          isProUnlockedProvider.overrideWith((ref) => true),
        ],
        saveScreenFileName: ScreenshotPaths.raw('mobile_playback.png'),
      );

      _saveToGithubDir(screenBytes, 'mobile_playback.png');
      expect(screenBytes.isNotEmpty, isTrue);
    });

    testWidgets('2. Mobile 目录页 (Directory Page)', (tester) async {
      await _setupMocks();

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settingsService = TestSettingsService(prefs);
      settingsService.hasShownOnboarding = true;

      final dataset = createGithubLibraryDataset();
      final activeSong = dataset.songs[0];

      final snapshot = AudioSnapshot(
        isPlaying: true,
        isTransitioning: false,
        isLastActionNext: null,
        currentMusic: activeSong,
        position: const Duration(seconds: 45),
        duration: Duration(milliseconds: activeSong.durationMillis ?? 230453),
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
        isLyricsActive: false,
        sleepTimerRemaining: null,
        sleepTimerDuration: null,
      );

      final visualizerStreamController = StreamController<FftFrame>.broadcast();
      final audioService = MockAudioService(
        snapshot: snapshot,
        artworkBytes: activeSong.artworkBytes,
        visualizerStream: visualizerStreamController.stream,
      );

      final scannerService = MockScannerService(
        rootFolders: [dataset.rootFolder],
        metadataMap: dataset.metadataMap,
      );
      scannerService.setNavigationState(dataset.rootFolder, []);

      final screenBytes = await captureMobileScreen(
        tester: tester,
        screenChild: const SafeArea(
          bottom: false,
          child: FoldersPage(),
        ),
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settingsService),
          audioServiceProvider.overrideWith((ref) => audioService),
          audioSnapshotProvider.overrideWith((ref) => snapshot),
          audioCurrentMusicProvider.overrideWith((ref) => activeSong),
          scannerServiceProvider.overrideWith((ref) => scannerService),
          albumLibraryProvider.overrideWith((ref) => Stream.value(dataset.albums)),
          isProUnlockedProvider.overrideWith((ref) => true),
        ],
        saveScreenFileName: ScreenshotPaths.raw('mobile_directory.png'),
      );

      _saveToGithubDir(screenBytes, 'mobile_directory.png');
      expect(screenBytes.isNotEmpty, isTrue);
    });

    testWidgets('3. Mobile 最近播放页 (Recently Played Page)', (tester) async {
      await _setupMocks();

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settingsService = TestSettingsService(prefs);
      settingsService.hasShownOnboarding = true;

      final dataset = createGithubLibraryDataset();
      final activeSong = dataset.songs[0];

      final snapshot = AudioSnapshot(
        isPlaying: true,
        isTransitioning: false,
        isLastActionNext: null,
        currentMusic: activeSong,
        position: const Duration(seconds: 45),
        duration: Duration(milliseconds: activeSong.durationMillis ?? 230453),
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
        isLyricsActive: false,
        sleepTimerRemaining: null,
        sleepTimerDuration: null,
      );

      final visualizerStreamController = StreamController<FftFrame>.broadcast();
      final audioService = MockAudioService(
        snapshot: snapshot,
        artworkBytes: activeSong.artworkBytes,
        visualizerStream: visualizerStreamController.stream,
      );

      final scannerService = MockScannerService(
        rootFolders: [dataset.rootFolder],
        metadataMap: dataset.metadataMap,
      );

      final playlistService = PlaylistService();

      final screenBytes = await captureMobileScreen(
        tester: tester,
        screenChild: Scaffold(
          appBar: AppBar(
            title: const Text('最近播放'),
            centerTitle: true,
            automaticallyImplyLeading: false,
          ),
          body: const SafeArea(
            bottom: false,
            child: RecentlyPlayedTab(),
          ),
        ),
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settingsService),
          audioServiceProvider.overrideWith((ref) => audioService),
          audioSnapshotProvider.overrideWith((ref) => snapshot),
          audioCurrentMusicProvider.overrideWith((ref) => activeSong),
          scannerServiceProvider.overrideWith((ref) => scannerService),
          recentlyPlayedSongsProvider.overrideWith((ref, range) => Stream.value(dataset.insightEntries)),
          albumLibraryProvider.overrideWith((ref) => Stream.value(dataset.albums)),
          artistLibraryProvider.overrideWith((ref) => Stream.value([])),
          playlistServiceProvider.overrideWith((ref) => playlistService),
          isProUnlockedProvider.overrideWith((ref) => true),
        ],
        saveScreenFileName: ScreenshotPaths.raw('mobile_recently_played.png'),
      );

      _saveToGithubDir(screenBytes, 'mobile_recently_played.png');
      expect(screenBytes.isNotEmpty, isTrue);
    });
  });
}
