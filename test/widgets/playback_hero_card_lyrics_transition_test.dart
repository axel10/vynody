import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/audio_snapshot.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/lyrics_panel.dart';
import 'package:vynody/widgets/playback_hero_card.dart';
import 'package:vynody/widgets/playback_ui_tuning.dart';

AudioSnapshot _createTestSnapshot({bool isLyricsActive = false}) {
  return AudioSnapshot(
    isPlaying: true,
    isTransitioning: false,
    isLastActionNext: null,
    currentMusic: const MusicFile(
      id: 1,
      name: 'test.mp3',
      path: '/test/music.mp3',
      title: 'Test Title',
      artist: 'Test Artist',
    ),
    position: const Duration(seconds: 10),
    duration: const Duration(seconds: 200),
    volume: 1.0,
    isMuted: false,
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
    historyCursor: null,
    deckCursor: null,
    isVisualizerEnabled: false,
    dynamicStartColor: null,
    dynamicEndColor: null,
    isLyricsActive: isLyricsActive,
    sleepTimerRemaining: null,
    sleepTimerDuration: null,
    playbackSpeed: 1.0,
  );
}

class _TestAudioService extends AudioService {
  @override
  AudioSnapshot build() {
    return _createTestSnapshot();
  }

  @override
  MusicFile? get currentMusic => const MusicFile(
        id: 1,
        name: 'test.mp3',
        path: '/test/music.mp3',
        title: 'Test Title',
        artist: 'Test Artist',
      );

  @override
  List<MusicFile> get queue => const [];

  @override
  List<MusicFile> get playbackQueue => const [];

  @override
  int get currentIndex => 0;

  @override
  bool get isBuffering => false;

  @override
  Duration get duration => const Duration(seconds: 200);

  @override
  Duration get position => const Duration(seconds: 10);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
  });

  testWidgets(
    'PlaybackHeroCard configures zero duration for lyrics transition when animateLyricsTransition is false',
    (tester) async {
      final testAudio = _TestAudioService();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWith((ref) => testAudio),
          audioServiceStateProvider.overrideWith(() => testAudio),
          settingsServiceProvider.overrideWith((ref) => settings),
          audioSnapshotProvider.overrideWith(
            (ref) => _createTestSnapshot(isLyricsActive: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: PlaybackHeroCard(
                isMini: false,
                isLandscape: false,
                isLyricsMode: true,
                animateLyricsTransition: false,
              ),
            ),
          ),
        ),
      );

      final tweenBuilders = tester.widgetList<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>),
      );
      // The second TweenAnimationBuilder controls the lyrics transition (the first is landscape)
      final lyricsTweenBuilder = tweenBuilders.last;
      expect(lyricsTweenBuilder.duration, Duration.zero);

      expect(find.byType(LyricsPanel), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'PlaybackHeroCard configures normal transitionDuration when animateLyricsTransition is true',
    (tester) async {
      final testAudio = _TestAudioService();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWith((ref) => testAudio),
          audioServiceStateProvider.overrideWith(() => testAudio),
          settingsServiceProvider.overrideWith((ref) => settings),
          audioSnapshotProvider.overrideWith(
            (ref) => _createTestSnapshot(isLyricsActive: false),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: PlaybackHeroCard(
                isMini: false,
                isLandscape: false,
                isLyricsMode: false,
                animateLyricsTransition: true,
              ),
            ),
          ),
        ),
      );

      final tweenBuilders = tester.widgetList<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>),
      );
      final lyricsTweenBuilder = tweenBuilders.last;
      expect(lyricsTweenBuilder.duration, PlaybackHeroCardUiTuning.transitionDuration);

      await tester.pump(const Duration(seconds: 1));
    },
  );
}
