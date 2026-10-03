import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/audio_snapshot.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/playback/playback_controls.dart';
import 'package:vynody/widgets/playback/playback_progress_section.dart';

AudioSnapshot _createTestSnapshot() {
  return AudioSnapshot(
    isPlaying: true,
    isTransitioning: false,
    isLastActionNext: null,
    currentMusic: null,
    position: const Duration(seconds: 50),
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
    isLyricsActive: false,
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;
  late _TestAudioService testAudio;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'show_playback_audio_info': true,
      'progress_bar_style': 'standard',
    });
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
    testAudio = _TestAudioService();
  });

  testWidgets('PlaybackProgressSection does not contain PlaybackAudioInfoLabel',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioServiceProvider.overrideWith((ref) => testAudio),
          audioServiceStateProvider.overrideWith(() => testAudio),
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PlaybackProgressSection(
              currentMusic: null,
              controlsScale: 1.0,
              tLyrics: 0.0,
              isLandscape: false,
              buttonsRowWidth: 320.0,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PlaybackProgressSection), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PlaybackProgressSection),
        matching: find.byType(PlaybackAudioInfoLabel),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'PlaybackControls places PlaybackAudioInfoLabel below PlaybackProgressSection in portrait standard mode',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioServiceProvider.overrideWith((ref) => testAudio),
          audioServiceStateProvider.overrideWith(() => testAudio),
          settingsServiceProvider.overrideWith((ref) => settings),
          audioIsPlayingProvider.overrideWith((ref) => false),
        ],
        child: const OKToast(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: PlaybackControls(
                  width: 400.0,
                  layoutWidth: 400.0,
                  controlsScale: 1.0,
                  tLyrics: 0.0,
                  isLandscape: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PlaybackControls), findsOneWidget);
    final progressFinder = find.byType(PlaybackProgressSection);
    final audioInfoFinder = find.byType(PlaybackAudioInfoLabel);

    expect(progressFinder, findsOneWidget);
    expect(audioInfoFinder, findsOneWidget);

    final progressBottom = tester.getBottomLeft(progressFinder).dy;
    final audioInfoTop = tester.getTopLeft(audioInfoFinder).dy;

    // Audio info is below the progress section and main controls row
    expect(audioInfoTop, greaterThan(progressBottom));
  });

  testWidgets(
      'PlaybackControls places PlaybackAudioInfoLabel below PlaybackProgressSection in landscape mode',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioServiceProvider.overrideWith((ref) => testAudio),
          audioServiceStateProvider.overrideWith(() => testAudio),
          settingsServiceProvider.overrideWith((ref) => settings),
          audioIsPlayingProvider.overrideWith((ref) => false),
        ],
        child: const OKToast(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: PlaybackControls(
                  width: 600.0,
                  layoutWidth: 600.0,
                  controlsScale: 1.0,
                  tLyrics: 0.0,
                  isLandscape: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PlaybackControls), findsOneWidget);
    final progressFinder = find.byType(PlaybackProgressSection);
    final audioInfoFinder = find.byType(PlaybackAudioInfoLabel);

    expect(progressFinder, findsOneWidget);
    expect(audioInfoFinder, findsOneWidget);

    final progressBottom = tester.getBottomLeft(progressFinder).dy;
    final audioInfoTop = tester.getTopLeft(audioInfoFinder).dy;

    // Audio info is below the progress section in landscape too
    expect(audioInfoTop, greaterThan(progressBottom));
  });
}
