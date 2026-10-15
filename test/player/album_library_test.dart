import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildAlbumSummaries', () {
    test('groups tracks with explicit albumArtist into a single album', () {
      final songs = [
        const SongMetadata(
          path: '/music/album1/01.mp3',
          title: 'Wanna Be Startin Somethin',
          album: 'Thriller',
          artist: 'Michael Jackson',
          albumArtist: 'Michael Jackson',
          trackNumber: 1,
          duration: 360000,
        ),
        const SongMetadata(
          path: '/music/album1/02.mp3',
          title: 'The Girl Is Mine',
          album: 'Thriller',
          artist: 'Michael Jackson & Paul McCartney',
          albumArtist: 'Michael Jackson',
          trackNumber: 2,
          duration: 220000,
        ),
      ];

      final albums = buildAlbumSummaries(songs);

      expect(albums.length, 1);
      final album = albums.first;
      expect(album.title, 'Thriller');
      expect(album.artist, 'Michael Jackson');
      expect(album.songs.length, 2);
      expect(album.songs[0].artist, 'Michael Jackson');
      expect(album.songs[1].artist, 'Michael Jackson & Paul McCartney');
      expect(album.songs[0].albumArtist, 'Michael Jackson');
      expect(album.songs[1].albumArtist, 'Michael Jackson');
      expect(album.totalDurationMillis, 580000);
    });

    test('groups tracks without explicit albumArtist in same folder by dominant artist', () {
      final songs = [
        const SongMetadata(
          path: '/music/divide/01.mp3',
          title: 'Eraser',
          album: 'Divide',
          artist: 'Ed Sheeran',
          trackNumber: 1,
          duration: 200000,
        ),
        const SongMetadata(
          path: '/music/divide/02.mp3',
          title: 'Perfect Duet',
          album: 'Divide',
          artist: 'Ed Sheeran feat. Beyonce',
          trackNumber: 2,
          duration: 260000,
        ),
        const SongMetadata(
          path: '/music/divide/03.mp3',
          title: 'Shape of You',
          album: 'Divide',
          artist: 'Ed Sheeran',
          trackNumber: 3,
          duration: 230000,
        ),
      ];

      final albums = buildAlbumSummaries(songs);

      expect(albums.length, 1);
      final album = albums.first;
      expect(album.title, 'Divide');
      expect(album.artist, 'Ed Sheeran');
      expect(album.songs.length, 3);
      expect(album.songs[1].artist, 'Ed Sheeran feat. Beyonce');
    });

    test('does not merge same-named albums from different artists in different folders', () {
      final songs = [
        const SongMetadata(
          path: '/music/queen/gh/01.mp3',
          title: 'Bohemian Rhapsody',
          album: 'Greatest Hits',
          artist: 'Queen',
          albumArtist: 'Queen',
          trackNumber: 1,
        ),
        const SongMetadata(
          path: '/music/abba/gh/01.mp3',
          title: 'Dancing Queen',
          album: 'Greatest Hits',
          artist: 'Abba',
          albumArtist: 'Abba',
          trackNumber: 1,
        ),
      ];

      final albums = buildAlbumSummaries(songs);

      expect(albums.length, 2);
      expect(albums.map((a) => a.artist), containsAll(['Queen', 'Abba']));
    });

    test('computes sortedGenres by count descending and yearRangeText for multiple years', () {
      final songs = [
        const SongMetadata(
          path: '/music/rock/01.mp3',
          title: 'Track 1',
          album: 'Anthology',
          artist: 'The Band',
          albumArtist: 'The Band',
          year: 1998,
          genres: ['Rock', 'Pop'],
        ),
        const SongMetadata(
          path: '/music/rock/02.mp3',
          title: 'Track 2',
          album: 'Anthology',
          artist: 'The Band',
          albumArtist: 'The Band',
          year: 2004,
          genres: ['Rock', 'Classic Rock'],
        ),
        const SongMetadata(
          path: '/music/rock/03.mp3',
          title: 'Track 3',
          album: 'Anthology',
          artist: 'The Band',
          albumArtist: 'The Band',
          year: 2001,
          genres: ['Rock'],
        ),
      ];

      final albums = buildAlbumSummaries(songs);
      expect(albums.length, 1);
      final album = albums.first;

      // Rock: 3 tracks, Pop: 1 track, Classic Rock: 1 track
      expect(album.sortedGenres.first, 'Rock');
      expect(album.sortedGenres, containsAllInOrder(['Rock']));
      expect(album.sortedGenres.length, 3);
      expect(album.yearRangeText, '1998 - 2004');
      expect(album.genresText, contains('Rock'));
    });

    test('computes single year when all tracks share same year', () {
      final songs = [
        const SongMetadata(
          path: '/music/pop/01.mp3',
          title: 'Pop 1',
          album: 'Pop Album',
          artist: 'Pop Star',
          year: 2023,
          genres: ['Pop'],
        ),
        const SongMetadata(
          path: '/music/pop/02.mp3',
          title: 'Pop 2',
          album: 'Pop Album',
          artist: 'Pop Star',
          year: 2023,
          genres: ['Pop', 'Dance'],
        ),
      ];

      final albums = buildAlbumSummaries(songs);
      expect(albums.length, 1);
      final album = albums.first;

      expect(album.yearRangeText, '2023');
      expect(album.sortedGenres, ['Pop', 'Dance']);
      expect(album.genresText, 'Pop / Dance');
    });
  });
}
