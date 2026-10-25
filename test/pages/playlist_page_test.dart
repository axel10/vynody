import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/pages/playlist_detail_page.dart';
import 'package:vynody/pages/playlist_tab.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/playlist_service.dart';

import '../widgets/helpers/mobile_screenshot_harness.dart' hide Playlist;

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

class _TestPlaylistService extends PlaylistService {
  final List<Playlist> _customPlaylists = [];

  _TestPlaylistService([List<Playlist>? initial]) {
    if (initial != null) {
      _customPlaylists.addAll(initial);
    }
  }

  @override
  List<Playlist> get playlists => List.unmodifiable(_customPlaylists);

  @override
  Future<Playlist> createPlaylist(String name) async {
    final pl = Playlist(
      id: 'test_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
    );
    _customPlaylists.add(pl);
    notifyListeners();
    return pl;
  }

  @override
  Future<void> addSongsToPlaylist(String playlistId, List<MusicFile> songs) async {
    final index = _customPlaylists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final updated = _customPlaylists[index].copyWith(
        songs: [..._customPlaylists[index].songs, ...songs],
      );
      _customPlaylists[index] = updated;
      notifyListeners();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testTempDir;
  late TestSettingsService settingsService;
  late MockAudioService audioService;
  late MockScannerService scannerService;
  late _TestPlaylistService playlistService;
  late AudioSnapshot snapshot;

  setUpAll(() async {
    testTempDir = Directory.systemTemp.createTempSync('playlist_tab_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(testTempDir);
    await loadMobileTestFonts();
  });

  tearDownAll(() {
    try {
      if (testTempDir.existsSync()) {
        testTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);

    snapshot = AudioSnapshot(
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

    scannerService = MockScannerService(
      rootFolders: const [],
    );

    playlistService = _TestPlaylistService();
  });

  Widget buildTestWidget({WidgetRef? outRef, ProviderContainer? container}) {
    final app = MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: PlaylistTab(),
      ),
    );

    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: OKToast(child: app),
      );
    }

    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceProvider.overrideWith((ref) => audioService),
        audioSnapshotProvider.overrideWith((ref) => snapshot),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        scannerServiceProvider.overrideWith((ref) => scannerService),
        playlistServiceProvider.overrideWith((ref) => playlistService),
      ],
      child: OKToast(child: app),
    );
  }

  testWidgets('PlaylistTab navigates to detail and pops when selectedPlaylistId is set to null',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final testPlaylist = await playlistService.createPlaylist('我的专属歌单');
    await playlistService.addSongsToPlaylist(testPlaylist.id, [
      const MusicFile(
        path: '/test/music/song1.mp3',
        name: 'song1.mp3',
        title: '测试曲目一',
        artist: '测试歌手',
        durationMillis: 180000,
      ),
    ]);

    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceProvider.overrideWith((ref) => audioService),
        audioSnapshotProvider.overrideWith((ref) => snapshot),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        scannerServiceProvider.overrideWith((ref) => scannerService),
        playlistServiceProvider.overrideWith((ref) => playlistService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildTestWidget(container: container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('我的专属歌单'), findsOneWidget);

    // Tap on playlist item to open detail
    await tester.tap(find.text('我的专属歌单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PlaylistDetailPage), findsOneWidget);
    expect(container.read(selectedPlaylistIdProvider), testPlaylist.id);

    // Now simulate clicking "All Playlists" in Rail: selectedPlaylistIdProvider -> null
    container.read(selectedPlaylistIdProvider.notifier).set(null);
    await tester.pumpAndSettle();

    // Detail page should be popped back to PlaylistTab list!
    expect(find.byType(PlaylistDetailPage), findsNothing);
    expect(find.text('我的专属歌单'), findsOneWidget);
  });

  testWidgets('PlaylistTab switches directly from playlist A to playlist B',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final playlistA = await playlistService.createPlaylist('歌单A');
    final playlistB = await playlistService.createPlaylist('歌单B');
    await playlistService.addSongsToPlaylist(playlistA.id, [
      const MusicFile(
        path: '/test/music/songA.mp3',
        name: 'songA.mp3',
        title: '曲目A',
        artist: '歌手A',
        durationMillis: 180000,
      ),
    ]);
    await playlistService.addSongsToPlaylist(playlistB.id, [
      const MusicFile(
        path: '/test/music/songB.mp3',
        name: 'songB.mp3',
        title: '曲目B',
        artist: '歌手B',
        durationMillis: 200000,
      ),
    ]);

    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceProvider.overrideWith((ref) => audioService),
        audioSnapshotProvider.overrideWith((ref) => snapshot),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        scannerServiceProvider.overrideWith((ref) => scannerService),
        playlistServiceProvider.overrideWith((ref) => playlistService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildTestWidget(container: container));
    await tester.pumpAndSettle();

    // Open playlist A
    await tester.tap(find.text('歌单A'));
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistDetailPage), findsOneWidget);
    expect(find.text('曲目A'), findsOneWidget);
    expect(container.read(selectedPlaylistIdProvider), playlistA.id);

    // Switch to playlist B via provider (like clicking playlist B on rail)
    container.read(selectedPlaylistIdProvider.notifier).set(playlistB.id);
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistDetailPage), findsOneWidget);
    expect(find.text('曲目B'), findsOneWidget);
    expect(find.text('曲目A'), findsNothing);
    expect(container.read(selectedPlaylistIdProvider), playlistB.id);
  });
}
