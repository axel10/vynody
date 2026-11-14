import 'dart:io';
import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/remote_album_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/utils/app_icons.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'package:vynody/widgets/album_detail_widgets.dart';
import 'package:vynody/widgets/app_top_nav_bar.dart';
import 'package:vynody/pages/remote/remote_library_sub_host_page.dart';

import '../../widgets/helpers/mobile_screenshot_harness.dart';

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

  final testServer = RemoteServer(
    id: 'test_server',
    name: 'Navidrome Server',
    type: RemoteServerType.subsonic,
    url: 'http://127.0.0.1:4533',
    username: 'testuser',
    createdAt: DateTime.now(),
  );

  MockAudioService createAudioService() {
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

    return MockAudioService(
      snapshot: snapshot,
      visualizerStream: const Stream.empty(),
    );
  }

  setUpAll(() async {
    testTempDir = await Directory.systemTemp.createTemp('remote_album_detail_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(testTempDir);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);
  });

  tearDownAll(() async {
    try {
      if (testTempDir.existsSync()) {
        testTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Widget createWidget({Size size = const Size(400, 800)}) {
    final audio = createAudioService();
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceStateProvider.overrideWith(() => audio),
        audioServiceProvider.overrideWith((ref) => audio),
        audioCurrentMusicProvider.overrideWith((ref) => null),
      ],
      child: OKToast(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.only(top: 24),
            ),
            child: RemoteAlbumDetailPage(
              server: testServer,
              password: 'password',
              albumId: 'al-123',
              albumName: 'Remote Test Album',
              artistName: 'Remote Test Artist',
              coverArtId: 'art-123',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('RemoteAlbumDetailPage renders AppTopNavBar with refresh action in landscape only and aligns to contentMaxWidth', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createWidget(size: const Size(1400, 900)));
    await tester.pump();

    // Verify AppTopNavBar is rendered instead of legacy AlbumDetailNavBar
    expect(find.byType(AppTopNavBar), findsOneWidget);
    expect(find.byIcon(kAppBackIcon), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.my_location_rounded), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsNothing);

    // Verify AppTopNavBar receives contentMaxWidth = kSingleColumnContentMaxWidth
    final navBar = tester.widget<AppTopNavBar>(find.byType(AppTopNavBar));
    expect(navBar.contentMaxWidth, equals(kSingleColumnContentMaxWidth));
    expect(navBar.actions, hasLength(1));

    // Portrait hides top-bar refresh action (uses pull-to-refresh)
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpWidget(createWidget(size: const Size(400, 800)));
    await tester.pump();
    final portraitNavBar = tester.widget<AppTopNavBar>(find.byType(AppTopNavBar));
    expect(portraitNavBar.actions, isNull);
  });

  testWidgets('AlbumPortraitHeaderBanner and AlbumLandscapeHeaderBanner render remote album presentation', (tester) async {
    // 1. Portrait
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlbumPortraitHeaderBanner(
            title: 'Remote Album',
            subtitle: 'Remote Artist',
            tagLabel: 'ALBUM',
            metadata: const Text('10 songs'),
            actionButtons: const [Icon(Icons.play_arrow)],
            coverWidget: const SizedBox(width: 160, height: 160),
            barHeight: 80,
          ),
        ),
      ),
    );
    expect(find.byType(AlbumPortraitHeaderBanner), findsOneWidget);
    expect(find.text('Remote Album'), findsOneWidget);
    expect(find.text('Remote Artist'), findsOneWidget);

    // 2. Landscape
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlbumLandscapeHeaderBanner(
            title: 'Remote Album',
            subtitle: 'Remote Artist',
            tagLabel: 'ALBUM',
            metadata: const Text('10 songs'),
            actionButtons: const [Icon(Icons.play_arrow)],
            coverWidget: const SizedBox(width: 200, height: 200),
          ),
        ),
      ),
    );
    expect(find.byType(AlbumLandscapeHeaderBanner), findsOneWidget);
    expect(find.text('Remote Album'), findsOneWidget);
  });

  testWidgets('RemoteAlbumDetailPage within RemoteLibrarySubHostPage has single railWidth padding in landscape', (tester) async {
    const screenSize = Size(1200, 800);
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final navigatorKeys = List.generate(6, (_) => GlobalKey<NavigatorState>());

    final audio = createAudioService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settingsService),
          audioServiceStateProvider.overrideWith(() => audio),
          audioServiceProvider.overrideWith((ref) => audio),
          audioCurrentMusicProvider.overrideWith((ref) => null),
        ],
        child: OKToast(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(
                size: screenSize,
                padding: EdgeInsets.only(top: 24),
              ),
              child: Scaffold(
                body: RemoteLibrarySubHostPage(
                  initialIndex: 0,
                  navigatorKeys: navigatorKeys,
                  onBack: () {},
                  onRefresh: (_) {},
                  tabs: [
                    (ctx) => ElevatedButton(
                      onPressed: () {
                        navigatorKeys[0].currentState?.push(
                          MaterialPageRoute(
                            builder: (_) => RemoteAlbumDetailPage(
                              server: testServer,
                              password: 'password',
                              albumId: 'al-123',
                              albumName: 'Remote Test Album',
                            ),
                          ),
                        );
                      },
                      child: const Text('Open Album'),
                    ),
                    for (int i = 1; i < 6; i++) (ctx) => const SizedBox(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 点击打开详情页
    await tester.tap(find.text('Open Album'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(RemoteAlbumDetailPage), findsOneWidget);

    // 详情页自身作为全屏路由，其左侧贴合屏幕边缘 (0.0)
    final detailPageFinder = find.byType(RemoteAlbumDetailPage);
    final detailPageRect = tester.getRect(detailPageFinder);
    expect(detailPageRect.left, equals(0.0));

    // RemoteAlbumDetailPage 内的 Scaffold body 的左内边距正好是一次 railWidth
    final scaffoldBodyFinder = find.descendant(
      of: detailPageFinder,
      matching: find.byType(Scaffold),
    );
    expect(scaffoldBodyFinder, findsOneWidget);
    final scaffoldBodyWidget = tester.widget<Scaffold>(scaffoldBodyFinder);
    final bodyPadding = scaffoldBodyWidget.body as Padding;
    final edgeInsets = bodyPadding.padding as EdgeInsets;
    // 横屏下 railWidth > 0 且仅被避让一次（默认展开态侧栏宽度为 216.0）
    expect(edgeInsets.left, equals(216.0));
  });
}
