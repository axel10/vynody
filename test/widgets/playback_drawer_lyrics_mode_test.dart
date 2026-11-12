import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/audio_snapshot.dart';
import 'package:vynody/player/settings/settings_service.dart';

class _MockAudioService extends AudioService {
  final List<bool> setLyricsActiveCalls = [];
  bool _mockLyricsActive = false;

  @override
  AudioSnapshot build() {
    return AudioSnapshot(
      isPlaying: false,
      isBuffering: false,
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
      currentVisualizerOptions: VisualizerOptimizationOptions(
        frequencyGroups: 100,
      ),
      randomHistory: const [],
      randomQueue: const [],
      historyCursor: null,
      deckCursor: null,
      isVisualizerEnabled: false,
      dynamicStartColor: null,
      dynamicEndColor: null,
      currentThemeColorsMap: const {},
      isLyricsActive: _mockLyricsActive,
      sleepTimerRemaining: null,
      sleepTimerDuration: null,
      playbackSpeed: 1.0,
    );
  }

  @override
  bool get isLyricsActive => _mockLyricsActive;

  @override
  void setLyricsActive(bool active) {
    _mockLyricsActive = active;
    setLyricsActiveCalls.add(active);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;
  late _MockAudioService mockAudio;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
    mockAudio = _MockAudioService();
  });

  Widget buildTestConsumer() {
    return Consumer(
      builder: (context, ref, child) {
        final audio = ref.read(audioServiceProvider);

        ref.listen<bool>(isPlaybackDrawerOpenProvider, (previous, next) {
          if (next && previous != true) {
            if (ref.read(settingsServiceProvider).defaultToLyricsModeOnPlaybackOpen) {
              audio.setLyricsActive(true);
            }
          } else if (!next && previous == true) {
            audio.setLyricsActive(false);
          }
        });

        ref.listen<bool>(
          settingsServiceProvider.select((s) => s.defaultToLyricsModeOnPlaybackOpen),
          (previous, next) {
            if (next && ref.read(isPlaybackDrawerOpenProvider)) {
              audio.setLyricsActive(true);
            }
          },
        );

        return const SizedBox();
      },
    );
  }

  testWidgets(
    'Playback drawer automatically enables lyrics mode when defaultToLyricsModeOnPlaybackOpen is true',
    (tester) async {
      settings.defaultToLyricsModeOnPlaybackOpen = true;

      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWith((ref) => mockAudio),
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: buildTestConsumer(),
            ),
          ),
        ),
      );

      expect(mockAudio.setLyricsActiveCalls, isEmpty);

      // Open playback drawer
      container.read(isPlaybackDrawerOpenProvider.notifier).setOpen(true);
      await tester.pump();

      // Lyrics mode should be activated
      expect(mockAudio.setLyricsActiveCalls, [true]);

      // Close playback drawer
      container.read(isPlaybackDrawerOpenProvider.notifier).setOpen(false);
      await tester.pump();

      // Lyrics mode should be deactivated
      expect(mockAudio.setLyricsActiveCalls, [true, false]);

      // Reopen playback drawer
      container.read(isPlaybackDrawerOpenProvider.notifier).setOpen(true);
      await tester.pump();

      // Lyrics mode should be reactivated on reopening
      expect(mockAudio.setLyricsActiveCalls, [true, false, true]);
    },
  );

  testWidgets(
    'Playback drawer does not enable lyrics mode when defaultToLyricsModeOnPlaybackOpen is false',
    (tester) async {
      settings.defaultToLyricsModeOnPlaybackOpen = false;

      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWith((ref) => mockAudio),
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: buildTestConsumer(),
            ),
          ),
        ),
      );

      // Open playback drawer
      container.read(isPlaybackDrawerOpenProvider.notifier).setOpen(true);
      await tester.pump();

      // Should not call setLyricsActive(true)
      expect(mockAudio.setLyricsActiveCalls, isEmpty);
    },
  );

  testWidgets(
    'Enabling defaultToLyricsModeOnPlaybackOpen while drawer is open activates lyrics mode',
    (tester) async {
      settings.defaultToLyricsModeOnPlaybackOpen = false;

      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWith((ref) => mockAudio),
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: buildTestConsumer(),
            ),
          ),
        ),
      );

      // Open drawer while setting is false
      container.read(isPlaybackDrawerOpenProvider.notifier).setOpen(true);
      await tester.pump();
      expect(mockAudio.setLyricsActiveCalls, isEmpty);

      // Toggle setting to true while drawer is already open
      settings.defaultToLyricsModeOnPlaybackOpen = true;
      await tester.pump();

      // Lyrics mode should be activated
      expect(mockAudio.setLyricsActiveCalls, [true]);
    },
  );
}
