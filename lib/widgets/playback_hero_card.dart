import 'dart:ui' show lerpDouble, ImageFilter;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../player/audio_riverpod.dart';
import '../models/music_file.dart';
import '../utils/playback_utils.dart';
import '../utils/song_context_menu_utils.dart';
import '../widgets/cover_carousel.dart';
import '../widgets/lyrics_panel.dart';
import '../widgets/mini_player_widgets.dart';
import '../widgets/waveform_progress_bar.dart';

const String playbackHeroTag = 'player_capsule';

enum _TrackInfoMenuTarget { title, artistAlbum }

class _PlaybackPaneLayout {
  const _PlaybackPaneLayout({
    required this.top,
    required this.left,
    required this.width,
    required this.height,
    required this.opacity,
  });

  final double top;
  final double left;
  final double width;
  final double height;
  final double opacity;
}

class _PlaybackCardLayout {
  const _PlaybackCardLayout({
    required this.cover,
    required this.info,
    required this.controls,
    required this.lyrics,
    required this.trackInfoAlign,
    required this.controlsScale,
  });

  final _PlaybackPaneLayout cover;
  final _PlaybackPaneLayout info;
  final _PlaybackPaneLayout controls;
  final _PlaybackPaneLayout lyrics;
  final TextAlign trackInfoAlign;
  final double controlsScale;
}

class PlaybackHeroCard extends ConsumerWidget {
  const PlaybackHeroCard({
    super.key,
    required this.isMini,
    this.isLyricsMode = false,
    this.isLandscape = false,
    this.isNext = true,
    this.showVisualizerToggle = true,
    this.showMiniVolumeSlider = false,
    this.onShowMoreMenu,
    this.onMiniTap,
    this.onCyclePlaylistMode,
    this.onShowPlaylistModeSelector,
    this.onShowRandomModeSelector,
    this.onScrubbing,
    this.onSeek,
    this.onToggleVisualizer,
    this.onTagCompletionTap,
    this.onTagCompletionLongPress,
    this.onSleepTimerTap,
    this.onEqualizerTap,
    this.onPrevious,
    this.onPlayPause,
    this.onNext,
    this.onVolumeTap,
    this.onVolumeChanged,
    this.onMiniMouseExit,
    this.onVolumeDrag,
    this.onVolumeScroll,
    this.onCoverTap,
    this.onCarouselAnimationComplete,
    this.overrideProgress,
    this.overridePosition,
    this.overrideWaveform,
    this.lyricsBottomSpacerHeight = 0.0,
    this.lyricsBottomTabBarHeight = 0.0,
  });

  final bool isMini;
  final bool isLyricsMode;
  final bool isLandscape;
  final bool isNext;
  final bool showMiniVolumeSlider;
  final List<double>? overrideWaveform;
  final double? overrideProgress;
  final Duration? overridePosition;
  final bool showVisualizerToggle;
  final VoidCallback? onShowMoreMenu;
  final VoidCallback? onMiniTap;
  final VoidCallback? onCyclePlaylistMode;
  final VoidCallback? onShowPlaylistModeSelector;
  final VoidCallback? onShowRandomModeSelector;
  final ValueChanged<double>? onScrubbing;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onToggleVisualizer;
  final VoidCallback? onTagCompletionTap;
  final VoidCallback? onTagCompletionLongPress;
  final VoidCallback? onSleepTimerTap;
  final VoidCallback? onEqualizerTap;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onVolumeTap;
  final ValueChanged<double>? onVolumeChanged;
  final VoidCallback? onMiniMouseExit;
  final ValueChanged<double>? onVolumeDrag;
  final ValueChanged<double>? onVolumeScroll;
  final VoidCallback? onCoverTap;
  final ValueChanged<Uint8List?>? onCarouselAnimationComplete;
  final double lyricsBottomSpacerHeight;
  final double lyricsBottomTabBarHeight;

  double _lerp2D(
    BuildContext context,
    double pN,
    double pL,
    double lN,
    double lL,
    double tLyrics,
    double tLand,
  ) {
    final p = lerpDouble(pN, pL, tLyrics) ?? pN;
    final l = lerpDouble(lN, lL, tLyrics) ?? lN;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final raw = lerpDouble(p, l, tLand) ?? p;
    return (raw * dpr).round() / dpr;
  }

  double _responsiveLandscapeScale(double width, double height) {
    final shortestSide = math.min(width, height);
    final t = ((shortestSide - 720.0) / (2160.0 - 720.0)).clamp(0.0, 1.0);
    return lerpDouble(0.82, 1.62, t) ?? 1.0;
  }

  double _clampDouble(double value, double min, double max) {
    final lower = math.min(min, max);
    final upper = math.max(min, max);
    return value.clamp(lower, upper).toDouble();
  }

  Future<void> _showTrackInfoContextMenu(
    BuildContext context,
    Offset globalPosition, {
    required _TrackInfoMenuTarget target,
    required MusicFile? currentMusic,
  }) async {
    await showSongContextMenu(
      context,
      globalPosition,
      song: currentMusic,
      mode: target == _TrackInfoMenuTarget.title
          ? SongContextMenuMode.title
          : SongContextMenuMode.artistAlbum,
    );
  }

  String _formatSleepTimer(Duration duration) {
    final safe = duration < Duration.zero ? Duration.zero : duration;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);
    return [
      hours.toString().padLeft(2, '0'),
      minutes.toString().padLeft(2, '0'),
      seconds.toString().padLeft(2, '0'),
    ].join(':');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Hero(
      tag: playbackHeroTag,
      child: Material(
        type: MaterialType.transparency,
        child: isMini
            ? _buildMiniCard(context, ref)
            : _buildFullCard(context, ref),
      ),
    );
  }

  Widget _buildMiniCard(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final isPlaying = ref.watch(audioIsPlayingProvider);
    final progress = ref.watch(audioProgressProvider);
    return MouseRegion(
      onExit: (_) => onMiniMouseExit?.call(),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black.withValues(alpha: 0.82)
              : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color:
                  (Theme.of(context).brightness == Brightness.dark
                          ? Colors.black
                          : Colors.grey[400]!)
                      .withValues(alpha: 0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.6,
                  child: MiniSpectrumBackground(
                    audio: ref.read(audioServiceProvider),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onMiniTap,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const MiniArtwork(),
                            const SizedBox(width: 14),
                            Flexible(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 160,
                                ),
                                child: _MiniPlayerProgressInfo(
                                  currentMusic: currentMusic,
                                  progress: progress,
                                  onScrubbing: onScrubbing,
                                  onSeek: onSeek,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MiniControlButton(
                          icon: Icons.skip_previous_rounded,
                          onPressed: onPrevious,
                          tooltip: AppLocalizations.of(context)!.previous,
                        ),
                        const SizedBox(width: 8),
                        MiniControlButton(
                          icon: isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          onPressed: onPlayPause,
                          tooltip: isPlaying
                              ? AppLocalizations.of(context)!.pause
                              : AppLocalizations.of(context)!.play,
                        ),
                        const SizedBox(width: 8),
                        MiniControlButton(
                          icon: Icons.skip_next_rounded,
                          onPressed: onNext,
                          tooltip: AppLocalizations.of(context)!.next,
                        ),
                        if (isLandscape) const SizedBox(width: 10),
                        if (isLandscape)
                          MiniInlineVolumeControl(
                            volume: ref.watch(audioVolumeProvider),
                            showSlider: showMiniVolumeSlider,
                            onTap: onVolumeTap,
                            onChanged: onVolumeChanged,
                            tooltip: AppLocalizations.of(context)!.volume,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullCard(BuildContext context, WidgetRef ref) {
    const animDuration = Duration(milliseconds: 400);
    const animCurve = Curves.fastOutSlowIn;
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    // 核心动画容器：使用 TweenAnimationBuilder 对 2D 平面上的多个布局变量（尺寸、位置、不透明度）进行线性插值处理。
    // 这使得点击封面切换 `isLyricsMode` 后，UI 元素能平滑移动/缩放，例如：
    // - 封面从大变小并挪到角落
    // - 歌词面板从下而上“浮现”
    // - 播放控制按键在手机竖屏时向下滑出屏幕
    return TweenAnimationBuilder<double>(
      duration: animDuration,
      curve: animCurve,
      tween: Tween<double>(end: isLandscape ? 1.0 : 0.0),
      builder: (context, tLand, _) {
        return TweenAnimationBuilder<double>(
          duration: animDuration,
          curve: animCurve,
          tween: Tween<double>(end: isLyricsMode ? 1.0 : 0.0),
          builder: (context, tLyrics, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.roundToDouble();
                final height = constraints.maxHeight.roundToDouble();
                final layout = _buildPlaybackCardLayout(
                  context,
                  width: width,
                  height: height,
                  tLyrics: tLyrics,
                  tLand: tLand,
                );

                return SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: layout.lyrics.top,
                        left: layout.lyrics.left,
                        width: layout.lyrics.width,
                        height: layout.lyrics.height,
                        child: Opacity(
                          opacity: layout.lyrics.opacity.clamp(0.0, 1.0),
                          child: IgnorePointer(
                            ignoring: layout.lyrics.opacity < 0.5,
                            child: _buildLyricsPanelWidget(context, ref),
                          ),
                        ),
                      ),
                      Positioned(
                        // 控件区
                        top: layout.controls.top,
                        left: layout.controls.left,
                        width: layout.controls.width,
                        height: layout.controls.height,
                        child: Opacity(
                          opacity: layout.controls.opacity.clamp(0.0, 1.0),
                          child: IgnorePointer(
                            ignoring: layout.controls.opacity < 0.5,
                            child: FittedBox(
                              // 控件区
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: isLandscape
                                    ? _clampDouble(
                                        width * 0.38 * layout.controlsScale,
                                        420.0,
                                        760.0,
                                      )
                                    : math.max(layout.controls.width, 380.0),
                                child: _buildPlaybackControlsWidget(
                                  context,
                                  ref,
                                  isLarge:
                                      isLandscape &&
                                      (height > 1000 ||
                                          width > 2400 ||
                                          layout.controlsScale > 0.95),
                                  controlsScale: isLandscape
                                      ? layout.controlsScale
                                      : 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: layout.cover.top,
                        left: layout.cover.left,
                        width: layout.cover.width,
                        height: layout.cover.height,
                        child: _buildAlbumArtCore(
                          context,
                          ref,
                          layout.cover.width,
                        ),
                      ),
                      Positioned(
                        top: layout.info.top,
                        left: layout.info.left,
                        width: layout.info.width,
                        height: layout.info.height,
                        child: _buildTrackInfo(
                          context,
                          currentMusic,
                          layout.trackInfoAlign,
                          tLyrics,
                          height,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  _PlaybackCardLayout _buildPlaybackCardLayout(
    BuildContext context, {
    required double width,
    required double height,
    required double tLyrics,
    required double tLand,
  }) {
    final landscapeScale = isLandscape
        ? _responsiveLandscapeScale(width, height)
        : 1.0;

    // ---------------- Portrait Normal ----------------
    const pMinInfoH = 80.0;
    const pMinControlsH = 220.0;
    const pBottomGap = 0.0;
    const pMidGap = 4.0;
    final pBottomAreaNeeded = pMinInfoH + pMinControlsH + pMidGap + pBottomGap;

    final pNormalInfoTop = (height - pBottomAreaNeeded) < height * 0.62
        ? math.max(height * 0.20, height - pBottomAreaNeeded)
        : height * 0.62;

    final pNormalInfoLeft = 16.0;
    final pNormalInfoWidth = width - 32.0;
    final pNormalInfoHeight = pMinInfoH;

    final pNormalControlsTop = pNormalInfoTop + pNormalInfoHeight + pMidGap;
    final pNormalControlsLeft = 16.0;
    final pNormalControlsWidth = width - 32.0;
    final pNormalControlsHeight = math.max(
      pMinControlsH,
      height - pNormalControlsTop - pBottomGap,
    );
    final pNormalControlsOpacity = 1.0;

    final pNormalCoverAreaH = pNormalInfoTop;
    final pNormalCoverSide = math.min(width * 0.98, pNormalCoverAreaH * 0.96);
    final pNormalCoverTop = (pNormalCoverAreaH - pNormalCoverSide) / 2;
    final pNormalCoverLeft = (width - pNormalCoverSide) / 2;

    final pNormalLyricsTop = height;
    final pNormalLyricsLeft = 16.0;
    final pNormalLyricsWidth = width - 32.0;
    final pNormalLyricsHeight = height - pNormalInfoTop;
    final pNormalLyricsOpacity = 0.0;

    // ---------------- Portrait Lyrics ----------------
    final pLyricsCoverSide = math.min(120.0, width * 0.32);
    const pLyricsCoverTop = 12.0;
    const pLyricsCoverLeft = 12.0;

    const pLyricsInfoTop = 12.0;
    final pLyricsInfoLeft = pLyricsCoverLeft + pLyricsCoverSide + 14.0;
    final pLyricsInfoWidth = width - pLyricsInfoLeft - 16.0;
    final pLyricsInfoHeight = pLyricsCoverSide;

    final pLyricsControlsTop = height;
    final pLyricsControlsLeft = 16.0;
    final pLyricsControlsWidth = width - 32.0;
    final pLyricsControlsHeight = pNormalControlsHeight;
    final pLyricsControlsOpacity = 0.0;

    final pLyricsLyricsTop = pLyricsCoverTop + pLyricsCoverSide + 16.0;
    final pLyricsLyricsLeft = 16.0;
    final pLyricsLyricsWidth = width - 32.0;
    final pLyricsLyricsHeight = height - pLyricsLyricsTop;
    final pLyricsLyricsOpacity = 1.0;

    // ---------------- Landscape Normal ----------------
    final landscapeNormalLift = height > 1000 ? 0.0 : 30.0;
    const landscapeLyricsLift = 0.0;
    final lNormalCoverSideBase = math.min(width * 0.34, height * 0.78);
    final lNormalCoverSide = _clampDouble(
      lNormalCoverSideBase * landscapeScale,
      360.0,
      math.min(math.min(width * 0.42, height * 0.86), 980.0),
    );
    final lNormalCoverTop =
        (height - lNormalCoverSide) / 2 - landscapeNormalLift;
    final lNormalCoverLeft =
        width * 0.05 + (width * 0.40 - lNormalCoverSide) / 2;

    final lNormalInfoHeight = _clampDouble(
      (height > 1000 ? 120.0 : 90.0) * landscapeScale,
      80.0,
      130.0,
    );
    final lNormalControlsHeight = _clampDouble(
      (height > 1000 ? 280.0 : 200.0) * landscapeScale,
      180.0,
      260.0,
    );

    final lNormalInfoTop =
        height * 0.5 -
        (lNormalInfoHeight + lNormalControlsHeight) / 2 -
        landscapeNormalLift;
    final lNormalInfoLeft = width * 0.5;
    final lNormalInfoWidth = width * 0.40;

    final lNormalControlsTop = lNormalInfoTop + lNormalInfoHeight;
    final lNormalControlsLeft = width * 0.5;
    final lNormalControlsWidth = width * 0.40;
    final lNormalControlsOpacity = 1.0;

    final lNormalLyricsTop = 16.0;
    final lNormalLyricsLeft = width;
    final lNormalLyricsWidth = width * 0.40;
    final lNormalLyricsHeight = height - 32.0;
    final lNormalLyricsOpacity = 0.0;

    // ---------------- Landscape Lyrics ----------------
    final lColWidth = _clampDouble(width * 0.30 * landscapeScale, 300.0, 620.0);

    final lLyricsCoverSideBase = lColWidth*0.85;
    final lLyricsCoverSide = lLyricsCoverSideBase;
    final lLyricsCoverTop = 12.0 - landscapeLyricsLift;
    final lLyricsCoverLeft = (lColWidth - lLyricsCoverSide) / 2;

    final lLyricsInfoTop = lLyricsCoverTop + lLyricsCoverSide + 24.0;
    final lLyricsInfoLeft = 16.0;
    final lLyricsInfoWidth = lColWidth - 32.0;
    final lLyricsInfoHeight = _clampDouble(
      (height > 1000 ? 100.0 : 80.0) * landscapeScale,
      76.0,
      110.0,
    );

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

    final cover = _lerpPane(
      context,
      pNormal: _PlaybackPaneLayout(
        top: pNormalCoverTop,
        left: pNormalCoverLeft,
        width: pNormalCoverSide,
        height: pNormalCoverSide,
        opacity: 1.0,
      ),
      pLyrics: _PlaybackPaneLayout(
        top: pLyricsCoverTop,
        left: pLyricsCoverLeft,
        width: pLyricsCoverSide,
        height: pLyricsCoverSide,
        opacity: 1.0,
      ),
      lNormal: _PlaybackPaneLayout(
        top: lNormalCoverTop,
        left: lNormalCoverLeft,
        width: lNormalCoverSide,
        height: lNormalCoverSide,
        opacity: 1.0,
      ),
      lLyrics: _PlaybackPaneLayout(
        top: lLyricsCoverTop,
        left: lLyricsCoverLeft,
        width: lLyricsCoverSide,
        height: lLyricsCoverSide,
        opacity: 1.0,
      ),
      tLyrics: tLyrics,
      tLand: tLand,
    );

    final info = _lerpPane(
      context,
      pNormal: _PlaybackPaneLayout(
        top: pNormalInfoTop,
        left: pNormalInfoLeft,
        width: pNormalInfoWidth,
        height: pNormalInfoHeight,
        opacity: 1.0,
      ),
      pLyrics: _PlaybackPaneLayout(
        top: pLyricsInfoTop,
        left: pLyricsInfoLeft,
        width: pLyricsInfoWidth,
        height: pLyricsInfoHeight,
        opacity: 1.0,
      ),
      lNormal: _PlaybackPaneLayout(
        top: lNormalInfoTop,
        left: lNormalInfoLeft,
        width: lNormalInfoWidth,
        height: lNormalInfoHeight,
        opacity: 1.0,
      ),
      lLyrics: _PlaybackPaneLayout(
        top: lLyricsInfoTop,
        left: lLyricsInfoLeft,
        width: lLyricsInfoWidth,
        height: lLyricsInfoHeight,
        opacity: 1.0,
      ),
      tLyrics: tLyrics,
      tLand: tLand,
    );

    final controls = _lerpPane(
      context,
      pNormal: _PlaybackPaneLayout(
        top: pNormalControlsTop,
        left: pNormalControlsLeft,
        width: pNormalControlsWidth,
        height: pNormalControlsHeight,
        opacity: pNormalControlsOpacity,
      ),
      pLyrics: _PlaybackPaneLayout(
        top: pLyricsControlsTop,
        left: pLyricsControlsLeft,
        width: pLyricsControlsWidth,
        height: pLyricsControlsHeight,
        opacity: pLyricsControlsOpacity,
      ),
      lNormal: _PlaybackPaneLayout(
        top: lNormalControlsTop,
        left: lNormalControlsLeft,
        width: lNormalControlsWidth,
        height: lNormalControlsHeight,
        opacity: lNormalControlsOpacity,
      ),
      lLyrics: _PlaybackPaneLayout(
        top: lLyricsControlsTop,
        left: lLyricsControlsLeft,
        width: lLyricsControlsWidth,
        height: lLyricsControlsHeight,
        opacity: lLyricsControlsOpacity,
      ),
      tLyrics: tLyrics,
      tLand: tLand,
    );

    final lyrics = _lerpPane(
      context,
      pNormal: _PlaybackPaneLayout(
        top: pNormalLyricsTop,
        left: pNormalLyricsLeft,
        width: pNormalLyricsWidth,
        height: pNormalLyricsHeight,
        opacity: pNormalLyricsOpacity,
      ),
      pLyrics: _PlaybackPaneLayout(
        top: pLyricsLyricsTop,
        left: pLyricsLyricsLeft,
        width: pLyricsLyricsWidth,
        height: pLyricsLyricsHeight,
        opacity: pLyricsLyricsOpacity,
      ),
      lNormal: _PlaybackPaneLayout(
        top: lNormalLyricsTop,
        left: lNormalLyricsLeft,
        width: lNormalLyricsWidth,
        height: lNormalLyricsHeight,
        opacity: lNormalLyricsOpacity,
      ),
      lLyrics: _PlaybackPaneLayout(
        top: lLyricsLyricsTop,
        left: lLyricsLyricsLeft,
        width: lLyricsLyricsWidth,
        height: lLyricsLyricsHeight,
        opacity: lLyricsLyricsOpacity,
      ),
      tLyrics: tLyrics,
      tLand: tLand,
    );

    final trackInfoAlign = isLandscape
        ? TextAlign.center
        : (isLyricsMode ? TextAlign.left : TextAlign.center);

    return _PlaybackCardLayout(
      cover: cover,
      info: info,
      controls: controls,
      lyrics: lyrics,
      trackInfoAlign: trackInfoAlign,
      controlsScale: landscapeScale,
    );
  }

  _PlaybackPaneLayout _lerpPane(
    BuildContext context, {
    required _PlaybackPaneLayout pNormal,
    required _PlaybackPaneLayout pLyrics,
    required _PlaybackPaneLayout lNormal,
    required _PlaybackPaneLayout lLyrics,
    required double tLyrics,
    required double tLand,
  }) {
    return _PlaybackPaneLayout(
      top: _lerp2D(
        context,
        pNormal.top,
        pLyrics.top,
        lNormal.top,
        lLyrics.top,
        tLyrics,
        tLand,
      ),
      left: _lerp2D(
        context,
        pNormal.left,
        pLyrics.left,
        lNormal.left,
        lLyrics.left,
        tLyrics,
        tLand,
      ),
      width: _lerp2D(
        context,
        pNormal.width,
        pLyrics.width,
        lNormal.width,
        lLyrics.width,
        tLyrics,
        tLand,
      ),
      height: _lerp2D(
        context,
        pNormal.height,
        pLyrics.height,
        lNormal.height,
        lLyrics.height,
        tLyrics,
        tLand,
      ),
      opacity: _lerp2D(
        context,
        pNormal.opacity,
        pLyrics.opacity,
        lNormal.opacity,
        lLyrics.opacity,
        tLyrics,
        tLand,
      ),
    );
  }

  Widget _buildAlbumArtCore(
    BuildContext context,
    WidgetRef ref,
    double currentSize,
  ) {
    final playlist = ref.watch(audioPlaybackQueueProvider);
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    if (playlist.isEmpty) {
      return Center(
        child: Container(
          width: currentSize * 0.8,
          height: currentSize * 0.8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.black87,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 50,
                spreadRadius: 15,
              ),
            ],
          ),
          child: const Icon(Icons.music_note, size: 80, color: Colors.white54),
        ),
      );
    }

    final cover = ExcludeSemantics(
      child: CoverCarousel(
        playlist: playlist,
        currentIndex: currentIndex,
        audioService: ref.read(audioServiceProvider),
        isNext: isNext,
        displaySize: currentSize,
        onPageChanged: (page) {
          final audio = ref.read(audioServiceProvider);
          if (page >= 0 && page < playlist.length && page != currentIndex) {
            audio.playAtIndex(page);
          }
        },
        onAnimationComplete: onCarouselAnimationComplete,
      ),
    );

    if (onCoverTap == null) return cover;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCoverTap,
      child: cover,
    );
  }

  Widget _buildTrackInfo(
    BuildContext context,
    MusicFile? currentMusic,
    TextAlign align,
    double lyricsModeT,
    double height,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final title = currentMusic?.displayName ?? l10n.notSelected;
    final showArtistAlbum = currentMusic != null;

    final rawAlbum = currentMusic?.album?.trim() ?? '';
    final rawArtist = currentMusic?.artist?.trim() ?? '';

    bool isUnknown(String val) {
      if (val.isEmpty) return true;
      final lower = val.toLowerCase();
      return lower == 'unknown' ||
          lower == 'unknown artist' ||
          lower == 'unknown album';
    }

    final bool hasArtist = !isUnknown(rawArtist);
    final bool hasAlbum = !isUnknown(rawAlbum);
    final transition = lyricsModeT.clamp(0.0, 1.0);
    final titleAlignment = align == TextAlign.left
        ? Alignment.lerp(Alignment.center, Alignment.centerLeft, transition)!
        : Alignment.center;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: Align(
            alignment: titleAlignment,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: (details) {
                _showTrackInfoContextMenu(
                  context,
                  details.globalPosition,
                  target: _TrackInfoMenuTarget.title,
                  currentMusic: currentMusic,
                );
              },
              onLongPressStart: (details) {
                HapticFeedback.mediumImpact();
                _showTrackInfoContextMenu(
                  context,
                  details.globalPosition,
                  target: _TrackInfoMenuTarget.title,
                  currentMusic: currentMusic,
                );
              },
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                curve: Curves.fastOutSlowIn,
                textAlign: TextAlign.start,
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  color: Colors.white,
                  fontSize: lyricsModeT > 0.5 && !isLandscape
                      ? 18
                      : (isLandscape && height > 1000 ? 30 : 22),
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
        if (showArtistAlbum)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SizedBox(
              width: double.infinity,
              child: Align(
                alignment: titleAlignment,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) {
                    _showTrackInfoContextMenu(
                      context,
                      details.globalPosition,
                      target: _TrackInfoMenuTarget.artistAlbum,
                      currentMusic: currentMusic,
                    );
                  },
                  onLongPressStart: (details) {
                    HapticFeedback.mediumImpact();
                    _showTrackInfoContextMenu(
                      context,
                      details.globalPosition,
                      target: _TrackInfoMenuTarget.artistAlbum,
                      currentMusic: currentMusic,
                    );
                  },
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.fastOutSlowIn,
                    textAlign: TextAlign.start,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: Colors.white70,
                      fontSize: lyricsModeT > 0.5 && !isLandscape
                          ? 13
                          : (isLandscape && height > 1000 ? 18 : 15),
                      height: 1.3,
                    ),
                    child: Text(
                      hasArtist && hasAlbum
                          ? '$rawArtist — $rawAlbum'
                          : (hasArtist
                                ? rawArtist
                                : (hasAlbum ? rawAlbum : l10n.unknown)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaybackControlsWidget(
    BuildContext context,
    WidgetRef ref, {
    bool isLarge = false,
    double controlsScale = 1.0,
  }) {
    final playbackMode = ref.watch(audioPlaybackModeProvider);
    final isRandomMode = ref.watch(audioIsRandomModeProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final playlistService = ref.watch(playlistServiceProvider);
    final isFavorite =
        currentMusic != null && playlistService.isFavoriteSong(currentMusic);
    final currentThemeColorsMap = ref.watch(audioCurrentThemeColorsMapProvider);
    final duration = ref.watch(audioDurationProvider);
    final sleepTimerRemaining = ref.watch(audioSleepTimerRemainingProvider);
    final isPlaying = ref.watch(audioIsPlayingProvider);
    final progress = ref.watch(audioProgressProvider);
    final l10n = AppLocalizations.of(context)!;

    final isWaveformEnabled = ref.watch(
      settingsServiceProvider.select((s) => s.isWaveformProgressBarEnabled),
    );

    // 竖屏模式下如果启用波形进度条，则使用叠层布局 (Overlay layout in portrait if waveform is enabled)
    final useOverlayStyle = !isLandscape && !isLyricsMode && isWaveformEnabled;

    // 提取公共组件 (Extract common components)
    final topButtonsRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.more_horiz, color: Colors.white70),
          onPressed: onShowMoreMenu,
          tooltip: l10n.more,
        ),
        IconButton(
          icon: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: (isLarge ? 36 : 28) * controlsScale,
            color: isFavorite ? Colors.redAccent : Colors.white70,
          ),
          onPressed: currentMusic == null
              ? null
              : () async {
                  final playlistService = ref.read(playlistServiceProvider);
                  await playlistService.toggleFavoriteSong(currentMusic);
                },
          tooltip: isFavorite ? l10n.removeFromFavorites : l10n.addToFavorites,
        ),
        GestureDetector(
          onLongPress: onShowPlaylistModeSelector,
          child: IconButton(
            icon: Icon(
              getPlaylistModeIcon(playbackMode),
              size: (isLarge ? 36 : 28) * controlsScale,
              color: Colors.white70,
            ),
            onPressed: onCyclePlaylistMode,
            tooltip: getPlaylistModeName(playbackMode, l10n),
          ),
        ),
        GestureDetector(
          onLongPress: onShowRandomModeSelector,
          child: IconButton(
            icon: Icon(
              Icons.shuffle_rounded,
              size: (isLarge ? 36 : 28) * controlsScale,
              color: isRandomMode
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white70,
            ),
            onPressed: () {
              final audio = ref.read(audioServiceProvider);
              if (audio.settingsService.randomRange == 1 && !isRandomMode) {
                final playlistService = ref.read(playlistServiceProvider);
                final List<MusicFile> allSongs = [];
                final pathSet = <String>{};
                for (final p in playlistService.playlists) {
                  for (final s in p.songs) {
                    if (pathSet.add(s.path)) allSongs.add(s);
                  }
                }
                audio.toggleRandomMode(globalSongs: allSongs);
              } else {
                audio.toggleRandomMode();
              }
            },
            tooltip: l10n.randomMode,
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.auto_fix_high_rounded,
            size: (isLarge ? 36 : 28) * controlsScale,
            color: Colors.white70,
          ),
          onPressed: onTagCompletionTap,
          onLongPress: onTagCompletionLongPress,
          tooltip: l10n.tagCompletion,
        ),
        Tooltip(
          message: sleepTimerRemaining != null
              ? l10n.sleepTimerRemaining(_formatSleepTimer(sleepTimerRemaining))
              : l10n.sleepTimer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSleepTimerTap,
            child: SizedBox(
              width: 74 * controlsScale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bedtime_rounded,
                    size: (isLarge ? 36 : 28) * controlsScale,
                    color: sleepTimerRemaining != null
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white70,
                  ),
                  if (sleepTimerRemaining != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatSleepTimer(sleepTimerRemaining),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 10 * controlsScale,
                        height: 1.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.tune_rounded,
            size: (isLarge ? 36 : 28) * controlsScale,
            color: Colors.white70,
          ),
          onPressed: onEqualizerTap,
          tooltip: l10n.equalizer,
        ),
      ],
    );

    final mainControlsRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            showVisualizerToggle ? Icons.analytics : Icons.analytics_outlined,
            size: (isLarge ? 36 : 28) * controlsScale,
            color: showVisualizerToggle ? Colors.white : Colors.white70,
          ),
          onPressed: onToggleVisualizer,
          tooltip: AppLocalizations.of(context)!.visualizer,
        ),
        SizedBox(width: 4 * controlsScale),
        IconButton(
          icon: Icon(
            Icons.skip_previous_rounded,
            size: (isLarge ? 64 : 48) * controlsScale,
            color: Colors.white,
          ),
          onPressed: onPrevious,
          tooltip: l10n.previous,
        ),
        SizedBox(width: 16 * controlsScale),
        Container(
          width: (isLarge ? 96 : 72) * controlsScale,
          height: (isLarge ? 96 : 72) * controlsScale,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12 * controlsScale,
                spreadRadius: 2 * controlsScale,
              ),
            ],
          ),
          child: IconButton(
            onPressed: onPlayPause,
            tooltip: isPlaying ? l10n.pause : l10n.play,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: (isLarge ? 56 : 40) * controlsScale,
              color:
                  currentThemeColorsMap['darkVibrant'] ??
                  currentThemeColorsMap['darkMuted'] ??
                  Colors.black,
            ),
          ),
        ),
        SizedBox(width: 16 * controlsScale),
        IconButton(
          icon: Icon(
            Icons.skip_next_rounded,
            size: (isLarge ? 64 : 48) * controlsScale,
            color: Colors.white,
          ),
          onPressed: onNext,
          tooltip: l10n.next,
        ),
        SizedBox(width: 8 * controlsScale),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            onVolumeDrag?.call(details.primaryDelta ?? 0);
          },
          child: Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                onVolumeScroll?.call(pointerSignal.scrollDelta.dy);
              }
            },
            child: IconButton(
              icon: Icon(
                getVolumeIcon(ref.watch(audioVolumeProvider)),
                size: (isLarge ? 36 : 28) * controlsScale,
                color: Colors.white70,
              ),
              onPressed: onVolumeTap,
              tooltip: l10n.volume,
            ),
          ),
        ),
      ],
    );

    if (useOverlayStyle) {
      final waveform = overrideWaveform ?? currentMusic?.waveform ?? const [];
      final displayProgress = overrideProgress ?? progress.clamp(0.0, 1.0);

      return Column(
        key: const ValueKey('overlay_controls_column'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          topButtonsRow,
          const SizedBox(height: 8),
          Stack(
            key: const ValueKey('overlay_controls_stack'),
            alignment: Alignment.center,
            children: [
              // 波形进度条作为背景 (Waveform as background)
              // 让 WaveformProgressBar 成为非定位子组件以撑开 Stack 的高度
              WaveformProgressBar(
                waveform: waveform,
                progress: displayProgress,
                duration: duration,
                onScrubbing: onScrubbing ?? (_) {},
                onSeek: onSeek ?? (_) {},
                height: 240, // 增加高度以实现叠层感 (Increase height for overlay feel)
              ),
              // 播放控制按钮叠在上面 (Playback controls on top)
              Padding(
                padding: const EdgeInsets.only(top: 20), // 稍微向下偏移以避开波形顶部时间预览
                child: mainControlsRow,
              ),
              // 时间显示在底部左右两侧 (Time display at bottom corners)
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

    // 默认布局 (Default layout)
    return Column(
      key: const ValueKey('default_controls_column'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        topButtonsRow,
        SizedBox(height: isLandscape ? 16 : 12),
        Builder(
          builder: (context) {
            final waveform =
                overrideWaveform ?? currentMusic?.waveform ?? const [];
            final displayProgress =
                overrideProgress ?? progress.clamp(0.0, 1.0);

            if (isWaveformEnabled) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: WaveformProgressBar(
                  waveform: waveform,
                  progress: displayProgress,
                  duration: duration,
                  onScrubbing: onScrubbing ?? (_) {},
                  onSeek: onSeek ?? (_) {},
                  height: 100,
                ),
              );
            }
            return _buildStandardSlider(context, displayProgress);
          },
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
        SizedBox(height: isLandscape ? 16 : 12),
        mainControlsRow,
      ],
    );
  }

  Widget _buildLyricsPanelWidget(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final position = ref.watch(audioPositionProvider);
    final currentThemeColorsMap = ref.watch(audioCurrentThemeColorsMapProvider);
    final accent =
        currentThemeColorsMap['darkVibrant'] ??
        currentThemeColorsMap['darkMuted'] ??
        Colors.white;

    return LyricsPanel(
      key: ValueKey('$currentIndex:${currentMusic?.path ?? 'no-track'}'),
      lyrics: currentMusic?.lyrics,
      position: position,
      accentColor: accent,
      bottomSpacerHeight: lyricsBottomSpacerHeight,
      bottomTabBarHeight: lyricsBottomTabBarHeight,
    );
  }

  Widget _buildStandardSlider(BuildContext context, double displayProgress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
          thumbColor: Colors.white,
          overlayColor: Colors.white.withValues(alpha: 0.1),
        ),
        child: Slider(
          value: displayProgress.clamp(0.0, 1.0),
          onChanged: onScrubbing,
          onChangeEnd: (value) {
            onSeek?.call(value);
          },
        ),
      ),
    );
  }
}

class _MiniPlayerProgressInfo extends ConsumerStatefulWidget {
  final MusicFile? currentMusic;
  final double progress;
  final ValueChanged<double>? onScrubbing;
  final ValueChanged<double>? onSeek;

  const _MiniPlayerProgressInfo({
    required this.currentMusic,
    required this.progress,
    this.onScrubbing,
    this.onSeek,
  });

  @override
  ConsumerState<_MiniPlayerProgressInfo> createState() =>
      _MiniPlayerProgressInfoState();
}

class _MiniPlayerProgressInfoState
    extends ConsumerState<_MiniPlayerProgressInfo> {
  bool _isHovering = false;
  bool _isDragging = false;
  double? _dragValue;

  bool get _isActive => _isHovering || _isDragging;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(audioPositionProvider);
    final duration = ref.watch(audioDurationProvider);
    final currentMusic = widget.currentMusic;

    final displayProgress = _isDragging
        ? (_dragValue ?? widget.progress)
        : widget.progress;
    final displayPosition = _isDragging
        ? Duration(
            milliseconds:
                (duration.inMilliseconds * (_dragValue ?? widget.progress))
                    .toInt(),
          )
        : position;

    final subtitle = [
      if (currentMusic?.artist != null && currentMusic!.artist!.isNotEmpty)
        currentMusic.artist,
      if (currentMusic?.album != null && currentMusic!.album!.isNotEmpty)
        currentMusic.album,
    ].join(' - ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 32,
          child: Stack(
            children: [
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 200),
                tween: Tween<double>(begin: 0, end: _isActive ? 5.0 : 0.0),
                builder: (context, blur, child) {
                  return ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isActive ? 0.3 : 1.0,
                      child: child,
                    ),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      currentMusic?.displayName ??
                          AppLocalizations.of(context)!.notSelected,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color:
                              (Theme.of(context).brightness == Brightness.dark
                                      ? Colors.white
                                      : Colors.black87)
                                  .withValues(alpha: 0.6),
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (_isActive)
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '${formatDuration(displayPosition)} / ${formatDuration(duration)}',
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        MouseRegion(
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              setState(() {
                _isDragging = true;
                _dragValue = widget.progress;
              });
            },
            onHorizontalDragUpdate: (details) {
              if (!_isDragging) return;
              final RenderBox box = context.findRenderObject() as RenderBox;
              final double localX = details.localPosition.dx;
              final double newProgress = (localX / box.size.width).clamp(
                0.0,
                1.0,
              );
              setState(() {
                _dragValue = newProgress;
              });
              widget.onScrubbing?.call(newProgress);
            },
            onHorizontalDragEnd: (details) {
              if (!_isDragging) return;
              final finalProgress = _dragValue ?? widget.progress;
              setState(() {
                _isDragging = false;
                _dragValue = null;
              });
              widget.onSeek?.call(finalProgress);
            },
            onTapDown: (details) {
              final RenderBox box = context.findRenderObject() as RenderBox;
              final double localX = details.localPosition.dx;
              final double newProgress = (localX / box.size.width).clamp(
                0.0,
                1.0,
              );
              widget.onScrubbing?.call(newProgress);
              widget.onSeek?.call(newProgress);
            },
            onTap:
                () {}, // Consume tap to prevent bubbling to parent mini player tap
            child: Container(
              height: 10,
              color: Colors.transparent,
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: _isActive ? 6 : 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: _isActive ? 6 : 3,
                    value: displayProgress.clamp(0.0, 1.0),
                    backgroundColor:
                        Theme.of(context).brightness == Brightness.dark
                        ? Colors.white24
                        : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
