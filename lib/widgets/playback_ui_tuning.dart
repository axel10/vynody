import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

enum PlaybackViewportTier { compact, large, ultraLarge }

class PlaybackViewportProfile {
  const PlaybackViewportProfile({
    required this.width,
    required this.height,
    required this.isLandscape,
    required this.landscapeScale,
    required this.tier,
  });

  final double width;
  final double height;
  final bool isLandscape;
  final double landscapeScale;
  final PlaybackViewportTier tier;

  double get shortestSide => math.min(width, height);
  double get longestSide => math.max(width, height);

  bool get isLargeOrAbove => tier.index >= PlaybackViewportTier.large.index;

  bool get isUltraLargeOrAbove =>
      tier.index >= PlaybackViewportTier.ultraLarge.index;
}

class PlaybackPageUiTuning {
  PlaybackPageUiTuning._();

  static const double desktopTopSpacer = 32.0;
  static const double statusBannerTop = 12.0;

  static const double lyricsLandscapeLeftPadding = 40.0;
  static const double lyricsPortraitLeftPadding = 16.0;
  static const double normalLandscapeHorizontalPadding = 32.0;
  static const double normalPortraitHorizontalPadding = 24.0;
  static const double lyricsLandscapeRightPadding = 24.0;
  static const double lyricsPortraitRightPadding = 16.0;
  static const double landscapeTopPadding = 32.0;
  static const double portraitTopPadding = 12.0;
  static const double lyricsTopPadding = 8.0;

  static EdgeInsets contentPadding({
    required bool isLandscape,
    required bool isLyricsMode,
    required double bottomPadding,
    required bool reserveBottomNavSpace,
  }) {
    final left = isLyricsMode
        ? (isLandscape ? lyricsLandscapeLeftPadding : lyricsPortraitLeftPadding)
        : (isLandscape
              ? normalLandscapeHorizontalPadding
              : normalPortraitHorizontalPadding);
    final top = isLyricsMode
        ? lyricsTopPadding
        : (isLandscape ? landscapeTopPadding : portraitTopPadding);
    final right = isLyricsMode
        ? (isLandscape
              ? lyricsLandscapeRightPadding
              : lyricsPortraitRightPadding)
        : (isLandscape
              ? normalLandscapeHorizontalPadding
              : normalPortraitHorizontalPadding);
    final bottom = reserveBottomNavSpace ? bottomPadding : 0.0;

    return EdgeInsets.fromLTRB(left, top, right, bottom);
  }
}

class PlaybackHeroCardUiTuning {
  PlaybackHeroCardUiTuning._();

  static const Duration transitionDuration = Duration(milliseconds: 400);

  static const double landscapeScaleShortestMin = 720.0;
  static const double landscapeScaleShortestMax = 2160.0;
  static const double landscapeScaleMin = 0.82;
  static const double landscapeScaleMax = 1.62;

  static const double landscapeCompactLiftThreshold = 1000.0;
  static const double landscapeCompactLift = 30.0;

  static const double portraitInfoMinHeight = 80.0;
  static const double portraitControlsMinHeight = 220.0;
  static const double portraitBottomGap = 0.0;
  static const double portraitMidGap = 4.0;
  static const double portraitInfoTopFraction = 0.62;
  static const double portraitInfoTopMinFraction = 0.20;
  static const double portraitInfoLeft = 16.0;
  static const double portraitInfoHorizontalInset = 32.0;
  static const double portraitCoverWidthFactor = 0.98;
  static const double portraitCoverHeightFactor = 0.96;
  static const double portraitLyricsCoverMaxSide = 120.0;
  static const double portraitLyricsCoverWidthFactor = 0.32;
  static const double portraitLyricsCoverTop = 12.0;
  static const double portraitLyricsCoverLeft = 12.0;
  static const double portraitLyricsInfoTop = 12.0;
  static const double portraitLyricsInfoGap = 14.0;
  static const double portraitLyricsRightInset = 26.0;
  static const double portraitLyricsBottomInset = 32.0;
  static const double portraitLyricsSpacing = 16.0;

  static const double landscapeNormalCoverWidthFactor = 0.34;
  static const double landscapeNormalCoverHeightFactor = 0.78;
  static const double landscapeNormalCoverMinSide = 360.0;
  static const double landscapeNormalCoverMaxWidthFactor = 0.42;
  static const double landscapeNormalCoverMaxHeightFactor = 0.86;
  static const double landscapeNormalCoverMaxSide = 980.0;
  static const double landscapeNormalCoverLeftMarginFactor = 0.07;
  static const double landscapeNormalCoverColumnFactor = 0.40;
  static const double landscapeNormalInfoHeightCompact = 90.0;
  static const double landscapeNormalInfoHeightLarge = 120.0;
  static const double landscapeNormalInfoHeightMin = 80.0;
  static const double landscapeNormalInfoHeightMax = 130.0;
  static const double landscapeNormalControlsHeightCompact = 200.0;
  static const double landscapeNormalControlsHeightLarge = 280.0;
  static const double landscapeNormalControlsHeightMin = 180.0;
  static const double landscapeNormalControlsHeightMax = 260.0;

  static const double landscapeLyricsColumnWidthFactor = 0.30;
  static const double landscapeLyricsColumnMinWidth = 300.0;
  static const double landscapeLyricsColumnMaxWidth = 620.0;
  static const double landscapeLyricsCoverRatio = 0.75; // 横屏歌词模式下封面大小
  static const double landscapeLyricsCoverTop = 12.0;
  static const double landscapeLyricsInfoTopGap = 24.0;
  static const double landscapeLyricsInfoHeightCompact = 80.0;
  static const double landscapeLyricsInfoHeightLarge = 100.0;
  static const double landscapeLyricsInfoHeightMin = 76.0;
  static const double landscapeLyricsInfoHeightMax = 110.0;
  static const double landscapeLyricsControlsTopGap = 16.0;

  static const double controlsLandscapeWidthFactor = 0.38;
  static const double controlsLandscapeWidthMin = 420.0;
  static const double controlsLandscapeWidthMax = 500.0;
  static const double controlsLandscapeWidthMaxUltraLarge = 700.0;
  static const double controlsPortraitWidthMin = 380.0;
  static const double controlsLandscapeLargeHeightThreshold = 1000.0;
  static const double controlsLandscapeLargeWidthThreshold = 2400.0;
  static const double controlsLandscapeLargeScaleThreshold = 0.95;
  static const double controlsLandscapeScaleMultiplier =
      0.85; // 新增：单独控制控件区的缩放倍率

  static const double trackTitlePortraitLyricsFont = 18.0;
  static const double trackTitleLandscapeFont = 22.0;
  static const double trackTitleLandscapeLargeFont = 30.0;
  static const double trackArtistPortraitLyricsFont = 13.0;
  static const double trackArtistLandscapeFont = 15.0;
  static const double trackArtistLandscapeLargeFont = 18.0;

  static const double controlsRowLandscapeGap = 16.0;
  static const double controlsRowPortraitGap = 12.0;
  static const double topButtonsLandscapeLargeGap = 30.0;
  static const double topButtonsLandscapeGap = 22.0;
  static const double topButtonsLandscapeSpacer = 16.0;
  static const double topButtonsPortraitSpacer = 12.0;
  static const double waveformOverlayHeight = 240.0;
  static const double waveformOverlayTopPadding = 20.0;
  static const double waveformOverlayTimeSide = 20.0;
  static const double waveformOverlayTimeBottom = 10.0;
  static const double waveformStandardHeight = 100.0;
  static const double waveformStandardHorizontalPadding = 16.0;
  static const double waveformStandardTimeRowHorizontalPadding = 20.0;
  static const double waveformStandardTimeRowSpacing = 8.0;

  static PlaybackViewportProfile viewportProfile({
    required double width,
    required double height,
    required bool isLandscape,
  }) {
    final landscapeScale = isLandscape
        ? landscapeScaleForSize(width, height)
        : 1.0;
    final tier = _classifyViewport(
      width: width,
      height: height,
      landscapeScale: landscapeScale,
    );

    return PlaybackViewportProfile(
      width: width,
      height: height,
      isLandscape: isLandscape,
      landscapeScale: landscapeScale,
      tier: tier,
    );
  }

  static double landscapeScaleForSize(double width, double height) {
    final shortestSide = math.min(width, height);
    final t =
        ((shortestSide - landscapeScaleShortestMin) /
                (landscapeScaleShortestMax - landscapeScaleShortestMin))
            .clamp(0.0, 1.0);
    return lerpDouble(landscapeScaleMin, landscapeScaleMax, t) ?? 1.0;
  }

  static PlaybackViewportTier _classifyViewport({
    required double width,
    required double height,
    required double landscapeScale,
  }) {
    // 这些阈值集中在一个地方，后面要加“超大屏 / 超超大屏”时，只需要改这里。
    if (width >= 3840 || height >= 2160 || landscapeScale >= 1.50) {
      return PlaybackViewportTier.ultraLarge;
    }
    if (width >= controlsLandscapeLargeWidthThreshold ||
        height >= controlsLandscapeLargeHeightThreshold ||
        landscapeScale >= controlsLandscapeLargeScaleThreshold) {
      return PlaybackViewportTier.large;
    }
    return PlaybackViewportTier.compact;
  }
}
