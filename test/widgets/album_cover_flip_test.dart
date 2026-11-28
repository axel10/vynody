import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/album_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/widgets/album_cover.dart';
import 'package:vynody/widgets/app_top_nav_bar.dart';
import 'package:vynody/widgets/cover_flip_route.dart';

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

Rect _transformedGlobalRect(WidgetTester tester, Finder finder) {
  final renderBox = tester.renderObject<RenderBox>(finder);
  final matrix = renderBox.getTransformTo(null);
  return MatrixUtils.transformRect(matrix, Offset.zero & renderBox.size);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testTempDir;
  late TestSettingsService settingsService;
  late AlbumSummary sampleAlbum;
  late AudioSnapshot baseSnapshot;
  late dynamic demoData;
  late MockAudioService audioService;
  late MockScannerService scannerService;

  setUpAll(() async {
    testTempDir = await Directory.systemTemp.createTemp('album_flip_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(testTempDir);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);

    demoData = createDemoLibraryData(
      basePath: '/test/music',
      demoItems: defaultDemoListEn,
    );
    sampleAlbum = demoData.albums.first;

    baseSnapshot = AudioSnapshot(
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
      snapshot: baseSnapshot,
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

  Widget buildApp(Widget home) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        isBlurEffectEnabledProvider.overrideWith((ref) => true),
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
        home: home,
      ),
    );
  }

  testWidgets('CoverFlipRegistry captures active visible source and skips offstage', (tester) async {
    const tag = 'album_cover:test_1';
    late BuildContext activeCtx;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Offstage(
                offstage: true,
                child: CoverFlipSource(
                  tag: tag,
                  borderRadius: 6.0,
                  child: SizedBox(width: 80, height: 80),
                ),
              ),
              Positioned(
                left: 40,
                top: 120,
                child: Builder(
                  builder: (context) {
                    activeCtx = context;
                    return const CoverFlipSource(
                      tag: tag,
                      borderRadius: 12.0,
                      sourceBucketSize: 250.0,
                      child: SizedBox(
                        key: ValueKey('visible_source'),
                        width: 100,
                        height: 100,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final origin = CoverFlipRegistry.captureOrigin(activeCtx, tag: tag);
    expect(origin, isNotNull);
    expect(origin!.rect, const Rect.fromLTWH(40, 120, 100, 100));
    expect(origin.borderRadius, 12.0);
    expect(origin.sourceBucketSize, 250.0);
  });

  testWidgets('pushAlbumDetailPage flies cover from origin to target and restores on pop', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildApp(
        Scaffold(
          body: Builder(
            builder: (context) {
              return Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, bottom: 80),
                  child: GestureDetector(
                    key: const ValueKey('source_tap'),
                    onTap: () => pushAlbumDetailPage<void>(
                      context,
                      album: sampleAlbum,
                    ),
                    child: CoverFlipSource(
                      tag: albumCoverFlipTag(sampleAlbum.id),
                      borderRadius: 12.0,
                      sourceBucketSize: 250.0,
                      child: AlbumCover(
                        key: const ValueKey('source_cover'),
                        album: sampleAlbum,
                        size: 96,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sourceFinder = find.byKey(const ValueKey('source_cover'));
    final originRect = tester.getRect(sourceFinder);
    expect(originRect.width, 96.0);

    await tester.tap(find.byKey(const ValueKey('source_tap')));
    // Frame 0: the pushed PageRoute is held offstage by MaterialApp's
    // HeroController (`to.offstage = to.animation.value == 0`), so the detail
    // page is mounted but NOT painted on this frame. The source cover must
    // therefore still be visible — hiding it here leaves a one-frame hole where
    // the tapped cover used to be ("点下去的瞬间条目闪一下").
    await tester.pump();
    expect(find.byType(AlbumDetailPage), findsNothing);
    expect(
      find.ancestor(of: sourceFinder, matching: find.byType(Opacity)),
      findsNothing,
    );

    final frame0DetailCoverFinder = find.descendant(
      of: find.byType(AlbumDetailPage, skipOffstage: false),
      matching: find.byType(AlbumCover, skipOffstage: false),
    );
    expect(frame0DetailCoverFinder, findsOneWidget);
    final frame0CoverRect =
        _transformedGlobalRect(tester, frame0DetailCoverFinder);
    expect(frame0CoverRect.left, closeTo(originRect.left, 0.5));
    expect(frame0CoverRect.top, closeTo(originRect.top, 0.5));
    expect(frame0CoverRect.width, closeTo(originRect.width, 0.5));
    expect(
      find.descendant(
        of: find.descendant(
          of: find.byType(AlbumDetailPage, skipOffstage: false),
          matching: find.byType(AppTopNavBar, skipOffstage: false),
        ),
        matching: find.byType(BackdropFilter, skipOffstage: false),
      ),
      findsNothing,
    );

    // Frame 1+: target measured, flight advances smoothly without BackdropFilter.
    await tester.pump(const Duration(milliseconds: 16));

    // Detail AlbumCover should now be flying and source should be hidden (opacity 0).
    final sourceOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: sourceFinder,
        matching: find.byType(Opacity),
      ).first,
    );
    expect(sourceOpacity.opacity, 0.0);

    final detailCoverFinder = find.descendant(
      of: find.byType(AlbumDetailPage),
      matching: find.byType(AlbumCover),
    );
    expect(detailCoverFinder, findsOneWidget);
    final midStartRect = _transformedGlobalRect(tester, detailCoverFinder);
    // Early in flight, cover is much closer to origin (96x96) than target (260x260).
    expect(midStartRect.width, lessThan(160.0));
    expect(midStartRect.top, greaterThan(originRect.top - 120.0));
    expect(
      find.descendant(
        of: find.descendant(
          of: find.byType(AlbumDetailPage),
          matching: find.byType(AppTopNavBar),
        ),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );

    final Element flyingElement = tester.element(detailCoverFinder);

    // Advance to mid-flight.
    await tester.pump(const Duration(milliseconds: 160));
    final midRect = _transformedGlobalRect(tester, detailCoverFinder);
    expect(midRect.width, greaterThan(midStartRect.width));
    expect(midRect.width, lessThan(260.0));
    expect(tester.element(detailCoverFinder), same(flyingElement));

    // Settle into detail page; AppTopNavBar blur is restored once transition completes.
    await tester.pumpAndSettle();
    expect(tester.element(detailCoverFinder), same(flyingElement));
    final settledRect = _transformedGlobalRect(tester, detailCoverFinder);
    expect(settledRect.width, closeTo(260.0, 0.5));
    expect(settledRect.height, closeTo(260.0, 0.5));
    expect(
      find.descendant(
        of: find.descendant(
          of: find.byType(AlbumDetailPage),
          matching: find.byType(AppTopNavBar),
        ),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );

    // Pop back: cover should fly back and source becomes visible again once dismissed.
    Navigator.of(tester.element(find.byType(AlbumDetailPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final popMidRect = _transformedGlobalRect(tester, detailCoverFinder);
    expect(popMidRect.width, lessThan(260.0));
    expect(popMidRect.width, greaterThan(96.0));

    await tester.pumpAndSettle();
    expect(find.byType(AlbumDetailPage), findsNothing);
    // Source cover is visible again (no Opacity(0) wrapper left).
    final restoredOpacityFinder = find.ancestor(
      of: sourceFinder,
      matching: find.byType(Opacity),
    );
    expect(restoredOpacityFinder, findsNothing);
  });

  testWidgets('push 首帧不留空白：源封面可见性只在详情页已绘制的那一帧让出', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildApp(
        Scaffold(
          body: Builder(
            builder: (context) {
              return Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, bottom: 80),
                  child: GestureDetector(
                    key: const ValueKey('blank_source_tap'),
                    onTap: () => pushAlbumDetailPage<void>(
                      context,
                      album: sampleAlbum,
                    ),
                    child: CoverFlipSource(
                      tag: albumCoverFlipTag(sampleAlbum.id),
                      borderRadius: 12.0,
                      sourceBucketSize: 250.0,
                      child: AlbumCover(
                        key: const ValueKey('blank_source_cover'),
                        album: sampleAlbum,
                        size: 96,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sourceFinder = find.byKey(const ValueKey('blank_source_cover'));
    final originRect = tester.getRect(sourceFinder);

    await tester.tap(find.byKey(const ValueKey('blank_source_tap')));

    for (int frame = 0; frame < 4; frame++) {
      await tester.pump(
        frame == 0 ? Duration.zero : const Duration(milliseconds: 16),
      );

      final bool sourceHidden = find
          .ancestor(of: sourceFinder, matching: find.byType(Opacity))
          .evaluate()
          .any((e) => (e.widget as Opacity).opacity == 0.0);
      final bool detailPainted =
          find.byType(AlbumDetailPage).evaluate().isNotEmpty;

      // 不变量：源封面被隐藏时，详情页必须已经在绘制（飞行层接管那一刻起），
      // 否则列表上就出现「既没有源封面、也没有飞行封面」的空白帧。
      expect(
        sourceHidden && !detailPainted,
        isFalse,
        reason: 'frame $frame 出现空白帧：源封面已隐藏但详情页尚未绘制',
      );

      if (detailPainted) {
        final coverFinder = find.descendant(
          of: find.byType(AlbumDetailPage),
          matching: find.byType(AlbumCover),
        );
        final rect = _transformedGlobalRect(tester, coverFinder);
        // 首次绘制时飞行封面必须贴着源尺寸起飞，不能先跳到 260 的目标槽位。
        if (frame <= 1) {
          expect(rect.width, lessThan(originRect.width + 24.0));
        }
      }
    }

    await tester.pumpAndSettle();
    expect(find.byType(AlbumDetailPage), findsOneWidget);
  });

  testWidgets('pushAlbumDetailPage falls back to MaterialPageRoute without source', (tester) async {
    await tester.pumpWidget(
      buildApp(
        Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => pushAlbumDetailPage<void>(
                context,
                album: sampleAlbum,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final detailWidget = tester.widget<AlbumDetailPage>(
      find.byType(AlbumDetailPage),
    );
    expect(detailWidget.coverOrigin, isNull);
    expect(find.byType(AlbumCover), findsOneWidget);
  });

  testWidgets('pop falls back to fade and restores source when scrolled past cover', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final baseSong = sampleAlbum.songs.first;
    final longSongs = List.generate(
      30,
      (i) => baseSong.copyWith(
        id: i + 1,
        path: '/test/music/track_$i.flac',
        title: 'Track $i',
      ),
    );
    final longAlbum = AlbumSummary(
      id: '${sampleAlbum.id}_long',
      title: sampleAlbum.title,
      artist: sampleAlbum.artist,
      songs: longSongs,
      representativeSong: longSongs.first,
      totalDurationMillis: longSongs.length * 180000,
    );

    await tester.pumpWidget(
      buildApp(
        Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: GestureDetector(
                  key: const ValueKey('source_tap_scroll'),
                  onTap: () => pushAlbumDetailPage<void>(
                    context,
                    album: longAlbum,
                  ),
                  child: CoverFlipSource(
                    tag: albumCoverFlipTag(longAlbum.id),
                    borderRadius: 12.0,
                    child: AlbumCover(
                      key: const ValueKey('source_cover_scroll'),
                      album: longAlbum,
                      size: 100,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('source_tap_scroll')));
    await tester.pumpAndSettle();

    // Scroll far down so the header cover is completely off-screen.
    final scrollFinder = find.descendant(
      of: find.byType(AlbumDetailPage),
      matching: find.byType(Scrollable),
    );
    await tester.drag(scrollFinder.first, const Offset(0, -1000));
    await tester.pumpAndSettle();

    // Trigger pop; source cover must immediately become visible again during fade pop.
    Navigator.of(tester.element(find.byType(AlbumDetailPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final sourceFinder = find.byKey(const ValueKey('source_cover_scroll'));
    final sourceOpacity = find.ancestor(
      of: sourceFinder,
      matching: find.byType(Opacity),
    );
    expect(sourceOpacity, findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(AlbumDetailPage), findsNothing);
  });
}
