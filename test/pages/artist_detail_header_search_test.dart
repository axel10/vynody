// 本地艺术家详情页「标题区搜索」的布局回归测试。
//
// 锁定的行为：
// 1. 搜索开关挂在操作区行尾——横屏与圆形「播放 / 随机」同一行、
//    竖屏与「播放全部 / 随机」同一行，不再单独占一行；
// 2. 点开后搜索框出现在页头与专辑分组之间，无命中走独立空态；
// 3. 再点一次收起并清空搜索词。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/pages/artist_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/library/playlist_service.dart';
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
  late List<MusicFile> songs;
  late ArtistSummary artist;

  setUpAll(() async {
    testTempDir = Directory.systemTemp.createTempSync('artist_header_search_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(testTempDir);
    await loadMobileTestFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);

    songs = [
      MusicFile(
        path: '/test/music/glimmer/1.mp3',
        name: 'River Lights.mp3',
        title: 'River Lights',
        artist: 'Lin Zhou',
        albumArtist: 'Lin Zhou',
        album: 'City Glimmer',
        trackNumber: 1,
        durationMillis: 180000,
      ),
      MusicFile(
        path: '/test/music/glimmer/2.mp3',
        name: 'Paper Moon.mp3',
        title: 'Paper Moon',
        artist: 'Lin Zhou',
        albumArtist: 'Lin Zhou',
        album: 'City Glimmer',
        trackNumber: 2,
        durationMillis: 200000,
      ),
    ];

    artist = ArtistSummary(
      queryKey: 'lin zhou',
      name: 'Lin Zhou',
      songs: songs,
      representativeSong: songs.first,
      songCount: songs.length,
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
        audioServiceStateProvider.overrideWith(() => audioService),
        audioServiceProvider.overrideWith((ref) => audioService),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        playlistServiceProvider.overrideWith((ref) => PlaylistService()),
        scannerServiceProvider.overrideWith(
          (ref) => MockScannerService(rootFolders: const []),
        ),
        artistLibraryProvider.overrideWith((ref) => Stream.value([artist])),
        albumLibraryProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget wrap(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(),
        home: Scaffold(body: ArtistDetailContent(artist: artist)),
      ),
    );
  }

  void setSurface(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 搜索开关与操作区按钮是否排在同一行（纵向中心差 < 8px）。
  void expectSameRow(WidgetTester tester) {
    final search = tester.getCenter(find.byIcon(Icons.search_rounded));
    final shuffle = tester.getCenter(find.byIcon(Icons.shuffle));
    expect(
      (search.dy - shuffle.dy).abs(),
      lessThan(8),
      reason: '搜索开关应与「随机播放」在同一行，实际 dy 差 '
          '${(search.dy - shuffle.dy).abs()}',
    );
    expect(
      search.dx,
      greaterThan(shuffle.dx),
      reason: '搜索开关应排在操作区行尾',
    );
  }

  testWidgets('横屏：搜索开关与圆形播放 / 随机按钮同排', (tester) async {
    setSurface(tester, const Size(1024, 768));
    final container = createContainer();

    await tester.pumpWidget(wrap(container));
    await tester.pumpAndSettle();

    expectSameRow(tester);
  });

  testWidgets('竖屏：搜索开关与「播放全部 / 随机」同排', (tester) async {
    setSurface(tester, const Size(390, 844));
    final container = createContainer();

    await tester.pumpWidget(wrap(container));
    await tester.pumpAndSettle();

    expectSameRow(tester);
  });

  testWidgets('点开搜索：搜索框出现在页头下方，无命中走空态', (tester) async {
    setSurface(tester, const Size(390, 844));
    final container = createContainer();

    await tester.pumpWidget(wrap(container));
    await tester.pumpAndSettle();

    expect(find.byType(LibrarySearchField), findsNothing);

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(LibrarySearchField), findsOneWidget);

    await tester.enterText(find.byType(LibrarySearchField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的专辑或歌曲'), findsOneWidget);

    // 再点一次：收起 + 清空，专辑重新出现。
    // 空态里也有一个 search_off 图标，所以只认开关那个 IconButton。
    final closeToggle = find.ancestor(
      of: find.byIcon(Icons.search_off_rounded),
      matching: find.byType(IconButton),
    );
    expect(closeToggle, findsOneWidget);
    await tester.tap(closeToggle);
    await tester.pumpAndSettle();
    expect(find.byType(LibrarySearchField), findsNothing);
    expect(find.text('City Glimmer'), findsWidgets);
  });
}
