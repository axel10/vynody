import 'package:flutter_test/flutter_test.dart';

import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/widgets/lyrics_interlude_indicator.dart';

void main() {
  group('buildLyricsDisplayEntries', () {
    test('inserts intro interlude when first lyric starts at or after 5s and preserves originalIndex', () {
      final lines = [
        const LyricLine(timestamp: Duration(seconds: 8), text: 'Angel of my dreams'),
        const LyricLine(timestamp: Duration(seconds: 12), text: 'Second line'),
      ];

      final entries = buildLyricsDisplayEntries(lines);

      expect(entries.length, 3);
      expect(entries[0].isInterlude, isTrue);
      expect(entries[0].interlude!.isIntro, isTrue);
      expect(entries[0].interlude!.startMs, 0);
      expect(entries[0].interlude!.endMs, 8000);

      expect(entries[1].isInterlude, isFalse);
      expect(entries[1].originalIndex, 0);
      expect(entries[1].line!.text, 'Angel of my dreams');

      expect(entries[2].isInterlude, isFalse);
      expect(entries[2].originalIndex, 1);
      expect(entries[2].line!.text, 'Second line');
    });

    test('does not insert intro interlude when first lyric starts before 5s', () {
      final lines = [
        const LyricLine(timestamp: Duration(milliseconds: 4999), text: 'First line'),
      ];

      final entries = buildLyricsDisplayEntries(lines);

      expect(entries.length, 1);
      expect(entries[0].isInterlude, isFalse);
      expect(entries[0].originalIndex, 0);
    });

    test('does not duplicate intro when first line is already a blank timed line', () {
      final lines = [
        const LyricLine(timestamp: Duration.zero, text: ''),
        const LyricLine(timestamp: Duration(seconds: 7), text: 'First lyric'),
      ];

      final entries = buildLyricsDisplayEntries(lines);

      expect(entries.length, 2);
      expect(entries[0].isInterlude, isTrue);
      expect(entries[0].interlude!.startMs, 0);
      expect(entries[0].interlude!.endMs, 7000);
      expect(entries[0].interlude!.sourceLineIndex, 0);
      expect(entries[1].originalIndex, 1);
    });

    test('converts timed blank line >= 5s into interlude and merges consecutive blank lines', () {
      final lines = [
        const LyricLine(timestamp: Duration(seconds: 2), text: 'Line 1'),
        const LyricLine(timestamp: Duration(seconds: 6), text: ''),
        const LyricLine(timestamp: Duration(seconds: 9), text: '   '),
        const LyricLine(timestamp: Duration(seconds: 14), text: 'Line 2'),
      ];

      final entries = buildLyricsDisplayEntries(lines);

      expect(entries.length, 3);
      expect(entries[0].originalIndex, 0);
      expect(entries[1].isInterlude, isTrue);
      expect(entries[1].interlude!.startMs, 6000);
      expect(entries[1].interlude!.endMs, 14000);
      expect(entries[2].originalIndex, 3);
    });

    test('skips short blank lines (< 5s) and trailing outro blank lines', () {
      final lines = [
        const LyricLine(timestamp: Duration(seconds: 1), text: 'Line 1'),
        const LyricLine(timestamp: Duration(seconds: 5), text: ''),
        const LyricLine(timestamp: Duration(seconds: 9), text: 'Line 2'),
        const LyricLine(timestamp: Duration(seconds: 15), text: ''),
      ];

      final entries = buildLyricsDisplayEntries(lines);

      expect(entries.length, 2);
      expect(entries[0].originalIndex, 0);
      expect(entries[1].originalIndex, 2);
    });

    test('inserts interlude for word-by-word lyrics when gap after last word >= 5s', () {
      final lines = [
        const LyricLine(
          timestamp: Duration(seconds: 1),
          text: 'Hello world',
          words: [
            LyricWord(timestamp: Duration(seconds: 1), durationMs: 500, text: 'Hello '),
            LyricWord(timestamp: Duration(milliseconds: 1500), durationMs: 1000, text: 'world'),
          ],
        ),
        const LyricLine(timestamp: Duration(seconds: 8), text: 'Next verse'),
      ];

      final entries = buildLyricsDisplayEntries(lines);

      // last word ends at 2500ms, next line starts at 8000ms -> gap = 5500ms >= 5000ms
      expect(entries.length, 3);
      expect(entries[0].originalIndex, 0);
      expect(entries[1].isInterlude, isTrue);
      expect(entries[1].interlude!.startMs, 2500);
      expect(entries[1].interlude!.endMs, 8000);
      expect(entries[2].originalIndex, 1);
    });

    test('does not insert interlude for word-by-word lyrics when gap after last word < 5s', () {
      final lines = [
        const LyricLine(
          timestamp: Duration(seconds: 1),
          text: 'Hello',
          words: [
            LyricWord(timestamp: Duration(seconds: 1), durationMs: 2500, text: 'Hello'),
          ],
        ),
        const LyricLine(timestamp: Duration(seconds: 8), text: 'Next verse'),
      ];

      final entries = buildLyricsDisplayEntries(lines);

      // last word ends at 3500ms, next line starts at 8000ms -> gap = 4500ms < 5000ms
      expect(entries.length, 2);
      expect(entries.every((e) => !e.isInterlude), isTrue);
    });

    test('never guesses interlude between plain line-synced lyrics without blank lines', () {
      final lines = [
        const LyricLine(timestamp: Duration(seconds: 1), text: 'Long held note'),
        const LyricLine(timestamp: Duration(seconds: 20), text: 'Next line'),
      ];

      final entries = buildLyricsDisplayEntries(lines);

      expect(entries.length, 2);
      expect(entries.every((e) => !e.isInterlude), isTrue);
    });

    test('returns plain untimed lyrics unchanged', () {
      final lines = [
        const LyricLine(timestamp: Duration.zero, text: 'Plain 1', isTimed: false),
        const LyricLine(timestamp: Duration.zero, text: '', isTimed: false),
        const LyricLine(timestamp: Duration.zero, text: 'Plain 2', isTimed: false),
      ];

      final entries = buildLyricsDisplayEntries(lines);

      expect(entries.length, 3);
      expect(entries.every((e) => !e.isInterlude), isTrue);
    });
  });

  group('computeInterludeDotsFrame', () {
    test('lights up three dots sequentially across the interlude duration', () {
      const durationMs = 6000;
      // Exit phase starts at 6000 - 560 = 5440ms -> segment ≈ 1813ms each

      final early = computeInterludeDotsFrame(elapsedMs: 900, durationMs: durationMs);
      expect(early.groupOpacity, closeTo(1.0, 0.01));
      expect(early.dots[0].opacity, greaterThan(early.dots[1].opacity));
      expect(early.dots[1].opacity, closeTo(0.26, 0.01));
      expect(early.dots[2].opacity, closeTo(0.26, 0.01));

      final middle = computeInterludeDotsFrame(elapsedMs: 2800, durationMs: durationMs);
      expect(middle.dots[0].opacity, closeTo(1.0, 0.01));
      expect(middle.dots[1].opacity, greaterThan(0.5));
      expect(middle.dots[2].opacity, closeTo(0.26, 0.01));

      final allLit = computeInterludeDotsFrame(elapsedMs: 5440, durationMs: durationMs);
      expect(allLit.dots[0].opacity, closeTo(1.0, 0.01));
      expect(allLit.dots[1].opacity, closeTo(1.0, 0.01));
      expect(allLit.dots[2].opacity, closeTo(1.0, 0.01));
      expect(allLit.groupOpacity, closeTo(1.0, 0.01));
    });

    test('expands, then shrinks and fades out right before next lyric', () {
      const durationMs = 6000;
      // Exit phase: 5440ms .. 6000ms (560ms). Peak at ~5440 + 213 = 5653ms.
      final peak = computeInterludeDotsFrame(elapsedMs: 5650, durationMs: durationMs);
      expect(peak.groupScale, greaterThan(1.18));
      expect(peak.groupOpacity, closeTo(1.0, 0.01));

      final shrinking = computeInterludeDotsFrame(elapsedMs: 5880, durationMs: durationMs);
      expect(shrinking.groupScale, lessThan(peak.groupScale));
      expect(shrinking.groupOpacity, lessThan(0.8));
      expect(shrinking.groupOpacity, greaterThan(0.0));

      final ended = computeInterludeDotsFrame(elapsedMs: 6000, durationMs: durationMs);
      expect(ended.groupOpacity, 0.0);
    });
  });
}
