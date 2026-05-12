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
      builder: (context, t, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final uiScale = (h / 1300.0).clamp(1.0, 2.5);

            // ---------------- Layout Configuration ----------------
            // Column width in lyrics mode
            final colWidth = (w * 0.35).clamp(320.0 * uiScale, 600.0 * uiScale);

            // ---------------- Album Art ----------------
            // Normal: Left half, large. Lyrics: Left column, smaller.
            final nCoverSize = math.min(w * 0.42, h * 0.8).clamp(0.0, 900.0 * uiScale);
            final lCoverSize = math.min(colWidth * 0.85, h * 0.4).clamp(0.0, 480.0 * uiScale);
            
            final coverSize = lerpDouble(nCoverSize, lCoverSize, t)!;
            final coverTop = lerpDouble((h - nCoverSize) / 2 - (h > 1000 ? 0 : 30), 12.0 * uiScale, t)!;
            final coverLeft = lerpDouble(w * 0.05 + (w * 0.45 - nCoverSize) / 2, (colWidth - lCoverSize) / 2, t)!;

            // ---------------- Track Info ----------------
            // Normal: Right half, top. Lyrics: Left column, below cover.
            final nInfoHeight = (h > 1000 ? 110.0 : 90.0) * uiScale;
            final lInfoHeight = (h > 1000 ? 100.0 : 80.0) * uiScale;
            
            final nInfoTop = h * 0.5 - (nInfoHeight + 240 * uiScale) / 2 - (h > 1000 ? 0 : 30);
            final lInfoTop = coverTop + lCoverSize + 24.0 * uiScale;
            
            final infoTop = lerpDouble(nInfoTop, lInfoTop, t)!;
            final infoLeft = lerpDouble(w * 0.5, 16.0 * uiScale, t)!;
            final infoWidth = lerpDouble(w * 0.45, colWidth - 32.0 * uiScale, t)!;
            final infoHeight = lerpDouble(nInfoHeight, lInfoHeight, t)!;

            // ---------------- Controls ----------------
            // Normal: Right half, below info. Lyrics: Left column, bottom.
            final nControlsTop = nInfoTop + nInfoHeight;
            final lControlsTop = lInfoTop + lInfoHeight + 16.0 * uiScale;
            
            final controlsTop = lerpDouble(nControlsTop, lControlsTop, t)!;
            final controlsLeft = lerpDouble(w * 0.5, 16.0 * uiScale, t)!;
            final controlsWidth = lerpDouble(w * 0.45, colWidth - 32.0 * uiScale, t)!;
            final controlsHeight = lerpDouble(240 * uiScale, h - lControlsTop - 32.0 * uiScale, t)!;

            // ---------------- Lyrics Panel ----------------
            // Normal: Off-screen right. Lyrics: Right column.
            final lyricsLeft = lerpDouble(w, colWidth + 16.0 * uiScale, t)!;
            final lyricsWidth = w - lyricsLeft - 32.0 * uiScale;
            final lyricsOpacity = t.clamp(0.0, 1.0);

            return SizedBox(
              width: w,
              height: h,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Lyrics Panel
                  Positioned(
                    top: 16.0 * uiScale,
                    left: lyricsLeft,
                    width: lyricsWidth,
                    height: h - 32.0 * uiScale,
                    child: Opacity(
                      opacity: lyricsOpacity,
                      child: IgnorePointer(
                        ignoring: t < 0.5,
                        child: PlaybackLyricsPanel(
                          currentMusic: currentMusic,
                          bottomSpacerHeight: lyricsBottomSpacerHeight,
                          bottomTabBarHeight: lyricsBottomTabBarHeight,
                        ),
                      ),
                    ),
                  ),

                  // Controls
                  Positioned(
                    top: controlsTop,
                    left: controlsLeft,
                    width: controlsWidth,
                    height: controlsHeight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: (w > 2000 ? 720.0 : (w > 1200 ? 620.0 : 540.0)) * uiScale,
                        child: PlaybackControls(
                          isLandscape: true,
                          isLyricsMode: isLyricsMode,
                          uiScale: uiScale,
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

                  // Album Art
                  Positioned(
                    top: coverTop,
                    left: coverLeft,
                    width: coverSize,
                    height: coverSize,
                    child: PlaybackAlbumArt(
                      isNext: isNext,
                      displaySize: coverSize,
                      onCoverTap: onCoverTap,
                      onCarouselAnimationComplete: onCarouselAnimationComplete,
                    ),
                  ),

                  // Track Info
                  Positioned(
                    top: infoTop,
                    left: infoLeft,
                    width: infoWidth,
                    height: infoHeight,
                    child: PlaybackTrackInfo(
                      currentMusic: currentMusic,
                      align: TextAlign.center,
                      uiScale: uiScale,
                      lyricsModeT: t,
                      height: h,
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
