// 媒体库二级页「离开主页面即销毁」的回归测试。
//
// 场景：最近播放页切到专辑视图 → 点 Rail 切到其它主页面 → 再从 Rail 子项回到媒体库。
// 二级宿主页是 LibraryPage 内部 Navigator 的一条路由，切走主页面并不会销毁它，
// 于是页面状态（洞察页筛选、各 tab 滚动位置、三级详情）会残留：回来后仍然是专辑 tab。
//
// 现在 LibraryPage 监听 mainTabIndexProvider，离开媒体库主页面时主动把二级宿主退回仪表盘，
// 让页面状态随路由一起销毁（筛选状态在宿主页 dispose 时复位）。
//
// 锁定的行为：
// 1. 页面存活（停留在媒体库内）时状态必须保留 —— 页内切子分类不应丢视图与滚动位置；
// 2. 离开媒体库主页面后，二级宿主退栈、筛选状态复位；
// 3. 从 Rail 子项重新进入时是干净页面（歌曲 + 全部时间）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/pages/library_page.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/widgets/library_ranked_album_list.dart';
import 'package:vynody/widgets/library_ranked_song_list.dart';
import 'package:vynody/widgets/section_type_toggle.dart';

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

  testWidgets('离开媒体库主页面会销毁二级宿主，从 Rail 子项回来是干净页面', (tester) async {
    setSurface(tester, const Size(430, 932));
    final container = createContainer();

    // 模拟用户当前停在「媒体库」主页面
    container.read(mainTabIndexProvider.notifier).setIndex(2);

    await tester.pumpWidget(wrap(container, const LibraryPage()));
    await settle(tester);

    // 从 Rail 子项进入「最近播放」
    container.read(libraryActiveTabIndexProvider.notifier).set(1);
    await settle(tester);
    expect(find.byType(LibraryRankedSongList), findsOneWidget);

    // 切到专辑视图
    await tester.tap(find.text('专辑').first);
    await settle(tester);
    expect(find.byType(LibraryRankedAlbumList), findsOneWidget);
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

    // 点 Rail 切到其它主页面（例如队列）
    container.read(mainTabIndexProvider.notifier).setIndex(3);
    await settle(tester);

    expect(
      container.read(libraryActiveTabIndexProvider),
      isNull,
      reason: '离开媒体库主页面时二级宿主应退回仪表盘',
    );
    expect(
      container.read(recentlyPlayedFilterProvider).isDefault,
      isTrue,
      reason: '页面销毁后筛选状态应复位',
    );

    // 再从 Rail 子项回到「最近播放」：应是歌曲视图
    container.read(mainTabIndexProvider.notifier).setIndex(2);
    await settle(tester);
    container.read(libraryActiveTabIndexProvider.notifier).set(1);
    await settle(tester);

    expect(find.byType(LibraryRankedSongList), findsOneWidget);
    expect(find.byType(LibraryRankedAlbumList), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
