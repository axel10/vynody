import 'package:audio_core/audio_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/queue_random_manager.dart';

void main() {
  group('QueueRandomManager Tests', () {
    final songs = List.generate(
      5,
      (i) => MusicFile(
        id: i + 1,
        name: 'song${i + 1}.mp3',
        path: '/music/song${i + 1}.mp3',
        title: 'Song ${i + 1}',
        artist: 'Artist',
      ),
    );

    test('reconcile with Fisher-Yates policy builds deck', () {
      final manager = QueueRandomManager();
      manager.setPolicy(
        RandomPolicy(
          scope: RandomScope.all(),
          strategy: RandomStrategy.fisherYates(),
          label: 'shuffleRandom',
        ),
      );

      manager.reconcile(
        queue: songs,
        currentTrack: songs[0],
        currentIndex: 0,
      );

      expect(manager.currentDeck.length, 5);
      expect(manager.currentDeck.contains(songs[0].path), isTrue);
      expect(manager.history.isNotEmpty, isTrue);
      expect(manager.history.last.trackId, songs[0].path);
    });

    test('resolveAdjacentIndex next and previous navigates correctly', () {
      final manager = QueueRandomManager();
      manager.setPolicy(
        RandomPolicy(
          scope: RandomScope.all(),
          strategy: RandomStrategy.fisherYates(),
          label: 'shuffleRandom',
        ),
      );

      manager.reconcile(
        queue: songs,
        currentTrack: songs[0],
        currentIndex: 0,
      );

      final nextIdx = manager.resolveAdjacentIndex(
        next: true,
        queue: songs,
        currentTrack: songs[0],
      );

      expect(nextIdx, isNotNull);
      expect(nextIdx! >= 0 && nextIdx < songs.length, isTrue);

      final prevIdx = manager.resolveAdjacentIndex(
        next: false,
        queue: songs,
        currentTrack: songs[nextIdx],
      );

      expect(prevIdx, 0);
    });

    test('complete random strategy selects within bounds', () {
      final manager = QueueRandomManager();
      manager.setPolicy(
        RandomPolicy(
          scope: RandomScope.all(),
          strategy: RandomStrategy.random(),
          label: 'completeRandom',
        ),
      );

      manager.reconcile(
        queue: songs,
        currentTrack: songs[0],
        currentIndex: 0,
      );

      final nextIdx = manager.resolveAdjacentIndex(
        next: true,
        queue: songs,
        currentTrack: songs[0],
      );

      expect(nextIdx, isNotNull);
      expect(nextIdx! >= 0 && nextIdx < songs.length, isTrue);
    });

    test('restoreState restores history and deck accurately', () {
      final manager = QueueRandomManager();
      final policy = RandomPolicy(
        scope: RandomScope.all(),
        strategy: RandomStrategy.fisherYates(),
        label: 'shuffleRandom',
      );

      final historyEntries = [
        RandomHistoryEntry(
          trackId: songs[0].path,
          playlistId: 'vynody_queue',
          trackIndex: 0,
          policyKey: policy.key,
          generatedAt: DateTime.now(),
        ),
        RandomHistoryEntry(
          trackId: songs[1].path,
          playlistId: 'vynody_queue',
          trackIndex: 1,
          policyKey: policy.key,
          generatedAt: DateTime.now(),
        ),
      ];

      manager.restoreState(
        policy: policy,
        history: historyEntries,
        historyCursor: 1,
        deck: [songs[0].path, songs[1].path, songs[2].path],
        deckCursor: 1,
      );

      expect(manager.history.length, 2);
      expect(manager.historyCursor, 1);
      expect(manager.currentDeck.length, 3);
      expect(manager.deckCursor, 1);

      // Previous should go back to index 0
      final prev = manager.resolveAdjacentIndex(
        next: false,
        queue: songs,
        currentTrack: songs[1],
      );
      expect(prev, 0);
      expect(manager.historyCursor, 0);
    });
  });
}
