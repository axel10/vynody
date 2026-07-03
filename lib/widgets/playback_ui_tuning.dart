import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class PlaybackPageUiTuning {
  PlaybackPageUiTuning._();

  static bool isSmallWindow(
    Size size, {
    required bool isWaveformEnabled,
    bool isSmallWindowMode = false,
  }) {
    if (isSmallWindowMode) {
      return true;
    }
    try {
      final displays = ui.PlatformDispatcher.instance.displays;
      if (displays.isNotEmpty) {
        final screenHeight = displays.first.size.height / displays.first.devicePixelRatio;
        if (size.height >= screenHeight / 2) {
          return false;
        }
      }
    } catch (_) {}

    if (size.width < 240 || size.height < 240) {
      return true;
    }

    final bool isLandscape = size.width > size.height;

    if (isLandscape) {
      final double width = size.width;
      final double height = size.height;

      final lNormalContentWidth = width
          .clamp(0.0, math.max(1600.0, height * 2.5).toDouble())
          .toDouble();
      final lNormalOffsetX = (width - lNormalContentWidth) / 2;
      final lColumnWidth = lNormalContentWidth * 0.5;

      final lNormalControlsWidth = (lNormalContentWidth * 0.24 + 72).clamp(
        PlaybackHeroCardUiTuning.lControlsMinWidth,
        PlaybackHeroCardUiTuning.lControlsMaxWidth,
      );
      final lNormalCoverSide = math
          .min(
            lColumnWidth * PlaybackHeroCardUiTuning.lNormalCoverSideFactor,
            height * PlaybackHeroCardUiTuning.lNormalCoverSideFactor,
          )
          .clamp(
            PlaybackHeroCardUiTuning.lCoverMinSide,
            PlaybackHeroCardUiTuning.lCoverMaxSide,
          );

      final lNormalLeftCenter = lNormalOffsetX + (lNormalContentWidth * 0.25);
      final lNormalCoverLeft = lNormalLeftCenter - (lNormalCoverSide / 2);
      final lNormalCoverRightEdge = lNormalCoverLeft + lNormalCoverSide;
      final lContentRightEdge = lNormalOffsetX + lNormalContentWidth;
      final lRemainingSpace = lContentRightEdge - lNormalCoverRightEdge;

      final lNormalControlsLeft =
          lNormalCoverRightEdge + (lRemainingSpace - lNormalControlsWidth) / 2;

      final gap = lNormalControlsLeft - lNormalCoverRightEdge;
      const safetyMargin = -20.0;

      return gap < safetyMargin;
    } else {
      final double width = size.width;
      final double height = size.height;

      final pNormalScale = (width / PlaybackHeroCardUiTuning.pControlsScaleBase).clamp(0.9, 1.15);
      
      final pNormalControlsBaseIdealHeight =
          (PlaybackHeroCardUiTuning.controlsTopButtonsHeight +
          (isWaveformEnabled
              ? PlaybackHeroCardUiTuning.waveformStandardTimeRowSpacing
              : PlaybackHeroCardUiTuning.controlsRowPortraitGap) +
          (isWaveformEnabled
              ? PlaybackHeroCardUiTuning.waveformOverlayHeight
              : 48.0) +
          (isWaveformEnabled
              ? 0.0
              : (8.0 +
                    PlaybackHeroCardUiTuning.controlsTimeRowHeight +
                    PlaybackHeroCardUiTuning.controlsRowPortraitGap +
                    PlaybackHeroCardUiTuning.controlsMainButtonsHeight))) * 1.0;

      final pNormalControlsHeight =
          (pNormalControlsBaseIdealHeight * pNormalScale)
              .clamp(0.0, height * PlaybackHeroCardUiTuning.pControlsHeightFactor)
              .ceilToDouble();
      final pNormalInfoHeight = PlaybackHeroCardUiTuning.pInfoHeight * pNormalScale;

      final pNormalBottomLimit =
          height - PlaybackHeroCardUiTuning.portraitBottomReservedSpace;

      final pNormalTotalContentHeight = pNormalInfoHeight + pNormalControlsHeight;

      final hypotheticalCoverSide = math
          .min(
            width,
            pNormalBottomLimit -
                pNormalTotalContentHeight -
                PlaybackHeroCardUiTuning.pNormalCoverInfoMinGap,
          );

      const coverThreshold = 240.0;
      return hypotheticalCoverSide < coverThreshold;
    }
  }


  static const Size smallWindowMinSize = Size(360, 360);
  static const Size smallWindowMaxSize = Size(600, 600);
  static const Size smallWindowDefaultSize = Size(360, 360);

  static const double desktopTopSpacer = 32.0;
  static const double statusBannerTop = 12.0;

  static const double lyricsLandscapeLeftPadding = 40.0;
  static const double lyricsPortraitLeftPadding = 16.0;
  static const double normalLandscapeHorizontalPadding = 32.0;
  static const double normalPortraitHorizontalPadding = 8.0;
  static const double lyricsLandscapeRightPadding = 24.0;
  static const double lyricsPortraitRightPadding = 16.0;
  static const double landscapeTopPadding = 32.0;
  static const double landscapeBottomPadding = 32.0;
  static const double portraitTopPadding = 12.0;
  static const double lyricsTopPadding = 8.0;

  static const double lyricsVerticalPadding = 28.0; // 每行歌词之间的间距

  // 歌词自适应字体大小配置参数
  static const double lyricsMinFontScale = 1.0;
  static const double lyricsMaxFontScale = 3.0;
  static const double lyricsBaseScaleSmallScreenWidth = 360.0;
  static const double lyricsBaseScaleLargeScreenWidth = 1000.0;
  static const double lyricsMinBaseScale = 0.9;
  static const double lyricsMaxBaseScale = 1.15;
  static const double lyricsPanelWidthReference = 360.0;
  static const double lyricsPanelWidthGrowFactor = 0.0015;
  static const double lyricsPanelWidthShrinkFactor = 0.0025;

  static EdgeInsets contentPadding({
    required bool isLandscape,
    required bool isLyricsMode,
    required double bottomPadding,
    required bool reserveBottomNavSpace,
    bool isSmallWin = false,
  }) {
    if (isSmallWin) {
      return EdgeInsets.zero;
    }
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
    final bottom = isLandscape
        ? (isLyricsMode ? lyricsTopPadding : landscapeBottomPadding)
        : (reserveBottomNavSpace ? bottomPadding : 0.0);

    return EdgeInsets.fromLTRB(left, top, right, bottom);
  }
}

class PlaybackHeroCardUiTuning {
  PlaybackHeroCardUiTuning._();

  static const Duration transitionDuration = Duration(milliseconds: 400);

  // 竖屏参数 (Portrait parameters)
  static const double pInfoHeight = 80.0;
  static const double pCoverMaxSide = 1000.0;
  static const double pNormalCoverInfoMinGap = 26.0; // 竖屏下标题区距离封面底部的最小距离
  static const double portraitControlsWidthFactor =
      1.0; // 竖屏控件区宽度比例 (0.0 - 1.0)
  static const double pControlsHeightFactor = 0.58; // 竖屏控件区最大高度比例 (相对于屏幕高度)

  // 横屏参数 (Landscape parameters)
  static const double lControlsMinWidth = 440.0;
  static const double lControlsMaxWidth = 1000.0;
  static const double lCoverMinSide = 240.0;
  static const double lCoverMaxSide = 1800.0;
  static const double lNormalCoverSideFactor = 0.72; // 横屏普通模式封面尺寸系数
  static const double lLyricsPreferredCoverSide = 360.0;

  static const double trackTitlePortraitLyricsFont = 20.0;
  static const double trackTitleStandardFont = 24.0;
  static const double trackArtistPortraitLyricsFont = 14.0;
  static const double trackArtistStandardFont = 16.0;

  // static const double controlsRowLandscapeGap = 16.0;
  static const double controlsRowPortraitGap = 8.0;
  static const double topButtonsHorizontalPadding = 0.0; // 顶部按钮行的水平内边距
  static const double topButtonsIconSize = 22.0; // 顶部按钮图标的基础大小
  static const double topButtonsInnerGap = 6.0; // 减小按钮之间的间距

  static const double waveformOverlayHeight = 200.0;
  static const double waveformOverlayTimeSide = 20.0;
  static const double waveformOverlayTimeBottom = 10.0;
  static const double waveformPortraitLyricsHeight = 100.0; // 竖屏下波形进度条的高度
  static const double waveformLandscapeHeight = 74.0; // 横屏下波形进度条的高度
  static const double waveformStandardHorizontalPadding = 16.0;
  static const double waveformStandardTimeRowSpacing = 0.0;
  static const double portraitWaveformOverflowScale =
      1.35; // 竖屏波形进度条溢出缩放 (仅视觉，不影响布局)
  static const double minProgressTimeFontSize = 11.0; // 小窗模式时间文字最小尺寸
  static const double waveformBarWidth = 7.0; // 波形柱子宽度
  static const double waveformBarGap = 2.0; // 波形柱子间隙
  static const double waveformBarWidthLandscape = 4.5; // 横屏下波形柱子宽度
  static const double waveformBarGapLandscape = 2; // 横屏下波形柱子间隙


  // 控件区理想高度计算及缩放基准 (Ideal height calculation and scaling base)
  // 减小此值会让按钮和文字在相同屏幕宽度下显得更大
  static const double pControlsScaleBase = 375.0; // 竖屏缩放基准
  static const double lControlsScaleBase = 480.0; // 横屏缩放基准
  static const double controlsTopButtonsHeight = 44.0; // 减小顶部按钮高度
  static const double controlsMainButtonsHeight = 72.0;
  static const double controlsTimeRowHeight = 24.0;
  static const double controlsTimeGap = 8.0;
  static const double progressBarWidthFactor = 1.0; // 进度条宽度比例（相对于按钮区）
  static const double portraitProgressBarWidthFactor =
      1.0; // 竖屏进度条宽度比例
  static const double landscapeInfoControlsGap = 0.0; // 横屏下标题区到控件区的距离
  static const double landscapeInfoHeightBase = 48.0;
  static const double controlsRowLandscapeGap = 12.0;

  static const double portraitBottomReservedSpace = 0;
}
