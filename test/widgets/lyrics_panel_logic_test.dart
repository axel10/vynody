import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_flow/widgets/lyrics_panel.dart';

void main() {
  group('shouldShowGenerateLyricsButton', () {
    test('hides the button when there is no current song', () {
      expect(shouldShowGenerateLyricsButton(hasCurrentSong: false), isFalse);
    });

    test('shows the button after lyrics are cleared for the current song', () {
      expect(shouldShowGenerateLyricsButton(hasCurrentSong: true), isTrue);
    });
  });

  group('calculateLyricTopOffsetFromPanelTop', () {
    test('returns the visual top offset for the selected lyric line', () {
      final top = calculateLyricTopOffsetFromPanelTop(
        lineHeights: const [40.0, 50.0, 60.0],
        lineCenters: const [20.0, 65.0, 125.0],
        lineIndex: 1,
        scrollOffset: 10.0,
        scale: 1.12,
      );

      expect(top, closeTo(27.0, 0.0001));
    });

    test('returns null when the line index is out of range', () {
      final top = calculateLyricTopOffsetFromPanelTop(
        lineHeights: const [40.0],
        lineCenters: const [20.0],
        lineIndex: 2,
        scrollOffset: 0.0,
      );

      expect(top, isNull);
    });
  });
}
