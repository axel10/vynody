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

  group('LrcUtils.parseTimedLyrics word-by-word', () {
    test('parses interspersed word-by-word timestamps', () {
      const lrc = '[00:48.940]我[00:49.370]爱[00:50.030]你';
      final parsed = LrcUtils.parseTimedLyrics(lrc);
      
      expect(parsed.length, 1);
      final line = parsed[0];
      expect(line.timestamp, const Duration(milliseconds: 48940));
      expect(line.text, '我爱你');
      expect(line.words, isNotNull);
      expect(line.words!.length, 3);
      
      expect(line.words![0].text, '我');
      expect(line.words![0].timestamp, const Duration(milliseconds: 48940));
      expect(line.words![0].durationMs, 430); // 49370 - 48940 = 430
      
      expect(line.words![1].text, '爱');
      expect(line.words![1].timestamp, const Duration(milliseconds: 49370));
      expect(line.words![1].durationMs, 660); // 50030 - 49370 = 660
      
      expect(line.words![2].text, '你');
      expect(line.words![2].timestamp, const Duration(milliseconds: 50030));
      expect(line.words![2].durationMs, 1000); // default
    });

    test('parses word-by-word with trailing timestamp', () {
      const lrc = '[00:48.940]我[00:49.370]爱[00:50.030]你[00:50.800]';
      final parsed = LrcUtils.parseTimedLyrics(lrc);
      
      expect(parsed.length, 1);
      final line = parsed[0];
      expect(line.text, '我爱你');
      expect(line.words!.length, 3);
      expect(line.words![2].text, '你');
      expect(line.words![2].timestamp, const Duration(milliseconds: 50030));
      expect(line.words![2].durationMs, 770); // 50800 - 50030 = 770
    });
  });
}
