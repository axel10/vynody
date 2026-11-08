import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_snapshot.dart';

AudioSnapshot _createSnapshot({
  Duration position = Duration.zero,
  List<MusicFile> randomHistory = const [],
  List<MusicFile> randomQueue = const [],
  Map<String, Color> currentThemeColorsMap = const {},
}) {
  return AudioSnapshot(
    isPlaying: true,
    isTransitioning: false,
    isLastActionNext: null,
    currentMusic: const MusicFile(name: 'a.mp3', path: '/a.mp3'),
    position: position,
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
    randomHistory: randomHistory,
    randomQueue: randomQueue,
    currentThemeColorsMap: currentThemeColorsMap,
  );
}

class _TestSnapshotNotifier extends Notifier<AudioSnapshot> {
  _TestSnapshotNotifier(this._initial);
  final AudioSnapshot _initial;

  @override
  AudioSnapshot build() => _initial;

  void emit(AudioSnapshot next) {
    state = next;
  }
}

void main() {
  group('AudioRiverpod collection providers deduplication', () {
    test('audioRandomHistoryProvider does not notify when list content is equal', () async {
      final initial = _createSnapshot(
        randomHistory: List.unmodifiable([
          const MusicFile(name: 'a.mp3', path: '/a.mp3'),
        ]),
      );
      final notifier = _TestSnapshotNotifier(initial);
      final testSnapshotProvider = NotifierProvider<_TestSnapshotNotifier, AudioSnapshot>(
        () => notifier,
      );

      final container = ProviderContainer(
        overrides: [
          audioSnapshotProvider.overrideWith((ref) => ref.watch(testSnapshotProvider)),
        ],
      );
      addTearDown(container.dispose);

      int historyNotifications = 0;
      container.listen(
        audioRandomHistoryProvider,
        (prev, next) {
          historyNotifications++;
        },
      );
      container.read(audioRandomHistoryProvider);

      // 1. Update position only, with brand new List.unmodifiable instance with identical contents
      notifier.emit(
        initial.copyWith(
          position: const Duration(seconds: 1),
          randomHistory: List.unmodifiable([
            const MusicFile(name: 'a.mp3', path: '/a.mp3'),
          ]),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(historyNotifications, 0, reason: 'Equal list content must not trigger notification');

      // 2. Change list content: must notify
      notifier.emit(
        initial.copyWith(
          randomHistory: List.unmodifiable([
            const MusicFile(name: 'b.mp3', path: '/b.mp3'),
          ]),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(historyNotifications, 1, reason: 'Modified list content must trigger notification');
    });

    test('audioRandomQueueProvider does not notify when list content is equal', () async {
      final initial = _createSnapshot(
        randomQueue: List.unmodifiable([
          const MusicFile(name: 'a.mp3', path: '/a.mp3'),
        ]),
      );
      final notifier = _TestSnapshotNotifier(initial);
      final testSnapshotProvider = NotifierProvider<_TestSnapshotNotifier, AudioSnapshot>(
        () => notifier,
      );

      final container = ProviderContainer(
        overrides: [
          audioSnapshotProvider.overrideWith((ref) => ref.watch(testSnapshotProvider)),
        ],
      );
      addTearDown(container.dispose);

      int queueNotifications = 0;
      container.listen(
        audioRandomQueueProvider,
        (prev, next) {
          queueNotifications++;
        },
      );
      container.read(audioRandomQueueProvider);

      notifier.emit(
        initial.copyWith(
          position: const Duration(seconds: 1),
          randomQueue: List.unmodifiable([
            const MusicFile(name: 'a.mp3', path: '/a.mp3'),
          ]),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(queueNotifications, 0, reason: 'Equal list content must not trigger notification');

      notifier.emit(
        initial.copyWith(
          randomQueue: List.unmodifiable([
            const MusicFile(name: 'c.mp3', path: '/c.mp3'),
          ]),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(queueNotifications, 1, reason: 'Modified list content must trigger notification');
    });

    test('audioCurrentThemeColorsMapProvider does not notify when map content is equal', () async {
      final initial = _createSnapshot(
        currentThemeColorsMap: Map.unmodifiable({
          'primary': Colors.red,
        }),
      );
      final notifier = _TestSnapshotNotifier(initial);
      final testSnapshotProvider = NotifierProvider<_TestSnapshotNotifier, AudioSnapshot>(
        () => notifier,
      );

      final container = ProviderContainer(
        overrides: [
          audioSnapshotProvider.overrideWith((ref) => ref.watch(testSnapshotProvider)),
        ],
      );
      addTearDown(container.dispose);

      int themeColorNotifications = 0;
      container.listen(
        audioCurrentThemeColorsMapProvider,
        (prev, next) {
          themeColorNotifications++;
        },
      );
      container.read(audioCurrentThemeColorsMapProvider);

      notifier.emit(
        initial.copyWith(
          position: const Duration(seconds: 1),
          currentThemeColorsMap: Map.unmodifiable({
            'primary': Colors.red,
          }),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(themeColorNotifications, 0, reason: 'Equal map content must not trigger notification');

      notifier.emit(
        initial.copyWith(
          currentThemeColorsMap: Map.unmodifiable({
            'primary': Colors.blue,
          }),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(themeColorNotifications, 1, reason: 'Modified map content must trigger notification');
    });
  });
}
