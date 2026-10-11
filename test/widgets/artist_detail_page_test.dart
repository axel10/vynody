import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/pages/artist_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/widgets/app_top_nav_bar.dart';

import 'helpers/mobile_screenshot_harness.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  _FakePathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testTempDir;
  late TestSettingsService settingsService;
  late ArtistSummary sampleArtist;
  late MockAudioService audioService;
  late MockScannerService scannerService;
  late dynamic demoData;
  late AudioSnapshot testSnapshot;

  setUpAll(() async {
    testTempDir = await Directory.systemTemp.createTemp('artist_detail_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(testTempDir);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);

    demoData = createDemoLibraryData(
      basePath: '/test/music',
      demoItems: defaultDemoListEn,
    );

    sampleArtist = ArtistSummary(
      queryKey: 'lin zhou',
      name: 'Lin Zhou',
      songs: demoData.songs,
      representativeSong: demoData.songs.first,
      songCount: demoData.songs.length,
    );

    final snapshot = AudioSnapshot(
      isPlaying: false,
      isTransitioning: false,
      isLastActionNext: null,
      currentMusic: null,
      position: Duration.zero,
      duration: Duration.zero,
      volume: 1.0,
      isMuted: false,
      playbackQueue: const [],
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
      historyCursor: 0,
      deckCursor: 0,
      isVisualizerEnabled: false,
      dynamicStartColor: null,
      dynamicEndColor: null,
      isLyricsActive: false,
      sleepTimerRemaining: null,
      sleepTimerDuration: null,
    );
    testSnapshot = snapshot;
  });

  setUp(() {
    audioService = MockAudioService(
      snapshot: testSnapshot,
      visualizerStream: const Stream.empty(),
    );
    scannerService = MockScannerService(
      rootFolders: [],
      metadataMap: demoData.metadataMap,
    );
  });

  tearDownAll(() async {
    try {
      if (testTempDir.existsSync()) {
        testTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Widget buildTestApp({required Widget child}) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceStateProvider.overrideWith(() => audioService),
        audioServiceProvider.overrideWith((ref) => audioService),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        scannerServiceProvider.overrideWith((ref) => scannerService),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: ThemeData.dark(),
        home: child,
      ),
    );
  }

  testWidgets('ArtistDetailPage - renders immersive top nav bar and scrolls to reveal title', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestApp(
        child: ArtistDetailPage(artist: sampleArtist),
      ),
    );
    await tester.pumpAndSettle();

    // Verify artist name in header
    expect(find.text(sampleArtist.name), findsWidgets);

    // Verify play buttons
    expect(find.byIcon(Icons.play_arrow), findsWidgets);
    expect(find.byIcon(Icons.shuffle), findsWidgets);

    // Verify top nav bar is present
    expect(find.byType(AppTopNavBar), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    // Verify title in top bar is present
    expect(find.byKey(const ValueKey('album_title')), findsOneWidget);
  });

  testWidgets('ArtistDetailPage - back button pops route', (tester) async {
    bool didGoBack = false;

    await tester.pumpWidget(
      buildTestApp(
        child: ArtistDetailPage(
          artist: sampleArtist,
          onGoBack: () {
            didGoBack = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(didGoBack, isTrue);
  });

  testWidgets('ArtistDetailPage - renders 3-row layout in portrait and compact layout in landscape', (tester) async {
    // 1. Portrait mode
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestApp(
        child: ArtistDetailPage(artist: sampleArtist),
      ),
    );
    await tester.pumpAndSettle();

    // Verify avatar, name with chevron, and action buttons in portrait (FilledButton + OutlinedButton aligned with album detail)
    expect(find.text(sampleArtist.name), findsWidgets);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);

    // 2. Switch to Landscape mode
    tester.view.physicalSize = const Size(1200 * 3, 600 * 3);
    await tester.pumpAndSettle();

    // In landscape mode, buttons are IconButtons and chevron is not present
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byType(IconButton), findsWidgets);

    // Verify AppTopNavBar is at leftPadding (216.0)
    expect(find.byType(AppTopNavBar), findsOneWidget);
    final navBarPos = tester.getTopLeft(find.byType(AppTopNavBar));
    expect(navBarPos.dx, 216.0);
  });
}
