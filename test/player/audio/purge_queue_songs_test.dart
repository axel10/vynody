import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';

void main() {
  group('Queue purge path filtering tests', () {
    test('ScannerPathUtils.pathContains identifies children correctly', () {
      final root = p.normalize('/Users/test/Music');
      final child1 = p.normalize('/Users/test/Music/Album1/track1.mp3');
      final child2 = p.normalize('/Users/test/Music/track2.flac');
      final outside = p.normalize('/Users/test/Downloads/track3.mp3');

      expect(ScannerPathUtils.pathContains(root, child1), isTrue);
      expect(ScannerPathUtils.pathContains(root, child2), isTrue);
      expect(ScannerPathUtils.pathContains(root, outside), isFalse);
    });

    test('Purge song filter correctly matches by path and root', () {
      final root = p.normalize('/storage/music');
      final songs = [
        const MusicFile(
          id: 1,
          name: 'song1.mp3',
          path: '/storage/music/song1.mp3',
          title: 'Song 1',
          artist: 'Artist 1',
        ),
        const MusicFile(
          id: 2,
          name: 'song2.mp3',
          path: '/storage/music/sub/song2.mp3',
          title: 'Song 2',
          artist: 'Artist 2',
        ),
        const MusicFile(
          id: 3,
          name: 'song3.mp3',
          path: '/other/path/song3.mp3',
          title: 'Song 3',
          artist: 'Artist 3',
        ),
      ];

      final roots = [ScannerPathUtils.normalizePath(root)];

      bool shouldRemove(MusicFile song) {
        final normPath = ScannerPathUtils.normalizePath(song.path);
        for (final r in roots) {
          if (ScannerPathUtils.pathContains(r, normPath)) return true;
        }
        return false;
      }

      final remaining = songs.where((s) => !shouldRemove(s)).toList();

      expect(remaining.length, 1);
      expect(remaining.first.path, '/other/path/song3.mp3');
    });

    test('Remote URIs match prefix under remote root', () {
      final remoteRoot = 'webdav://myserver/music';
      final remoteSong1 = 'webdav://myserver/music/album/song1.flac';
      final remoteSong2 = 'webdav://myserver/other/song2.flac';

      bool isSongUnderRemoteRoot(String songPath, String rootPath) {
        return songPath.toLowerCase().startsWith(rootPath.toLowerCase());
      }

      expect(isSongUnderRemoteRoot(remoteSong1, remoteRoot), isTrue);
      expect(isSongUnderRemoteRoot(remoteSong2, remoteRoot), isFalse);
    });
  });
}
