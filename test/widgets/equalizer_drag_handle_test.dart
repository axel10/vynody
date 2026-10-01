import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audio_core/audio_core.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_snapshot.dart';
import 'package:vynody/player/audio/equalizer_presets.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/equalizer_panel.dart';
import 'package:vynody/l10n/app_localizations.dart';

import 'helpers/mobile_screenshot_harness.dart';

void main() {
  testWidgets('EqualizerPanel displays drag handle at the top', (tester) async {
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EqualizerPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify EqualizerPanel exists
    expect(find.byType(EqualizerPanel), findsOneWidget);

    // Verify drag handle exists (rounded container with radius 2)
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
}
