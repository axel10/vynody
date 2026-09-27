import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/utils/folder_helpers.dart';

void main() {
  group('folder_helpers', () {
    test('hasSongArtwork returns true if artwork or thumbnail exists', () {
      expect(hasSongArtwork(null), isFalse);
      expect(hasSongArtwork(const MusicFile(path: '/a.mp3', name: 'a.mp3')), isFalse);
      expect(
        hasSongArtwork(const MusicFile(
          path: '/a.mp3',
          name: 'a.mp3',
          artworkPath: '/art.jpg',
        )),
        true,
      );
      expect(
        hasSongArtwork(const MusicFile(
          path: '/a.mp3',
          name: 'a.mp3',
          thumbnailPath: '/thumb.jpg',
        )),
        true,
      );
    });

    test('formatDurationMs formats milliseconds into strings', () {
      expect(formatDurationMs(null), '0:00');
      expect(formatDurationMs(0), '0:00');
      expect(formatDurationMs(65000), '1:05');
      expect(formatDurationMs(3665000), '1:01:05');
    });

    test('formatFileSize formats byte count to human-readable size', () {
      expect(formatFileSize(null), '0 B');
      expect(formatFileSize(500), '500 B');
      expect(formatFileSize(1024 * 500), '500.0 KB');
      expect(formatFileSize(1024 * 1024 * 5), '5.0 MB');
    });
  });
}
