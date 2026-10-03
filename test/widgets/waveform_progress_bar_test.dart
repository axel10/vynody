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
import 'package:vynody/widgets/waveform_progress_bar.dart';

void main() {
  testWidgets('WaveformProgressBar renders and handles drag with inertia', (
    WidgetTester tester,
  ) async {
    final testAudio = _TestAudioService();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);

    double currentProgress = 0.5;
    double? seekedProgress;
    double? scrubbedProgress;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioServiceProvider.overrideWith((ref) => testAudio),
          audioServiceStateProvider.overrideWith(() => testAudio),
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 80,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return WaveformProgressBar(
                      waveform: List.generate(100, (i) => 0.5),
                      progress: currentProgress,
                      duration: const Duration(seconds: 200),
                      isPlaying: false,
                      isScrolling: true,
                      barWidth: 6.0,
                      barGap: 4.0,
                      onScrubbing: (val) {
                        scrubbedProgress = val;
                      },
                      onSeek: (val) {
                        seekedProgress = val;
                        setState(() {
                          currentProgress = val;
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(WaveformProgressBar), findsOneWidget);

    // Fling gesture to simulate drag and release with velocity
    await tester.fling(
      find.byType(WaveformProgressBar),
      const Offset(-100, 0), // Swipe left -> progress should increase
      1000, // 1000 px/s velocity
    );

    // After fling started, inertia simulation runs over time
    await tester.pump(const Duration(milliseconds: 100));
    expect(scrubbedProgress, isNotNull);
    expect(scrubbedProgress!, greaterThan(0.5));

    // Let inertia animation finish completely
    await tester.pumpAndSettle();

    expect(seekedProgress, isNotNull);
    expect(seekedProgress!, greaterThan(0.5));
  });

  testWidgets('WaveformProgressBar stops inertia on tap down', (
    WidgetTester tester,
  ) async {
    final testAudio = _TestAudioService();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);

    double currentProgress = 0.5;
    double? seekedProgress;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioServiceProvider.overrideWith((ref) => testAudio),
          audioServiceStateProvider.overrideWith(() => testAudio),
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 80,
                child: WaveformProgressBar(
                  waveform: List.generate(100, (i) => 0.5),
                  progress: currentProgress,
                  duration: const Duration(seconds: 200),
                  isPlaying: false,
                  isScrolling: true,
                  barWidth: 6.0,
                  barGap: 4.0,
                  onScrubbing: (_) {},
                  onSeek: (val) {
                    seekedProgress = val;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Fling to start inertia
    await tester.fling(
      find.byType(WaveformProgressBar),
      const Offset(-100, 0),
      1000,
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Tap to interrupt inertia
    await tester.tap(find.byType(WaveformProgressBar));
    await tester.pumpAndSettle();

    expect(seekedProgress, isNotNull);
    expect(seekedProgress!, greaterThan(0.5));
  });

  testWidgets(
    'WaveformProgressBar delays seek at song end and cancels if user drags again',
    (WidgetTester tester) async {
      final testAudio = _TestAudioService();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      double currentProgress = 0.95;
      double? seekedProgress;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioServiceProvider.overrideWith((ref) => testAudio),
            audioServiceStateProvider.overrideWith(() => testAudio),
            settingsServiceProvider.overrideWith((ref) => settings),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 80,
                  child: WaveformProgressBar(
                    waveform: List.generate(100, (i) => 0.5),
                    progress: currentProgress,
                    duration: const Duration(seconds: 200),
                    isPlaying: false,
                    isScrolling: true,
                    barWidth: 6.0,
                    barGap: 4.0,
                    onScrubbing: (_) {},
                    onSeek: (val) {
                      seekedProgress = val;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Fling left strongly towards the end of the song
      await tester.fling(
        find.byType(WaveformProgressBar),
        const Offset(-150, 0),
        1000,
      );
      // Wait for inertia to reach end
      await tester.pump(const Duration(milliseconds: 100));

      // At 100ms, it just reached the end, delay timer is running, seek has NOT happened yet
      expect(seekedProgress, isNull);

      // Now user drags again before the 600ms delay timer fires
      await tester.drag(
        find.byType(WaveformProgressBar),
        const Offset(50, 0), // drag right back into song
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Release slow drag
      await tester.pumpAndSettle();

      // Seek happened at dragged back position, NOT at 1.0!
      expect(seekedProgress, isNotNull);
      expect(seekedProgress!, lessThan(1.0));
    },
  );

  testWidgets(
    'WaveformProgressBar scrolling mode supports long-press anywhere (left and right)',
    (WidgetTester tester) async {
      final testAudio = _TestAudioService();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      settings.enableWaveformLongPressSeek = true;
      settings.waveformLongPressSeekSpeed = 2.5;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioServiceProvider.overrideWith((ref) => testAudio),
            audioServiceStateProvider.overrideWith(() => testAudio),
            settingsServiceProvider.overrideWith((ref) => settings),
          ],
          child: OKToast(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 300,
                    height: 80,
                    child: WaveformProgressBar(
                      waveform: List.generate(100, (i) => 0.5),
                      progress: 0.5,
                      duration: const Duration(seconds: 200),
                      isPlaying: true,
                      isScrolling: true,
                      onScrubbing: (_) {},
                      onSeek: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(WaveformProgressBar));

      // 1. Long press on LEFT side (e.g. x = 30 out of width 300)
      final leftGesture = await tester.startGesture(topLeft + const Offset(30, 40));
      await tester.pump(const Duration(milliseconds: 600));

      expect(testAudio.currentSpeed, equals(2.5));

      // Release left long press -> speed resets
      await leftGesture.up();
      await tester.pump();
      expect(testAudio.currentSpeed, equals(1.0));

      // 2. Long press on RIGHT side (e.g. x = 270 out of width 300)
      final rightGesture = await tester.startGesture(topLeft + const Offset(270, 40));
      await tester.pump(const Duration(milliseconds: 600));

      expect(testAudio.currentSpeed, equals(2.5));

      // Release right long press -> speed resets
      await rightGesture.up();
      await tester.pump();
      expect(testAudio.currentSpeed, equals(1.0));

      dismissAllToast(showAnim: false);
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'WaveformProgressBar static mode does not trigger long-press fast forward and retains immediate tap-down seek',
    (WidgetTester tester) async {
      final testAudio = _TestAudioService();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      settings.enableWaveformLongPressSeek = true;
      settings.waveformLongPressSeekSpeed = 2.5;

      double? seekedProgress;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioServiceProvider.overrideWith((ref) => testAudio),
            audioServiceStateProvider.overrideWith(() => testAudio),
            settingsServiceProvider.overrideWith((ref) => settings),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 80,
                  child: WaveformProgressBar(
                    waveform: List.generate(100, (i) => 0.5),
                    progress: 0.2,
                    duration: const Duration(seconds: 200),
                    isPlaying: true,
                    isScrolling: false,
                    onScrubbing: (_) {},
                    onSeek: (val) {
                      seekedProgress = val;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(WaveformProgressBar));

      // Tap on static waveform -> seeks on tap-down
      final gesture = await tester.startGesture(topLeft + const Offset(150, 40));
      await tester.pump(const Duration(milliseconds: 150));
      // In static mode, onTapDown seeks to position (150 / 300 = 0.5)
      expect(seekedProgress, equals(0.5));

      await tester.pump(const Duration(milliseconds: 600));
      // Speed remains 1.0 (no long press fast forward)
      expect(testAudio.currentSpeed, equals(1.0));

      await gesture.up();
      await tester.pump();
      expect(testAudio.currentSpeed, equals(1.0));
    },
  );
}

AudioSnapshot createTestAudioSnapshot({double playbackSpeed = 1.0}) {
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
    playbackSpeed: playbackSpeed,
  );
}

class _TestAudioService extends AudioService {
  double currentSpeed = 1.0;

  @override
  AudioSnapshot build() {
    return createTestAudioSnapshot(playbackSpeed: currentSpeed);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    currentSpeed = speed;
    state = createTestAudioSnapshot(playbackSpeed: speed);
  }
}

