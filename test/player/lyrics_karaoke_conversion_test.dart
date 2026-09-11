import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/lyrics/lyrics_ai_shared.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/utils/lrc_utils.dart';

void main() {
  group('Lyrics Karaoke Conversion Tests', () {
    test('buildConvertToKaraokePrompt formats prompt with lyrics and retains timestamps', () {
      const inputLyrics = '[00:01.00]Hello world\n[00:05.00]Second line of song';
      final prompt = LyricsAiPromptBuilder.buildConvertToKaraokePrompt(lyrics: inputLyrics);

      expect(
        prompt,
        contains('严格保持原歌词的分行结构和行数不变，原歌词有几行输出就必须是几行！绝对禁止在词与词、字与字之间换行！'),
      );
      expect(prompt, contains('[00:01.00]Hello world\n[00:05.00]Second line of song'));
    });

    test('buildConvertToKaraokePrompt retains plain text lyrics and newlines', () {
      const inputLyrics = 'Hello world\nSecond line of song\nThird line';
      final prompt = LyricsAiPromptBuilder.buildConvertToKaraokePrompt(lyrics: inputLyrics);

      expect(
        prompt,
        contains('待转换歌词如下：\nHello world\nSecond line of song\nThird line'),
      );
    });

    test('LyricsCacheSource.aiKaraoke serialization and helpers work properly', () {
      expect(LyricsCacheSource.fromDbValue('ai_karaoke'), LyricsCacheSource.aiKaraoke);
      expect(LyricsCacheSource.fromDbValue('gemini_karaoke'), LyricsCacheSource.aiKaraoke);
      expect(LyricsCacheSource.fromMusicLyricSource('ai_karaoke'), LyricsCacheSource.aiKaraoke);
      expect(LyricsCacheSource.aiKaraoke.dbValue, 'ai_karaoke');
      expect(LyricsCacheSource.aiKaraoke.musicLyricSource, 'ai');
      expect(LyricsCacheSource.aiKaraoke.isAiSource, isTrue);
    });

    test('isKaraokeLyricsLine correctly identifies word-by-word karaoke lines', () {
      expect(LrcUtils.isKaraokeLyricsLine('[00:01.00]Hello [00:01.50]world'), isTrue);
      expect(LrcUtils.isKaraokeLyricsLine('[00:01.00]每[00:01.50]个[00:02.00]字'), isTrue);
      expect(LrcUtils.isKaraokeLyricsLine('[00:01.00]<00:01.00>Hello <00:01.50>world'), isTrue);

      // Normal single timestamp line is not karaoke
      expect(LrcUtils.isKaraokeLyricsLine('[00:01.00]Hello world'), isFalse);
      // Multiple duplicate timestamps at line start with no text in-between is not karaoke
      expect(LrcUtils.isKaraokeLyricsLine('[00:01.00][00:05.00]Chorus line'), isFalse);
    });

    test('normalizeGeneratedLyricsText preserves karaoke word-by-word line structure', () {
      const karaokeLyrics = '''
[00:01.00]Hello [00:01.50]world [00:02.00]today
[00:05.00]Second [00:05.60]line [00:06.20]of [00:06.80]song
''';

      // Whether preserveKaraokeLineStructure is explicitly true or inferred
      final normalized1 = LrcUtils.normalizeGeneratedLyricsText(
        karaokeLyrics,
        preserveKaraokeLineStructure: true,
      );
      expect(
        normalized1,
        '[00:01.00]Hello [00:01.50]world [00:02.00]today\n[00:05.00]Second [00:05.60]line [00:06.20]of [00:06.80]song',
      );

      final normalized2 = LrcUtils.normalizeGeneratedLyricsText(
        karaokeLyrics,
        preserveKaraokeLineStructure: false,
      );
      expect(
        normalized2,
        '[00:01.00]Hello [00:01.50]world [00:02.00]today\n[00:05.00]Second [00:05.60]line [00:06.20]of [00:06.80]song',
      );
    });

    test('normalizeGeneratedLyricsText still expands stacked/packed timestamps for plain lines', () {
      const stackedLyrics = '[00:01.00][00:05.00]Repeated chorus line';
      final normalized = LrcUtils.normalizeGeneratedLyricsText(stackedLyrics);

      expect(
        normalized,
        '[00:01.00] Repeated chorus line\n[00:05.00] Repeated chorus line',
      );
    });

    test('normalizeGeneratedLyricsText collapses duplicate adjacent timestamps at line start', () {
      const lyricsWithDoubleLineStart =
          '[00:08.89][00:09.11]Some [00:09.47]days [00:09.68]you\'re [00:09.91]alone, [00:10.51] yeah';
      final normalized = LrcUtils.normalizeGeneratedLyricsText(
        lyricsWithDoubleLineStart,
        preserveKaraokeLineStructure: true,
      );
      expect(
        normalized,
        '[00:08.89]Some [00:09.47]days [00:09.68]you\'re [00:09.91]alone, [00:10.51] yeah',
      );
    });

    test('parseTimedLyrics does not duplicate line when line start has adjacent timestamps in karaoke', () {
      const lyricsWithDoubleLineStart =
          '[00:08.89][00:09.11]Some [00:09.47]days [00:09.68]you\'re [00:09.91]alone, [00:10.51] yeah\n'
          '[00:13.39][00:13.62]Some [00:13.88]days [00:14.22]this [00:14.39]don\'t [00:14.65]feel';

      final parsed = LrcUtils.parseTimedLyrics(lyricsWithDoubleLineStart);
      // There should only be 2 lines, NOT 4 lines!
      expect(parsed.length, 2);
      expect(parsed[0].text, "Some days you're alone, yeah");
      expect(parsed[0].words?.length, 5);
      expect(parsed[1].text, "Some days this don't feel");
    });
  });
}
