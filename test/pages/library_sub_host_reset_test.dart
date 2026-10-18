// 媒体库二级洞察页（最近播放 / 最多播放 / 最近添加）筛选状态的回归测试。
//
// 回归点：三页的「单曲 / 专辑」「时间跨度」存放在全局常驻的 NotifierProvider 中，
// 不随页面销毁回收；而滚动进度依附于 Widget 树，退出即归零。历史上只在仪表盘
// 的「查看全部」入口手动 reset，从 Rail 侧边栏等入口进入时不会复位，于是出现
// 「滚动回到顶部、视图却还停在专辑 tab」的半记忆状态。
//
// 现在筛选状态的生命周期与二级宿主页对齐（宿主页 dispose 时复位），本测试锁定：
// 1. 页面内切到专辑视图确实写入了全局 provider；
// 2. 页面销毁（退出二级页）后 provider 回到「歌曲 + 全部时间」。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/library_page.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import 'package:vynody/player/library/playlist_service.dart';
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

/// 固定媒体库子分类索引（1 = 最近播放）
class _FixedLibraryTabIndexNotifier extends LibraryActiveTabIndexNotifier {
  _FixedLibraryTabIndexNotifier(this._index);

  final int _index;

  @override
  int? build() => _index;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testTempDir;
  late TestSettingsService settingsService;
  late MockAudioService audioService;
  late MockScannerService scannerService;
  late PlaylistService playlistService;
  late List<LibraryInsightSongEntry> demoInsightEntries;
  late List<AlbumSummary> demoAlbums;

  setUpAll(() async {
    testTempDir = Directory.systemTemp.createTempSync('library_sub_host_reset_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(testTempDir);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);

    final demoData = createDemoLibraryData(
      basePath: '/test/music',
      demoItems: defaultDemoListEn.take(6).toList(),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    demoAlbums = demoData.albums;
    demoInsightEntries = demoData.songs
        .map(
          (s) => LibraryInsightSongEntry(
            song: s,
            playCount: 5,
            lastPlayedAt: now - 7200000,
            createdAt: now - 86400000,
          ),
        )
        .toList();
  });

  tearDownAll(() {
    try {
      if (testTempDir.existsSync()) {
        testTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() {
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

  ProviderContainer createContainer({int subIndex = 1}) {
    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceStateProvider.overrideWith(() => audioService),
        audioServiceProvider.overrideWith((ref) => audioService),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        scannerServiceProvider.overrideWith((ref) => scannerService),
        playlistServiceProvider.overrideWith((ref) => playlistService),
        recentlyPlayedSongsProvider.overrideWith(
          (ref, range) => Stream.value(demoInsightEntries),
        ),
        albumLibraryProvider.overrideWith((ref) => Stream.value(demoAlbums)),
        libraryActiveTabIndexProvider.overrideWith(
          () => _FixedLibraryTabIndexNotifier(subIndex),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget wrap(ProviderContainer container, Widget child) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: ThemeData.dark(),
        home: Scaffold(body: child),
      ),
    );
  }

  void setSurface(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('退出二级页后筛选状态复位为「歌曲 + 全部时间」', (tester) async {
    setSurface(tester, const Size(390, 844));
    final container = createContainer();
    final filter = container.read(recentlyPlayedFilterProvider.notifier);

    await tester.pumpWidget(wrap(container, const LibrarySubHostPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_insightType(tester), SectionItemType.songs);

    // 切到专辑视图
    await tester.tap(find.text('专辑').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_insightType(tester), SectionItemType.albums);
    expect(
      container.read(recentlyPlayedFilterProvider).type,
      SectionItemType.albums,
      reason: '切到专辑视图应写入全局筛选状态',
    );

    // 退出二级页：宿主页随路由销毁，筛选状态同步复位
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final state = container.read(recentlyPlayedFilterProvider);
    expect(state.type, SectionItemType.songs, reason: '再进入应回到歌曲 tab');
    expect(state.range, LibraryTimeRange.allTime);
    expect(filter.state.isDefault, isTrue);
  });

  testWidgets('退出二级页会一并复位最多播放与最近添加的筛选状态', (tester) async {
    setSurface(tester, const Size(390, 844));
    final container = createContainer();

    container
        .read(mostPlayedFilterProvider.notifier)
        .setBoth(type: SectionItemType.albums, range: LibraryTimeRange.last7Days);
    container
        .read(recentlyAddedFilterProvider.notifier)
        .setBoth(type: SectionItemType.albums, range: LibraryTimeRange.last30Days);

    await tester.pumpWidget(wrap(container, const LibrarySubHostPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 页面存活期间不应被清掉（保留用户在页内切 tab 的视图）
    expect(
      container.read(mostPlayedFilterProvider).type,
      SectionItemType.albums,
      reason: '页面存活时状态必须保留，否则页内切换会丢视图',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(container.read(mostPlayedFilterProvider).isDefault, isTrue);
    expect(container.read(recentlyAddedFilterProvider).isDefault, isTrue);
  });
}
