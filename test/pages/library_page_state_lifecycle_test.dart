// 媒体库页面状态生命周期的回归测试。
//
// 语义（2026-10-18 起）：状态生命周期 = Widget 生命周期。
// - 页内切换子分类：不销毁页面 → 保留（覆盖「洞察页筛选、各 tab 滚动位置、三级详情」）；
// - 切到其它主页面：同样不销毁二级宿主 → 保留，回来后原样恢复；
// - 真正退出（回到仪表盘 / 二级宿主出栈）：dispose → 复位（筛选回到「歌曲 + 全部时间」）。
//
// 曾经的做法是监听 mainTabIndexProvider，一旦离开媒体库主页面就 popUntil 到仪表盘，
// 顺带让各分类的三级详情一起出栈 —— 于是切走再回来必然丢状态，出栈时还会多放一次
// 封面 Hero 反向飞行。现在离开主页面不再碰路由栈。
//
// 锁定的行为：
// 1. 页面存活（停留在媒体库内）时状态必须保留 —— 页内切子分类不应丢视图；
// 2. 切到其它主页面后仍保留，子分类索引与筛选状态都不变；
// 3. 退回仪表盘（provider 置 null）时二级宿主出栈，筛选状态复位。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/pages/album_detail_page.dart';
import 'package:vynody/pages/albums_tab.dart';
import 'package:vynody/pages/library_page.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/widgets/album_zoom_item.dart';
import 'package:vynody/widgets/library_insight_list.dart';
import 'package:vynody/widgets/section_type_toggle.dart';

import '../widgets/helpers/mobile_screenshot_harness.dart';

/// 单曲 / 专辑共用同一个 [LibraryInsightList]，用它的 `type` 判断当前展示模式。
SectionItemType _insightType(WidgetTester tester) =>
    tester.widget<LibraryInsightList>(find.byType(LibraryInsightList)).type;

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
  late PlaylistService playlistService;
  late List<AlbumSummary> demoAlbums;
  late List<ArtistSummary> demoArtists;
  late List<LibraryInsightSongEntry> demoInsightEntries;

  setUpAll(() async {
    testTempDir = Directory.systemTemp.createTempSync('library_page_rail_leave_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(testTempDir);
    await loadMobileTestFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);

    final demoData = createDemoLibraryData(
      basePath: '/test/music',
      demoItems: defaultDemoListEn,
    );
    demoAlbums = demoData.albums;
    demoArtists = [
      ArtistSummary(
        queryKey: 'lin zhou',
        name: 'Lin Zhou',
        songs: demoData.songs.where((s) => s.artist == 'Lin Zhou').toList(),
        representativeSong: demoData.songs[0],
        songCount: 1,
      ),
    ];

    final now = DateTime.now().millisecondsSinceEpoch;
    demoInsightEntries = demoData.songs.take(6).map((song) {
      return LibraryInsightSongEntry(
        song: song,
        playCount: 12,
        lastPlayedAt: now - 3600000,
        createdAt: now - 86400000,
      );
    }).toList();

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
    scannerService = MockScannerService(rootFolders: []);
    playlistService = PlaylistService();
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
        scannerServiceProvider.overrideWith((ref) => scannerService),
        albumLibraryProvider.overrideWith((ref) => Stream.value(demoAlbums)),
        artistLibraryProvider.overrideWith((ref) => Stream.value(demoArtists)),
        playlistServiceProvider.overrideWith((ref) => playlistService),
        recentlyPlayedSongsProvider.overrideWith(
          (ref, range) => Stream.value(demoInsightEntries),
        ),
        mostPlayedSongsProvider.overrideWith(
          (ref, range) => Stream.value(demoInsightEntries),
        ),
        recentlyAddedSongsProvider.overrideWith(
          (ref, range) => Stream.value(demoInsightEntries),
        ),
        isProUnlockedProvider.overrideWith((ref) => true),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget wrap(ProviderContainer container, Widget child) {
    return UncontrolledProviderScope(
      container: container,
      child: OKToast(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(430, 932)),
            child: Material(child: child),
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

  testWidgets('切主页面保留页面状态，退回仪表盘才复位', (tester) async {
    setSurface(tester, const Size(430, 932));
    final container = createContainer();

    // 模拟用户当前停在「媒体库」主页面
    container.read(mainTabIndexProvider.notifier).setIndex(2);

    await tester.pumpWidget(wrap(container, const LibraryPage()));
    await settle(tester);

    // 从 Rail 子项进入「最近播放」
    container.read(libraryActiveTabIndexProvider.notifier).set(1);
    await settle(tester);
    expect(_insightType(tester), SectionItemType.songs);

    // 切到专辑视图
    await tester.tap(find.text('专辑').first);
    await settle(tester);
    expect(_insightType(tester), SectionItemType.albums);
    expect(container.read(recentlyPlayedFilterProvider).type, SectionItemType.albums);

    // 停留在媒体库（页内切换子分类）时状态应保留
    container.read(libraryActiveTabIndexProvider.notifier).set(2);
    await settle(tester);
    container.read(libraryActiveTabIndexProvider.notifier).set(1);
    await settle(tester);
    expect(
      container.read(recentlyPlayedFilterProvider).type,
      SectionItemType.albums,
      reason: '二级宿主存活期间，页内切换子分类不应丢视图',
    );

    // 点 Rail 切到其它主页面（例如队列）：不销毁页面，状态保留
    container.read(mainTabIndexProvider.notifier).setIndex(3);
    await settle(tester);

    expect(
      container.read(libraryActiveTabIndexProvider),
      1,
      reason: '切到其它主页面不应退回仪表盘，子分类索引原样保留',
    );
    expect(
      container.read(recentlyPlayedFilterProvider).type,
      SectionItemType.albums,
      reason: '切换主页面不销毁二级宿主，筛选状态应保留',
    );

    // 切回媒体库：仍是原来的«专辑»视图
    container.read(mainTabIndexProvider.notifier).setIndex(2);
    await settle(tester);
    expect(_insightType(tester), SectionItemType.albums);

    // 真正退出：退回仪表盘，二级宿主出栈，筛选状态复位
    container.read(libraryActiveTabIndexProvider.notifier).set(null);
    await settle(tester);

    expect(
      container.read(recentlyPlayedFilterProvider).isDefault,
      isTrue,
      reason: '页面销毁后筛选状态应复位',
    );

    // 再从 Rail 子项回到「最近播放」：应是歌曲视图
    container.read(libraryActiveTabIndexProvider.notifier).set(1);
    await settle(tester);

    expect(_insightType(tester), SectionItemType.songs);
    expect(tester.takeException(), isNull);
  });

  // 回归：每个子分类各持一条 Navigator 栈。曾经 9 个分类共用一条栈，切分类靠
  // popUntil 回到宿主，于是「进专辑详情 → 切到艺术家 → 切回专辑」必然丢详情，
  // 而且那次出栈还会触发封面 Hero 反向飞向已经不可见的专辑网格。
  testWidgets('进专辑详情后切子分类再切回，详情页仍在', (tester) async {
    setSurface(tester, const Size(430, 932));
    final container = createContainer();
    final keys = List<GlobalKey<NavigatorState>>.generate(
      9,
      (index) => GlobalKey<NavigatorState>(debugLabel: 'test_library_tab_$index'),
    );

    await tester.pumpWidget(
      wrap(container, LibrarySubHostPage(tabNavigatorKeys: keys)),
    );
    await settle(tester);

    // 进入「专辑」子分类
    container.read(libraryActiveTabIndexProvider.notifier).set(4);
    await settle(tester);
    expect(find.byType(AlbumsTab), findsOneWidget);

    // 点第一张专辑卡进入详情
    await tester.tap(find.byType(AlbumZoomItem).first);
    await settle(tester);
    expect(find.byType(AlbumDetailPage), findsOneWidget);
    expect(keys[4].currentState!.canPop(), isTrue);

    // 切到「艺术家」：专辑分类的栈不能被出栈
    container.read(libraryActiveTabIndexProvider.notifier).set(5);
    await settle(tester);
    expect(
      keys[4].currentState!.canPop(),
      isTrue,
      reason: '切子分类不应出栈，专辑详情必须留在自己的栈里',
    );
    expect(
      keys[5].currentState!.canPop(),
      isFalse,
      reason: '其它子分类应停在自己的根页面',
    );

    // 切回「专辑」：详情页原样恢复
    container.read(libraryActiveTabIndexProvider.notifier).set(4);
    await settle(tester);
    expect(find.byType(AlbumDetailPage), findsOneWidget);
    expect(keys[4].currentState!.canPop(), isTrue);

    // 在自己的栈里按返回：详情页关闭，回到专辑网格，不影响其它分类
    await keys[4].currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(AlbumDetailPage), findsNothing);
    expect(keys[4].currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  // 回归：三级页面进的是子分类自己的 Navigator，落在宿主的 IndexedStack（body）里，
  // 而宿主顶栏是 Stack 里后画的那个 —— 两者位置完全重合。若宿主顶栏不让位，
  // 用户看到的是子分类标题，点左上角返回实际弹掉的是整个二级宿主（直接回媒体库首页）。
  testWidgets('打开详情页后宿主顶栏让位，左上角返回只退详情', (tester) async {
    setSurface(tester, const Size(430, 932));
    final container = createContainer();
    final keys = List<GlobalKey<NavigatorState>>.generate(
      9,
      (index) => GlobalKey<NavigatorState>(debugLabel: 'test_library_tab_$index'),
    );

    await tester.pumpWidget(
      wrap(container, LibrarySubHostPage(tabNavigatorKeys: keys)),
    );
    await settle(tester);

    final hostBar = find.byKey(const ValueKey('library_subhost_top_bar'));
    // 最近的 AnimatedOpacity 是 AutoHideHeader 内部那个（跟随滚动隐藏），
    // 宿主顶栏的「让位」开关是再外面一层，所以要取第 2 个祖先。
    double hostBarOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: hostBar, matching: find.byType(AnimatedOpacity)).at(1),
        )
        .opacity;

    // 根页面：宿主顶栏在位
    container.read(libraryActiveTabIndexProvider.notifier).set(4);
    await settle(tester);
    expect(hostBar, findsOneWidget);
    expect(hostBarOpacity(), 1.0);

    // 进详情：宿主顶栏必须让位，露出详情页自己的顶栏（详情标题 + 详情返回按钮）
    await tester.tap(find.byType(AlbumZoomItem).first);
    await settle(tester);
    expect(find.byType(AlbumDetailPage), findsOneWidget);
    expect(
      hostBarOpacity(),
      0.0,
      reason: '详情页自带同位置的顶栏，宿主顶栏盖在上面会顶掉它的标题与返回按钮',
    );

    // 点详情页自己的左上角返回：只退详情，不能弹掉二级宿主
    final detailBack = find.descendant(
      of: find.byType(AlbumDetailPage),
      matching: find.byIcon(Icons.arrow_back_rounded),
    );
    expect(detailBack, findsOneWidget);
    await tester.tap(detailBack);
    await tester.pumpAndSettle();

    expect(find.byType(AlbumDetailPage), findsNothing);
    expect(find.byType(AlbumsTab), findsOneWidget, reason: '应回到专辑网格，而不是媒体库首页');
    expect(keys[4].currentState!.canPop(), isFalse);
    expect(hostBarOpacity(), 1.0, reason: '回到根页面后宿主顶栏要恢复');

    // 从其它主页面切回媒体库（页面不销毁）后，栈里的详情页仍应让宿主顶栏保持让位
    await tester.tap(find.byType(AlbumZoomItem).first);
    await settle(tester);
    expect(hostBarOpacity(), 0.0);
    expect(tester.takeException(), isNull);
  });
}
