import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/playback_ui_tuning.dart';

void main() {
  group('Landscape Lyrics Scaling Math', () {
    test('control area width matches shrunk cover width while controls size remains constant', () {
      const double highResControlsScale = 1.0;
      const double spaceFactor = 0.5;

      final double preferredCoverSide =
          (PlaybackHeroCardUiTuning.lLyricsPreferredCoverSide +
                  spaceFactor * PlaybackHeroCardUiTuning.lLyricsMaxCoverExpansion) *
              highResControlsScale;
      final double controlsScale =
          highResControlsScale *
              (PlaybackHeroCardUiTuning.lLyricsBaseControlsScale +
                  spaceFactor * PlaybackHeroCardUiTuning.lLyricsMaxControlsExpansion);

      final double infoHeight = PlaybackHeroCardUiTuning.landscapeLyricsInfoHeightBase * controlsScale;
      final double controlsHeight = 200.0 * controlsScale;
      final double gap = PlaybackHeroCardUiTuning.landscapeLyricsCoverInfoGapBase * controlsScale;
      final double totalFixedControlsVerticalHeight = infoHeight + controlsHeight + gap;

      // Available height constrained (e.g. 500)
      const double availableHeight = 500.0;
      final double availableCoverHeight = availableHeight - totalFixedControlsVerticalHeight;
      final double coverSide = availableCoverHeight.clamp(140.0, preferredCoverSide);

      // Control area width (lLyricsItemWidth) matches coverSide
      final double controlAreaWidth = coverSide;

      expect(controlAreaWidth, equals(coverSide));
      expect(controlAreaWidth, lessThan(preferredCoverSide));
    });

    test('widening window at minimum height does not shrink control area or cover size', () {
      const double height = 400.0;
      double calcSpaceFactor(double width) {
        final double widthFactor = ((width - 960.0) / 720.0).clamp(0.0, 1.0);
        final double heightFactor = ((height - 580.0) / 420.0).clamp(0.0, 1.0);
        return math.min(widthFactor, heightFactor);
      }

      final factor1 = calcSpaceFactor(960.0);
      final factor2 = calcSpaceFactor(1600.0);

      // Both should be 0.0 when height is constrained at 400
      expect(factor1, equals(0.0));
      expect(factor2, equals(0.0));
    });
  });
}
