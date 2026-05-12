import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_file.dart';
import '../player/audio_riverpod.dart';
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
      builder: (context, t, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final isWaveformEnabled = ref.watch(
              settingsServiceProvider.select((s) => s.isWaveformProgressBarEnabled),
            );

            // ---------------- UI Scaling ----------------
            final uiScale = (h / 1150.0).clamp(1.0, 2.5);

            // ---------------- Layout Constants ----------------
            final headerHeight = 110.0 * uiScale; // Height for album+info in lyrics mode
            final controlsHeight = (isWaveformEnabled ? 320.0 : 280.0) * uiScale;

            // ---------------- Album Art ----------------
            // Normal: Large, centered top. Lyrics: Small, top-left.
            final nCoverSize = math.min(w * 0.9, h - controlsHeight - 150 * uiScale);
            final lCoverSize = math.min(100.0 * uiScale, w * 0.3);
            
            final coverSize = lerpDouble(nCoverSize, lCoverSize, t)!;
            final coverTop = lerpDouble(h * 0.08, 12.0 * uiScale, t)!;
            final coverLeft = lerpDouble((w - nCoverSize) / 2, 12.0 * uiScale, t)!;

            // ---------------- Track Info ----------------
            // Normal: Below cover. Lyrics: Right of cover.
            final nInfoTop = coverTop + nCoverSize + 20 * uiScale;
            final lInfoTop = 12.0 * uiScale;
            final lInfoLeft = 12.0 * uiScale + lCoverSize + 16.0 * uiScale;
            
            final infoTop = lerpDouble(nInfoTop, lInfoTop, t)!;
            final infoLeft = lerpDouble(16.0 * uiScale, lInfoLeft, t)!;
            final infoWidth = lerpDouble(w - 32.0 * uiScale, w - lInfoLeft - 16.0 * uiScale, t)!;
            final infoHeight = lerpDouble(80.0 * uiScale, lCoverSize, t)!;

            // ---------------- Controls & Lyrics ----------------
            // Controls: Fade out and move down in lyrics mode.
            // Lyrics: Fade in and move up in lyrics mode.
            final controlsOpacity = (1.0 - t * 2).clamp(0.0, 1.0);
            final lyricsOpacity = (t * 2 - 1.0).clamp(0.0, 1.0);

            return SizedBox(
              width: w,
              height: h,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Lyrics Panel
                  Positioned(
                    top: lerpDouble(h, headerHeight + 20 * uiScale, t)!,
                    left: 0,
                    right: 0,
                    bottom: 0,
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
                    bottom: lerpDouble(0, -100, t)!,
                    left: 0,
                    right: 0,
                    height: controlsHeight,
                    child: Opacity(
                      opacity: controlsOpacity,
                      child: IgnorePointer(
                        ignoring: t > 0.5,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomCenter,
                          child: SizedBox(
                            width: isWaveformEnabled ? w : 420 * uiScale,
                            child: PlaybackControls(
                              isLandscape: false,
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
                      align: isLyricsMode ? TextAlign.left : TextAlign.center,
                      uiScale: uiScale,
                      lyricsModeT: t,
                      height: h,
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
