import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/most_played_tab.dart';
import 'package:vynody/pages/recently_added_tab.dart';
import 'package:vynody/pages/recently_played_tab.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/widgets/draggable_album_item.dart';
import 'package:vynody/widgets/library_ranked_album_list.dart';
import 'package:vynody/widgets/library_ranked_song_list.dart';
import 'package:vynody/widgets/library_selection_panel.dart';
import 'package:vynody/widgets/section_type_toggle.dart';
import 'package:vynody/widgets/time_range_dropdown.dart';

import '../widgets/helpers/mobile_screenshot_harness.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testTempDir;
  late TestSettingsService settingsService;
  late ({
    List<MusicFile> songs,
    List<AlbumSummary> albums,
    Map<String, dynamic> metadataMap
  }) demoData;
  late List<LibraryInsightSongEntry> demoInsightEntries;

  setUpAll(() async {
    testTempDir = Directory.systemTemp.createTempSync('recently_view_tabs_test_');
    PathProviderPlatform.instance = _FakePathProvider(testTempDir);
    await loadMobileTestFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);

    demoData = createDemoLibraryData(
      basePath: '/test/music',
      demoItems: defaultDemoListEn,
    );

    demoInsightEntries = demoData.songs.map((s) {
      return LibraryInsightSongEntry(
        song: s,
        playCount: 5,
        lastPlayedAt: DateTime.now().millisecondsSinceEpoch - 7200000,
        createdAt: DateTime.now().millisecondsSinceEpoch - 86400000,
      );
    }).toList();
  });

  tearDownAll(() {
    try {
      if (testTempDir.existsSync()) {
        testTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Widget buildTestTab(Widget tab, {Size size = const Size(800, 900)}) {
    final audioSnapshot = AudioSnapshot(
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
    final audioService = MockAudioService(
      snapshot: audioSnapshot,
      visualizerStream: const Stream.empty(),
    );

    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceProvider.overrideWith((ref) => audioService),
        audioSnapshotProvider.overrideWith((ref) => audioSnapshot),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        albumLibraryProvider.overrideWith((ref) => Stream.value(demoData.albums)),
        mostPlayedSongsProvider.overrideWith(
          (ref, range) => Stream.value(demoInsightEntries),
        ),
        recentlyPlayedSongsProvider.overrideWith(
          (ref, range) => Stream.value(demoInsightEntries),
        ),
        recentlyAddedSongsProvider.overrideWith(
          (ref, range) => Stream.value(demoInsightEntries),
        ),
      ],
      child: OKToast(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF38BDF8),
              brightness: Brightness.dark,
            ),
          ),
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Scaffold(body: tab),
          ),
        ),
      ),
    );
  }

  Future<void> switchToAlbums(WidgetTester tester) async {
    await tester.tap(find.text('专辑').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('RecentlyPlayedTab - 默认单曲视图，切换后展示专辑视图', (tester) async {
    await tester.pumpWidget(buildTestTab(const RecentlyPlayedTab()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(SectionTypeToggle), findsOneWidget);
    expect(find.byType(TimeRangeDropdown), findsOneWidget);
    expect(find.byType(LibraryRankedSongList), findsOneWidget);
    expect(find.byType(LibraryRankedAlbumList), findsNothing);

    await switchToAlbums(tester);

    expect(find.byType(LibraryRankedAlbumList), findsOneWidget);
    expect(find.byType(LibraryRankedSongList), findsNothing);
  });

  testWidgets('RecentlyAddedTab - 默认单曲视图，切换后展示专辑视图', (tester) async {
    await tester.pumpWidget(buildTestTab(const RecentlyAddedTab()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(SectionTypeToggle), findsOneWidget);
    expect(find.byType(TimeRangeDropdown), findsOneWidget);
    expect(find.byType(LibraryRankedSongList), findsOneWidget);
    expect(find.byType(LibraryRankedAlbumList), findsNothing);

    await switchToAlbums(tester);

    expect(find.byType(LibraryRankedAlbumList), findsOneWidget);
    expect(find.byType(LibraryRankedSongList), findsNothing);
  });

  testWidgets('MostPlayedTab 专辑视图 - 支持长按多选、拖拽与底部操作面板', (tester) async {
    await tester.pumpWidget(buildTestTab(const MostPlayedTab()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await switchToAlbums(tester);

    expect(find.byType(LibraryRankedAlbumList), findsOneWidget);
    // 每一行专辑都是拖拽源
    expect(find.byType(DraggableAlbumItem), findsWidgets);

    // 长按第一行进入多选
    final firstRow = find
        .descendant(of: find.byType(ListView), matching: find.byType(InkWell))
        .first;
    await tester.longPress(firstRow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LibrarySelectionPanel), findsOneWidget);
    expect(find.byType(Checkbox), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
