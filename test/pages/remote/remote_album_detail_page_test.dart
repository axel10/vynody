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
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/widgets/album_detail_widgets.dart';

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
  late MockAudioService audioService;

  final testServer = RemoteServer(
    id: 'test_server',
    name: 'Navidrome Server',
    type: RemoteServerType.subsonic,
    url: 'http://127.0.0.1:4533',
    username: 'testuser',
    createdAt: DateTime.now(),
  );

  setUpAll(() async {
    testTempDir = await Directory.systemTemp.createTemp('remote_album_detail_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(testTempDir);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);

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

  tearDownAll(() async {
    try {
      if (testTempDir.existsSync()) {
        testTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Widget createWidget({Size size = const Size(400, 800)}) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceProvider.overrideWith((ref) => audioService),
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

  testWidgets('RemoteAlbumDetailPage renders AlbumDetailNavBar with actions in portrait', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createWidget());
    await tester.pump();

    expect(find.byType(AlbumDetailNavBar), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
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
            coverBackground: const SizedBox(width: 400, height: 400),
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
}
