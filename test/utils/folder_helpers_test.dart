import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/utils/folder_helpers.dart';

void main() {
  group('findRepresentativeSong', () {
    test('returns null when folder has no songs', () {
      final folder = MusicFolder(path: '/music', name: 'music');
      expect(findRepresentativeSong(folder), isNull);
    });

    test('prefers song with artwork in files over first song without artwork', () {
      const song1NoArt = MusicFile(path: '/music/01.mp3', name: '01.mp3');
      const song2WithArt = MusicFile(
        path: '/music/02.mp3',
        name: '02.mp3',
        artworkPath: '/covers/02.jpg',
      );
      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [song1NoArt, song2WithArt],
      );

      expect(findRepresentativeSong(folder), equals(song2WithArt));
    });

    test('prefers song with artwork in allSongs (subFolders) if files has no artwork', () {
      const song1NoArt = MusicFile(path: '/music/01.mp3', name: '01.mp3');
      const subSongWithArt = MusicFile(
        path: '/music/sub/02.mp3',
        name: '02.mp3',
        thumbnailPath: '/thumbs/02.png',
      );
      final subFolder = MusicFolder(
        path: '/music/sub',
        name: 'sub',
        files: [subSongWithArt],
      );
      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [song1NoArt],
        subFolders: [subFolder],
      );

      expect(findRepresentativeSong(folder), equals(subSongWithArt));
    });

    test('falls back to first file if no song has artwork', () {
      const song1 = MusicFile(path: '/music/01.mp3', name: '01.mp3');
      const song2 = MusicFile(path: '/music/02.mp3', name: '02.mp3');
      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [song1, song2],
      );

      expect(findRepresentativeSong(folder), equals(song1));
    });
  });
}
