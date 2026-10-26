// 本地流派 tab 的搜索布局回归测试。
//
// 锁定的行为：
// 1. 横屏分栏时搜索框收进左栏（页头不再渲染搜索，右侧详情另有自己的搜索）；
// 2. 竖屏单栏时搜索回到页头（左栏栏头随分栏一起消失）；
// 3. 左栏搜索真的在过滤左列表。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/genre_summary.dart';
import 'package:vynody/pages/genres_tab.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import 'package:vynody/widgets/library_search_field.dart';

import '../widgets/helpers/mobile_screenshot_harness.dart';

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
  late List<GenreSummary> demoGenres;

  setUpAll(() async {
    testTempDir = Directory.systemTemp.createTempSync('genres_tab_search_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(testTempDir);
    await loadMobileTestFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);

    MusicFile song(String album, String title, int track) => MusicFile(
          path: '/test/music/$album/$track.mp3',
          name: '$title.mp3',
          title: title,
          artist: 'Demo Artist',
          albumArtist: 'Demo Artist',
          album: album,
          trackNumber: track,
          durationMillis: 180000,
        );

    demoGenres = [
      GenreSummary(
        name: 'Jazz',
        songCount: 2,
        songs: [song('Kind of Blue', 'So What', 1), song('Kind of Blue', 'Freddie', 2)],
      ),
      GenreSummary(
        name: 'Pop',
        songCount: 1,
        songs: [song('Thriller', 'Billie Jean', 1)],
      ),
      GenreSummary(
        name: 'Rock',
        songCount: 1,
        songs: [song('Abbey Road', 'Come Together', 1)],
      ),
    ];

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

    audioService = MockAudioService(
      snapshot: snapshot,
      visualizerStream: const Stream.empty(),
    );
  });

  tearDownAll(() {
    try {
      if (testTempDir.existsSync()) {
        testTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceProvider.overrideWith((ref) => audioService),
        audioSnapshotProvider.overrideWith((ref) => audioService.snapshot),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        genreLibraryProvider.overrideWith((ref) => Stream.value(demoGenres)),
        albumLibraryProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget wrap(ProviderContainer container, Size size) {
    return UncontrolledProviderScope(
      container: container,
      child: OKToast(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: const Material(child: GenresTab()),
          ),
        ),
      ),
    );
  }

  void setSurface(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('横屏：搜索收进左栏，页头不再有第二个搜索框', (tester) async {
    const size = Size(1100, 640);
    setSurface(tester, size);
    final container = createContainer();

    await tester.pumpWidget(wrap(container, size));
    await settle(tester);

    // 左栏栏头里的那一个搜索框。
    expect(find.byType(LibrarySearchField), findsOneWidget);

    // 横屏只有两处放大镜：左栏搜索框的前缀图标 + 右侧详情自己的搜索开关。
    // 页头那条（竖屏的折叠式入口）不再重复出现。
    expect(find.byIcon(Icons.search_rounded), findsNWidgets(2));

    // 三个流派都在左列表里：Jazz 同时出现在详情页头，故只校验另外两个。
    expect(find.text('Pop'), findsOneWidget);
    expect(find.text('Rock'), findsOneWidget);

    // 详情页头的搜索开关固定在操作区行尾（与艺术家详情同序）：
    // 「播放全部 → 随机播放 → 搜索」，所以它必须排在页头那个播放按钮右侧。
    // 曲目区也有「播放全部」，取最靠右的那个即页头按钮。
    final searchToggle = tester.getCenter(find.byTooltip('搜索'));
    final playAllFinder = find.byTooltip('播放全部');
    final playAllCenters = [
      for (var i = 0; i < playAllFinder.evaluate().length; i++)
        tester.getCenter(playAllFinder.at(i)),
    ];
    final rightmostPlayAll = playAllCenters
        .reduce((a, b) => a.dx >= b.dx ? a : b);
    expect(searchToggle.dx, greaterThan(rightmostPlayAll.dx));
  });

  testWidgets('横屏：左栏搜索只过滤左列表', (tester) async {
    const size = Size(1100, 640);
    setSurface(tester, size);
    final container = createContainer();

    await tester.pumpWidget(wrap(container, size));
    await settle(tester);

    await tester.enterText(find.byType(LibrarySearchField), 'rock');
    await settle(tester);

    expect(find.text('Rock'), findsWidgets);
    expect(find.text('Pop'), findsNothing);
    expect(find.text('Jazz'), findsNothing);
  });

  testWidgets('窄横屏（手机横放）：页头去掉搜索后不挤爆', (tester) async {
    // 800 宽时左栏只有 260，页头剩下的标题 + 四个操作按钮必须还排得下。
    const size = Size(800, 420);
    setSurface(tester, size);
    final container = createContainer();

    await tester.pumpWidget(wrap(container, size));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(LibrarySearchField), findsOneWidget);
  });

  testWidgets('横屏：右侧详情自己的搜索只过滤详情内的曲目', (tester) async {
    const size = Size(1100, 640);
    setSurface(tester, size);
    final container = createContainer();

    await tester.pumpWidget(wrap(container, size));
    await settle(tester);

    // 先选中 Pop（详情里只有 Billie Jean 一首）。
    await tester.tap(find.text('Pop'));
    await settle(tester);
    expect(find.text('Billie Jean'), findsOneWidget);

    // 展开详情页头的搜索（左栏搜索框没有 tooltip，这里取到的是详情那个）。
    await tester.tap(find.byTooltip('搜索'));
    await settle(tester);
    expect(find.byType(LibrarySearchField), findsNWidgets(2));

    // 搜一个详情里没有的词 → 走「没命中」空态，左列表不受影响。
    await tester.enterText(find.byType(LibrarySearchField).last, 'zzz');
    await settle(tester);
    expect(find.text('Billie Jean'), findsNothing);
    expect(find.text('没有匹配的专辑或歌曲'), findsOneWidget);
    // 左列表不受详情搜索影响：Pop 仍在列表里（详情页头也有同名标题）。
    expect(find.text('Pop'), findsWidgets);
    expect(find.text('Rock'), findsOneWidget);

    // 清空后曲目回来。
    await tester.tap(find.text('清空搜索'));
    await settle(tester);
    expect(find.text('Billie Jean'), findsOneWidget);
  });

  testWidgets('竖屏：没有左栏，搜索回到页头', (tester) async {
    const size = Size(430, 932);
    setSurface(tester, size);
    final container = createContainer();

    await tester.pumpWidget(wrap(container, size));
    await settle(tester);

    expect(find.byType(LibrarySearchField), findsNothing);
    // 页头的折叠式搜索入口（LibrarySearchField 自己不会再画一个）。
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.text('Jazz'), findsOneWidget);
  });
}
