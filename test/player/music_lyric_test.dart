import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_lyric.dart';
import 'package:vynody/models/music_lyric_translation.dart';

void main() {
  group('MusicLyric.getEffectiveTranslationLanguage', () {
    test('returns target language when translation exists', () {
      final lyric = MusicLyric(
        translations: {
          'en': MusicLyricTranslation(
            languageCode: 'en',
            translatedText: 'Hello',
            translatedLines: ['Hello'],
          ),
        },
      );
      expect(lyric.getEffectiveTranslationLanguage('en'), 'en');
    });

    test('returns target language when translations are empty', () {
      final lyric = const MusicLyric();
      expect(lyric.getEffectiveTranslationLanguage('zh'), 'zh');
    });

    test('falls back to existing translation when target does not exist', () {
      final lyric = MusicLyric(
        translations: {
          'en': MusicLyricTranslation(
            languageCode: 'en',
            translatedText: 'Hello',
            translatedLines: ['Hello'],
          ),
        },
      );
      expect(lyric.getEffectiveTranslationLanguage('zh'), 'en');
    });

    test('falls back to the most recently updated translation when multiple exist and target does not exist', () {
      final lyric = MusicLyric(
        translations: {
          'en': MusicLyricTranslation(
            languageCode: 'en',
            translatedText: 'Hello',
            translatedLines: ['Hello'],
            updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
          'es': MusicLyricTranslation(
            languageCode: 'es',
            translatedText: 'Hola',
            translatedLines: ['Hola'],
            updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
          ),
        },
      );
      expect(lyric.getEffectiveTranslationLanguage('zh'), 'es');
    });
  });
}
