import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/lyrics/lyrics_ai_shared.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';

void main() {
  group('Lyrics Karaoke Conversion Tests', () {
    test('buildConvertToKaraokePrompt formats prompt with lyrics and retains timestamps', () {
      const inputLyrics = '[00:01.00]Hello world\n[00:05.00]Second line of song';
      final prompt = LyricsAiPromptBuilder.buildConvertToKaraokePrompt(lyrics: inputLyrics);

      expect(
        prompt,
        '将以下歌词转换成卡拉ok歌词，即在每个单词前添加时间轴。注意保留歌词中的换行：\n[00:01.00]Hello world\n[00:05.00]Second line of song',
      );
    });

    test('buildConvertToKaraokePrompt retains plain text lyrics and newlines', () {
      const inputLyrics = 'Hello world\nSecond line of song\nThird line';
      final prompt = LyricsAiPromptBuilder.buildConvertToKaraokePrompt(lyrics: inputLyrics);

      expect(
        prompt,
        '将以下歌词转换成卡拉ok歌词，即在每个单词前添加时间轴。注意保留歌词中的换行：\nHello world\nSecond line of song\nThird line',
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
  });
}
