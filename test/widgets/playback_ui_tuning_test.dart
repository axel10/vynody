/*
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_flow/widgets/playback_ui_tuning.dart';

void main() {
  group('PlaybackViewportProfile', () {
    test('classifies compact windows as compact', () {
      final profile = PlaybackHeroCardUiTuning.viewportProfile(
        width: 1280,
        height: 800,
        isLandscape: true,
      );

      expect(profile.tier, PlaybackViewportTier.compact);
      expect(profile.isLargeOrAbove, isFalse);
      expect(profile.landscapeScale, greaterThan(0.0));
    });

    test('classifies current large-screen thresholds as large', () {
      final profile = PlaybackHeroCardUiTuning.viewportProfile(
        width: 2560,
        height: 1440,
        isLandscape: true,
      );

      expect(profile.tier, PlaybackViewportTier.large);
      expect(profile.isLargeOrAbove, isTrue);
      expect(profile.isUltraLargeOrAbove, isFalse);
    });

    test('classifies 4k-class windows as ultra-large', () {
      final profile = PlaybackHeroCardUiTuning.viewportProfile(
        width: 3840,
        height: 2160,
        isLandscape: true,
      );

      expect(profile.tier, PlaybackViewportTier.ultraLarge);
      expect(profile.isUltraLargeOrAbove, isTrue);
    });
  });
}
*/

void main() {}

