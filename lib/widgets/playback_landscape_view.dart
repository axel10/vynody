import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_file.dart';
import 'playback_hero_card_shared.dart';

class PlaybackLandscapeView extends ConsumerWidget {
  const PlaybackLandscapeView({
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

            // ---------------- Landscape Normal ----------------
            final landscapeNormalLift = height > 1000 ? 0.0 : 30.0;
            const landscapeLyricsLift = 0.0;

            final lNormalCoverSide = math.min(width * 0.42, height * 0.85).clamp(0.0, 900.0);
            final lNormalCoverTop = (height - lNormalCoverSide) / 2 - landscapeNormalLift;
            final lNormalCoverLeft = width * 0.05 + (width * 0.45 - lNormalCoverSide) / 2;

            final lNormalInfoHeight = height > 1000 ? 120.0 : 90.0;
            final lNormalControlsHeight = height > 1000 ? 280.0 : 200.0;

            final lNormalInfoTop = height * 0.5 - (lNormalInfoHeight + lNormalControlsHeight) / 2 - landscapeNormalLift;
            final lNormalInfoLeft = width * 0.5;
            final lNormalInfoWidth = width * 0.45;

            final lNormalControlsTop = lNormalInfoTop + lNormalInfoHeight;
            final lNormalControlsLeft = width * 0.5;
            final lNormalControlsWidth = width * 0.45;
            final lNormalControlsOpacity = 1.0;

            final lNormalLyricsTop = 16.0;
            final lNormalLyricsLeft = width;
            final lNormalLyricsWidth = width * 0.45;
            final lNormalLyricsHeight = height - 32.0;
            final lNormalLyricsOpacity = 0.0;

            // ---------------- Landscape Lyrics ----------------
            final lColWidth = (width * 0.35).clamp(320.0, 600.0);

            final lLyricsCoverSide = math.min(lColWidth * 0.85, height * 0.45).clamp(0.0, 480.0);
            final lLyricsCoverTop = 12.0 - landscapeLyricsLift;
            final lLyricsCoverLeft = (lColWidth - lLyricsCoverSide) / 2;

            final lLyricsInfoTop = lLyricsCoverTop + lLyricsCoverSide + 24.0;
            final lLyricsInfoLeft = 16.0;
            final lLyricsInfoWidth = lColWidth - 32.0;
            final lLyricsInfoHeight = height > 1000 ? 100.0 : 80.0;

            final lLyricsControlsTop = lLyricsInfoTop + lLyricsInfoHeight + 16.0;
            final lLyricsControlsLeft = 16.0;
            final lLyricsControlsWidth = lColWidth - 32.0;
            final lLyricsControlsHeight = height - lLyricsControlsTop - 32.0;
            final lLyricsControlsOpacity = 1.0;

            final lLyricsLyricsTop = 16.0;
            final lLyricsLyricsLeft = lColWidth + 16.0;
            final lLyricsLyricsWidth = width - lLyricsLyricsLeft - 32.0;
            final lLyricsLyricsHeight = height - 32.0;
            final lLyricsLyricsOpacity = 1.0;

            // ---------------- 插值计算 ----------------
            double lerp(double a, double b) => lerpDouble(a, b, tLyrics) ?? a;

            final coverSide = lerp(lNormalCoverSide, lLyricsCoverSide);
            final coverTop = lerp(lNormalCoverTop, lLyricsCoverTop);
            final coverLeft = lerp(lNormalCoverLeft, lLyricsCoverLeft);

            final infoTop = lerp(lNormalInfoTop, lLyricsInfoTop);
            final infoLeft = lerp(lNormalInfoLeft, lLyricsInfoLeft);
            final infoWidth = lerp(lNormalInfoWidth, lLyricsInfoWidth);
            final infoHeight = lerp(lNormalInfoHeight, lLyricsInfoHeight);

            final controlsTop = lerp(lNormalControlsTop, lLyricsControlsTop);
            final controlsLeft = lerp(lNormalControlsLeft, lLyricsControlsLeft);
            final controlsWidth = lerp(lNormalControlsWidth, lLyricsControlsWidth);
            final controlsHeight = lerp(lNormalControlsHeight, lLyricsControlsHeight);
            final controlsOpacity = lerp(lNormalControlsOpacity, lLyricsControlsOpacity);

            final lyricsTop = lerp(lNormalLyricsTop, lLyricsLyricsTop);
            final lyricsLeft = lerp(lNormalLyricsLeft, lLyricsLyricsLeft);
            final lyricsWidth = lerp(lNormalLyricsWidth, lLyricsLyricsWidth);
            final lyricsHeight = lerp(lNormalLyricsHeight, lLyricsLyricsHeight);
            final lyricsOpacity = lerp(lNormalLyricsOpacity, lLyricsLyricsOpacity);

            const targetInfoAlign = TextAlign.center;

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
                            width: (width > 2000 ? 580.0 : (width > 1200 ? 500.0 : 450.0)),
                            child: PlaybackControls(
                              isLandscape: true,
                              isLyricsMode: isLyricsMode,
                              isLarge: height > 1000 || width > 2000,
                              onShowMoreMenu: onShowMoreMenu,
                              onCyclePlaylistMode: onCyclePlaylistMode,
                              onShowPlaylistModeSelector: onShowPlaylistModeSelector,
                              onShowRandomModeSelector: onShowRandomModeSelector,
                              onTagCompletionTap: onTagCompletionTap,
                              onTagCompletionLongPress: onTagCompletionLongPress,
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
                      lyricsModeT: tLyrics,
                      height: height,
                      isLandscape: true,
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
