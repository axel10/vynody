import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_file.dart';
import 'playback_hero_card_shared.dart';

class PlaybackPortraitView extends ConsumerWidget {
  const PlaybackPortraitView({
    super.key,
    required this.isLyricsMode,
    required this.currentMusic,
    required this.isNext,
    required this.onCoverTap,
    required this.onCarouselAnimationComplete,
    required this.onScrubbing,
    required this.onSeek,
    required this.onToggleVisualizer,
    required this.showVisualizerToggle,
    required this.onShowMoreMenu,
    required this.onCyclePlaylistMode,
    required this.onShowPlaylistModeSelector,
    required this.onShowRandomModeSelector,
    required this.onTagCompletionTap,
    required this.onTagCompletionLongPress,
    required this.onSleepTimerTap,
    required this.onEqualizerTap,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onVolumeTap,
    required this.onVolumeDrag,
    required this.onVolumeScroll,
    required this.overrideProgress,
    required this.overridePosition,
    required this.overrideWaveform,
    required this.lyricsBottomSpacerHeight,
    required this.lyricsBottomTabBarHeight,
  });

  final bool isLyricsMode;
  final MusicFile? currentMusic;
  final bool isNext;
  final VoidCallback? onCoverTap;
  final ValueChanged<Uint8List?>? onCarouselAnimationComplete;
  final ValueChanged<double>? onScrubbing;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onToggleVisualizer;
  final bool showVisualizerToggle;
  final VoidCallback? onShowMoreMenu;
  final VoidCallback? onCyclePlaylistMode;
  final VoidCallback? onShowPlaylistModeSelector;
  final VoidCallback? onShowRandomModeSelector;
  final VoidCallback? onTagCompletionTap;
  final VoidCallback? onTagCompletionLongPress;
  final VoidCallback? onSleepTimerTap;
  final VoidCallback? onEqualizerTap;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onVolumeTap;
  final ValueChanged<double>? onVolumeDrag;
  final ValueChanged<double>? onVolumeScroll;
  final double? overrideProgress;
  final Duration? overridePosition;
  final List<double>? overrideWaveform;
  final double lyricsBottomSpacerHeight;
  final double lyricsBottomTabBarHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const animDuration = Duration(milliseconds: 400);
    const animCurve = Curves.fastOutSlowIn;

    return TweenAnimationBuilder<double>(
      duration: animDuration,
      curve: animCurve,
      tween: Tween<double>(end: isLyricsMode ? 1.0 : 0.0),
      builder: (context, tLyrics, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.roundToDouble();
            final height = constraints.maxHeight.roundToDouble();
            // ---------------- UI Scaling ----------------
            // Base height for scaling. (Increase this to make UI smaller on large screens)
            final uiScale = (height / 1150.0).clamp(1.0, 2.5);

            // ---------------- Portrait Normal ----------------
            final pMinInfoH = 80.0 * uiScale;
            final pMinControlsH = 280.0 * uiScale;
            const pBottomGap = 0.0;
            final pMidGap = 4.0 * uiScale;
            final pBottomAreaNeeded =
                pMinInfoH + pMinControlsH + pMidGap + pBottomGap;

            final pNormalInfoTop = (height - pBottomAreaNeeded) < height * 0.62
                ? math.max(height * 0.20, height - pBottomAreaNeeded)
                : height * 0.62;

            final pNormalInfoLeft = 16.0 * uiScale;
            final pNormalInfoWidth = width - 32.0 * uiScale;
            final pNormalInfoHeight = pMinInfoH;

            final pNormalCoverGap = 24.0 * uiScale;
            final pNormalCoverAreaH = math.max(0.0, pNormalInfoTop - pNormalCoverGap);
            final pNormalCoverSide = math.max(0.0, math.min(width * 1, pNormalCoverAreaH * 1));
            final pNormalCoverTop = (pNormalCoverAreaH - pNormalCoverSide) / 2;
            final pNormalCoverLeft = (width - pNormalCoverSide) / 2;

            final pNormalControlsTop =
                pNormalInfoTop + pNormalInfoHeight + pMidGap;
            final pNormalControlsLeft = 0.0;
            final pNormalControlsWidth = width;
            final pNormalControlsHeight = math.max(
              pMinControlsH,
              height - pNormalControlsTop - pBottomGap,
            );
            final pNormalControlsOpacity = 1.0;

            final pNormalLyricsTop = height;
            final pNormalLyricsLeft = 16.0 * uiScale;
            final pNormalLyricsWidth = width - 32.0 * uiScale;
            final pNormalLyricsHeight = height - pNormalInfoTop;
            final pNormalLyricsOpacity = 0.0;

            // ---------------- Portrait Lyrics ----------------
            final pLyricsCoverSide = math.min(120.0 * uiScale, width * 0.32);
            final pLyricsCoverTop = 12.0 * uiScale;
            final pLyricsCoverLeft = 12.0 * uiScale;

            final pLyricsInfoTop = 12.0 * uiScale;
            final pLyricsInfoLeft =
                pLyricsCoverLeft + pLyricsCoverSide + 14.0 * uiScale;
            final pLyricsInfoWidth = width - pLyricsInfoLeft - 16.0 * uiScale;
            final pLyricsInfoHeight = pLyricsCoverSide;

            final pLyricsControlsTop = height;
            final pLyricsControlsLeft = 16.0 * uiScale;
            final pLyricsControlsWidth = width - 32.0 * uiScale;
            final pLyricsControlsHeight = pNormalControlsHeight;
            final pLyricsControlsOpacity = 0.0;

            final pLyricsLyricsTop =
                pLyricsCoverTop + pLyricsCoverSide + 16.0 * uiScale;
            final pLyricsLyricsLeft = 16.0 * uiScale;
            final pLyricsLyricsWidth = width - 32.0 * uiScale;
            final pLyricsLyricsHeight = height - pLyricsLyricsTop;
            final pLyricsLyricsOpacity = 1.0;

            // ---------------- 插值计算 ----------------
            double lerp(double a, double b) => lerpDouble(a, b, tLyrics) ?? a;

            final coverSide = lerp(pNormalCoverSide, pLyricsCoverSide);
            final coverTop = lerp(pNormalCoverTop, pLyricsCoverTop);
            final coverLeft = lerp(pNormalCoverLeft, pLyricsCoverLeft);

            final infoTop = lerp(pNormalInfoTop, pLyricsInfoTop);
            final infoLeft = lerp(pNormalInfoLeft, pLyricsInfoLeft);
            final infoWidth = lerp(pNormalInfoWidth, pLyricsInfoWidth);
            final infoHeight = lerp(pNormalInfoHeight, pLyricsInfoHeight);

            final controlsTop = lerp(pNormalControlsTop, pLyricsControlsTop);
            final controlsLeft = lerp(pNormalControlsLeft, pLyricsControlsLeft);
            final controlsWidth = lerp(
              pNormalControlsWidth,
              pLyricsControlsWidth,
            );
            final controlsHeight = lerp(
              pNormalControlsHeight,
              pLyricsControlsHeight,
            );
            final controlsOpacity = lerp(
              pNormalControlsOpacity,
              pLyricsControlsOpacity,
            );

            final lyricsTop = lerp(pNormalLyricsTop, pLyricsLyricsTop);
            final lyricsLeft = lerp(pNormalLyricsLeft, pLyricsLyricsLeft);
            final lyricsWidth = lerp(pNormalLyricsWidth, pLyricsLyricsWidth);
            final lyricsHeight = lerp(pNormalLyricsHeight, pLyricsLyricsHeight);
            final lyricsOpacity = lerp(
              pNormalLyricsOpacity,
              pLyricsLyricsOpacity,
            );

            final targetInfoAlign = isLyricsMode
                ? TextAlign.left
                : TextAlign.center;

            return SizedBox(
              width: width,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: lyricsTop,
                    left: lyricsLeft,
                    width: lyricsWidth,
                    height: lyricsHeight,
                    child: Opacity(
                      opacity: lyricsOpacity.clamp(0.0, 1.0),
                      child: IgnorePointer(
                        ignoring: lyricsOpacity < 0.5,
                        child: PlaybackLyricsPanel(
                          currentMusic: currentMusic,
                          bottomSpacerHeight: lyricsBottomSpacerHeight,
                          bottomTabBarHeight: lyricsBottomTabBarHeight,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: controlsTop,
                    left: controlsLeft,
                    width: controlsWidth,
                    height: controlsHeight,
                    child: Opacity(
                      opacity: controlsOpacity.clamp(0.0, 1.0),
                      child: IgnorePointer(
                        ignoring: controlsOpacity < 0.5,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: math.max(width, 420 * uiScale),
                            child: PlaybackControls(
                              isLandscape: false,
                              isLyricsMode: isLyricsMode,
                              uiScale: uiScale,
                              onShowMoreMenu: onShowMoreMenu,
                              onCyclePlaylistMode: onCyclePlaylistMode,
                              onShowPlaylistModeSelector:
                                  onShowPlaylistModeSelector,
                              onShowRandomModeSelector:
                                  onShowRandomModeSelector,
                              onTagCompletionTap: onTagCompletionTap,
                              onTagCompletionLongPress:
                                  onTagCompletionLongPress,
                              onSleepTimerTap: onSleepTimerTap,
                              onEqualizerTap: onEqualizerTap,
                              onToggleVisualizer: onToggleVisualizer,
                              showVisualizerToggle: showVisualizerToggle,
                              onPrevious: onPrevious,
                              onPlayPause: onPlayPause,
                              onNext: onNext,
                              onVolumeTap: onVolumeTap,
                              onVolumeDrag: onVolumeDrag,
                              onVolumeScroll: onVolumeScroll,
                              overrideProgress: overrideProgress,
                              overridePosition: overridePosition,
                              overrideWaveform: overrideWaveform,
                              onScrubbing: onScrubbing,
                              onSeek: onSeek,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: coverTop,
                    left: coverLeft,
                    width: coverSide,
                    height: coverSide,
                    child: PlaybackAlbumArt(
                      isNext: isNext,
                      displaySize: coverSide,
                      onCoverTap: onCoverTap,
                      onCarouselAnimationComplete: onCarouselAnimationComplete,
                    ),
                  ),
                  Positioned(
                    top: infoTop,
                    left: infoLeft,
                    width: infoWidth,
                    height: infoHeight,
                    child: PlaybackTrackInfo(
                      currentMusic: currentMusic,
                      align: targetInfoAlign,
                      uiScale: uiScale,
                      lyricsModeT: tLyrics,
                      height: height,
                      isLandscape: false,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
