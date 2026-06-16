import 'package:flutter_test/flutter_test.dart';

import 'package:vynody/player/lyrics/lyrics_ai_stream_parser.dart';

void main() {
  group('LyricsAiStreamTextParser', () {
    test('ignores reasoning fields when extracting text', () {
      final parser = LyricsAiStreamTextParser();
      const payload = '''
{"choices":[{"delta":{"content":"","reasoning":"thinking...","reasoning_details":[{"type":"reasoning.text","text":"hidden"}]}}]}
''';

      final extracted = parser.extractText(payload);

      expect(extracted, isNull);
    });

    test('detects refusal-like text', () {
      final parser = LyricsAiStreamTextParser();

      expect(parser.looksLikeRefusalText('很抱歉，我无法提供这首歌的完整歌词。'), isTrue);
      expect(
        parser.looksLikeRefusalText('Here is the requested LRC content.'),
        isFalse,
      );
    });

    test('extracts visible content while ignoring reasoning payloads', () {
      final parser = LyricsAiStreamTextParser();
      const payload = '''
{"choices":[{"delta":{"content":"[00:01.00]hello","reasoning":"thinking...","reasoning_details":[{"type":"reasoning.text","text":"hidden"}]}}]}
''';

      final extracted = parser.extractText(payload);

      expect(extracted, '[00:01.00]hello');
    });
  });
}
