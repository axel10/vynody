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
import '../widgets/playback_ui_tuning.dart';
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

  double _lerp2DSmooth(
    double pN,
    double pL,
    double lN,
    double lL,
    double tLyrics,
    double tLand,
  ) {
    final p = lerpDouble(pN, pL, tLyrics) ?? pN;
    final l = lerpDouble(lN, lL, tLyrics) ?? lN;
    return lerpDouble(p, l, tLand) ?? p;
  }

  // Removed viewportProfile

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
    const animDuration = PlaybackHeroCardUiTuning.transitionDuration;
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
                final isWaveformEnabled = ref.watch(
                  settingsServiceProvider.select(
                    (s) => s.isWaveformProgressBarEnabled,
                  ),
                );

                final layout = _buildPlaybackCardLayout(
                  context,
                  width: width,
                  height: height,
                  tLyrics: tLyrics,
                  tLand: tLand,
                  isWaveformEnabled: isWaveformEnabled,
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
                              alignment: Alignment.center,
                              child: SizedBox(
                                width:
                                    (isLandscape
                                        ? lerpDouble(
                                            PlaybackHeroCardUiTuning
                                                .lControlsScaleBase,
                                            PlaybackHeroCardUiTuning
                                                .lLyricsPreferredCoverSide,
                                            tLyrics,
                                          )!
                                        : width *
                                            PlaybackHeroCardUiTuning
                                                .portraitControlsWidthFactor) *
                                    layout.controlsScale,
                                child: _buildPlaybackControlsWidget(
                                  context,
                                  ref,
                                  controlsScale: layout.controlsScale,
                                  tLyrics: tLyrics,
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
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.lerp(
                            Alignment.center,
                            Alignment.lerp(
                              Alignment.center,
                              Alignment.topCenter,
                              tLyrics,
                            )!,
                            tLand,
                          )!,
                          child: SizedBox(
                            width: layout.info.width,
                            child: _buildTrackInfo(
                              context,
                              currentMusic,
                              layout.trackInfoAlign,
                              tLyrics,
                              layout.controlsScale,
                            ),
                          ),
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
    required bool isWaveformEnabled,
  }) {
    // ---------------- Portrait Normal ----------------
    final pNormalControlsBaseIdealHeight =
        PlaybackHeroCardUiTuning.controlsTopButtonsHeight +
        PlaybackHeroCardUiTuning.controlsRowPortraitGap +
        (isWaveformEnabled
            ? PlaybackHeroCardUiTuning.waveformOverlayHeight
            : 48.0) + // Normal slider height is roughly 48
        (isWaveformEnabled
            ? 0.0
            : (8.0 + // Time gap
                PlaybackHeroCardUiTuning.controlsTimeRowHeight +
                PlaybackHeroCardUiTuning.controlsRowPortraitGap +
                PlaybackHeroCardUiTuning.controlsMainButtonsHeight));

    final pNormalControlsWidth =
        width * PlaybackHeroCardUiTuning.portraitControlsWidthFactor;
    final pNormalControlsRawScale =
        pNormalControlsWidth / PlaybackHeroCardUiTuning.pControlsScaleBase;

    final pNormalControlsHeight =
        (pNormalControlsBaseIdealHeight * pNormalControlsRawScale)
            .clamp(0.0, height * PlaybackHeroCardUiTuning.pControlsHeightFactor)
            .ceilToDouble();
    final pNormalInfoHeight = PlaybackHeroCardUiTuning.pInfoHeight;

    // 避让底部 Tab 栏高度 (Avoid bottom tab bar height)
    final pNormalBottomLimit = height - PlaybackHeroCardUiTuning.portraitBottomReservedSpace;

    // 封面贴顶 (Cover sticks to top)
    const pNormalCoverTop = 0.0;

    // 内容总高度 (Total content height: Info + Controls)
    final pNormalTotalContentHeight = pNormalInfoHeight + pNormalControlsHeight;

    // 封面尺寸：在满足下方内容展示空间的情况下，尽量占满宽度
    // 留出最小间距以防重叠 (Reserved min gap to prevent overlap)
    final pNormalCoverSide = math
        .min(
          width,
          pNormalBottomLimit -
              pNormalTotalContentHeight -
              PlaybackHeroCardUiTuning.pNormalCoverInfoMinGap,
        )
        .clamp(0.0, PlaybackHeroCardUiTuning.pCoverMaxSide)
        .toDouble();

    // 在封面底部到 Tab 栏顶部之间的剩余空间内居中放置标题和控件区
    // Center title and controls between bottom of cover and top of tab bar
    final pNormalAvailableHeight = pNormalBottomLimit - pNormalCoverSide;
    final pNormalContentTop =
        pNormalCoverSide +
        (pNormalAvailableHeight - pNormalTotalContentHeight) / 2;

    final pNormalInfoTop = pNormalContentTop;
    final pNormalControlsTop = pNormalInfoTop + pNormalInfoHeight;

    // ---------------- Portrait Lyrics ----------------
    final pLyricsCoverSide = 120.0;
    const pLyricsCoverTop = 16.0;
    const pLyricsCoverLeft = 16.0;

    final pLyricsInfoHeight = pLyricsCoverSide;
    const pLyricsInfoTop = pLyricsCoverTop;
    final pLyricsInfoLeft = pLyricsCoverLeft + pLyricsCoverSide + 16.0;

    // ---------------- Landscape Normal ----------------
    final lNormalContentWidth = width
        .clamp(0.0, math.max(1600.0, height * 2.5).toDouble())
        .toDouble();
    final lNormalOffsetX = (width - lNormalContentWidth) / 2;

    final lColumnWidth = lNormalContentWidth * 0.5;

    // 横屏普通模式控件区宽度：采用具有较高基底和较低增长率的公式，
    // 使得在窗口化（较小宽度）时控件区比例更大，而在全屏（较大宽度）时保持原样。
    // (Landscape normal controls width: Use a formula with a higher base and lower growth rate,
    // making the controls area relatively larger in windowed mode while maintaining fullscreen size.)
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
    final lNormalCoverTop = (height - lNormalCoverSide) / 2;
    final lNormalCoverLeft = lNormalLeftCenter - (lNormalCoverSide / 2);

    final lNormalCoverRightEdge = lNormalCoverLeft + lNormalCoverSide;
    final lContentRightEdge = lNormalOffsetX + lNormalContentWidth;
    final lRemainingSpace = lContentRightEdge - lNormalCoverRightEdge;

    final lNormalControlsLeft =
        lNormalCoverRightEdge + (lRemainingSpace - lNormalControlsWidth) / 2;
    final lNormalInfoLeft = lNormalControlsLeft;

    // Snap the normal landscape panes to whole pixels to avoid 1px overflow
    // when the window is resized and the layout lands on fractional values.
    final lNormalControlsRawScale =
        lNormalControlsWidth / PlaybackHeroCardUiTuning.lControlsScaleBase;

    // 标题区实际高度 (Title actual height)
    final lNormalInfoHeight =
        (PlaybackHeroCardUiTuning.landscapeInfoHeightBase *
                lNormalControlsRawScale.clamp(0.0, 1.8))
            .ceilToDouble();

    // 控件区动态高度计算 (Dynamic controls height)
    final lNormalControlsBaseIdealHeight =
        PlaybackHeroCardUiTuning.controlsTopButtonsHeight +
        PlaybackHeroCardUiTuning.controlsRowLandscapeGap +
        (isWaveformEnabled
            ? PlaybackHeroCardUiTuning.waveformStandardHeight
            : 48.0) + // Use smaller height when waveform is disabled
        PlaybackHeroCardUiTuning.controlsTimeGap +
        PlaybackHeroCardUiTuning.controlsTimeRowHeight +
        PlaybackHeroCardUiTuning.controlsRowLandscapeGap +
        PlaybackHeroCardUiTuning.controlsMainButtonsHeight;

    final lNormalControlsHeight =
        (lNormalControlsBaseIdealHeight *
                lNormalControlsRawScale.clamp(0.0, 1.8))
            .clamp(
              0.0,
              height * 0.5,
            ) // Remove pControlsMinHeight clamp to allow exact fit
            .ceilToDouble();

    final lNormalGap = PlaybackHeroCardUiTuning.landscapeInfoControlsGap;
    final lNormalInfoTop =
        (height * 0.5 -
                (lNormalInfoHeight + lNormalControlsHeight + lNormalGap) / 2)
            .roundToDouble();
    final lNormalControlsTop = lNormalInfoTop + lNormalInfoHeight + lNormalGap;

    // ---------------- Landscape Lyrics ----------------
    // 左侧列的目标宽度只跟高度相关，避免随着窗口横向拉伸产生跳变。
    const lLyricsTopPadding = 16.0;
    const lLyricsOuterLeftPadding = 32.0;
    const lLyricsInnerLeftPadding = 16.0;
    const lLyricsCoverInfoSpacing = 24.0;
    final lLyricsInfoControlsSpacing =
        PlaybackHeroCardUiTuning.landscapeInfoControlsGap;
    const lLyricsPreferredCoverSide =
        PlaybackHeroCardUiTuning.lLyricsPreferredCoverSide;
    final lLyricsAvailableHeight = math.max(
      0.0,
      height - (lLyricsTopPadding * 2),
    );
    // Determine the total width of the left column (mainly dictated by the controls area)
    final double lLyricsMaxColumnWidth = math.min(width * 0.45, 800.0);
    final double lLyricsColumnWidth = (width * 0.20).clamp(
      math.min(380.0, lLyricsMaxColumnWidth),
      lLyricsMaxColumnWidth,
    );
    final double lLyricsWidthScale = (lLyricsColumnWidth / 400.0).clamp(
      1.0,
      1.8,
    );

    final lLyricsInfoBaseHeight =
        PlaybackHeroCardUiTuning.landscapeInfoHeightBase;
    final lLyricsControlsBaseHeight = lNormalControlsBaseIdealHeight;

    final lLyricsPreferredTotalHeight =
        (lLyricsPreferredCoverSide * lLyricsWidthScale) +
        lLyricsCoverInfoSpacing +
        (lLyricsInfoBaseHeight * lLyricsWidthScale) +
        lLyricsInfoControlsSpacing +
        (lLyricsControlsBaseHeight * lLyricsWidthScale);
    final lLyricsScale = lLyricsPreferredTotalHeight <= 0.0
        ? 1.0
        : math.min(1.0, lLyricsAvailableHeight / lLyricsPreferredTotalHeight);
    final lLyricsCoverSide =
        lLyricsPreferredCoverSide * lLyricsWidthScale * lLyricsScale;
    final double lLyricsItemWidth = lLyricsCoverSide;
    final lLyricsInfoHeight =
        lLyricsInfoBaseHeight * lLyricsWidthScale * lLyricsScale;
    final lLyricsControlsHeight =
        lLyricsControlsBaseHeight * lLyricsWidthScale * lLyricsScale;
    final lLyricsCoverTop = lLyricsTopPadding;

    // 居中对齐逻辑：封面、信息区和控制区在列宽内统一居中对齐
    // Centering logic: cover, info and controls are centered within the column and aligned in width
    final lLyricsCoverLeft =
        lLyricsOuterLeftPadding + (lLyricsColumnWidth - lLyricsCoverSide) / 2;
    final lLyricsInfoLeft = lLyricsCoverLeft;
    final lLyricsControlsLeft = lLyricsCoverLeft;

    final lLyricsInfoTop =
        lLyricsCoverTop + lLyricsCoverSide + lLyricsCoverInfoSpacing;

    final lLyricsControlsTop =
        lLyricsInfoTop + lLyricsInfoHeight + lLyricsInfoControlsSpacing;

    final lLyricsLyricsLeft =
        lLyricsOuterLeftPadding + lLyricsColumnWidth + lLyricsInnerLeftPadding;
    final double lLyricsLyricsWidth = math.max(
      0.0,
      width - lLyricsLyricsLeft - 32.0,
    );

    // 移除离散的 isLarge 逻辑，改用连续的百分比缩放
    // Remove discrete isLarge logic, use continuous percentage scaling
    final currentControlsScale = _lerp2DSmooth(
      1.0,
      1.0,
      // 横屏普通模式：基于列宽进行缩放，放宽最小缩放限制以允许在小窗口下更自然的布局
      (lNormalControlsWidth / PlaybackHeroCardUiTuning.lControlsScaleBase).clamp(
        0.85,
        1.8,
      ),
      // 横屏歌词模式：结合宽度基准和高度缩放系数
      (lLyricsWidthScale * lLyricsScale).clamp(0.4, 2.0),
      tLyrics,
      tLand,
    );

    // Build the Panes
    // Cover
    final cover = _lerpPane(
      context,
      pNormal: _PlaybackPaneLayout(
        top: pNormalCoverTop,
        left: (width - pNormalCoverSide) / 2,
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

    // Info
    final info = _lerpPane(
      context,
      pNormal: _PlaybackPaneLayout(
        top: pNormalInfoTop,
        left: 24.0,
        width: width - 48.0,
        height: pNormalInfoHeight,
        opacity: 1.0,
      ),
      pLyrics: _PlaybackPaneLayout(
        top: pLyricsInfoTop,
        left: pLyricsInfoLeft,
        width: width - pLyricsInfoLeft - 16.0,
        height: pLyricsInfoHeight,
        opacity: 1.0,
      ),
      lNormal: _PlaybackPaneLayout(
        top: lNormalInfoTop,
        left: lNormalInfoLeft,
        width: lNormalControlsWidth,
        height: lNormalInfoHeight,
        opacity: 1.0,
      ),
      lLyrics: _PlaybackPaneLayout(
        top: lLyricsInfoTop,
        left: lLyricsInfoLeft,
        width: lLyricsItemWidth,
        height: lLyricsInfoHeight,
        opacity: 1.0,
      ),
      tLyrics: tLyrics,
      tLand: tLand,
    );

    // Controls
    final controls = _lerpPane(
      context,
      pNormal: _PlaybackPaneLayout(
        top: pNormalControlsTop,
        left: (width - math.min(width, pNormalControlsWidth)) / 2,
        width: math.min(width, pNormalControlsWidth),
        height: pNormalControlsHeight,
        opacity: 1.0,
      ),
      pLyrics: _PlaybackPaneLayout(
        top: height,
        left: 16.0,
        width: width - 32.0,
        height: pNormalControlsHeight,
        opacity: 0.0,
      ),
      lNormal: _PlaybackPaneLayout(
        top: lNormalControlsTop,
        left: lNormalControlsLeft,
        width: lNormalControlsWidth,
        height: lNormalControlsHeight,
        opacity: 1.0,
      ),
      lLyrics: _PlaybackPaneLayout(
        top: lLyricsControlsTop,
        left: lLyricsControlsLeft,
        width: lLyricsItemWidth,
        height: lLyricsControlsHeight,
        opacity: 1.0,
      ),
      tLyrics: tLyrics,
      tLand: tLand,
    );

    // Lyrics
    final lyrics = _lerpPane(
      context,
      pNormal: _PlaybackPaneLayout(
        top: height,
        left: 16.0,
        width: width - 32.0,
        height: height - pNormalInfoTop,
        opacity: 0.0,
      ),
      pLyrics: _PlaybackPaneLayout(
        top: pLyricsCoverTop + pLyricsCoverSide + 16.0,
        left: 16.0,
        width: width - 32.0,
        height: height - (pLyricsCoverTop + pLyricsCoverSide + 16.0),
        opacity: 1.0,
      ),
      lNormal: _PlaybackPaneLayout(
        top: 16.0,
        left: width,
        width: lLyricsColumnWidth,
        height: height - 32.0,
        opacity: 0.0,
      ),
      lLyrics: _PlaybackPaneLayout(
        top: 16.0,
        left: lLyricsLyricsLeft,
        width: lLyricsLyricsWidth,
        height: height - 32.0,
        opacity: 1.0,
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
      controlsScale: currentControlsScale,
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
      opacity: _lerp2DSmooth(
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
    double controlsScale,
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
      mainAxisSize: MainAxisSize.min,
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
                  fontSize:
                      (lyricsModeT > 0.5 && !isLandscape
                          ? PlaybackHeroCardUiTuning
                                .trackTitlePortraitLyricsFont
                          : PlaybackHeroCardUiTuning.trackTitleStandardFont) *
                      controlsScale,
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
                      fontSize:
                          (lyricsModeT > 0.5 && !isLandscape
                              ? PlaybackHeroCardUiTuning
                                    .trackArtistPortraitLyricsFont
                              : PlaybackHeroCardUiTuning
                                    .trackArtistStandardFont) *
                          controlsScale,
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
    double controlsScale = 1.0,
    double tLyrics = 0.0,
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

    final topButtonsCount = 7;
    final topButtonsGaps = topButtonsCount - 1;
    final singleButtonWidth =
        PlaybackHeroCardUiTuning.controlsTopButtonsHeight * controlsScale;
    final gapWidth =
        PlaybackHeroCardUiTuning.topButtonsInnerGap * controlsScale;
    final buttonsRowWidth =
        topButtonsCount * singleButtonWidth + topButtonsGaps * gapWidth;

    final baseWidth = isLandscape
        ? (lerpDouble(
              PlaybackHeroCardUiTuning.lControlsScaleBase,
              PlaybackHeroCardUiTuning.lLyricsPreferredCoverSide,
              tLyrics,
            )!)
        : PlaybackHeroCardUiTuning.pControlsScaleBase;

    final totalWidth = baseWidth * controlsScale;

    // 竖屏模式下如果启用波形进度条，则使用叠层布局 (Overlay layout in portrait if waveform is enabled)
    final useOverlayStyle = !isLandscape && !isLyricsMode && isWaveformEnabled;

    // 提取公共组件 (Extract common components)
    final topButtonsRow = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PlaybackHeroCardUiTuning.topButtonsHorizontalPadding,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: singleButtonWidth,
                height: singleButtonWidth,
              ),
              icon: Icon(
                Icons.more_horiz,
                size:
                    PlaybackHeroCardUiTuning.topButtonsIconSize * controlsScale,
                color: Colors.white70,
              ),
              onPressed: onShowMoreMenu,
              tooltip: l10n.more,
            ),
            SizedBox(
              width: PlaybackHeroCardUiTuning.topButtonsInnerGap * controlsScale,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: singleButtonWidth,
                height: singleButtonWidth,
              ),
              icon: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size:
                    PlaybackHeroCardUiTuning.topButtonsIconSize * controlsScale,
                color: isFavorite ? Colors.redAccent : Colors.white70,
              ),
              onPressed:
                  currentMusic == null
                       ? null
                       : () async {
                         final playlistService = ref.read(
                           playlistServiceProvider,
                         );
                         await playlistService.toggleFavoriteSong(
                           currentMusic,
                         );
                       },
              tooltip:
                  isFavorite ? l10n.removeFromFavorites : l10n.addToFavorites,
            ),
            SizedBox(
              width: PlaybackHeroCardUiTuning.topButtonsInnerGap * controlsScale,
            ),
            GestureDetector(
              onLongPress: onShowPlaylistModeSelector,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: singleButtonWidth,
                  height: singleButtonWidth,
                ),
                icon: Icon(
                  getPlaylistModeIcon(playbackMode),
                  size:
                      PlaybackHeroCardUiTuning.topButtonsIconSize *
                      controlsScale,
                  color: Colors.white70,
                ),
                onPressed: onCyclePlaylistMode,
                tooltip: getPlaylistModeName(playbackMode, l10n),
              ),
            ),
            SizedBox(
              width: PlaybackHeroCardUiTuning.topButtonsInnerGap * controlsScale,
            ),
            GestureDetector(
              onLongPress: onShowRandomModeSelector,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: singleButtonWidth,
                  height: singleButtonWidth,
                ),
                icon: Icon(
                  Icons.shuffle_rounded,
                  size:
                      PlaybackHeroCardUiTuning.topButtonsIconSize *
                      controlsScale,
                  color:
                      isRandomMode
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white70,
                ),
                onPressed: () {
                  final audio = ref.read(audioServiceProvider);
                  if (audio.settingsService.randomRange == 1 &&
                      !isRandomMode) {
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
            SizedBox(
              width: PlaybackHeroCardUiTuning.topButtonsInnerGap * controlsScale,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: singleButtonWidth,
                height: singleButtonWidth,
              ),
              icon: Icon(
                Icons.auto_fix_high_rounded,
                size:
                    PlaybackHeroCardUiTuning.topButtonsIconSize * controlsScale,
                color: Colors.white70,
              ),
              onPressed: onTagCompletionTap,
              onLongPress: onTagCompletionLongPress,
              tooltip: l10n.tagCompletion,
            ),
            SizedBox(
              width: PlaybackHeroCardUiTuning.topButtonsInnerGap * controlsScale,
            ),
            Tooltip(
              message:
                  sleepTimerRemaining != null
                      ? l10n.sleepTimerRemaining(
                        _formatSleepTimer(sleepTimerRemaining),
                      )
                      : l10n.sleepTimer,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSleepTimerTap,
                child: Container(
                  width: PlaybackHeroCardUiTuning.controlsTopButtonsHeight *
                      controlsScale,
                  height: PlaybackHeroCardUiTuning.controlsTopButtonsHeight *
                      controlsScale,
                  alignment: Alignment.topCenter,
                  padding: EdgeInsets.only(
                    top: (PlaybackHeroCardUiTuning.controlsTopButtonsHeight -
                            PlaybackHeroCardUiTuning.topButtonsIconSize) /
                        2 *
                        controlsScale,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.bedtime_rounded,
                        size: PlaybackHeroCardUiTuning.topButtonsIconSize *
                            controlsScale,
                        color:
                            sleepTimerRemaining != null
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white70,
                      ),
                      if (sleepTimerRemaining != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatSleepTimer(sleepTimerRemaining),
                          maxLines: 1,
                          overflow: TextOverflow.visible,
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
            SizedBox(
              width: PlaybackHeroCardUiTuning.topButtonsInnerGap * controlsScale,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: singleButtonWidth,
                height: singleButtonWidth,
              ),
              icon: Icon(
                Icons.tune_rounded,
                size:
                    PlaybackHeroCardUiTuning.topButtonsIconSize * controlsScale,
                color: Colors.white70,
              ),
              onPressed: onEqualizerTap,
              tooltip: l10n.equalizer,
            ),
          ],
        ),
      ),
    );


    final mainControlsRow = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(
              showVisualizerToggle ? Icons.analytics : Icons.analytics_outlined,
              size: 28 * controlsScale,
              color: showVisualizerToggle ? Colors.white : Colors.white70,
            ),
            onPressed: onToggleVisualizer,
            tooltip: AppLocalizations.of(context)!.visualizer,
          ),
          SizedBox(width: 4 * controlsScale),
          IconButton(
            icon: Icon(
              Icons.skip_previous_rounded,
              size: 48 * controlsScale,
              color: Colors.white,
            ),
            onPressed: onPrevious,
            tooltip: l10n.previous,
          ),
          SizedBox(width: 16 * controlsScale),
          Container(
            width: 72 * controlsScale,
            height: 72 * controlsScale,
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
                size: 40 * controlsScale,
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
              size: 48 * controlsScale,
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
                  size: 28 * controlsScale,
                  color: Colors.white70,
                ),
                onPressed: onVolumeTap,
                tooltip: l10n.volume,
              ),
            ),
          ),
        ],
      ),
    );

    // 进度条及时间显示容器 (Common container for progress bar and time display)
    Widget buildProgressSection() {
      // 在横屏切换到歌词模式的过程中，平滑插值宽度系数和基准宽度
      // 在横屏切换到歌词模式的过程中，平滑插值宽度系数
      final widthFactor = isLandscape
          ? (lerpDouble(
              PlaybackHeroCardUiTuning.progressBarWidthFactor,
              1.0,
              tLyrics,
            )!)
          : PlaybackHeroCardUiTuning.portraitProgressBarWidthFactor;

      return SizedBox(
        width: buttonsRowWidth * widthFactor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                final waveform =
                    overrideWaveform ?? currentMusic?.waveform ?? const [];
                final displayProgress =
                    overrideProgress ?? progress.clamp(0.0, 1.0);

                if (isWaveformEnabled) {
                  final waveformWidget = WaveformProgressBar(
                    waveform: waveform,
                    progress: displayProgress,
                    duration: duration,
                    onScrubbing: onScrubbing ?? (_) {},
                    onSeek: onSeek ?? (_) {},
                    height:
                        PlaybackHeroCardUiTuning.waveformStandardHeight *
                        controlsScale,
                  );
                  if (!isLandscape) {
                    return Transform.scale(
                      scaleX:
                          PlaybackHeroCardUiTuning.portraitWaveformOverflowScale,
                      child: waveformWidget,
                    );
                  }
                  return waveformWidget;
                }
                return _buildStandardSlider(
                  context,
                  displayProgress,
                  controlsScale,
                  noPadding: true,
                );
              },
            ),
            SizedBox(
              height:
                  (isLandscape
                      ? PlaybackHeroCardUiTuning.controlsTimeGap
                      : 8.0) *
                  controlsScale,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(
                      overridePosition ?? ref.watch(audioPositionProvider),
                    ),
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12 * controlsScale,
                    ),
                  ),
                  Text(
                    formatDuration(duration),
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12 * controlsScale,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (useOverlayStyle) {
      final waveform = overrideWaveform ?? currentMusic?.waveform ?? const [];
      final displayProgress = overrideProgress ?? progress.clamp(0.0, 1.0);

      return Column(
        key: const ValueKey('overlay_controls_column'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          topButtonsRow,
          const SizedBox(
            height: PlaybackHeroCardUiTuning.waveformStandardTimeRowSpacing,
          ),
          Stack(
            key: const ValueKey('overlay_controls_stack'),
            alignment: Alignment.center,
            children: [
              // 1. 只有波形进度条进行缩放 (Only waveform is scaled)
              Transform.scale(
                scaleX: PlaybackHeroCardUiTuning.portraitWaveformOverflowScale,
                child: SizedBox(
                  width: totalWidth,
                  child: WaveformProgressBar(
                    waveform: waveform,
                    progress: displayProgress,
                    duration: duration,
                    onScrubbing: onScrubbing ?? (_) {},
                    onSeek: onSeek ?? (_) {},
                    height:
                        PlaybackHeroCardUiTuning.waveformOverlayHeight *
                        controlsScale,
                  ),
                ),
              ),
              // 2. 时间文字单独平移，避免拉伸 (Time text translated separately to avoid stretching)
              // 计算平移距离：使其跟随波形向外移动，但增加阻尼，并严格限制最小屏幕边距
              Builder(
                builder: (context) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  final pagePadding =
                      PlaybackPageUiTuning.normalPortraitHorizontalPadding;
                  const minScreenMargin = 10.0; // 强制要求的最小屏幕边距

                  // 计算当前 FittedBox 的缩放比例 (理想宽度 / 实际显示宽度)
                  // 注意：此处 cardWidth 是 PlaybackHeroCard 的实际可用宽度
                  final cardWidth = screenWidth - (pagePadding * 2);
                  final fittedScale = cardWidth / totalWidth;

                  // 初始位移计算 (带阻尼)
                  final rawShift =
                      (PlaybackHeroCardUiTuning.waveformOverlayTimeSide -
                              totalWidth / 2) *
                          (PlaybackHeroCardUiTuning.portraitWaveformOverflowScale -
                              1) *
                          0.8;

                  // 限制位移：确保 (pagePadding + (side + shift) * fittedScale) >= minScreenMargin
                  // 解得：shift >= (minScreenMargin - pagePadding) / fittedScale - side
                  final minAllowedShift =
                      (minScreenMargin - pagePadding) / fittedScale -
                      PlaybackHeroCardUiTuning.waveformOverlayTimeSide;

                  // 因为 shift 是负数（向左移），所以是用 clamp(minAllowedShift, 0)
                  // 对于右侧文字，它是对称的
                  final safeShift = rawShift.clamp(minAllowedShift, 0.0);

                  return SizedBox(
                    width: totalWidth,
                    height:
                        PlaybackHeroCardUiTuning.waveformOverlayHeight *
                        controlsScale,
                    child: Stack(
                      children: [
                        Positioned(
                          left: PlaybackHeroCardUiTuning.waveformOverlayTimeSide,
                          bottom:
                              PlaybackHeroCardUiTuning.waveformOverlayTimeBottom,
                          child: Transform.translate(
                            offset: Offset(safeShift, 0),
                            child: Text(
                              formatDuration(
                                overridePosition ??
                                    ref.watch(audioPositionProvider),
                              ),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12 * controlsScale,
                                fontWeight: FontWeight.bold,
                                shadows: const [
                                  Shadow(color: Colors.black45, blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right:
                              PlaybackHeroCardUiTuning.waveformOverlayTimeSide,
                          bottom:
                              PlaybackHeroCardUiTuning.waveformOverlayTimeBottom,
                          child: Transform.translate(
                            offset: Offset(-safeShift, 0),
                            child: Text(
                              formatDuration(duration),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12 * controlsScale,
                                fontWeight: FontWeight.bold,
                                shadows: const [
                                  Shadow(color: Colors.black45, blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // 3. 播放控制按钮叠在上面，不跟随缩放 (Playback controls on top, no scaling)
              Padding(
                padding: const EdgeInsets.only(
                  top: PlaybackHeroCardUiTuning.waveformOverlayTopPadding,
                  left: 16,
                  right: 16,
                ),
                child: mainControlsRow,
              ),
            ],
          ),
        ],
      );
    }

    // 默认布局 (Default layout)
    if (isLandscape) {
      return Column(
        key: const ValueKey('default_controls_column'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          topButtonsRow,
          SizedBox(
            height:
                PlaybackHeroCardUiTuning.controlsRowLandscapeGap *
                controlsScale,
          ),
          buildProgressSection(),
          SizedBox(
            height:
                PlaybackHeroCardUiTuning.controlsRowLandscapeGap *
                controlsScale,
          ),
          mainControlsRow,
        ],
      );
    }

    // 竖屏非叠加布局 (Portrait non-overlay)
    return Column(
      key: const ValueKey('default_controls_column_portrait'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        topButtonsRow,
        SizedBox(
          height:
              PlaybackHeroCardUiTuning.controlsRowPortraitGap * controlsScale,
        ),
        buildProgressSection(),
        SizedBox(
          height:
              PlaybackHeroCardUiTuning.controlsRowPortraitGap * controlsScale,
        ),
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

  Widget _buildStandardSlider(
    BuildContext context,
    double displayProgress,
    double controlsScale, {
    bool noPadding = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: noPadding
            ? 0.0
            : PlaybackHeroCardUiTuning.waveformStandardHorizontalPadding,
      ),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4 * controlsScale,
          thumbShape: RoundSliderThumbShape(
            enabledThumbRadius: 7 * controlsScale,
          ),
          overlayShape: RoundSliderOverlayShape(
            overlayRadius: 16 * controlsScale,
          ),
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
