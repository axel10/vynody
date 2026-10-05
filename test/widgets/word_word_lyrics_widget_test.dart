import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_snapshot.dart';
import 'package:vynody/widgets/lyrics_panel_views.dart';

AudioSnapshot _createTestSnapshot({double speed = 1.0}) {
  return AudioSnapshot(
    isPlaying: true,
    isTransitioning: false,
    isLastActionNext: null,
    currentMusic: null,
    position: const Duration(milliseconds: 1500),
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
    isLyricsActive: true,
    sleepTimerRemaining: null,
    sleepTimerDuration: null,
    playbackSpeed: speed,
  );
}

void main() {
  testWidgets('WordWordLyricsWidget renders inactive text when isActive is false', (tester) async {
    final words = [
      LyricWord(timestamp: const Duration(seconds: 1), durationMs: 500, text: '満'),
      LyricWord(timestamp: const Duration(milliseconds: 1500), durationMs: 500, text: 'た'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: WordWordLyricsWidget(
              words: words,
              lineStyle: const TextStyle(fontSize: 20),
              activeColor: Colors.white,
              inactiveColor: Colors.grey,
              isLeftAligned: true,
              isActive: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('満た'), findsOneWidget);
    expect(find.byType(ClipPath), findsNothing);
  });

  testWidgets('WordWordLyricsWidget clips active text with progress when transitioning', (tester) async {
    final words = [
      LyricWord(timestamp: const Duration(seconds: 1), durationMs: 1000, text: '満'),
      LyricWord(timestamp: const Duration(seconds: 2), durationMs: 1000, text: 'た'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPositionProvider.overrideWith((ref) => const Duration(milliseconds: 1500)),
          audioIsPlayingProvider.overrideWith((ref) => true),
          audioSnapshotProvider.overrideWith((ref) => _createTestSnapshot()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WordWordLyricsWidget(
              words: words,
              lineStyle: const TextStyle(fontSize: 20),
              activeColor: Colors.white,
              inactiveColor: Colors.grey,
              isLeftAligned: true,
              isActive: true,
              layoutMaxWidth: 400,
            ),
          ),
        ),
      ),
    );

    // During transition of "満" (500ms into 1000ms), both inactive and active text are present
    // in a Stack with ClipPath
    expect(find.byType(ClipPath), findsOneWidget);
    expect(find.text('満た'), findsNWidgets(2));
  });

  testWidgets('WordWordLyricsWidget renders only active text when all words completed', (tester) async {
    final words = [
      LyricWord(timestamp: const Duration(seconds: 1), durationMs: 500, text: '満'),
      LyricWord(timestamp: const Duration(milliseconds: 1500), durationMs: 500, text: 'た'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPositionProvider.overrideWith((ref) => const Duration(seconds: 3)),
          audioIsPlayingProvider.overrideWith((ref) => true),
          audioSnapshotProvider.overrideWith((ref) => _createTestSnapshot()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WordWordLyricsWidget(
              words: words,
              lineStyle: const TextStyle(fontSize: 20),
              activeColor: Colors.white,
              inactiveColor: Colors.grey,
              isLeftAligned: true,
              isActive: true,
              layoutMaxWidth: 400,
            ),
          ),
        ),
      ),
    );

    expect(find.text('満た'), findsOneWidget);
    expect(find.byType(ClipPath), findsNothing);
  });

  testWidgets('WordWordLyricsWidget renders only inactive text when not started', (tester) async {
    final words = [
      LyricWord(timestamp: const Duration(seconds: 5), durationMs: 500, text: '満'),
      LyricWord(timestamp: const Duration(milliseconds: 5500), durationMs: 500, text: 'た'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPositionProvider.overrideWith((ref) => const Duration(seconds: 1)),
          audioIsPlayingProvider.overrideWith((ref) => true),
          audioSnapshotProvider.overrideWith((ref) => _createTestSnapshot()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WordWordLyricsWidget(
              words: words,
              lineStyle: const TextStyle(fontSize: 20),
              activeColor: Colors.white,
              inactiveColor: Colors.grey,
              isLeftAligned: true,
              isActive: true,
              layoutMaxWidth: 400,
            ),
          ),
        ),
      ),
    );

    expect(find.text('満た'), findsOneWidget);
    expect(find.byType(ClipPath), findsNothing);
  });
}

