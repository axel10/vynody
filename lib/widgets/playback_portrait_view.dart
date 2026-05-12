import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_file.dart';
import '../player/audio_riverpod.dart';
import '../utils/playback_utils.dart';
import 'waveform_progress_bar.dart';
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
              settingsServiceProvider.select(
                (s) => s.isWaveformProgressBarEnabled,
              ),
            );

            // ---------------- UI Scaling ----------------
            final uiScale = (h / 1150.0).clamp(1.0, 2.5);

            // ---------------- Layout Constants ----------------
            final headerHeight =
                110.0 * uiScale; // Height for album+info in lyrics mode
            final controlsHeight =
                (isWaveformEnabled ? 320.0 : 210.0) * uiScale;

            // ---------------- Album Art ----------------
            // Normal: Large, centered top. Lyrics: Small, top-left.
            final nCoverSize = math.min(
              w * 0.9,
              h - controlsHeight - 150 * uiScale,
            );
            final lCoverSize = math.min(100.0 * uiScale, w * 0.3);

            final coverSize = lerpDouble(nCoverSize, lCoverSize, t)!;
            final coverTop = lerpDouble(h * 0.08, 12.0 * uiScale, t)!;
            final coverLeft = lerpDouble(
              (w - nCoverSize) / 2,
              12.0 * uiScale,
              t,
            )!;

            // ---------------- Track Info ----------------
            // Normal: Below cover. Lyrics: Right of cover.
            final nInfoTop = coverTop + nCoverSize + 20 * uiScale;
            final lInfoTop = 12.0 * uiScale;
            final lInfoLeft = 12.0 * uiScale + lCoverSize + 16.0 * uiScale;

            final infoLeft = lerpDouble(16.0 * uiScale, lInfoLeft, t)!;
            final infoWidth = lerpDouble(
              w - 32.0 * uiScale,
              w - lInfoLeft - 16.0 * uiScale,
              t,
            )!;
            // Normal mode only needs enough height for title + artist lines.
            final infoHeight = 55.0 * uiScale;

            // ---------------- Controls & Lyrics ----------------
            // Controls: Fade out and move down in lyrics mode.
            // Lyrics: Fade in and move up in lyrics mode.
            final controlsOpacity = (1.0 - t * 2).clamp(0.0, 1.0);
            final lyricsOpacity = (t * 2 - 1.0).clamp(0.0, 1.0);
            final bottomReservedHeight =
                lyricsBottomSpacerHeight + lyricsBottomTabBarHeight;
            final contentBandTop = nInfoTop;
            final contentBandBottom = h - bottomReservedHeight;
            final contentBandHeight = math.max(
              0.0,
              contentBandBottom - contentBandTop,
            );
            final controlGap = 0.0 * uiScale;
            final stackedContentHeight =
                infoHeight + controlGap + controlsHeight;
            final centeredContentTop =
                contentBandTop +
                math.max(0.0, (contentBandHeight - stackedContentHeight) / 2);
            final normalInfoTop = centeredContentTop;
            final normalControlsTop =
                centeredContentTop + infoHeight + controlGap;
            final infoTop = lerpDouble(normalInfoTop, lInfoTop, t)!;

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
                    top: lerpDouble(normalControlsTop, h + 24 * uiScale, t)!,
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
                            child: PlaybackPortraitControls(
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

class PlaybackPortraitControls extends ConsumerWidget {
  final bool isLyricsMode;
  final double uiScale;
  final VoidCallback? onShowMoreMenu;
  final VoidCallback? onCyclePlaylistMode;
  final VoidCallback? onShowPlaylistModeSelector;
  final VoidCallback? onShowRandomModeSelector;
  final VoidCallback? onTagCompletionTap;
  final VoidCallback? onTagCompletionLongPress;
  final VoidCallback? onSleepTimerTap;
  final VoidCallback? onEqualizerTap;
  final VoidCallback? onToggleVisualizer;
  final bool showVisualizerToggle;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onVolumeTap;
  final ValueChanged<double>? onVolumeDrag;
  final ValueChanged<double>? onVolumeScroll;
  final double? overrideProgress;
  final Duration? overridePosition;
  final List<double>? overrideWaveform;
  final ValueChanged<double>? onScrubbing;
  final ValueChanged<double>? onSeek;

  const PlaybackPortraitControls({
    super.key,
    required this.isLyricsMode,
    required this.uiScale,
    this.onShowMoreMenu,
    this.onCyclePlaylistMode,
    this.onShowPlaylistModeSelector,
    this.onShowRandomModeSelector,
    this.onTagCompletionTap,
    this.onTagCompletionLongPress,
    this.onSleepTimerTap,
    this.onEqualizerTap,
    this.onToggleVisualizer,
    required this.showVisualizerToggle,
    this.onPrevious,
    this.onPlayPause,
    this.onNext,
    this.onVolumeTap,
    this.onVolumeDrag,
    this.onVolumeScroll,
    this.overrideProgress,
    this.overridePosition,
    this.overrideWaveform,
    this.onScrubbing,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final duration = ref.watch(audioDurationProvider);
    final progress = ref.watch(audioProgressProvider);
    final isWaveformEnabled = ref.watch(
      settingsServiceProvider.select((s) => s.isWaveformProgressBarEnabled),
    );

    final useOverlayStyle = !isLyricsMode && isWaveformEnabled;

    final topRow = PlaybackTopButtonsRow(
      uiScale: uiScale,
      onShowMoreMenu: onShowMoreMenu,
      onCyclePlaylistMode: onCyclePlaylistMode,
      onShowPlaylistModeSelector: onShowPlaylistModeSelector,
      onShowRandomModeSelector: onShowRandomModeSelector,
      onTagCompletionTap: onTagCompletionTap,
      onTagCompletionLongPress: onTagCompletionLongPress,
      onSleepTimerTap: onSleepTimerTap,
      onEqualizerTap: onEqualizerTap,
    );

    final mainRow = PlaybackMainButtonsRow(
      uiScale: uiScale,
      isLandscape: false,
      onToggleVisualizer: onToggleVisualizer,
      showVisualizerToggle: showVisualizerToggle,
      onPrevious: onPrevious,
      onPlayPause: onPlayPause,
      onNext: onNext,
      onVolumeTap: onVolumeTap,
      onVolumeDrag: onVolumeDrag,
      onVolumeScroll: onVolumeScroll,
    );

    if (useOverlayStyle) {
      final waveform = overrideWaveform ?? currentMusic?.waveform ?? const [];
      final displayProgress = overrideProgress ?? progress.clamp(0.0, 1.0);

      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          topRow,
          Stack(
            alignment: Alignment.center,
            children: [
              WaveformProgressBar(
                waveform: waveform,
                progress: displayProgress,
                duration: duration,
                onScrubbing: onScrubbing ?? (_) {},
                onSeek: onSeek ?? (_) {},
                height: 240,
                showTooltip: false,
              ),
              mainRow,
              Positioned(
                left: 20,
                bottom: 10,
                child: Text(
                  formatDuration(
                    overridePosition ?? ref.watch(audioPositionProvider),
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                  ),
                ),
              ),
              Positioned(
                right: 20,
                bottom: 10,
                child: Text(
                  formatDuration(duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Default Column Layout
    final waveform = overrideWaveform ?? currentMusic?.waveform ?? const [];
    final displayProgress = overrideProgress ?? progress.clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        topRow,
        const SizedBox(height: 12),
        if (isWaveformEnabled)
          WaveformProgressBar(
            waveform: waveform,
            progress: displayProgress,
            duration: duration,
            onScrubbing: onScrubbing ?? (_) {},
            onSeek: onSeek ?? (_) {},
            height: 100,
            showTooltip: false,
          )
        else
          buildStandardSlider(
            context: context,
            displayProgress: displayProgress,
            onScrubbing: onScrubbing,
            onSeek: onSeek,
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(
                  overridePosition ?? ref.watch(audioPositionProvider),
                ),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                formatDuration(duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        mainRow,
      ],
    );
  }
}
