import 'package:flutter_test/flutter_test.dart';

import 'package:vynody/player/lyrics/lyrics_ai_shared.dart';
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

  group('LyricsAiTranslationStreamProcessor line-by-line streaming', () {
    test('emits only complete lines until newline, and flushes on force', () {
      final preparation = LyricsAiTranslationPreparation(
        sourceLines: ['Line 1', 'Line 2'],
        blankLineIndexes: [],
        compactSourceLines: ['Line 1', 'Line 2'],
      );
      final processor = LyricsAiTranslationStreamProcessor(
        preparation: preparation,
      );

      // Incomplete first line
      processor.addChunk('第一行翻译的前半句');
      expect(processor.buildProgressSnapshot(), isNull);

      // Completes first line with newline
      processor.addChunk('后半句\n');
      final snapshot1 = processor.buildProgressSnapshot();
      expect(snapshot1, isNotNull);
      expect(snapshot1!.visibleLines.length, 2);
      expect(snapshot1.visibleLines[0], '第一行翻译的前半句后半句');
      expect(snapshot1.visibleLines[1], '');

      // Incomplete second line
      processor.addChunk('第二行翻译的前半句');
      expect(processor.buildProgressSnapshot(), isNull);

      // Force flush at stream end emits the remaining line
      final finalSnapshot = processor.buildProgressSnapshot(force: true);
      expect(finalSnapshot, isNotNull);
      expect(finalSnapshot!.visibleLines[1], '第二行翻译的前半句');
    });
  });
}
