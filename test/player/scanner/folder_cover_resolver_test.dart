import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/scanner/folder_cover_resolver.dart';

void main() {
  group('FolderCoverResolver', () {
    test('compareSongsForFolderCover prioritizes trackNumber then falls back to title and name', () {
      const track1SongZ = MusicFile(path: '/1z.mp3', name: 'Z.mp3', title: 'Zebra', trackNumber: 1);
      const track2SongA = MusicFile(path: '/2a.mp3', name: 'A.mp3', title: 'Apple', trackNumber: 2);
      const track2SongB = MusicFile(path: '/2b.mp3', name: 'B.mp3', title: 'Banana', trackNumber: 2);
      const noTrackSongA = MusicFile(path: '/na.mp3', name: 'A.mp3', title: 'Apple');
      const noTrackSongZ = MusicFile(path: '/nz.mp3', name: 'Z.mp3', title: 'Zebra');
      const noTrackNoTitleCat = MusicFile(path: '/cat.mp3', name: 'Cat.mp3');
      const noTrackNoTitleDog = MusicFile(path: '/dog.mp3', name: 'Dog.mp3');

      final list = [
        noTrackSongZ,
        noTrackNoTitleDog,
        track2SongB,
        noTrackSongA,
        track1SongZ,
        noTrackNoTitleCat,
        track2SongA,
      ];
      list.sort(FolderCoverResolver.compareSongsForFolderCover);

      expect(list.map((s) => s.path).toList(), [
        '/1z.mp3',  // Track 1 (even though Title is Zebra)
        '/2a.mp3',  // Track 2, Title Apple
        '/2b.mp3',  // Track 2, Title Banana
        '/na.mp3',  // No track, Title Apple
        '/cat.mp3', // No track, Name Cat.mp3
        '/dog.mp3', // No track, Name Dog.mp3
        '/nz.mp3',  // No track, Title Zebra
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

    test('evaluateRepresentativeSongForFolder uses hasArtwork true directly without probe and skips hasArtwork false', () async {
      const songNoArt = MusicFile(path: '/music/no.mp3', name: 'no.mp3', title: 'AAA', hasArtwork: false);
      const songHasArt = MusicFile(path: '/music/yes.mp3', name: 'yes.mp3', title: 'BBB', hasArtwork: true);
      const songUnknown = MusicFile(path: '/music/unk.mp3', name: 'unk.mp3', title: 'CCC');

      final probedPaths = <String>[];
      Future<bool> mockProbe(String path) async {
        probedPaths.add(path);
        return true;
      }

      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [songNoArt, songHasArt, songUnknown],
      );

      final rep = await FolderCoverResolver.evaluateRepresentativeSongForFolder(
        folder,
        probeCover: mockProbe,
      );

      expect(rep, equals(songHasArt));
      expect(probedPaths, isEmpty); // Zero I/O probes! songNoArt skipped, songHasArt chosen directly!
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

