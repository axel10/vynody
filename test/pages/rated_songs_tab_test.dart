import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/rated_songs_tab.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import 'package:vynody/player/settings/settings_service.dart';

import '../widgets/helpers/mobile_screenshot_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settingsService;
  late MockAudioService audioService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = SettingsService(prefs);

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

  final testSongs = [
    LibraryInsightSongEntry(
      song: const MusicFile(
        path: '/music/song_5star.mp3',
        name: 'song_5star.mp3',
        title: 'Song Five',
        artist: 'Artist A',
        durationMillis: 180000,
      ),
      playCount: 5,
      createdAt: 500,
    ),
    LibraryInsightSongEntry(
      song: const MusicFile(
        path: '/music/song_3star.mp3',
        name: 'song_3star.mp3',
        title: 'Song Three',
        artist: 'Artist B',
        durationMillis: 200000,
      ),
      playCount: 3,
      createdAt: 300,
    ),
    LibraryInsightSongEntry(
      song: const MusicFile(
        path: '/music/song_1star.mp3',
        name: 'song_1star.mp3',
        title: 'Song One',
        artist: 'Artist C',
        durationMillis: 150000,
      ),
      playCount: 1,
      createdAt: 100,
    ),
  ];

  Widget buildTestWidget() {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceStateProvider.overrideWith(() => audioService),
        audioServiceProvider.overrideWithValue(audioService),
        allRatedSongsProvider.overrideWith(
          (ref) => Stream.value(testSongs),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: Scaffold(
          body: RatedSongsTab(),
        ),
      ),
    );
  }

  testWidgets('displays all rated songs including 1, 3, and 5 stars', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Song Five'), findsOneWidget);
    expect(find.text('Song Three'), findsOneWidget);
    expect(find.text('Song One'), findsOneWidget);
  });

  testWidgets('star filter chip filters songs to only selected star rating', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Tap 3 star chip
    final threeStarChip = find.widgetWithText(ChoiceChip, '3');
    expect(threeStarChip, findsOneWidget);
    await tester.tap(threeStarChip);
    await tester.pumpAndSettle();

    expect(find.text('Song Three'), findsOneWidget);
    expect(find.text('Song Five'), findsNothing);
    expect(find.text('Song One'), findsNothing);

    // Tap all stars chip
    final allStarsChip = find.text('全部星级');
    expect(allStarsChip, findsOneWidget);
    await tester.tap(allStarsChip);
    await tester.pumpAndSettle();

    expect(find.text('Song Five'), findsOneWidget);
    expect(find.text('Song Three'), findsOneWidget);
    expect(find.text('Song One'), findsOneWidget);
  });

  testWidgets('sort dialog allows changing sort order', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Tap sort icon button
    final sortButton = find.byIcon(Icons.sort_rounded);
    expect(sortButton, findsOneWidget);
    await tester.tap(sortButton);
    await tester.pumpAndSettle();

    // Sort dialog should appear with options
    expect(find.text('评分星级'), findsOneWidget);
    expect(find.text('歌曲标题'), findsOneWidget);
    expect(find.text('艺术家'), findsOneWidget);
    expect(find.text('最近添加'), findsOneWidget);

    // Select 歌曲标题
    await tester.tap(find.text('歌曲标题'));
    await tester.pumpAndSettle();

    // Confirm dialog
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // Dialog closed and setting updated
    expect(settingsService.ratedSongSortField, RatedSongSortField.title);
  });
}
