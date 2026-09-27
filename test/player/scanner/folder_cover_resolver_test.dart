import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/scanner/folder_cover_resolver.dart';

void main() {
  group('FolderCoverResolver', () {
    test('compareSongsByTitle sorts by title ascending, falling back to name', () {
      const songA = MusicFile(path: '/a.mp3', name: 'Z.mp3', title: 'Apple');
      const songB = MusicFile(path: '/b.mp3', name: 'A.mp3', title: 'Banana');
      const songC = MusicFile(path: '/c.mp3', name: 'Cat.mp3');
      const songD = MusicFile(path: '/d.mp3', name: 'Dog.mp3');

      final list = [songD, songB, songC, songA];
      list.sort(FolderCoverResolver.compareSongsByTitle);

      expect(list.map((s) => s.path).toList(), [
        '/a.mp3', // Title: Apple
        '/b.mp3', // Title: Banana
        '/c.mp3', // Name: Cat.mp3
        '/d.mp3', // Name: Dog.mp3
      ]);
    });

    test('evaluateRepresentativeSongForFolder short-circuits probing on first match in title order', () async {
      const songA = MusicFile(path: '/music/z.mp3', name: 'z.mp3', title: 'AAA');
      const songB = MusicFile(path: '/music/b.mp3', name: 'b.mp3', title: 'BBB');
      const songC = MusicFile(path: '/music/a.mp3', name: 'a.mp3', title: 'CCC');

      final probedPaths = <String>[];
      Future<bool> mockProbe(String path) async {
        probedPaths.add(path);
        if (path == '/music/z.mp3') return true; // AAA has cover
        if (path == '/music/b.mp3') return true; // BBB has cover
        return false;
      }

      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [songC, songB, songA],
      );

      final rep = await FolderCoverResolver.evaluateRepresentativeSongForFolder(
        folder,
        probeCover: mockProbe,
      );

      expect(rep, equals(songA)); // Title 'AAA' (/music/z.mp3) is first in title ascending
      expect(probedPaths, equals(['/music/z.mp3'])); // Short-circuited! Did not probe BBB or CCC
    });

    test('computeFolderCoversBottomUp computes leaves first and bubbles up correctly', () async {
      // Subfolder has a file with cover
      const subSongNoCover = MusicFile(path: '/music/sub/1.mp3', name: '1.mp3', title: '1');
      const subSongWithCover = MusicFile(path: '/music/sub/2.mp3', name: '2.mp3', title: '2');
      final subFolder = MusicFolder(
        path: '/music/sub',
        name: 'sub',
        files: [subSongNoCover, subSongWithCover],
      );

      // Root folder has a file without cover
      const rootSongNoCover = MusicFile(path: '/music/root.mp3', name: 'root.mp3', title: 'Root');
      final rootFolder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [rootSongNoCover],
        subFolders: [subFolder],
      );

      final covers = await FolderCoverResolver.computeFolderCoversBottomUp(
        rootFolder,
        probeCover: (path) async => path == '/music/sub/2.mp3',
      );

      expect(subFolder.representativeSongCache, equals(subSongWithCover));
      expect(rootFolder.representativeSongCache, equals(subSongWithCover)); // Inherited from subFolder

      expect(covers, {
        '/music/sub': '/music/sub/2.mp3',
        '/music': '/music/sub/2.mp3',
      });
    });

    test('subfolders inheritance is deterministic regardless of list ordering (name ascending)', () async {
      const coverSongA = MusicFile(path: '/music/albumA/1.mp3', name: '1.mp3', artworkPath: '/art/a.jpg');
      const coverSongB = MusicFile(path: '/music/albumB/1.mp3', name: '1.mp3', artworkPath: '/art/b.jpg');

      final albumA = MusicFolder(path: '/music/albumA', name: 'Album A', files: [coverSongA]);
      final albumB = MusicFolder(path: '/music/albumB', name: 'Album B', files: [coverSongB]);

      // Root with subfolders in reversed order (Album B first, as if user sorted descending)
      final rootFolderDesc = MusicFolder(
        path: '/music',
        name: 'music',
        subFolders: [albumB, albumA],
      );

      final covers = await FolderCoverResolver.computeFolderCoversBottomUp(rootFolderDesc);

      // Root must deterministically inherit from Album A (name ascending), NOT Album B
      expect(rootFolderDesc.representativeSongCache, equals(coverSongA));
      expect(covers['/music'], equals('/music/albumA/1.mp3'));
    });
  });
}

