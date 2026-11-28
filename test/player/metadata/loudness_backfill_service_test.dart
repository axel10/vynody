import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/audio/loudness_normalization.dart';
import 'package:vynody/player/metadata/loudness_backfill_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

SongMetadata _makeSong({
  required String path,
  String title = 'Track',
  String album = 'Album',
  String artist = 'Artist',
  String? albumArtist,
}) {
  return SongMetadata(
    path: path,
    title: title,
    album: album,
    artist: artist,
    albumArtist: albumArtist,
  );
}

void main() {
  group('groupSongsForLoudnessAnalysis', () {
    test('groups tracks by normalized albumArtist/artist and album', () {
      final songs = [
        _makeSong(
          path: '/music/a1.flac',
          album: 'Alpha',
          artist: 'Feat A',
          albumArtist: 'Main Artist',
        ),
        _makeSong(
          path: '/music/a2.flac',
          album: ' alpha ',
          artist: 'Feat B',
          albumArtist: 'main artist',
        ),
        _makeSong(
          path: '/music/b1.flac',
          album: 'Beta',
          artist: 'Other',
        ),
        _makeSong(
          path: '/music/u1.flac',
          album: 'Unknown Album',
          artist: 'Solo',
        ),
        _makeSong(
          path: '/music/u2.flac',
          album: '',
          artist: 'Solo 2',
        ),
      ];

      final groups = groupSongsForLoudnessAnalysis(songs);
      expect(groups.length, 4);
      expect(groups[0].songs.map((s) => s.path), ['/music/a1.flac', '/music/a2.flac']);
      expect(groups[1].songs.map((s) => s.path), ['/music/b1.flac']);
      expect(groups[2].albumKey, isNull);
      expect(groups[2].songs.map((s) => s.path), ['/music/u1.flac']);
      expect(groups[3].albumKey, isNull);
      expect(groups[3].songs.map((s) => s.path), ['/music/u2.flac']);
    });
  });

  group('selectNextLoudnessGroupIndex', () {
    test('returns -1 for empty list and 0 when no priority target', () {
      expect(selectNextLoudnessGroupIndex(const [], null), -1);

      final groups = groupSongsForLoudnessAnalysis([
        _makeSong(path: '/a/1.flac', album: 'Album A', artist: 'Artist A'),
        _makeSong(path: '/b/1.flac', album: 'Album B', artist: 'Artist B'),
      ]);
      expect(selectNextLoudnessGroupIndex(groups, null), 0);
    });

    test('prioritizes currently playing album dynamically even if in middle/end', () {
      final groups = groupSongsForLoudnessAnalysis([
        _makeSong(path: '/a/1.flac', album: 'Album A', artist: 'Artist A'),
        _makeSong(path: '/b/1.flac', album: 'Album B', artist: 'Artist B'),
        _makeSong(path: '/c/1.flac', album: 'Album C', artist: 'Artist C'),
      ]);

      final idx = selectNextLoudnessGroupIndex(
        groups,
        const LoudnessPriorityTarget(
          path: '/c/2.flac',
          album: 'Album C',
          artist: 'Artist C',
        ),
      );
      expect(idx, 2);

      // Simulate removing the prioritized group and switching to another album mid-run.
      groups.removeAt(idx);
      final nextIdx = selectNextLoudnessGroupIndex(
        groups,
        const LoudnessPriorityTarget(
          path: '/b/1.flac',
          album: 'Album B',
          artist: 'Artist B',
        ),
      );
      expect(nextIdx, 1);
    });

    test('falls back to matching track path for unknown album or tag mismatch', () {
      final groups = groupSongsForLoudnessAnalysis([
        _makeSong(path: '/a/1.flac', album: 'Album A', artist: 'Artist A'),
        _makeSong(path: '/u/1.flac', album: 'Unknown', artist: 'Artist U'),
        _makeSong(path: '/c/1.flac', album: 'Album C', artist: 'Artist C'),
      ]);

      final unknownIdx = selectNextLoudnessGroupIndex(
        groups,
        const LoudnessPriorityTarget(
          path: '/u/1.flac',
          album: 'Unknown',
          artist: 'Artist U',
        ),
      );
      expect(unknownIdx, 2);

      final pathFallbackIdx = selectNextLoudnessGroupIndex(
        groups,
        const LoudnessPriorityTarget(
          path: '/c/1.flac',
          album: 'Different Tag',
          artist: 'Other Artist',
        ),
      );
      expect(pathFallbackIdx, 1);
    });
  });

  group('LoudnessBackfillState', () {
    test('tracks libraryFailed and failedInRun independently from analyzed count', () {
      const initial = LoudnessBackfillState(
        libraryTotal: 1216,
        libraryAnalyzed: 1198,
        libraryFailed: 18,
      );
      expect(initial.libraryProgress, closeTo(1198 / 1216, 1e-6));

      final updated = initial.copyWith(
        failedInRun: 2,
        libraryFailed: 20,
        lastError: 'File not accessible: missing.m4a',
      );
      expect(updated.libraryFailed, 20);
      expect(updated.failedInRun, 2);
      expect(updated.lastError, 'File not accessible: missing.m4a');
      expect(LoudnessSource.failed, lessThan(0));
    });
  });
}
