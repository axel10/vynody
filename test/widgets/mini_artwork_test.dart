import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/audio_snapshot.dart';
import 'package:vynody/widgets/mini_player_widgets.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

AudioSnapshot _createTestSnapshot([MusicFile? music]) {
  return AudioSnapshot(
    isPlaying: false,
    isTransitioning: false,
    isLastActionNext: null,
    currentMusic: music,
    position: Duration.zero,
    duration: Duration.zero,
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

class _FakeAudioService extends AudioService {
  final MusicFile? _music;
  _FakeAudioService([this._music]);

  @override
  AudioSnapshot build() => _createTestSnapshot(_music);

  @override
  Uint8List? getCachedArtwork(String? path) => null;

  @override
  List<MusicFile> get queue => _music != null ? [_music] : const [];

  @override
  List<MusicFile> get playbackQueue => queue;

  @override
  int get currentIndex => 0;

  @override
  bool get isBuffering => false;
}

void main() {
  testWidgets('MiniArtwork renders fallback icon when currentMusic is null',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioCurrentMusicProvider.overrideWithValue(null),
          audioServiceProvider.overrideWith((ref) => _FakeAudioService(null)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MiniArtwork(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.music_note), findsOneWidget);
    expect(find.byType(SongThumbnail), findsNothing);
  });

  testWidgets('MiniArtwork renders SongThumbnail when currentMusic is present',
      (tester) async {
    const testMusic = MusicFile(
      path: '/test/music.mp3',
      name: 'music.mp3',
      title: 'Test Song',
      artist: 'Test Artist',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioCurrentMusicProvider.overrideWithValue(testMusic),
          audioServiceProvider.overrideWith((ref) => _FakeAudioService(testMusic)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MiniArtwork(),
          ),
        ),
      ),
    );

    expect(find.byType(SongThumbnail), findsOneWidget);
    final thumbnailFinder = find.byType(SongThumbnail);
    final songThumbnail = tester.widget<SongThumbnail>(thumbnailFinder);
    expect(songThumbnail.path, '/test/music.mp3');
    expect(songThumbnail.width, 36.0);
    expect(songThumbnail.height, 36.0);
  });
}
