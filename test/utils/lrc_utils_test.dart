import 'package:flutter_test/flutter_test.dart';

import 'package:vynody/utils/lrc_utils.dart';

void main() {
  group('LrcUtils.normalizeGeneratedLyricsText', () {
    test('splits packed timed lyrics into one timestamp per line', () {
      const packedLyrics = '[00:01.00]第一句[00:05.00]第二句[00:09.00]第三句';

      final normalized = LrcUtils.normalizeGeneratedLyricsText(packedLyrics);

      expect(normalized, '[00:01.00] 第一句\n[00:05.00] 第二句\n[00:09.00] 第三句');

      final parsed = LrcUtils.parseTimedLyrics(normalized);
      expect(parsed.length, 3);
      expect(parsed[0].timestamp, const Duration(minutes: 0, seconds: 1));
      expect(parsed[0].text, '第一句');
      expect(parsed[1].timestamp, const Duration(minutes: 0, seconds: 5));
      expect(parsed[1].text, '第二句');
      expect(parsed[2].timestamp, const Duration(minutes: 0, seconds: 9));
      expect(parsed[2].text, '第三句');
    });

    test('duplicates shared text for consecutive timestamps', () {
      const packedLyrics = '[00:10.00][00:12.00]副歌';

      final normalized = LrcUtils.normalizeGeneratedLyricsText(packedLyrics);

      expect(normalized, '[00:10.00] 副歌\n[00:12.00] 副歌');

      final parsed = LrcUtils.parseTimedLyrics(normalized);
      expect(parsed.length, 2);
      expect(parsed[0].text, '副歌');
      expect(parsed[1].text, '副歌');
    });
  });
}
