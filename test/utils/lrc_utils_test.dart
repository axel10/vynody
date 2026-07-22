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

    test('parses Apple Music style angle brackets <mm:ss.xxx> word-by-word lyrics', () {
      const lrc = '<03:51.501>方<03:51.851>向<03:52.291>盘<03:52.741>周<03:53.161>围';
      final parsed = LrcUtils.parseTimedLyrics(lrc);

      expect(parsed.length, 1);
      final line = parsed[0];
      expect(line.timestamp, const Duration(minutes: 3, seconds: 51, milliseconds: 501));
      expect(line.text, '方向盘周围');
      expect(line.words, isNotNull);
      expect(line.words!.length, 5);

      expect(line.words![0].text, '方');
      expect(line.words![0].timestamp, const Duration(minutes: 3, seconds: 51, milliseconds: 501));
      expect(line.words![0].durationMs, 350); // 51.851 - 51.501

      expect(line.words![1].text, '向');
      expect(line.words![1].timestamp, const Duration(minutes: 3, seconds: 51, milliseconds: 851));
      expect(line.words![1].durationMs, 440); // 52.291 - 51.851

      expect(line.words![2].text, '盘');
      expect(line.words![2].timestamp, const Duration(minutes: 3, seconds: 52, milliseconds: 291));
      expect(line.words![2].durationMs, 450); // 52.741 - 52.291

      expect(line.words![3].text, '周');
      expect(line.words![3].durationMs, 420); // 53.161 - 52.741

      expect(line.words![4].text, '围');
    });

    test('parses multi-line word-per-line lyrics format with single/double newlines and trailing timestamp', () {
      const lrc = '<03:51.501>方\n<03:51.851>向\n<03:52.291>盘\n<03:52.741>周\n<03:53.161>围\n<03:53.600>\n<03:55.100>车\n<03:55.400>窗\n<03:55.800>外';
      final parsed = LrcUtils.parseTimedLyrics(lrc);

      expect(parsed.length, 2);

      final line1 = parsed[0];
      expect(line1.text, '方向盘周围');
      expect(line1.words!.length, 5);
      expect(line1.words![4].text, '围');
      expect(line1.words![4].durationMs, 439); // 53.600 - 53.161 = 439

      final line2 = parsed[1];
      expect(line2.text, '车窗外');
      expect(line2.words!.length, 3);
    });

    test('handles repeating word-per-line timestamp blocks accurately in file order', () {
      const lrc = '<01:51.501>方\n<01:51.851>向\n<01:52.291>盘\n<01:52.741>周\n<01:53.161>围\n<01:53.162>\n<01:51.501>方\n<01:51.851>向\n<01:52.291>盘\n<01:52.741>周\n<01:53.161>围';
      final parsed = LrcUtils.parseTimedLyrics(lrc);

      expect(parsed.length, 2);
      expect(parsed[0].text, '方向盘周围');
      expect(parsed[0].words!.length, 5);
      expect(parsed[0].words![0].text, '方');
      expect(parsed[0].words![1].text, '向');

      expect(parsed[1].text, '方向盘周围');
      expect(parsed[1].words!.length, 5);
    });
  });
}
