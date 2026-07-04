import 'dart:ui' show lerpDouble, ImageFilter;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/utils/playback_utils.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import '../widgets/cover_carousel.dart';
import '../widgets/lyrics_panel.dart';

import '../widgets/mini_player_widgets.dart';
import '../widgets/animated_play_pause_button.dart';
import '../widgets/playback_ui_tuning.dart';
import '../widgets/waveform_progress_bar.dart';
import 'marquee_text.dart';

const String playbackHeroTag = 'player_capsule';
double _maxWindowHeightSeen = 0.0;

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
  final void Function(Uint8List? artworkBytes, String? sourcePath)? onCarouselAnimationComplete;
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

  Future<void> _showCoverContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
    MusicFile? currentMusic,
  ) async {
    if (currentMusic == null) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final l10n = AppLocalizations.of(context)!;
    final audioService = ref.read(audioServiceProvider);

    final bytes = currentMusic.artworkBytes ?? audioService.getCachedArtwork(currentMusic.path);
    final hasCover = bytes != null && bytes.isNotEmpty;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        buildContextMenuItem<String>(
          value: 'copy_cover',
          enabled: hasCover,
          label: l10n.copyCover,
          icon: Icons.image_outlined,
          context: context,
        ),
      ],
    );

    if (!context.mounted || selected == null) return;

    if (selected == 'copy_cover') {
      try {
        if (bytes != null && bytes.isNotEmpty) {
          await Pasteboard.writeImage(bytes);
          if (context.mounted) {
            AppSnackBar.show(
              context,
              ref,
              SnackBar(content: Text(l10n.copyCoverSuccess)),
            );
          }
        }
      } catch (e) {
        debugPrint('Failed to copy cover to clipboard: $e');
        if (context.mounted) {
          AppSnackBar.show(
            context,
            ref,
            const SnackBar(content: Text('Failed to copy cover')),
          );
        }
      }
    }
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
                        const SizedBox(width: 4),
                        AnimatedPlayPauseButton(
                          isPlaying: isPlaying,
                          onPressed: onPlayPause,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black87,
                          size: 24,
                          padding: const EdgeInsets.all(6.0),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          tooltip: isPlaying
                              ? AppLocalizations.of(context)!.pause
                              : AppLocalizations.of(context)!.play,
                        ),
                        const SizedBox(width: 4),
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
                            onScroll: onVolumeScroll,
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

    final size = MediaQuery.of(context).size;
    final settings = ref.watch(settingsServiceProvider);



    final bool isSmallWindow = PlaybackPageUiTuning.isSmallWindow(
      size,
      isWaveformEnabled: settings.isWaveformProgressBarEnabled,
      isSmallWindowMode: settings.isSmallWindowMode,
    );
    final bool effectiveIsLandscape = isLandscape && !isSmallWindow;
    final bool effectiveIsLyricsMode = isLyricsMode && !isSmallWindow;

    // 核心动画容器：使用 TweenAnimationBuilder 对 2D 平面上的多个布局变量（尺寸、位置、不透明度）进行线性插值处理。
    // 这使得点击封面切换 `isLyricsMode` 后，UI 元素能平滑移动/缩放，例如：
    // - 封面从大变小并挪到角落
    // - 歌词面板从下而上“浮现”
    // - 播放控制按键在手机竖屏时向下滑出屏幕
    return TweenAnimationBuilder<double>(
      duration: animDuration,
      curve: animCurve,
      tween: Tween<double>(end: effectiveIsLandscape ? 1.0 : 0.0),
      builder: (context, tLand, _) {
        return TweenAnimationBuilder<double>(
          duration: animDuration,
          curve: animCurve,
          tween: Tween<double>(end: effectiveIsLyricsMode ? 1.0 : 0.0),
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
                final useOverlayStyle = !effectiveIsLandscape && !effectiveIsLyricsMode && isWaveformEnabled;

                final layout = _buildPlaybackCardLayout(
                  context,
                  width: width,
                  height: height,
                  tLyrics: tLyrics,
                  tLand: tLand,
                  isWaveformEnabled: isWaveformEnabled,
                  isSmallWindow: isSmallWindow,
                  lyricsStyle: settings.lyricsStyle,
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
                            child: Consumer(
                              builder: (context, ref, child) {
                                return _buildLyricsPanelWidget(context, ref);
                              },
                            ),
                          ),
                        ),
                      ),
                      if (isSmallWindow)
                        Positioned(
                          top: layout.info.top - 48.0,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final containerHeight = constraints.maxHeight;
                              final fadeStop = containerHeight > 0
                                  ? (48.0 / containerHeight).clamp(0.0, 1.0)
                                  : 0.2;
                              return ShaderMask(
                                shaderCallback: (rect) {
                                  return LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: const [
                                      Colors.transparent,
                                      Colors.black,
                                    ],
                                    stops: [0.0, fadeStop],
                                  ).createShader(rect);
                                },
                                blendMode: BlendMode.dstIn,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.35),
                                  ),
                                ),
                              );
                            },
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
                              child: Consumer(
                                builder: (context, ref, child) {
                                  return SizedBox(
                                    key: ValueKey('controls_sizing_box_${useOverlayStyle ? 'overlay' : 'default'}'),
                                    width:
                                        (effectiveIsLandscape
                                            ? layout.controls.width
                                            : width *
                                                  PlaybackHeroCardUiTuning
                                                      .portraitControlsWidthFactor),
                                    child: _buildPlaybackControlsWidget(
                                      context,
                                      ref,
                                      width: width,
                                      layoutWidth: layout.controls.width,
                                      controlsScale: layout.controlsScale,
                                      tLyrics: tLyrics,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (layout.cover.width > 0 && layout.cover.height > 0)
                        Positioned(
                          top: layout.cover.top,
                          left: layout.cover.left,
                          width: layout.cover.width,
                          height: layout.cover.height,
                          child: Consumer(
                            builder: (context, ref, child) {
                              return _buildAlbumArtCore(
                                context,
                                ref,
                                layout.cover.width,
                              );
                            },
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
    required bool isSmallWindow,
    required LyricsStyle lyricsStyle,
  }) {
    // ---------------- Portrait Normal ----------------
    final double scaleFactor = isSmallWindow ? 0.82 : 1.0;

    final pNormalControlsBaseIdealHeight =
        PlaybackHeroCardUiTuning.controlsTopButtonsHeight +
        (isWaveformEnabled
            ? PlaybackHeroCardUiTuning.waveformStandardTimeRowSpacing
            : PlaybackHeroCardUiTuning.controlsRowPortraitGap) +
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
    final pNormalScale =
        (width / PlaybackHeroCardUiTuning.pControlsScaleBase).clamp(0.9, 1.15) *
            scaleFactor;

    final double maxControlsHeightFactor = isSmallWindow
        ? 0.85
        : PlaybackHeroCardUiTuning.pControlsHeightFactor;

    final pNormalControlsHeight =
        (pNormalControlsBaseIdealHeight * pNormalScale)
            .clamp(0.0, height * maxControlsHeightFactor)
            .ceilToDouble();
    final pNormalInfoHeight = PlaybackHeroCardUiTuning.pInfoHeight * pNormalScale;

    // 避让底部 Tab 栏高度 (Avoid bottom tab bar height)
    final pNormalBottomLimit =
        height - PlaybackHeroCardUiTuning.portraitBottomReservedSpace;

    // 封面贴顶 (Cover sticks to top)
    const pNormalCoverTop = 0.0;

    // 内容总高度 (Total content height: Info + Controls)
    final pNormalTotalContentHeight = pNormalInfoHeight + pNormalControlsHeight;

    // 封面尺寸：在满足下方内容展示空间的情况下，尽量占满宽度
    // 留出最小间距以防重叠 (Reserved min gap to prevent overlap)
    final pNormalCoverSide = isSmallWindow
        ? 0.0
        : math
            .min(
              width,
              pNormalBottomLimit -
                  pNormalTotalContentHeight -
                  PlaybackHeroCardUiTuning.pNormalCoverInfoMinGap,
            )
            .clamp(0.0, PlaybackHeroCardUiTuning.pCoverMaxSide)
            .toDouble();

    final double pNormalInfoTop;
    final double pNormalControlsTop;

    if (isSmallWindow) {
      // 紧贴窗口底部 (Position right up against the bottom of the window)
      // 留出 12 像素底边距 (Leave 12px padding at the bottom)
      const double bottomPadding = 12.0;
      pNormalControlsTop = pNormalBottomLimit - pNormalControlsHeight - bottomPadding;
      pNormalInfoTop = pNormalControlsTop - pNormalInfoHeight - 4.0;
    } else {
      // 在封面底部到 Tab 栏顶部之间的剩余空间内居中放置标题和控件区
      final pNormalAvailableHeight = pNormalBottomLimit - pNormalCoverSide;
      final pNormalContentTop =
          pNormalCoverSide +
          (pNormalAvailableHeight - pNormalTotalContentHeight) / 2;

      pNormalInfoTop = pNormalContentTop;
      pNormalControlsTop = pNormalInfoTop + pNormalInfoHeight;
    }

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

    final double lNormalControlsScale = (lNormalControlsWidth / PlaybackHeroCardUiTuning.lControlsScaleBase)
        .clamp(0.85, 1.8);
    final double lNormalSingleButtonWidth = PlaybackHeroCardUiTuning.controlsTopButtonsHeight * lNormalControlsScale;
    final double lNormalGapWidth = PlaybackHeroCardUiTuning.topButtonsInnerGap * lNormalControlsScale;
    final double lNormalButtonsRowWidth = 7 * lNormalSingleButtonWidth + 6 * lNormalGapWidth;

    // When the gap between controls and cover is >= 80.0, the title area is at full width (lNormalControlsWidth).
    // As the gap shrinks from 80.0 to 0.0, the title area width gradually shrinks to align with the button area (lNormalButtonsRowWidth).
    const double gapStartShrink = 80.0;
    const double gapEndShrink = 0.0;
    final double gap = lNormalControlsLeft - lNormalCoverRightEdge;
    final double lNormalInfoWidthFactor = ((gap - gapEndShrink) / (gapStartShrink - gapEndShrink))
        .clamp(0.0, 1.0);
    final double lNormalInfoWidthAdjusted = lNormalButtonsRowWidth +
        (lNormalControlsWidth - lNormalButtonsRowWidth) * lNormalInfoWidthFactor;

    final double lNormalInfoLeftAdjusted = lNormalControlsLeft +
        (lNormalControlsWidth - lNormalInfoWidthAdjusted) / 2;

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
            ? PlaybackHeroCardUiTuning.waveformLandscapeHeight
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
    // 左侧列的目标宽度在普通歌词模式下只跟高度相关，在苹果歌词模式下为1:1宽度比。
    const lLyricsTopPadding = 16.0;
    const lLyricsOuterLeftPadding = 48.0;
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

    final double lLyricsColumnWidth;
    final double lLyricsLyricsLeft;
    final double lLyricsLyricsWidth;
    final double lLyricsScale;

    if (lyricsStyle == LyricsStyle.apple) {
      final double rightRatio = PlaybackHeroCardUiTuning.appleLyricsRightPanelRatio;
      final double leftRatio = 1.0 - rightRatio;
      lLyricsColumnWidth = width * leftRatio;
      lLyricsLyricsLeft = width * leftRatio + 24.0;
      lLyricsLyricsWidth = math.max(0.0, width * rightRatio - 24.0 - 48.0);
    } else {
      final double lLyricsMaxColumnWidth = math.min(width * 0.45, 800.0);
      lLyricsColumnWidth = (width * 0.20).clamp(
        math.min(380.0, lLyricsMaxColumnWidth),
        lLyricsMaxColumnWidth,
      );
      lLyricsLyricsLeft = lLyricsOuterLeftPadding + lLyricsColumnWidth + lLyricsInnerLeftPadding;
      lLyricsLyricsWidth = math.max(
        0.0,
        width - lLyricsLyricsLeft - 32.0,
      );
    }

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

    if (lyricsStyle == LyricsStyle.apple) {
      // For Apple Style: must fit both vertically and horizontally within the left column
      // Height adaptation: 0.75 of the screen height acts as the maximum control height limit.
      // It only starts shrinking together with the window when the window is small enough to require compression.
      final double constantHeight = lLyricsCoverInfoSpacing + lLyricsInfoControlsSpacing;
      final double scalableHeight = lLyricsPreferredTotalHeight - constantHeight;

      _maxWindowHeightSeen = math.max(_maxWindowHeightSeen, height);
      double screenHeight = _maxWindowHeightSeen;
      if (screenHeight <= 0.0) {
        try {
          final view = View.of(context);
          screenHeight = view.display.size.height / view.display.devicePixelRatio;
        } catch (_) {
          screenHeight = height;
        }
      }

      final double maxControlsHeight = screenHeight * 0.75;
      final double targetOccupiedHeight = math.min(maxControlsHeight, lLyricsAvailableHeight);

      final double heightScale = targetOccupiedHeight >= lLyricsPreferredTotalHeight
          ? 1.0
          : (scalableHeight <= 0.0
              ? 1.0
              : math.max(0.0, targetOccupiedHeight - constantHeight) / scalableHeight);

      final double maxHorizontalSpace = math.max(120.0, lLyricsColumnWidth - 64.0);
      final double lLyricsWidthFitScale = maxHorizontalSpace / (lLyricsPreferredCoverSide * lLyricsWidthScale);
      lLyricsScale = lLyricsPreferredTotalHeight <= 0.0
          ? 1.0
          : math.min(
              1.0,
              math.min(
                heightScale,
                lLyricsWidthFitScale,
              ),
            );
    } else {
      lLyricsScale = lLyricsPreferredTotalHeight <= 0.0
          ? 1.0
          : math.min(1.0, lLyricsAvailableHeight / lLyricsPreferredTotalHeight);
    }

    final lLyricsCoverSide =
        lLyricsPreferredCoverSide * lLyricsWidthScale * lLyricsScale;
    final double lLyricsItemWidth = lLyricsCoverSide;
    final lLyricsInfoHeight =
        lLyricsInfoBaseHeight * lLyricsWidthScale * lLyricsScale;
    final lLyricsControlsHeight =
        lLyricsControlsBaseHeight * lLyricsWidthScale * lLyricsScale;
    final double lLyricsCoverTop;
    if (lyricsStyle == LyricsStyle.apple) {
      final double lLyricsActualTotalHeight = lLyricsCoverSide +
          lLyricsCoverInfoSpacing +
          lLyricsInfoHeight +
          lLyricsInfoControlsSpacing +
          lLyricsControlsHeight;
      lLyricsCoverTop = math.max(16.0, (height - lLyricsActualTotalHeight) / 2);
    } else {
      lLyricsCoverTop = lLyricsTopPadding;
    }

    // 居中对齐逻辑：封面、信息区和控制区在列宽内统一居中对齐
    // Centering logic: cover, info and controls are centered within the column and aligned in width
    // 移除离散的 isLarge 逻辑，改用连续的百分比缩放
    // Remove discrete isLarge logic, use continuous percentage scaling
    final currentControlsScale = _lerp2DSmooth(
      // 竖屏：基于宽度进行缩放，稍微增加基准，让按钮在标准屏幕上保持舒适大小
      (width / PlaybackHeroCardUiTuning.pControlsScaleBase).clamp(0.9, 1.15),
      1.0,
      // 横屏普通模式：基于列宽进行缩放，放宽最小缩放限制以允许在小窗口下更自然的布局
      (lNormalControlsWidth / PlaybackHeroCardUiTuning.lControlsScaleBase)
          .clamp(0.85, 1.8),
      // 横屏歌词模式：结合宽度基准和高度缩放系数
      (lLyricsWidthScale * lLyricsScale).clamp(0.4, 2.0),
      tLyrics,
      tLand,
    ) * scaleFactor;

    final double lLyricsCoverLeft;
    final double lLyricsInfoLeft;
    final double lLyricsControlsLeft;

    if (lyricsStyle == LyricsStyle.apple) {
      final double leftAreaCenter = lLyricsColumnWidth / 2;
      lLyricsCoverLeft = (leftAreaCenter - lLyricsCoverSide / 2).clamp(
        32.0,
        math.max(32.0, lLyricsColumnWidth - lLyricsCoverSide - 24.0),
      );
      lLyricsInfoLeft = lLyricsCoverLeft;
      lLyricsControlsLeft = lLyricsCoverLeft;
    } else {
      lLyricsCoverLeft = lLyricsOuterLeftPadding;
      lLyricsInfoLeft = lLyricsCoverLeft;
      lLyricsControlsLeft = lLyricsCoverLeft;
    }

    final lLyricsInfoTop =
        lLyricsCoverTop + lLyricsCoverSide + lLyricsCoverInfoSpacing;

    final lLyricsControlsTop =
        lLyricsInfoTop + lLyricsInfoHeight + lLyricsInfoControlsSpacing;


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
        width: math.max(0.0, width - 48.0),
        height: pNormalInfoHeight,
        opacity: 1.0,
      ),
      pLyrics: _PlaybackPaneLayout(
        top: pLyricsInfoTop,
        left: pLyricsInfoLeft,
        width: math.max(0.0, width - pLyricsInfoLeft - 16.0),
        height: pLyricsInfoHeight,
        opacity: 1.0,
      ),
      lNormal: _PlaybackPaneLayout(
        top: lNormalInfoTop,
        left: lNormalInfoLeftAdjusted,
        width: lNormalInfoWidthAdjusted,
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
        width: math.max(0.0, width - 32.0),
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
        width: math.max(0.0, width - 32.0),
        height: math.max(0.0, height - pNormalInfoTop),
        opacity: 0.0,
      ),
      pLyrics: _PlaybackPaneLayout(
        top: pLyricsCoverTop + pLyricsCoverSide + 16.0,
        left: 16.0,
        width: math.max(0.0, width - 32.0),
        height: math.max(
          0.0,
          height - (pLyricsCoverTop + pLyricsCoverSide + 16.0),
        ),
        opacity: 1.0,
      ),
      lNormal: _PlaybackPaneLayout(
        top: 16.0,
        left: width,
        width: lLyricsColumnWidth,
        height: math.max(0.0, height - 32.0),
        opacity: 0.0,
      ),
      lLyrics: _PlaybackPaneLayout(
        top: 16.0,
        left: lLyricsLyricsLeft,
        width: lLyricsLyricsWidth,
        height: math.max(0.0, height - 32.0),
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
              // Deep soft ambient shadow
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 40,
                spreadRadius: 0,
                offset: const Offset(0, 16),
              ),
              // Crisp contact shadow
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                spreadRadius: -4,
                offset: const Offset(0, 8),
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

    final currentMusic = ref.watch(audioCurrentMusicProvider);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCoverTap,
      onSecondaryTapDown: (details) {
        _showCoverContextMenu(context, ref, details.globalPosition, currentMusic);
      },
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        _showCoverContextMenu(context, ref, details.globalPosition, currentMusic);
      },
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

    final titleSize = (isLandscape
            ? PlaybackHeroCardUiTuning.trackTitleStandardFont
            : lerpDouble(
                PlaybackHeroCardUiTuning.trackTitleStandardFont,
                PlaybackHeroCardUiTuning.trackTitlePortraitLyricsFont,
                transition,
              )!) *
        controlsScale;

    final artistSize = (isLandscape
            ? PlaybackHeroCardUiTuning.trackArtistStandardFont
            : lerpDouble(
                PlaybackHeroCardUiTuning.trackArtistStandardFont,
                PlaybackHeroCardUiTuning.trackArtistPortraitLyricsFont,
                transition,
              )!) *
        controlsScale;

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
              child: DefaultTextStyle(
                textAlign: TextAlign.start,
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  color: Colors.white,
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
                child: Builder(
                  builder: (context) {
                    final style = DefaultTextStyle.of(context).style;
                    return MarqueeText(
                      text: title,
                      style: style,
                      alignment: titleAlignment,
                    );
                  },
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
                  child: DefaultTextStyle(
                    textAlign: TextAlign.start,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: Colors.white70,
                      fontSize: artistSize,
                      height: 1.3,
                    ),
                    child: Builder(
                      builder: (context) {
                        final style = DefaultTextStyle.of(context).style;
                        return MarqueeText(
                          text: hasArtist && hasAlbum
                              ? '$rawArtist — $rawAlbum'
                              : (hasArtist
                                    ? rawArtist
                                    : (hasAlbum ? rawAlbum : l10n.unknown)),
                          style: style,
                          alignment: titleAlignment,
                        );
                      },
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
    required double width,
    required double layoutWidth,
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
    final sleepTimerRemaining = ref.watch(audioSleepTimerRemainingProvider);
    final isPlaying = ref.watch(audioIsPlayingProvider);
    final l10n = AppLocalizations.of(context)!;

    final isWaveformEnabled = ref.watch(
      settingsServiceProvider.select((s) => s.isWaveformProgressBarEnabled),
    );

    final size = MediaQuery.of(context).size;
    final settings = ref.read(settingsServiceProvider);
    final bool isSmallWindow = PlaybackPageUiTuning.isSmallWindow(
      size,
      isWaveformEnabled: settings.isWaveformProgressBarEnabled,
      isSmallWindowMode: settings.isSmallWindowMode,
    );
    final bool effectiveIsLandscape = isLandscape && !isSmallWindow;
    final bool effectiveIsLyricsMode = isLyricsMode && !isSmallWindow;

    final topButtonsCount = 7;
    final topButtonsGaps = topButtonsCount - 1;
    final singleButtonWidth =
        PlaybackHeroCardUiTuning.controlsTopButtonsHeight * controlsScale;
    final gapWidth =
        PlaybackHeroCardUiTuning.topButtonsInnerGap * controlsScale;
    final buttonsRowWidth =
        topButtonsCount * singleButtonWidth + topButtonsGaps * gapWidth;

    // 竖屏模式下如果启用波形进度条，则使用叠层布局 (Overlay layout in portrait if waveform is enabled)
    final useOverlayStyle = !effectiveIsLandscape && !effectiveIsLyricsMode && isWaveformEnabled;

    final widthFactor = effectiveIsLandscape
        ? (lerpDouble(
            PlaybackHeroCardUiTuning.progressBarWidthFactor,
            1.0,
            tLyrics,
          )!)
        : PlaybackHeroCardUiTuning.portraitProgressBarWidthFactor;

    final unifiedWidth = effectiveIsLandscape
        ? math.max(0.0, lerpDouble(buttonsRowWidth, layoutWidth, tLyrics)!)
        : math.max(0.0, math.min(width - 32.0, buttonsRowWidth * widthFactor));

    // 提取公共组件 (Extract common components)
    Widget wrapWithMaybeFitted(Widget child, {bool fit = false}) {
      if (fit && unifiedWidth < buttonsRowWidth) {
        return SizedBox(
          width: unifiedWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              width: buttonsRowWidth,
              child: child,
            ),
          ),
        );
      }
      return SizedBox(width: unifiedWidth, child: child);
    }

    final topButtonsRow = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PlaybackHeroCardUiTuning.topButtonsHorizontalPadding,
      ),
      child: wrapWithMaybeFitted(
        fit: true,
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: singleButtonWidth,
                height: singleButtonWidth,
              ),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: singleButtonWidth,
                height: singleButtonWidth,
              ),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size:
                    PlaybackHeroCardUiTuning.topButtonsIconSize * controlsScale,
                color: isFavorite ? Colors.redAccent : Colors.white70,
              ),
              onPressed: currentMusic == null
                  ? null
                  : () async {
                      final playlistService = ref.read(playlistServiceProvider);
                      await playlistService.toggleFavoriteSong(currentMusic);
                    },
              tooltip: isFavorite
                  ? l10n.removeFromFavorites
                  : l10n.addToFavorites,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: singleButtonWidth,
                height: singleButtonWidth,
              ),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(
                getPlaylistModeIcon(playbackMode),
                size:
                    PlaybackHeroCardUiTuning.topButtonsIconSize *
                    controlsScale,
                color: Colors.white70,
              ),
              onPressed: onCyclePlaylistMode,
              onLongPress: onShowPlaylistModeSelector,
              tooltip: getPlaylistModeName(playbackMode, l10n),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: singleButtonWidth,
                height: singleButtonWidth,
              ),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(
                Icons.shuffle_rounded,
                size:
                    PlaybackHeroCardUiTuning.topButtonsIconSize *
                    controlsScale,
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
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: singleButtonWidth,
                height: singleButtonWidth,
              ),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            Tooltip(
              message: sleepTimerRemaining != null
                  ? l10n.sleepTimerRemaining(
                      _formatSleepTimer(sleepTimerRemaining),
                    )
                  : l10n.sleepTimer,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSleepTimerTap,
                child: Container(
                  width:
                      PlaybackHeroCardUiTuning.controlsTopButtonsHeight *
                      controlsScale,
                  height:
                      PlaybackHeroCardUiTuning.controlsTopButtonsHeight *
                      controlsScale,
                  alignment: Alignment.topCenter,
                  padding: EdgeInsets.only(
                    top:
                        (PlaybackHeroCardUiTuning.controlsTopButtonsHeight -
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
                        size:
                            PlaybackHeroCardUiTuning.topButtonsIconSize *
                            controlsScale,
                        color: sleepTimerRemaining != null
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
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: singleButtonWidth,
                height: singleButtonWidth,
              ),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

    final controlIconColor = currentThemeColorsMap['darkVibrant'] ??
        currentThemeColorsMap['darkMuted'] ??
        Colors.black;

    // 内部辅助组件：构建带背景和阴影的次级控制按钮 (Internal helper: build secondary control)
    Widget buildSecondaryControl({
      required Widget Function(Color color, bool isWhiteBg) iconBuilder,
      required VoidCallback? onPressed,
      required double circleSize,
      String? tooltip,
    }) {
      if (useOverlayStyle) {
        return Container(
          width: circleSize * controlsScale,
          height: circleSize * controlsScale,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 10 * controlsScale,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: iconBuilder(controlIconColor, true),
            onPressed: onPressed,
            tooltip: tooltip,
          ),
        );
      } else {
        // 其他情况一律都是原来的白色图标 (Original white icon style)
        return IconButton(
          constraints: BoxConstraints.tightFor(
            width: circleSize * controlsScale,
            height: circleSize * controlsScale,
          ),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: iconBuilder(Colors.white, false),
          onPressed: onPressed,
          tooltip: tooltip,
        );
      }
    }

    final mainControlsRow = wrapWithMaybeFitted(
      Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          buildSecondaryControl(
            circleSize: (useOverlayStyle ? 42 : 40),
            iconBuilder: (color, isWhiteBg) => Icon(
              showVisualizerToggle ? Icons.analytics : Icons.analytics_outlined,
              size: (isWhiteBg ? 22 : 24) * controlsScale,
              color: showVisualizerToggle ? color : color.withValues(alpha: 0.6),
            ),
            onPressed: onToggleVisualizer,
            tooltip: AppLocalizations.of(context)!.visualizer,
          ),
          buildSecondaryControl(
            circleSize: (useOverlayStyle ? 56 : 60),
            iconBuilder: (color, isWhiteBg) => Icon(
              Icons.skip_previous_rounded,
              size: (isWhiteBg ? 34 : 52) * controlsScale,
              color: color,
            ),
            onPressed: onPrevious,
            tooltip: l10n.previous,
          ),
          useOverlayStyle
              ? Container(
                  width: 72 * controlsScale,
                  height: 72 * controlsScale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10 * controlsScale,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: AnimatedPlayPauseButton(
                    isPlaying: isPlaying,
                    onPressed: onPlayPause,
                    color: controlIconColor,
                    size: 42 * controlsScale,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    tooltip: isPlaying ? l10n.pause : l10n.play,
                  ),
                )
              : SizedBox(
                  width: 60 * controlsScale,
                  height: 60 * controlsScale,
                  child: AnimatedPlayPauseButton(
                    isPlaying: isPlaying,
                    onPressed: onPlayPause,
                    color: Colors.white,
                    size: 52 * controlsScale,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    tooltip: isPlaying ? l10n.pause : l10n.play,
                  ),
                ),
          buildSecondaryControl(
            circleSize: (useOverlayStyle ? 56 : 60),
            iconBuilder: (color, isWhiteBg) => Icon(
              Icons.skip_next_rounded,
              size: (isWhiteBg ? 34 : 48) * controlsScale,
              color: color,
            ),
            onPressed: onNext,
            tooltip: l10n.next,
          ),
          buildSecondaryControl(
            circleSize: (useOverlayStyle ? 42 : 40),
            iconBuilder: (color, isWhiteBg) => GestureDetector(
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
                child: Icon(
                  getVolumeIcon(ref.watch(audioVolumeProvider)),
                  size: (isWhiteBg ? 22 : 24) * controlsScale,
                  color: color,
                ),
              ),
            ),
            onPressed: onVolumeTap,
            tooltip: l10n.volume,
          ),
        ],
      ),
    );

    if (useOverlayStyle) {
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
              PlaybackOverlayProgressTimeLayer(
                key: const ValueKey('playback_overlay_progress_time_layer'),
                currentMusic: currentMusic,
                controlsScale: controlsScale,
                totalWidth: width,
                overrideProgress: overrideProgress,
                overridePosition: overridePosition,
                overrideWaveform: overrideWaveform,
                onScrubbing: onScrubbing,
                onSeek: onSeek,
                isLandscape: effectiveIsLandscape,
              ),
              // 3. 播放控制按钮叠在上面，不跟随缩放 (Playback controls on top, no scaling)
              mainControlsRow,
            ],
          ),
        ],
      );
    }

    // 默认布局 (Default layout)
    if (effectiveIsLandscape) {
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
          PlaybackProgressSection(
            key: const ValueKey('playback_progress_section_landscape'),
            currentMusic: currentMusic,
            controlsScale: controlsScale,
            tLyrics: tLyrics,
            isLandscape: effectiveIsLandscape,
            buttonsRowWidth: unifiedWidth,
            overrideProgress: overrideProgress,
            overridePosition: overridePosition,
            overrideWaveform: overrideWaveform,
            onScrubbing: onScrubbing,
            onSeek: onSeek,
          ),
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
        PlaybackProgressSection(
          key: const ValueKey('playback_progress_section_portrait'),
          currentMusic: currentMusic,
          controlsScale: controlsScale,
          tLyrics: tLyrics,
          isLandscape: effectiveIsLandscape,
          buttonsRowWidth: unifiedWidth,
          overrideProgress: overrideProgress,
          overridePosition: overridePosition,
          overrideWaveform: overrideWaveform,
          onScrubbing: onScrubbing,
          onSeek: onSeek,
        ),
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
}

class _ZeroPaddingTrackShape extends RoundedRectSliderTrackShape {
  const _ZeroPaddingTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 4.0;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

class PlaybackProgressSection extends ConsumerWidget {
  final MusicFile? currentMusic;
  final double controlsScale;
  final double tLyrics;
  final bool isLandscape;
  final double buttonsRowWidth;
  final double? overrideProgress;
  final Duration? overridePosition;
  final List<double>? overrideWaveform;
  final ValueChanged<double>? onScrubbing;
  final ValueChanged<double>? onSeek;

  const PlaybackProgressSection({
    super.key,
    required this.currentMusic,
    required this.controlsScale,
    required this.tLyrics,
    required this.isLandscape,
    required this.buttonsRowWidth,
    this.overrideProgress,
    this.overridePosition,
    this.overrideWaveform,
    this.onScrubbing,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(audioProgressProvider);
    final position = ref.watch(audioPositionProvider);
    final duration = ref.watch(audioDurationProvider);
    final isPlaying = ref.watch(audioIsPlayingProvider);
    final isWaveformEnabled = ref.watch(
      settingsServiceProvider.select((s) => s.isWaveformProgressBarEnabled),
    );
    final currentThemeColorsMap = ref.watch(audioCurrentThemeColorsMapProvider);
    final controlIconColor = currentThemeColorsMap['darkVibrant'] ??
        currentThemeColorsMap['darkMuted'] ??
        Colors.black;

    final waveform = overrideWaveform ?? currentMusic?.waveform ?? const [];
    final displayProgress = overrideProgress ?? progress.clamp(0.0, 1.0);

    // Calculate the horizontal padding to align with the outer visual edges of the outermost icons
    // Top button size: 44 * controlsScale, icon size: 22 * controlsScale (margin is 11 * controlsScale)
    // Bottom button size: 40 * controlsScale, icon size: 24 * controlsScale (margin is 8 * controlsScale)
    // We choose 11.0 * controlsScale to align with the visual boundaries of the outermost icons.
    final double horizontalPadding = isLandscape ? 11.0 * controlsScale : 0.0;

    Widget buildStandardSlider(BuildContext context, double displayProgress, double controlsScale, {bool noPadding = false}) {
      final double pad = noPadding
          ? horizontalPadding
          : PlaybackHeroCardUiTuning.waveformStandardHorizontalPadding;

      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: pad,
        ),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4 * controlsScale,
            trackShape: isLandscape ? const _ZeroPaddingTrackShape() : null,
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

    return SizedBox(
      width: buttonsRowWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(
            builder: (context) {
              if (isWaveformEnabled) {
                return Builder(
                  builder: (context) {
                    final size = MediaQuery.of(context).size;
                    final settings = ref.watch(settingsServiceProvider);
                    final isMinimized = ref.watch(isWindowMinimizedProvider);
                    final bool isSmallWindow = PlaybackPageUiTuning.isSmallWindow(
                      size,
                      isWaveformEnabled: settings.isWaveformProgressBarEnabled,
                      isSmallWindowMode: settings.isSmallWindowMode,
                    );
                    final double overflowScale = isLandscape
                        ? 1.0
                        : (isSmallWindow
                            ? 1.0
                            : PlaybackHeroCardUiTuning.portraitWaveformOverflowScale);

                    final widget = Padding(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                      child: WaveformProgressBar(
                        waveform: waveform,
                        progress: displayProgress,
                        duration: duration,
                        isPlaying: isPlaying,
                        onScrubbing: onScrubbing ?? (_) {},
                        onSeek: onSeek ?? (_) {},
                        isWindowMinimized: isMinimized,
                        height: (isLandscape
                                ? PlaybackHeroCardUiTuning.waveformLandscapeHeight
                                : PlaybackHeroCardUiTuning.waveformPortraitLyricsHeight) *
                            controlsScale,
                        barWidth: (isLandscape
                                ? PlaybackHeroCardUiTuning.waveformBarWidthLandscape
                                : PlaybackHeroCardUiTuning.waveformBarWidth) /
                            overflowScale,
                        barGap: (isLandscape
                                ? PlaybackHeroCardUiTuning.waveformBarGapLandscape
                                : PlaybackHeroCardUiTuning.waveformBarGap) /
                            overflowScale,
                      ),
                    );

                    if (!isLandscape) {
                      return Transform.scale(
                        scaleX: overflowScale,
                        child: widget,
                      );
                    }
                    return widget;
                  },
                );
              }
              return buildStandardSlider(
                context,
                displayProgress,
                controlsScale,
                noPadding: true,
              );
            },
          ),
          SizedBox(
            height: (isLandscape ? PlaybackHeroCardUiTuning.controlsTimeGap : 8.0) * controlsScale,
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? horizontalPadding : 8.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isLandscape || !isWaveformEnabled)
                  Text(
                    formatDuration(overridePosition ?? position),
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: math.max(PlaybackHeroCardUiTuning.minProgressTimeFontSize, 12 * controlsScale),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      formatDuration(overridePosition ?? position),
                      style: TextStyle(
                        color: controlIconColor,
                        fontSize: math.max(PlaybackHeroCardUiTuning.minProgressTimeFontSize, 11 * controlsScale),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (isLandscape || !isWaveformEnabled)
                  Text(
                    formatDuration(duration),
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: math.max(PlaybackHeroCardUiTuning.minProgressTimeFontSize, 12 * controlsScale),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      formatDuration(duration),
                      style: TextStyle(
                        color: controlIconColor,
                        fontSize: math.max(PlaybackHeroCardUiTuning.minProgressTimeFontSize, 11 * controlsScale),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlaybackOverlayProgressTimeLayer extends ConsumerWidget {
  final MusicFile? currentMusic;
  final double controlsScale;
  final double totalWidth;
  final double? overrideProgress;
  final Duration? overridePosition;
  final List<double>? overrideWaveform;
  final ValueChanged<double>? onScrubbing;
  final ValueChanged<double>? onSeek;
  final bool isLandscape;

  const PlaybackOverlayProgressTimeLayer({
    super.key,
    required this.currentMusic,
    required this.controlsScale,
    required this.totalWidth,
    required this.isLandscape,
    this.overrideProgress,
    this.overridePosition,
    this.overrideWaveform,
    this.onScrubbing,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(audioProgressProvider);
    final position = ref.watch(audioPositionProvider);
    final duration = ref.watch(audioDurationProvider);
    final isPlaying = ref.watch(audioIsPlayingProvider);
    final waveform = overrideWaveform ?? currentMusic?.waveform ?? const [];
    final displayProgress = overrideProgress ?? progress.clamp(0.0, 1.0);
    final currentThemeColorsMap = ref.watch(audioCurrentThemeColorsMapProvider);
    final controlIconColor = currentThemeColorsMap['darkVibrant'] ??
        currentThemeColorsMap['darkMuted'] ??
        Colors.black;

    return Stack(
      alignment: Alignment.center,
      children: [
        // 1. 只有波形进度条进行缩放 (Only waveform is scaled)
        Builder(
          builder: (context) {
            final size = MediaQuery.of(context).size;
            final settings = ref.watch(settingsServiceProvider);
            final isMinimized = ref.watch(isWindowMinimizedProvider);
            final bool isSmallWindow = PlaybackPageUiTuning.isSmallWindow(
              size,
              isWaveformEnabled: settings.isWaveformProgressBarEnabled,
              isSmallWindowMode: settings.isSmallWindowMode,
            );
            final double overflowScale = isSmallWindow
                ? 1.0
                : PlaybackHeroCardUiTuning.portraitWaveformOverflowScale;

            return Transform.scale(
              scaleX: overflowScale,
              child: SizedBox(
                width: totalWidth,
                child: WaveformProgressBar(
                  waveform: waveform,
                  progress: displayProgress,
                  duration: duration,
                  isPlaying: isPlaying,
                  onScrubbing: onScrubbing ?? (_) {},
                  onSeek: onSeek ?? (_) {},
                  isWindowMinimized: isMinimized,
                  height: PlaybackHeroCardUiTuning.waveformOverlayHeight * controlsScale,
                  barWidth: (isLandscape
                          ? PlaybackHeroCardUiTuning.waveformBarWidthLandscape
                          : PlaybackHeroCardUiTuning.waveformBarWidth) /
                      overflowScale,
                  barGap: (isLandscape
                          ? PlaybackHeroCardUiTuning.waveformBarGapLandscape
                          : PlaybackHeroCardUiTuning.waveformBarGap) /
                      overflowScale,
                ),
              ),
            );
          },
        ),
        // 2. 时间文字单独平移，避免拉伸 (Time text translated separately to avoid stretching)
        Builder(
          builder: (context) {
            final size = MediaQuery.of(context).size;
            final settings = ref.watch(settingsServiceProvider);
            final bool isSmallWindow = PlaybackPageUiTuning.isSmallWindow(
              size,
              isWaveformEnabled: settings.isWaveformProgressBarEnabled,
              isSmallWindowMode: settings.isSmallWindowMode,
            );
            final double overflowScale = isSmallWindow
                ? 1.0
                : PlaybackHeroCardUiTuning.portraitWaveformOverflowScale;

            final screenWidth = MediaQuery.of(context).size.width;
            final pagePadding = PlaybackPageUiTuning.normalPortraitHorizontalPadding;
            const minScreenMargin = 32.0;

            final cardWidth = screenWidth - (pagePadding * 2);
            final fittedScale = cardWidth / totalWidth;

            final rawShift = (PlaybackHeroCardUiTuning.waveformOverlayTimeSide - totalWidth / 2) *
                (overflowScale - 1) * 0.8;

            final safeFittedScale = (fittedScale.isFinite && fittedScale > 0) ? fittedScale : 1.0;
            final minAllowedShift = (minScreenMargin - pagePadding) / safeFittedScale -
                PlaybackHeroCardUiTuning.waveformOverlayTimeSide;

            final lowerBound = math.min(
              minAllowedShift.isFinite ? minAllowedShift : 0.0,
              0.0,
            );
            final safeShift = rawShift.isFinite ? rawShift.clamp(lowerBound, 0.0) : 0.0;

            return SizedBox(
              width: totalWidth,
              height: PlaybackHeroCardUiTuning.waveformOverlayHeight * controlsScale,
              child: Stack(
                children: [
                  Positioned(
                    left: PlaybackHeroCardUiTuning.waveformOverlayTimeSide,
                    bottom: PlaybackHeroCardUiTuning.waveformOverlayTimeBottom,
                    child: Transform.translate(
                      offset: Offset(safeShift, 0),
                      child: isLandscape
                          ? Text(
                              formatDuration(overridePosition ?? position),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: math.max(PlaybackHeroCardUiTuning.minProgressTimeFontSize, 12 * controlsScale),
                                fontWeight: FontWeight.bold,
                                shadows: const [
                                  Shadow(color: Colors.black45, blurRadius: 4),
                                ],
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(100),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                formatDuration(overridePosition ?? position),
                                style: TextStyle(
                                  color: controlIconColor,
                                  fontSize: math.max(PlaybackHeroCardUiTuning.minProgressTimeFontSize, 11 * controlsScale),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    right: PlaybackHeroCardUiTuning.waveformOverlayTimeSide,
                    bottom: PlaybackHeroCardUiTuning.waveformOverlayTimeBottom,
                    child: Transform.translate(
                      offset: Offset(-safeShift, 0),
                      child: isLandscape
                          ? Text(
                              formatDuration(duration),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: math.max(PlaybackHeroCardUiTuning.minProgressTimeFontSize, 12 * controlsScale),
                                fontWeight: FontWeight.bold,
                                shadows: const [
                                  Shadow(color: Colors.black45, blurRadius: 4),
                                ],
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(100),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                formatDuration(duration),
                                style: TextStyle(
                                  color: controlIconColor,
                                  fontSize: math.max(PlaybackHeroCardUiTuning.minProgressTimeFontSize, 11 * controlsScale),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
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
