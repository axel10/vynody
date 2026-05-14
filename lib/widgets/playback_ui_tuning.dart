import 'package:flutter/material.dart';

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

  // 竖屏参数 (Portrait parameters)
  static const double pControlsMinHeight = 180.0;
  static const double pControlsMaxHeight = 400.0;
  static const double pInfoHeight = 80.0;
  static const double pCoverMaxSide = 1000.0;

  // 横屏参数 (Landscape parameters)
  static const double lControlsMinWidth = 360.0;
  static const double lControlsMaxWidth = 1000.0;
  static const double lCoverMinSide = 240.0;
  static const double lCoverMaxSide = 1800.0;

  static const double trackTitlePortraitLyricsFont = 18.0;
  static const double trackTitleStandardFont = 22.0;
  static const double trackTitleLargeFont = 28.0;
  static const double trackArtistPortraitLyricsFont = 13.0;
  static const double trackArtistStandardFont = 15.0;
  static const double trackArtistLargeFont = 18.0;

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

  // 控件区理想高度计算及缩放基准 (Ideal height calculation and scaling base)
  static const double controlsScaleBase = 540.0;
  static const double controlsTopButtonsHeight = 48.0;
  static const double controlsMainButtonsHeight = 72.0;
  static const double controlsTimeRowHeight = 24.0;
  static const double controlsTimeGap = 8.0;
}
