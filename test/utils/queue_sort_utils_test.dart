import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/utils/queue_sort_utils.dart';

void main() {
  MusicFile buildSong({
    required String path,
    String? name,
    String? title,
    String? artist,
    String? album,
    int? trackNumber,
    int? durationMillis,
  }) {
    return MusicFile(
      path: path,
      name: name ?? path.split('/').last,
      title: title,
      artist: artist,
      album: album,
      trackNumber: trackNumber,
      durationMillis: durationMillis,
    );
  }

  group('QueueSortUtils.sortQueue', () {
    test('returns empty list unchanged', () {
      const empty = <MusicFile>[];
      expect(
        QueueSortUtils.sortQueue(empty, QueueSortField.title, true),
        isEmpty,
      );
    });

    test('title sorting uses natural order and supports descending', () {
      final songs = [
        buildSong(path: '/music/10.mp3', title: 'Track 10'),
        buildSong(path: '/music/2.mp3', title: 'Track 2'),
        buildSong(path: '/music/1.mp3', title: 'track 1'),
      ];

      final asc = QueueSortUtils.sortQueue(songs, QueueSortField.title, true);
      expect(
        asc.map((s) => s.title).toList(),
        ['track 1', 'Track 2', 'Track 10'],
      );

      final desc = QueueSortUtils.sortQueue(songs, QueueSortField.title, false);
      expect(
        desc.map((s) => s.title).toList(),
        ['Track 10', 'Track 2', 'track 1'],
      );

      // Original list must not be mutated in place.
      expect(songs.first.title, 'Track 10');
    });

    test('artist sorting breaks ties by displayName', () {
      final songs = [
        buildSong(path: '/music/b.mp3', title: 'Zulu', artist: 'Artist 2'),
        buildSong(path: '/music/a.mp3', title: 'Alpha', artist: 'Artist 2'),
        buildSong(path: '/music/c.mp3', title: 'Beta', artist: 'Artist 10'),
      ];

      final asc = QueueSortUtils.sortQueue(songs, QueueSortField.artist, true);
      expect(
        asc.map((s) => '${s.artist}:${s.title}').toList(),
        ['Artist 2:Alpha', 'Artist 2:Zulu', 'Artist 10:Beta'],
      );
    });

    test('album sorting breaks ties by trackNumber then displayName', () {
      final songs = [
        buildSong(
          path: '/music/3.mp3',
          title: 'B Side',
          album: 'Album A',
          trackNumber: 2,
        ),
        buildSong(
          path: '/music/1.mp3',
          title: 'Intro',
          album: 'Album A',
          trackNumber: 1,
        ),
        buildSong(
          path: '/music/2.mp3',
          title: 'A Side',
          album: 'Album A',
          trackNumber: 2,
        ),
        buildSong(
          path: '/music/4.mp3',
          title: 'Other',
          album: 'Album B',
          trackNumber: 1,
        ),
      ];

      final asc = QueueSortUtils.sortQueue(songs, QueueSortField.album, true);
      expect(
        asc.map((s) => s.path).toList(),
        ['/music/1.mp3', '/music/2.mp3', '/music/3.mp3', '/music/4.mp3'],
      );
    });

    test('duration sorting handles nulls as 0 and breaks ties by displayName', () {
      final songs = [
        buildSong(path: '/music/b.mp3', title: 'Bravo', durationMillis: 120000),
        buildSong(path: '/music/a.mp3', title: 'Alpha', durationMillis: 120000),
        buildSong(path: '/music/c.mp3', title: 'NullDur', durationMillis: null),
        buildSong(path: '/music/d.mp3', title: 'Long', durationMillis: 240000),
      ];

      final asc = QueueSortUtils.sortQueue(songs, QueueSortField.duration, true);
      expect(
        asc.map((s) => s.title).toList(),
        ['NullDur', 'Alpha', 'Bravo', 'Long'],
      );
    });

    test('filename sorting uses natural order on file name', () {
      final songs = [
        buildSong(path: '/a/disc10.flac', name: 'disc10.flac', title: 'A'),
        buildSong(path: '/a/disc2.flac', name: 'disc2.flac', title: 'Z'),
      ];

      final asc = QueueSortUtils.sortQueue(songs, QueueSortField.filename, true);
      expect(asc.map((s) => s.name).toList(), ['disc2.flac', 'disc10.flac']);
    });

    test('trackNumber sorting places non-null track numbers before nulls', () {
      final songs = [
        buildSong(path: '/music/n2.mp3', title: 'NoTrack B', trackNumber: null),
        buildSong(path: '/music/t10.mp3', title: 'Ten', trackNumber: 10),
        buildSong(path: '/music/n1.mp3', title: 'NoTrack A', trackNumber: null),
        buildSong(path: '/music/t2.mp3', title: 'Two', trackNumber: 2),
      ];

      final asc = QueueSortUtils.sortQueue(
        songs,
        QueueSortField.trackNumber,
        true,
      );
      expect(
        asc.map((s) => s.title).toList(),
        ['Two', 'Ten', 'NoTrack A', 'NoTrack B'],
      );

      final desc = QueueSortUtils.sortQueue(
        songs,
        QueueSortField.trackNumber,
        false,
      );
      expect(
        desc.map((s) => s.title).toList(),
        ['NoTrack B', 'NoTrack A', 'Ten', 'Two'],
      );
    });
  });
}
