import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/genre_summary.dart';
import 'package:vynody/models/year_summary.dart';
import 'package:vynody/pages/genre_detail_page.dart';
import 'package:vynody/pages/year_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/widgets/collection_detail_header.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

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
  late MockAudioService audioService;
  late MockScannerService scannerService;
  late dynamic demoData;
  late GenreSummary sampleGenre;
  late YearSummary sampleYear;
  late AudioSnapshot testSnapshot;

  setUpAll(() async {
    testTempDir = await Directory.systemTemp.createTemp('genre_year_detail_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(testTempDir);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);

    demoData = createDemoLibraryData(
      basePath: '/test/music',
      demoItems: defaultDemoListEn,
    );

    sampleGenre = GenreSummary(
      name: 'Pop',
      songCount: demoData.songs.length,
      songs: demoData.songs,
    );
    sampleYear = YearSummary(
      year: 2024,
      songCount: demoData.songs.length,
      songs: demoData.songs,
    );

    testSnapshot = AudioSnapshot(
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

  void setLandscape(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  void setPortrait(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('流派详情页 - 横屏不展示集合封面，列表按专辑分组渲染',
      (tester) async {
    setLandscape(tester);
    await tester.pumpWidget(
      buildTestApp(child: GenreDetailPage(genre: sampleGenre)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CollectionCover), findsNothing);
    expect(find.text(sampleGenre.name), findsWidgets);
    // 宽列表区使用「左侧专辑大图 + 右侧曲目列表」布局
    expect(
      find.byWidgetPredicate((w) => w is SongThumbnail && w.size == 190),
      findsWidgets,
    );
  });

  testWidgets('年份详情页 - 横屏不展示集合封面，列表按专辑分组渲染',
      (tester) async {
    setLandscape(tester);
    await tester.pumpWidget(
      buildTestApp(child: YearDetailPage(year: sampleYear)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CollectionCover), findsNothing);
    expect(find.text('2024'), findsWidgets);
    expect(
      find.byWidgetPredicate((w) => w is SongThumbnail && w.size == 190),
      findsWidgets,
    );
  });

  testWidgets('流派详情页 - 竖屏保留集合封面', (tester) async {
    setPortrait(tester);
    await tester.pumpWidget(
      buildTestApp(child: GenreDetailPage(genre: sampleGenre)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CollectionCover), findsOneWidget);
  });

  testWidgets('年份详情页 - 竖屏保留集合封面', (tester) async {
    setPortrait(tester);
    await tester.pumpWidget(
      buildTestApp(child: YearDetailPage(year: sampleYear)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CollectionCover), findsOneWidget);
  });
}
