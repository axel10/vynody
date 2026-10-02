import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/dialogs/visualizer_options_dialog.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';

import 'helpers/mobile_screenshot_harness.dart';

void main() {
  testWidgets('VisualizerOptionsDialog displays drag handle in portrait sheet mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settingsService = TestSettingsService(prefs);

    final demoSong = MusicFile(
      id: 1,
      path: '/test/demo.mp3',
      name: 'demo.mp3',
      title: 'Demo Song',
      artist: 'Demo Artist',
      album: 'Demo Album',
      durationMillis: 180000,
    );

    final eqConfig = EqualizerConfig(
      enabled: true,
      bandCount: 10,
      preampDb: 0.0,
      bassBoostDb: 0.0,
      bassBoostFrequencyHz: 80.0,
      bassBoostQ: 1.0,
      bandGainsDb: Float32List.fromList(EqualizerPresets.flat.referenceGains),
    );

    final snapshot = AudioSnapshot(
      isPlaying: false,
      isTransitioning: false,
      isLastActionNext: null,
      currentMusic: demoSong,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
      volume: 1.0,
      isMuted: false,
      playbackQueue: [demoSong],
      currentIndex: 0,
      isRandomMode: false,
      isShuffleRandomMode: false,
      playbackMode: AppPlaybackMode.queue,
      equalizerConfig: eqConfig,
      currentVisualizerOptions: const VisualizerOptimizationOptions(
        frequencyGroups: 100,
      ),
      randomHistory: const [],
      randomQueue: const [],
      historyCursor: null,
      deckCursor: null,
      isVisualizerEnabled: false,
      dynamicStartColor: Colors.blue,
      dynamicEndColor: Colors.black,
      isLyricsActive: false,
      sleepTimerRemaining: null,
      sleepTimerDuration: null,
    );

    final visualizerStreamController = StreamController<FftFrame>.broadcast();
    addTearDown(visualizerStreamController.close);

    final audioService = MockAudioService(
      snapshot: snapshot,
      visualizerStream: visualizerStreamController.stream,
    );

    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceProvider.overrideWith((ref) => audioService),
        audioSnapshotProvider.overrideWith((ref) => snapshot),
      ],
    );
    addTearDown(container.dispose);

    // 1. Portrait mode (width = 500, height = 900)
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VisualizerOptionsDialog(
              audio: audioService,
              settings: settingsService,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify VisualizerOptionsDialog exists
    expect(find.byType(VisualizerOptionsDialog), findsOneWidget);

    // Verify drag handle exists in portrait/sheet mode (rounded container with radius 2)
    final dragHandleFinder = find.byWidgetPredicate((widget) {
      if (widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).borderRadius ==
              BorderRadius.circular(2)) {
        return true;
      }
      return false;
    });

    expect(dragHandleFinder, findsOneWidget);
  });

  testWidgets(
      'VisualizerOptionsDialog adapts to dialog layout without drag handle on wide screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settingsService = TestSettingsService(prefs);

    final demoSong = MusicFile(
      id: 1,
      path: '/test/demo.mp3',
      name: 'demo.mp3',
      title: 'Demo Song',
      artist: 'Demo Artist',
      album: 'Demo Album',
      durationMillis: 180000,
    );

    final eqConfig = EqualizerConfig(
      enabled: true,
      bandCount: 10,
      preampDb: 0.0,
      bassBoostDb: 0.0,
      bassBoostFrequencyHz: 80.0,
      bassBoostQ: 1.0,
      bandGainsDb: Float32List.fromList(EqualizerPresets.flat.referenceGains),
    );

    final snapshot = AudioSnapshot(
      isPlaying: false,
      isTransitioning: false,
      isLastActionNext: null,
      currentMusic: demoSong,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
      volume: 1.0,
      isMuted: false,
      playbackQueue: [demoSong],
      currentIndex: 0,
      isRandomMode: false,
      isShuffleRandomMode: false,
      playbackMode: AppPlaybackMode.queue,
      equalizerConfig: eqConfig,
      currentVisualizerOptions: const VisualizerOptimizationOptions(
        frequencyGroups: 100,
      ),
      randomHistory: const [],
      randomQueue: const [],
      historyCursor: null,
      deckCursor: null,
      isVisualizerEnabled: false,
      dynamicStartColor: Colors.blue,
      dynamicEndColor: Colors.black,
      isLyricsActive: false,
      sleepTimerRemaining: null,
      sleepTimerDuration: null,
    );

    final visualizerStreamController = StreamController<FftFrame>.broadcast();
    addTearDown(visualizerStreamController.close);

    final audioService = MockAudioService(
      snapshot: snapshot,
      visualizerStream: visualizerStreamController.stream,
    );

    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioServiceProvider.overrideWith((ref) => audioService),
        audioSnapshotProvider.overrideWith((ref) => snapshot),
      ],
    );
    addTearDown(container.dispose);

    // Wide screen mode (width = 1200, height = 900)
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VisualizerOptionsDialog(
              audio: audioService,
              settings: settingsService,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify VisualizerOptionsDialog exists
    expect(find.byType(VisualizerOptionsDialog), findsOneWidget);

    // Verify drag handle does NOT exist in dialog mode
    final dragHandleFinder = find.byWidgetPredicate((widget) {
      if (widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).borderRadius ==
              BorderRadius.circular(2)) {
        return true;
      }
      return false;
    });

    expect(dragHandleFinder, findsNothing);

    // Verify close icon button is present
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
