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
}
