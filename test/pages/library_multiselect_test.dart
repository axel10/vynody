// 媒体库多选（二级分类页 / 三级详情页）端到端 Widget 测试。
//
// 重点覆盖：
// 1. 【回归】进入多选后不会被立刻踢出多选。
//    历史上 LibrarySubHostPage / 详情页把 PopScope 条件性地包在根节点上，
//    多选激活会让根节点 runtimeType 变化（AutoHideHeaderScope <-> PopScope），
//    Flutter 于是销毁并重建整棵子树；持有选中项的 widget 也在其中，
//    其 SongSelectionMixin.dispose 里的 Future.microtask(clearIfScope) 会在帧后
//    把刚建立的选中项清掉 —— 表现就是「一进入多选就立刻退出」。
// 2. 多选交互：累加选中 / 全选 / 取消。
// 3. 进入多选不重建列表子树（搜索框内容等 State 保留）。
// 4. 多选状态下系统返回键先退出多选，再次返回才离开页面。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/pages/album_detail_page.dart';
import 'package:vynody/pages/artist_detail_page.dart';
import 'package:vynody/pages/library_page.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/widgets/library_selection_scope.dart';

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

/// 固定媒体库子分类索引（5 = 艺术家）
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
  late List<MusicFile> demoSongs;
  late List<ArtistSummary> artists;
  late AlbumSummary sampleAlbum;

  setUpAll(() async {
    testTempDir = Directory.systemTemp.createTempSync('library_multiselect_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(testTempDir);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);

    final demoData = createDemoLibraryData(
      basePath: '/test/music',
      demoItems: defaultDemoListEn.take(6).toList(),
    );
    demoSongs = demoData.songs;

    // 三位艺术家：第一位带 3 首歌（横屏内嵌详情面板需要多首歌），
    // 另外两位各 1 首，便于区分「部分选中」与「全选」两种面板状态。
    artists = [
      ArtistSummary(
        queryKey: 'lin zhou',
        name: 'Lin Zhou',
        songs: demoSongs.take(3).toList(),
        representativeSong: demoSongs[0],
        songCount: 3,
      ),
      ArtistSummary(
        queryKey: 'sen mo',
        name: 'Sen Mo',
        songs: [demoSongs[3]],
        representativeSong: demoSongs[3],
        songCount: 1,
      ),
      ArtistSummary(
        queryKey: 'noon park',
        name: 'Noon Park',
        songs: [demoSongs[4]],
        representativeSong: demoSongs[4],
        songCount: 1,
      ),
    ];

    sampleAlbum = AlbumSummary(
      id: 'city glimmer::lin zhou',
      title: 'City Glimmer',
      artist: 'Lin Zhou',
      songs: demoSongs.take(3).toList(),
      representativeSong: demoSongs[0],
      totalDurationMillis: demoSongs
          .take(3)
          .fold<int>(0, (sum, s) => sum + (s.durationMillis ?? 0)),
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

  setUp(() {
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
        audioServiceStateProvider.overrideWith(() => audioService),
        audioServiceProvider.overrideWith((ref) => audioService),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        scannerServiceProvider.overrideWith((ref) => scannerService),
        playlistServiceProvider.overrideWith((ref) => playlistService),
        artistLibraryProvider.overrideWith((ref) => Stream.value(artists)),
        // 媒体库二级分类宿主固定停在「艺术家」页
        libraryActiveTabIndexProvider.overrideWith(
          () => _FixedLibraryTabIndexNotifier(5),
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
        home: child,
      ),
    );
  }

  void setSurface(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 进入多选后多跑几帧（含 dispose 微任务落地），断言多选仍在。
  Future<void> pumpFramesAfterSelection(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  LibrarySelectionState selectionOf(ProviderContainer container) =>
      container.read(librarySelectionStateProvider);

  group('媒体库二级页多选（LibrarySubHostPage + ArtistsTab）', () {
    testWidgets('长按艺术家进入多选后保持激活（回归：不会被立刻退出）', (tester) async {
      setSurface(tester, const Size(390, 844));
      final container = createContainer();

      await tester.pumpWidget(wrap(container, const LibrarySubHostPage()));
      await tester.pumpAndSettle();
      expect(find.text('Lin Zhou'), findsOneWidget);

      await tester.longPress(find.text('Lin Zhou'));
      await pumpFramesAfterSelection(tester);

      final state = selectionOf(container);
      expect(state.isActive, isTrue);
      expect(state.scope, LibrarySelectionScope.artist);
      expect(state.selectedKeys, {'lin zhou'});
      expect(container.read(librarySelectionScopeProvider),
          LibrarySelectionScope.artist);
      expect(find.byKey(const ValueKey('artist-selection-panel')),
          findsOneWidget);
      expect(find.text('已选择 1 位艺术家'), findsOneWidget);

      // 再等一阵，确认不会被子树重建后的 dispose 清掉
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('artist-selection-panel')),
          findsOneWidget);
      expect(selectionOf(container).selectedKeys, {'lin zhou'});
    });

    testWidgets('多选状态下可累加选中、全选、取消退出', (tester) async {
      setSurface(tester, const Size(390, 844));
      final container = createContainer();

      await tester.pumpWidget(wrap(container, const LibrarySubHostPage()));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Lin Zhou'));
      await pumpFramesAfterSelection(tester);
      expect(selectionOf(container).selectedKeys, {'lin zhou'});
      expect(find.text('已选择 1 位艺术家'), findsOneWidget);
      // 只选中了 3 位中的 1 位 -> 面板处于「全选」态
      expect(find.text('全选'), findsOneWidget);

      // 点击另一条累加
      await tester.tap(find.text('Sen Mo'));
      await tester.pump();
      expect(selectionOf(container).selectedKeys, {'lin zhou', 'sen mo'});
      expect(find.text('已选择 2 位艺术家'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);

      // 全选
      await tester.tap(find.text('全选'));
      await tester.pump();
      expect(selectionOf(container).selectedKeys,
          {'lin zhou', 'sen mo', 'noon park'});
      expect(find.text('已选择 3 位艺术家'), findsOneWidget);
      expect(find.text('取消全选'), findsOneWidget);

      // 取消全选 -> 清空选中并退出多选
      await tester.tap(find.text('取消全选'));
      await tester.pump();
      expect(selectionOf(container).isActive, isFalse);
      expect(selectionOf(container).scope, LibrarySelectionScope.none);
      expect(container.read(isLibrarySelectionActiveProvider), isFalse);

      // 重新进入后点关闭按钮退出
      await tester.longPress(find.text('Lin Zhou'));
      await pumpFramesAfterSelection(tester);
      expect(selectionOf(container).isActive, isTrue);

      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('artist-selection-panel')),
        matching: find.byIcon(Icons.close),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(selectionOf(container).isActive, isFalse);
      expect(find.byKey(const ValueKey('artist-selection-panel')),
          findsNothing);
    });

    testWidgets('进入多选不会重建列表子树（搜索状态保留）', (tester) async {
      setSurface(tester, const Size(390, 844));
      final container = createContainer();

      await tester.pumpWidget(wrap(container, const LibrarySubHostPage()));
      await tester.pumpAndSettle();

      final searchBtn = find.byIcon(Icons.search_rounded);
      if (searchBtn.evaluate().isNotEmpty) {
        await tester.tap(searchBtn);
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byType(TextField), 'Sen');
      await tester.pump();
      expect(find.text('Lin Zhou'), findsNothing);
      expect(find.text('Sen Mo'), findsOneWidget);

      await tester.longPress(find.text('Sen Mo'));
      await pumpFramesAfterSelection(tester);

      // 若子树被销毁重建，搜索词会被重置为空、列表恢复全量
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'Sen');
      expect(find.text('Lin Zhou'), findsNothing);
      expect(selectionOf(container).selectedKeys, {'sen mo'});
    });
  });

  group('媒体库二级页内嵌详情（横屏歌曲多选）', () {
    testWidgets('横屏艺术家页长按歌曲进入多选后保持激活（回归）', (tester) async {
      setSurface(tester, const Size(1280, 800));
      final container = createContainer();

      await tester.pumpWidget(wrap(container, const LibrarySubHostPage()));
      await tester.pumpAndSettle();

      // 横屏下艺术家页右侧内嵌详情面板（scope = library）
      final songTitle = demoSongs[0].displayName;
      expect(find.text(songTitle), findsOneWidget);

      await tester.longPress(find.text(songTitle));
      await pumpFramesAfterSelection(tester);

      final state = selectionOf(container);
      expect(state.isActive, isTrue);
      expect(state.scope, LibrarySelectionScope.library);
      expect(state.selectedKeys, {demoSongs[0].path});
      expect(find.byKey(const ValueKey('song-selection-panel')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('artist-selection-panel')),
          findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('song-selection-panel')),
          findsOneWidget);
      expect(selectionOf(container).selectedKeys, {demoSongs[0].path});
    });
  });

  group('媒体库三级详情页多选', () {
    testWidgets('专辑详情页：长按歌曲进入多选、累加、全选、取消', (tester) async {
      setSurface(tester, const Size(1280, 800));
      final container = createContainer();

      await tester.pumpWidget(wrap(container, AlbumDetailPage(album: sampleAlbum)));
      await tester.pumpAndSettle();

      final songs = sampleAlbum.songs;

      await tester.longPress(find.text(songs[0].displayName));
      await pumpFramesAfterSelection(tester);

      expect(selectionOf(container).scope, LibrarySelectionScope.library);
      expect(selectionOf(container).selectedKeys, {songs[0].path});
      expect(find.byKey(const ValueKey('library-selection-panel')),
          findsOneWidget);
      expect(find.text('已选择 1 首'), findsOneWidget);

      // 累加第二首
      await tester.tap(find.text(songs[1].displayName));
      await tester.pump();
      expect(selectionOf(container).selectedKeys,
          {songs[0].path, songs[1].path});
      expect(find.text('已选择 2 首'), findsOneWidget);

      // 全选
      await tester.tap(find.text('全选'));
      await tester.pump();
      expect(selectionOf(container).selectedKeys.length, songs.length);

      // 取消
      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('library-selection-panel')),
        matching: find.byIcon(Icons.close),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(selectionOf(container).isActive, isFalse);
      expect(find.byKey(const ValueKey('library-selection-panel')),
          findsNothing);
    });

    testWidgets('艺术家详情页：长按歌曲进入多选后保持激活', (tester) async {
      setSurface(tester, const Size(390, 1400));
      final container = createContainer();
      final artist = artists.first;

      await tester.pumpWidget(wrap(container, ArtistDetailPage(artist: artist)));
      await tester.pumpAndSettle();

      final song = artist.songs.first;
      await tester.longPress(find.byKey(ValueKey(song.path)));
      await pumpFramesAfterSelection(tester);

      expect(selectionOf(container).scope, LibrarySelectionScope.library);
      expect(selectionOf(container).selectedKeys, {song.path});
      expect(find.byKey(const ValueKey('library-selection-panel')),
          findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('library-selection-panel')),
          findsOneWidget);
      expect(selectionOf(container).selectedKeys, {song.path});
    });

    testWidgets('多选状态下返回键先退出多选，再次返回才关闭页面', (tester) async {
      setSurface(tester, const Size(1280, 800));
      final container = createContainer();

      await tester.pumpWidget(
        wrap(
          container,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AlbumDetailPage(album: sampleAlbum),
                    ),
                  ),
                  child: const Text('open-album'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open-album'));
      await tester.pumpAndSettle();
      expect(find.byType(AlbumDetailPage), findsOneWidget);

      await tester.longPress(find.text(sampleAlbum.songs[0].displayName));
      await pumpFramesAfterSelection(tester);
      expect(selectionOf(container).isActive, isTrue);

      // 第一次返回：只退出多选，页面保留
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(selectionOf(container).isActive, isFalse);
      expect(find.byType(AlbumDetailPage), findsOneWidget);

      // 第二次返回：正常关闭页面
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlbumDetailPage), findsNothing);
      expect(find.text('open-album'), findsOneWidget);
    });
  });
}
