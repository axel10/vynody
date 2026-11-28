import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/pages/artist_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/widgets/artist_avatar.dart';
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
  late ArtistSummary sampleArtist;
  late AudioSnapshot baseSnapshot;
  late dynamic demoData;
  late MockAudioService audioService;
  late MockScannerService scannerService;

  setUpAll(() async {
    testTempDir = await Directory.systemTemp.createTemp('artist_flip_test_');
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

  testWidgets(
      'pushArtistDetailPage flies avatar from origin to header slot and restores on pop',
      (tester) async {
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
                    onTap: () => pushArtistDetailPage<void>(
                      context,
                      artist: sampleArtist,
                    ),
                    child: CoverFlipSource(
                      tag: artistAvatarFlipTag(sampleArtist.queryKey),
                      borderRadius: 48.0,
                      child: ArtistAvatar(
                        key: const ValueKey('source_avatar'),
                        diameter: 96,
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

    final sourceFinder = find.byKey(const ValueKey('source_avatar'));
    final originRect = tester.getRect(sourceFinder);
    expect(originRect.width, 96.0);

    await tester.tap(find.byKey(const ValueKey('source_tap')));
    // Frame 0: source hidden, pushed route offstage for one frame, flight cover
    // already parked at the origin rect.
    await tester.pump();
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: sourceFinder, matching: find.byType(Opacity)).first,
          )
          .opacity,
      0.0,
    );
    final flyingCoverFinder = find.descendant(
      of: find.byType(ArtistDetailPage, skipOffstage: false),
      matching: find.byType(ArtistAvatar, skipOffstage: false),
    );
    expect(flyingCoverFinder, findsOneWidget);
    final frame0Rect = _transformedGlobalRect(tester, flyingCoverFinder);
    expect(frame0Rect.left, closeTo(originRect.left, 0.5));
    expect(frame0Rect.top, closeTo(originRect.top, 0.5));
    expect(frame0Rect.width, closeTo(originRect.width, 0.5));

    // Frame 1+: target slot measured, flight advances towards the header avatar
    // (104dp in portrait for this screen width).
    await tester.pump(const Duration(milliseconds: 16));
    final earlyRect = _transformedGlobalRect(tester, flyingCoverFinder);
    expect(earlyRect.width, lessThan(160.0));
    final Element flyingElement = tester.element(flyingCoverFinder);

    await tester.pump(const Duration(milliseconds: 160));
    final midRect = _transformedGlobalRect(tester, flyingCoverFinder);
    expect(midRect.width, greaterThan(earlyRect.width));
    expect(midRect.width, lessThan(104.0));

    await tester.pumpAndSettle();
    // Landing keeps the very same element (GlobalKey handoff into the slot).
    expect(tester.element(flyingCoverFinder), same(flyingElement));
    final settledRect = _transformedGlobalRect(tester, flyingCoverFinder);
    expect(settledRect.width, closeTo(104.0, 0.5));
    expect(settledRect.height, closeTo(104.0, 0.5));

    // Pop back: flies home, then the source avatar becomes visible again.
    Navigator.of(tester.element(find.byType(ArtistDetailPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final popMidRect = _transformedGlobalRect(tester, flyingCoverFinder);
    expect(popMidRect.width, lessThan(104.0));
    expect(popMidRect.width, greaterThan(96.0));

    await tester.pumpAndSettle();
    expect(find.byType(ArtistDetailPage), findsNothing);
    expect(
      find.ancestor(of: sourceFinder, matching: find.byType(Opacity)),
      findsNothing,
    );
  });

  testWidgets('pushArtistDetailPage falls back to MaterialPageRoute without source',
      (tester) async {
    await tester.pumpWidget(
      buildApp(
        Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => pushArtistDetailPage<void>(
                context,
                artist: sampleArtist,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final detailWidget = tester.widget<ArtistDetailPage>(
      find.byType(ArtistDetailPage),
    );
    expect(detailWidget.avatarOrigin, isNull);
    expect(find.byType(ArtistAvatar), findsWidgets);
  });
}
