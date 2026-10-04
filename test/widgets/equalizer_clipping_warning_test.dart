import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/widgets/equalizer_panel.dart';
import 'package:vynody/l10n/app_localizations.dart';

import 'helpers/mobile_screenshot_harness.dart';

class _SpyAudioService extends MockAudioService {
  double? lastSetPreamp;

  _SpyAudioService({
    required super.snapshot,
    required super.visualizerStream,
  });

  @override
  Future<void> setEqualizerPreamp(double value) async {
    lastSetPreamp = value;
  }
}

void main() {
  testWidgets('EqualizerPanel shows clipping warning and auto preamp button when gain + preamp > 0', (tester) async {
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

    // 10 bands with band 0 at +4.0 dB, preamp at 0.0 dB -> clipping!
    final bandGains = Float32List.fromList([4.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
    final eqConfig = EqualizerConfig(
      enabled: true,
      bandCount: 10,
      preampDb: 0.0,
      bassBoostDb: 0.0,
      bassBoostFrequencyHz: 80.0,
      bassBoostQ: 1.0,
      bandGainsDb: bandGains,
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

    final audioService = _SpyAudioService(
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

    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EqualizerPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify warning banner exists
    expect(find.text('音量过大，为了防止爆音请降低前置增益'), findsOneWidget);
    expect(find.text('自动降益'), findsOneWidget);

    // Tap "自动降益"
    await tester.tap(find.text('自动降益'));
    await tester.pump();

    // Preamp should be set to -4.0 dB
    expect(audioService.lastSetPreamp, equals(-4.0));
  });

  testWidgets('EqualizerPanel does NOT show clipping warning when total gain is <= 0', (tester) async {
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

    // All bands 0.0, preamp 0.0 -> no clipping
    final bandGains = Float32List.fromList(EqualizerPresets.flat.referenceGains);
    final eqConfig = EqualizerConfig(
      enabled: true,
      bandCount: 10,
      preampDb: 0.0,
      bassBoostDb: 0.0,
      bassBoostFrequencyHz: 80.0,
      bassBoostQ: 1.0,
      bandGainsDb: bandGains,
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

    final audioService = _SpyAudioService(
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

    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EqualizerPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify warning banner does NOT exist
    expect(find.text('音量过大，为了防止爆音请降低前置增益'), findsNothing);
    expect(find.text('自动降益'), findsNothing);
  });

  testWidgets('EqualizerPanel shows clipping warning and highlights knob when bass boost + preamp > 0', (tester) async {
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

    // All bands 0.0, but bass boost is 6.0 dB with preamp 0.0 dB -> clipping!
    final bandGains = Float32List.fromList(EqualizerPresets.flat.referenceGains);
    final eqConfig = EqualizerConfig(
      enabled: true,
      bandCount: 10,
      preampDb: 0.0,
      bassBoostDb: 6.0,
      bassBoostFrequencyHz: 80.0,
      bassBoostQ: 1.0,
      bandGainsDb: bandGains,
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

    final audioService = _SpyAudioService(
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

    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EqualizerPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify warning banner exists
    expect(find.text('音量过大，为了防止爆音请降低前置增益'), findsOneWidget);
    expect(find.text('自动降益'), findsOneWidget);

    // Tap "自动降益"
    await tester.tap(find.text('自动降益'));
    await tester.pump();

    // Preamp should be automatically reduced to -6.0 dB to offset bass boost
    expect(audioService.lastSetPreamp, equals(-6.0));
  });
}
