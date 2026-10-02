import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/audio/audio_service.dart';

void main() {
  group('AudioService URI & Artwork Cache Tests', () {
    test('safeDecodeUri returns raw string if no % present without decode overhead', () {
      const plainPath = '/storage/emulated/0/Music/Album/Song.mp3';
      expect(AudioService.safeDecodeUri(plainPath), plainPath);
      expect(AudioService.safeDecodeUri(null), '');
      expect(AudioService.safeDecodeUri(''), '');
    });

    test('safeDecodeUri correctly decodes percent-encoded URI', () {
      const encoded = 'file:///storage/emulated/0/Music/%E6%AD%8C%E6%9B%B2.mp3';
      const expected = 'file:///storage/emulated/0/Music/歌曲.mp3';
      expect(AudioService.safeDecodeUri(encoded), expected);
    });

    test('safeDecodeUri gracefully handles malformed percent encoding', () {
      const malformed = '/storage/100%_pure_music.mp3';
      expect(AudioService.safeDecodeUri(malformed), malformed);
    });
  });
}
