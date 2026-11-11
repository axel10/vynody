import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/remote_playlist_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/utils/app_icons.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'package:vynody/widgets/app_top_nav_bar.dart';

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
    testTempDir =
        await Directory.systemTemp.createTemp('remote_playlist_detail_test_');
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

  Widget createWidget({Size size = const Size(1400, 900)}) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceStateProvider.overrideWith(() => audioService),
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
            child: RemotePlaylistDetailPage(
              server: testServer,
              password: 'password',
              playlistId: 'pl-123',
              playlistName: 'Remote Test Playlist',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'RemotePlaylistDetailPage renders AppTopNavBar without actions and aligns to contentMaxWidth',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createWidget());
    await tester.pump();

    // Verify AppTopNavBar is rendered without actions
    expect(find.byType(AppTopNavBar), findsOneWidget);
    expect(find.byIcon(kAppBackIcon), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsNothing);
    expect(find.byIcon(Icons.my_location_rounded), findsNothing);

    // Verify contentMaxWidth is set
    final navBar = tester.widget<AppTopNavBar>(find.byType(AppTopNavBar));
    expect(navBar.contentMaxWidth, equals(kFolderPageMaxWidth));
    expect(navBar.actions, isNull);
  });
}
