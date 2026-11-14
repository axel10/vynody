import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/utils/clean_helper.dart';
import 'package:vynody/utils/language_code_utils.dart';
import 'package:vynody/utils/localized_text.dart';
import 'package:vynody/utils/lyrics_id_utils.dart';
import 'package:vynody/utils/query_url_utils.dart';

void main() {
  group('CleanHelper', () {
    test('stripSequenceNumber removes leading track/disc prefixes', () {
      expect(CleanHelper.stripSequenceNumber('01. Song Name'), 'Song Name');
      expect(CleanHelper.stripSequenceNumber('01-02_Song Name'), 'Song Name');
      expect(CleanHelper.stripSequenceNumber('  3 - Track'), 'Track');
      // Pure numbers should not be wiped out to empty string.
      expect(CleanHelper.stripSequenceNumber('1999'), '1999');
      expect(CleanHelper.stripSequenceNumber(''), '');
    });

    test('removeBrackets strips ASCII and CJK square brackets', () {
      expect(
        CleanHelper.removeBrackets('Song Name [Live] 【2024】'),
        'Song Name',
      );
      expect(
        CleanHelper.removeBrackets('[Hi-Res]   My   Song [FLAC]'),
        'My Song',
      );
      expect(CleanHelper.removeBrackets(''), '');
    });

    test('deriveCleanTitleFromFileName strips extension, brackets, and sequence', () {
      expect(
        CleanHelper.deriveCleanTitleFromFileName('/music/01. [2024] Midnight City [Live].flac'),
        'Midnight City',
      );
    });
  });

  group('LyricsIdUtils', () {
    test('fromLyricsText strips timestamps and normalizes line endings', () {
      const lrcCrlf = '[00:01.00]Hello\r\n[00:02.50]World\r\n';
      const lrcLf = '[00:10.00]Hello\n[00:20.00]World';

      final id1 = LyricsIdUtils.fromLyricsText(lrcCrlf);
      final id2 = LyricsIdUtils.fromLyricsText(lrcLf);

      expect(id1, hasLength(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(id1), isTrue);
      expect(id1, equals(id2));
    });

    test('fromLyricsText returns empty string for null or timestamp-only input', () {
      expect(LyricsIdUtils.fromLyricsText(null), '');
      expect(LyricsIdUtils.fromLyricsText('   '), '');
      expect(LyricsIdUtils.fromLyricsText('[00:01.00]\n[00:02.00]'), '');
    });
  });

  group('QueryUrlUtils', () {
    test('buildUrl handles empty parameters, encoded params, and raw params', () {
      expect(
        QueryUrlUtils.buildUrl('https://example.com/api'),
        'https://example.com/api',
      );

      final url = QueryUrlUtils.buildUrl(
        'https://example.com/search',
        queryParameters: {'q': 'hello world', 'a&b': '1+2'},
        rawQueryParameters: {'raw': 'foo/bar'},
      );

      expect(
        url,
        'https://example.com/search?q=hello+world&a%26b=1%2B2&raw=foo/bar',
      );
    });
  });

  group('LanguageCodeUtils', () {
    tearDown(() {
      LocalizedText.overrideLanguageCode = null;
    });

    test('normalizeLanguageCode normalizes Chinese variants and generic locales', () {
      expect(LanguageCodeUtils.normalizeLanguageCode('zh-Hant'), 'zh-tw');
      expect(LanguageCodeUtils.normalizeLanguageCode('zh_TW'), 'zh-tw');
      expect(LanguageCodeUtils.normalizeLanguageCode('zh-HK'), 'zh-tw');
      expect(LanguageCodeUtils.normalizeLanguageCode('zh-MO'), 'zh-tw');

      expect(LanguageCodeUtils.normalizeLanguageCode('zh'), 'zh-cn');
      expect(LanguageCodeUtils.normalizeLanguageCode('zh_CN'), 'zh-cn');
      expect(LanguageCodeUtils.normalizeLanguageCode('zh-Hans'), 'zh-cn');

      expect(LanguageCodeUtils.normalizeLanguageCode('en_US'), 'en');
      expect(LanguageCodeUtils.normalizeLanguageCode('JA-jp'), 'ja');
      expect(LanguageCodeUtils.normalizeLanguageCode('  '), '');
      expect(LanguageCodeUtils.normalizeLanguageCode(null), '');
    });

    test('currentAppLanguageCode respects overrideLanguageCode', () {
      LocalizedText.overrideLanguageCode = 'zh_Hant';
      expect(LanguageCodeUtils.currentAppLanguageCode(), 'zh-tw');

      LocalizedText.overrideLanguageCode = 'ja';
      expect(LanguageCodeUtils.currentAppLanguageCode(), 'ja');
    });
  });
}
