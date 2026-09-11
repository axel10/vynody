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

    test('does not create leading whitespace or whitespace tokens when space exists after line timestamp', () {
      const lrc = '[00:10.000] <00:10.000>Never <00:10.500>gonna <00:11.000>give <00:11.500>you <00:12.000>up';
      final parsed = LrcUtils.parseTimedLyrics(lrc);

      expect(parsed.length, 1);
      final line = parsed[0];
      expect(line.text, 'Never gonna give you up');
      expect(line.words, isNotNull);
      expect(line.words!.length, 5);
      expect(line.words![0].text, 'Never ');
      expect(line.words![0].text.startsWith(' '), isFalse);
      expect(line.words![1].text, 'gonna ');
      expect(line.words![4].text, 'up');
    });

    test('migrates leading spaces between words to previous word trailing space', () {
      const lrc = '[00:10.000] Never<00:10.500> gonna<00:11.000> give';
      final parsed = LrcUtils.parseTimedLyrics(lrc);

      expect(parsed.length, 1);
      final line = parsed[0];
      expect(line.text, 'Never gonna give');
      expect(line.words, isNotNull);
      expect(line.words!.length, 3);
      expect(line.words![0].text, 'Never ');
      expect(line.words![1].text, 'gonna ');
      expect(line.words![2].text, 'give');
    });
  });

  group('LrcUtils.restoreKaraokeLineBreaks', () {
    test('restores newlines when all newlines are lost in Chinese karaoke lyrics', () {
      const originalLyrics = '''
[00:01.00]我爱你中国
[00:05.00]亲爱的母亲
[00:10.00]我为你流泪
[00:15.00]也为你自豪
''';

      // Karaoke string with ALL newlines missing (single line)
      const lostNewlineKaraoke =
          '[00:01.00]我[00:01.50]爱[00:02.00]你[00:02.50]中[00:03.00]国'
          '[00:05.00]亲[00:05.50]爱[00:06.00]的[00:07.00]母[00:08.00]亲'
          '[00:10.00]我[00:11.00]为[00:12.00]你[00:13.00]流[00:14.00]泪'
          '[00:15.00]也[00:16.00]为[00:17.00]你[00:18.00]自[00:19.00]豪';

      final restored = LrcUtils.restoreKaraokeLineBreaks(
        karaokeLyrics: lostNewlineKaraoke,
        originalLyrics: originalLyrics,
      );

      final lines = restored.split('\n');
      expect(lines.length, 4);
      expect(lines[0], '[00:01.00]我[00:01.50]爱[00:02.00]你[00:02.50]中[00:03.00]国');
      expect(lines[1], '[00:05.00]亲[00:05.50]爱[00:06.00]的[00:07.00]母[00:08.00]亲');
      expect(lines[2], '[00:10.00]我[00:11.00]为[00:12.00]你[00:13.00]流[00:14.00]泪');
      expect(lines[3], '[00:15.00]也[00:16.00]为[00:17.00]你[00:18.00]自[00:19.00]豪');

      // Verify parseTimedLyrics produces 4 distinct timed lines with words
      final parsed = LrcUtils.parseTimedLyrics(restored);
      expect(parsed.length, 4);
      expect(parsed[0].text, '我爱你中国');
      expect(parsed[1].text, '亲爱的母亲');
      expect(parsed[2].text, '我为你流泪');
      expect(parsed[3].text, '也为你自豪');
    });

    test('restores newlines when all newlines are lost in English karaoke lyrics', () {
      const originalLyrics = '''
[00:20.10]Cause you were Romeo
[00:22.00]I was a scarlet letter
[00:24.00]And my daddy said
''';

      const lostNewlineKaraoke =
          '[00:20.10]Cause [00:20.50]you [00:20.80]were [00:21.10]Romeo '
          '[00:22.00]I [00:22.30]was [00:22.50]a [00:22.80]scarlet [00:23.20]letter '
          '[00:24.00]And [00:24.30]my [00:24.50]daddy [00:24.80]said';

      final restored = LrcUtils.restoreKaraokeLineBreaks(
        karaokeLyrics: lostNewlineKaraoke,
        originalLyrics: originalLyrics,
      );

      final lines = restored.split('\n');
      expect(lines.length, 3);
      expect(lines[0], '[00:20.10]Cause [00:20.50]you [00:20.80]were [00:21.10]Romeo');
      expect(lines[1], '[00:22.00]I [00:22.30]was [00:22.50]a [00:22.80]scarlet [00:23.20]letter');
      expect(lines[2], '[00:24.00]And [00:24.30]my [00:24.50]daddy [00:24.80]said');
    });

    test('restores newlines when original lyrics is plain text without timestamps', () {
      const plainOriginalLyrics = '''
First line of song
Second line of song
Third line of song
''';

      const lostNewlineKaraoke =
          '[00:01.00]First [00:01.50]line [00:02.00]of [00:02.50]song '
          '[00:05.00]Second [00:05.50]line [00:06.00]of [00:06.50]song '
          '[00:10.00]Third [00:10.50]line [00:11.00]of [00:11.50]song';

      final restored = LrcUtils.restoreKaraokeLineBreaks(
        karaokeLyrics: lostNewlineKaraoke,
        originalLyrics: plainOriginalLyrics,
      );

      final lines = restored.split('\n');
      expect(lines.length, 3);
      expect(lines[0], '[00:01.00]First [00:01.50]line [00:02.00]of [00:02.50]song');
      expect(lines[1], '[00:05.00]Second [00:05.50]line [00:06.00]of [00:06.50]song');
      expect(lines[2], '[00:10.00]Third [00:10.50]line [00:11.00]of [00:11.50]song');
    });

    test('preserves trailing timestamps on line end', () {
      const originalLyrics = '''
[00:01.00]Hello world
[00:05.00]Second line
''';

      const lostNewlineWithTrailing =
          '[00:01.00]Hello [00:01.50]world[00:02.00] '
          '[00:05.00]Second [00:05.50]line[00:06.00]';

      final restored = LrcUtils.restoreKaraokeLineBreaks(
        karaokeLyrics: lostNewlineWithTrailing,
        originalLyrics: originalLyrics,
      );

      final lines = restored.split('\n');
      expect(lines.length, 2);
      expect(lines[0], '[00:01.00]Hello [00:01.50]world[00:02.00]');
      expect(lines[1], '[00:05.00]Second [00:05.50]line[00:06.00]');
    });

    test('handles consecutive line-start timestamps [ts]<ts>', () {
      const originalLyrics = '''
[00:01.00]Hello world
[00:05.00]Second line
''';

      const lostNewlineDoubleTimestamps =
          '[00:01.00]<00:01.00>Hello <00:01.50>world '
          '[00:05.00]<00:05.00>Second <00:05.50>line';

      final restored = LrcUtils.restoreKaraokeLineBreaks(
        karaokeLyrics: lostNewlineDoubleTimestamps,
        originalLyrics: originalLyrics,
      );

      final lines = restored.split('\n');
      expect(lines.length, 2);
      expect(lines[0], '[00:01.00]<00:01.00>Hello <00:01.50>world');
      expect(lines[1], '[00:05.00]<00:05.00>Second <00:05.50>line');
    });

    test('does not modify lyrics if karaoke already has equal or more lines than original', () {
      const originalLyrics = '[00:01.00]Line 1\n[00:05.00]Line 2';
      const alreadySplitKaraoke = '[00:01.00]Line [00:02.00]1\n[00:05.00]Line [00:06.00]2';

      final restored = LrcUtils.restoreKaraokeLineBreaks(
        karaokeLyrics: alreadySplitKaraoke,
        originalLyrics: originalLyrics,
      );

      expect(restored, alreadySplitKaraoke);
    });

    test('normalizeGeneratedLyricsText automatically restores newlines when originalLyrics is passed', () {
      const originalLyrics = '''
[ti:Test Title]
[ar:Test Artist]
[00:01.00]Line one
[00:05.00]Line two
''';

      const rawAiSingleLine =
          '```lrc\n[00:01.00]Line [00:02.00]one [00:05.00]Line [00:06.00]two\n```';

      final normalized = LrcUtils.normalizeGeneratedLyricsText(
        rawAiSingleLine,
        preserveKaraokeLineStructure: true,
        originalLyrics: originalLyrics,
      );

      expect(normalized, '[00:01.00]Line [00:02.00]one\n[00:05.00]Line [00:06.00]two');
    });
  });
}
