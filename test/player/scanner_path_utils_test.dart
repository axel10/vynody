import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';

void main() {
  group('ScannerPathUtils path comparison tests', () {
    test('pathsEqual identifies equal and normalized paths', () {
      expect(ScannerPathUtils.pathsEqual('/a/b/c', '/a/b/c'), isTrue);
      expect(ScannerPathUtils.pathsEqual('/a/b/c/', '/a/b/c'), isTrue);
      expect(ScannerPathUtils.pathsEqual('/a/b/c', '/a/b/d'), isFalse);
    });

    test('isNormalizedPathWithinOrEqual handles identical and subpaths correctly', () {
      expect(
        ScannerPathUtils.isNormalizedPathWithinOrEqual('/a/b', '/a/b'),
        isTrue,
      );
      expect(
        ScannerPathUtils.isNormalizedPathWithinOrEqual('/a/b', '/a/b/c.mp3'),
        isTrue,
      );
      expect(
        ScannerPathUtils.isNormalizedPathWithinOrEqual('/a/b', '/a/b/sub/c.mp3'),
        isTrue,
      );
      // Prefix collision, not a subdirectory
      expect(
        ScannerPathUtils.isNormalizedPathWithinOrEqual('/a/b', '/a/bc/c.mp3'),
        isFalse,
      );
      expect(
        ScannerPathUtils.isNormalizedPathWithinOrEqual('/a/b', '/a/b_extra/c.mp3'),
        isFalse,
      );
      // Parent directory
      expect(
        ScannerPathUtils.isNormalizedPathWithinOrEqual('/a/b', '/a'),
        isFalse,
      );
      // Sibling / unrelated directory
      expect(
        ScannerPathUtils.isNormalizedPathWithinOrEqual('/a/b', '/other/c.mp3'),
        isFalse,
      );
      // Root directory
      expect(
        ScannerPathUtils.isNormalizedPathWithinOrEqual('/', '/a/b/c.mp3'),
        isTrue,
      );
    });

    test('pathContains handles raw paths correctly', () {
      expect(
        ScannerPathUtils.pathContains('/Users/music/', '/Users/music/artist/song.flac'),
        isTrue,
      );
      expect(
        ScannerPathUtils.pathContains('/Users/music', '/Users/music/artist/song.flac'),
        isTrue,
      );
      expect(
        ScannerPathUtils.pathContains('/Users/music', '/Users/music'),
        isTrue,
      );
      expect(
        ScannerPathUtils.pathContains('/Users/music', '/Users/music2/song.flac'),
        isFalse,
      );
      expect(
        ScannerPathUtils.pathContains('/Users/music', '/Users/downloads/song.flac'),
        isFalse,
      );
    });
  });
}
