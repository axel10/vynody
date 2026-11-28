import 'dart:async';
import 'dart:ui' show lerpDouble;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vynody/player/audio/android_usb_exclusive_controller.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'package:vynody/widgets/lyrics_panel.dart';
import 'package:vynody/widgets/playback_ui_tuning.dart';

import 'playback/playback_track_info.dart';
import 'playback/playback_controls.dart';
import 'playback/playback_album_art.dart';
import 'playback/playback_cover_flight.dart';
import 'playback/mini_player_card.dart';

export 'playback/playback_progress_section.dart';
export 'playback/playback_track_info.dart';
export 'playback/playback_controls.dart';
export 'playback/playback_album_art.dart';
export 'playback/mini_player_card.dart';

const String playbackHeroTag = 'player_capsule';

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
    this.leftAreaTotalHeight = 0.0,
  });

  final _PlaybackPaneLayout cover;
  final _PlaybackPaneLayout info;
  final _PlaybackPaneLayout controls;
  final _PlaybackPaneLayout lyrics;
  final TextAlign trackInfoAlign;
  final double controlsScale;
  final double leftAreaTotalHeight;
}

class PlaybackHeroCard extends ConsumerStatefulWidget {
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
    this.scrubProgressListenable,
    this.lyricsBottomSpacerHeight = 0.0,
    this.lyricsBottomTabBarHeight = 0.0,
    this.coverKey,
    this.lyricsKey,
    this.cardOriginOffset = Offset.zero,
    this.enableHero = true,
    this.animateLyricsTransition = true,
  });

  final bool isMini;
  final bool isLyricsMode;
  final bool animateLyricsTransition;
  final bool isLandscape;
  final bool isNext;
  final bool enableHero;
  final Offset cardOriginOffset;
  final bool showMiniVolumeSlider;
  final List<double>? overrideWaveform;
  final double? overrideProgress;
  final Duration? overridePosition;

  /// 拖动/抛掷进度条时的预览进度（null = 未在拖动）。
  ///
  /// 相比 [overrideProgress]/[overridePosition] 的“值传递”，这个 Listenable 不会
  /// 让上层页面为了更新一次进度而 setState，从而避免整页按指针频率重建。
  final ValueListenable<double?>? scrubProgressListenable;
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
  final void Function(Uint8List? artworkBytes, String? sourcePath)?
  onCarouselAnimationComplete;
  final double lyricsBottomSpacerHeight;
  final double lyricsBottomTabBarHeight;
  final GlobalKey? coverKey;
  final GlobalKey? lyricsKey;

  @override
  ConsumerState<PlaybackHeroCard> createState() => _PlaybackHeroCardState();
}

class _PlaybackHeroCardState extends ConsumerState<PlaybackHeroCard>
    with SingleTickerProviderStateMixin {
  static const double _kLyricsCollapseThreshold = 12.0;
  static const double _kLyricsExpandThreshold = 20.0;

  bool _isPortraitLyricsControlsExpanded = false;
  double _lyricsScrollDeltaAccumulator = 0.0;
  bool _animateLandscapeTransition = false;
  Timer? _landscapeTransitionTimer;

  /// 歌词面板「正处在转场中」的标记，交给 `_LyricsPanelTransitionWrapper`
  /// 决定要不要跟随 `audioPositionProvider`。
  ///
  /// 必须是 State 字段：以前在 `_buildFullCard` 里每次 build 新建一个，
  /// 转场里每帧都换实例 → wrapper 的 `didUpdateWidget` 每帧重挂 listener
  /// 并把 `_isTransitioning` 重置回 false，再被 microtask 改回 true 触发
  /// setState，等于每帧白重建两次。
  final ValueNotifier<bool> _lyricsPanelTransitioning = ValueNotifier<bool>(
    false,
  );

  /// 竖屏歌词页「滚动展开控制面板」的进度。以前这段动画由一个包住整张卡片
  /// 的 TweenAnimationBuilder 驱动，每帧都会重建子树；改成 controller 后
  /// 只有订阅它的 AnimatedBuilder 会重建。
  late final AnimationController _portraitControlsExpandController;
  late final CurvedAnimation _portraitControlsExpandAnimation;

  @override
  void initState() {
    super.initState();
    _portraitControlsExpandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _portraitControlsExpandAnimation = CurvedAnimation(
      parent: _portraitControlsExpandController,
      curve: Curves.easeOutCubic,
      // reverse 时 controller 从 1 走到 0，直接复用正向曲线会变成「先卡后窜」；
      // flipped 还原成旧的 TweenAnimationBuilder(1 → 0) 那种「先快后慢」。
      reverseCurve: Curves.easeOutCubic.flipped,
    );
  }

  @override
  void dispose() {
    _landscapeTransitionTimer?.cancel();
    _lyricsPanelTransitioning.dispose();
    _portraitControlsExpandAnimation.dispose();
    _portraitControlsExpandController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PlaybackHeroCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLandscape != widget.isLandscape) {
      final flightProgress = ref
          .read(playbackCoverFlightControllerProvider)
          .progressNotifier
          .value;
      if (flightProgress > 0.95) {
        _animateLandscapeTransition = true;
        _landscapeTransitionTimer?.cancel();
        _landscapeTransitionTimer = Timer(
          PlaybackHeroCardUiTuning.transitionDuration,
          () {
            if (mounted) {
              setState(() {
                _animateLandscapeTransition = false;
              });
            }
          },
        );
      } else {
        _landscapeTransitionTimer?.cancel();
        _animateLandscapeTransition = false;
      }
    }
    if (oldWidget.isLyricsMode && !widget.isLyricsMode) {
      Future.delayed(PlaybackHeroCardUiTuning.transitionDuration, () {
        if (mounted && !widget.isLyricsMode) {
          setState(() {
            _isPortraitLyricsControlsExpanded = false;
          });
          // 面板此时已在屏幕外，直接归位，不再补一段收起动画。
          _resetPortraitControlsExpandValue();
        }
      });
    } else if (!oldWidget.isLyricsMode && widget.isLyricsMode) {
      _isPortraitLyricsControlsExpanded = false;
      _resetPortraitControlsExpandValue();
    }
  }

  /// `didUpdateWidget` 发生在 build 阶段，直接给 controller 赋值会触发
  /// 订阅方的 setState-during-build，统一推到帧末。
  void _resetPortraitControlsExpandValue() {
    if (_portraitControlsExpandController.value == 0.0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _portraitControlsExpandController.value = 0.0;
    });
  }

  void _expandPortraitLyricsControls() {
    if (!mounted) return;
    if (!_isPortraitLyricsControlsExpanded) {
      setState(() {
        _isPortraitLyricsControlsExpanded = true;
      });
      _portraitControlsExpandController.forward();
    }
  }

  void _collapsePortraitLyricsControls() {
    if (!mounted) return;
    if (_isPortraitLyricsControlsExpanded) {
      setState(() {
        _isPortraitLyricsControlsExpanded = false;
      });
      _portraitControlsExpandController.reverse();
    }
  }

  void _handleLyricsScrollDelta(double delta) {
    if (delta > 0) {
      if (_lyricsScrollDeltaAccumulator < 0) {
        _lyricsScrollDeltaAccumulator = 0.0;
      }
      _lyricsScrollDeltaAccumulator += delta;
      if (_lyricsScrollDeltaAccumulator >= _kLyricsCollapseThreshold) {
        _collapsePortraitLyricsControls();
      }
    } else if (delta < 0) {
      if (_lyricsScrollDeltaAccumulator > 0) {
        _lyricsScrollDeltaAccumulator = 0.0;
      }
      _lyricsScrollDeltaAccumulator += delta;
      if (_lyricsScrollDeltaAccumulator <= -_kLyricsExpandThreshold) {
        _expandPortraitLyricsControls();
      }
    }
  }

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
    final dpr = MediaQuery.devicePixelRatioOf(context);
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

  _PlaybackPaneLayout _lerpPaneLayout(
    _PlaybackPaneLayout a,
    _PlaybackPaneLayout b,
    double t,
  ) {
    return _PlaybackPaneLayout(
      top: lerpDouble(a.top, b.top, t) ?? a.top,
      left: lerpDouble(a.left, b.left, t) ?? a.left,
      width: lerpDouble(a.width, b.width, t) ?? a.width,
      height: lerpDouble(a.height, b.height, t) ?? a.height,
      opacity: lerpDouble(a.opacity, b.opacity, t) ?? a.opacity,
    );
  }

  _PlaybackCardLayout _lerpPlaybackCardLayout(
    _PlaybackCardLayout start,
    _PlaybackCardLayout end,
    double t,
  ) {
    if (t <= 0.0) return start;
    if (t >= 1.0) return end;
    return _PlaybackCardLayout(
      cover: _lerpPaneLayout(start.cover, end.cover, t),
      info: _lerpPaneLayout(start.info, end.info, t),
      controls: _lerpPaneLayout(start.controls, end.controls, t),
      lyrics: _lerpPaneLayout(start.lyrics, end.lyrics, t),
      trackInfoAlign: t < 0.5 ? start.trackInfoAlign : end.trackInfoAlign,
      controlsScale: lerpDouble(start.controlsScale, end.controlsScale, t) ??
          start.controlsScale,
      leftAreaTotalHeight:
          lerpDouble(start.leftAreaTotalHeight, end.leftAreaTotalHeight, t) ??
              start.leftAreaTotalHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = Material(
      type: MaterialType.transparency,
      child: widget.isMini
          ? MiniPlayerCard(
              showMiniVolumeSlider: widget.showMiniVolumeSlider,
              onMiniTap: widget.onMiniTap,
              onPrevious: widget.onPrevious,
              onPlayPause: widget.onPlayPause,
              onNext: widget.onNext,
              onScrubbing: widget.onScrubbing,
              onSeek: widget.onSeek,
              onVolumeTap: widget.onVolumeTap,
              onVolumeChanged: widget.onVolumeChanged,
              onVolumeScroll: widget.onVolumeScroll,
              onMiniMouseExit: widget.onMiniMouseExit,
            )
          : _buildFullCard(context),
    );

    return card;
  }

  Widget _buildFullCard(BuildContext context) {
    final lyricsAnimDuration = widget.animateLyricsTransition
        ? PlaybackHeroCardUiTuning.transitionDuration
        : Duration.zero;
    const animDuration = PlaybackHeroCardUiTuning.transitionDuration;
    const animCurve = Curves.fastOutSlowIn;
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    final size = MediaQuery.sizeOf(context);
    final settings = ref.watch(settingsServiceProvider);

    final bool isLowMidEnd = ref.watch(isLowMidEndDeviceProvider);
    final isEffectiveWaveform = ref.watch(isEffectiveWaveformEnabledProvider);

    final bool isSmallWindow = PlaybackPageUiTuning.isSmallWindow(
      size,
      isWaveformEnabled: isEffectiveWaveform,
      isSmallWindowMode: settings.isSmallWindowMode,
    );
    final bool effectiveIsLandscape = widget.isLandscape && !isSmallWindow;
    final bool effectiveIsLyricsMode = widget.isLyricsMode && !isSmallWindow;

    final isTransitioningNotifier = _lyricsPanelTransitioning;

    final bool expandPortraitLyricsControlsOnScroll = ref.watch(
      settingsServiceProvider.select(
        (s) => s.expandPortraitLyricsControlsOnScroll,
      ),
    );

    final bool shouldExpandControls =
        expandPortraitLyricsControlsOnScroll &&
        _isPortraitLyricsControlsExpanded &&
        !effectiveIsLandscape;

    final progressBarStyle = ref.watch(effectiveProgressBarStyleProvider);
    final bool showAudioInfo = ref.watch(showPlaybackAudioInfoRowProvider);
    final bool isScrollingWaveform =
        progressBarStyle == ProgressBarStyle.scrollingWaveform;
    final bool isFullWaveform =
        progressBarStyle == ProgressBarStyle.fullWaveform;
    final bool isOverlayStyle = isScrollingWaveform && !effectiveIsLandscape;

    // 展开进度只驱动「变换」，不参与整卡重建：之前 300ms 的
    // TweenAnimationBuilder 直接包住 LayoutBuilder，导致每帧都在 layout
    // 阶段重建整棵卡片子树（实测一次展开约 96ms / 约 15 帧）。
    // 注意这里只能用「设置开关 + 横竖屏」做门控：收起的第一帧
    // _isPortraitLyricsControlsExpanded 就已经是 false，若用它来切换动画
    // 对象，收起会直接跳到 0，动画整个消失。
    final Animation<double> expandProgress =
        (!effectiveIsLandscape && expandPortraitLyricsControlsOnScroll)
        ? _portraitControlsExpandAnimation
        : const AlwaysStoppedAnimation<double>(0.0);

    final double pNormalScale = PlaybackHeroCardUiTuning.portraitControlsScale(
      size.width,
      height: size.height,
      isSmallWindow: isSmallWindow,
    );
    final double audioInfoHeight = showAudioInfo
        ? (PlaybackHeroCardUiTuning.audioInfoGap +
            PlaybackHeroCardUiTuning.audioInfoHeight)
        : 0.0;
    final double pNormalControlsBaseIdealHeight =
        PlaybackHeroCardUiTuning.controlsTopButtonsHeight +
        (isOverlayStyle
            ? PlaybackHeroCardUiTuning.waveformStandardTimeRowSpacing
            : PlaybackHeroCardUiTuning.controlsRowPortraitGap) +
        (isOverlayStyle
            ? PlaybackHeroCardUiTuning.waveformOverlayHeight
            : (isFullWaveform
                ? PlaybackHeroCardUiTuning.waveformStaticPortraitHeight
                : 48.0)) +
        (isOverlayStyle
            ? 0.0
            : (8.0 +
                  PlaybackHeroCardUiTuning.controlsTimeRowHeight +
                  PlaybackHeroCardUiTuning.controlsRowPortraitGap +
                  PlaybackHeroCardUiTuning.controlsMainButtonsHeight)) +
        audioInfoHeight;
    final double expandedControlsHeight = math.max(
      110.0,
      pNormalControlsBaseIdealHeight * pNormalScale,
    );
    final double topButtonsAndGap =
        (PlaybackHeroCardUiTuning.controlsTopButtonsHeight +
            (isOverlayStyle
                ? PlaybackHeroCardUiTuning.waveformStandardTimeRowSpacing
                : PlaybackHeroCardUiTuning.controlsRowPortraitGap)) *
        pNormalScale;
    final double progressBarTopFromBottom = math.max(
      0.0,
      expandedControlsHeight - topButtonsAndGap,
    );
    // 底部留白只跟随展开/收起的终值，不逐帧插值：逐帧插值会打穿
    // LyricsPanel 的 needsRebuild 缓存，导致每帧重建全部歌词行。
    final double effectiveLyricsBottomSpacer =
        widget.lyricsBottomSpacerHeight +
        (shouldExpandControls ? (progressBarTopFromBottom + 16.0) : 0.0);
    // 但底部「淡出」必须跟着面板一起上下走，否则面板一动淡出就整块跳。
    // 所以淡出另走一条只驱动 ShaderMask 的通道：基准 + delta * 进度。
    final double lyricsBottomReserveDelta =
        (!effectiveIsLandscape && expandPortraitLyricsControlsOnScroll)
        ? (progressBarTopFromBottom + 16.0)
        : 0.0;

    final lyricsPanelWidget = _LyricsPanelTransitionWrapper(
      isTransitioning: isTransitioningNotifier,
      isLyricsMode: effectiveIsLyricsMode,
      lyricsBottomSpacerHeight: effectiveLyricsBottomSpacer,
      lyricsBottomReserveBase: widget.lyricsBottomSpacerHeight,
      lyricsBottomReserveProgress: expandProgress,
      lyricsBottomReserveDelta: lyricsBottomReserveDelta,
      lyricsBottomTabBarHeight: widget.lyricsBottomTabBarHeight,
    );

    final collapseButtonsInLandscapeLyrics = ref.watch(
      settingsServiceProvider.select(
        (s) => s.collapseButtonsInLandscapeLyrics,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.roundToDouble();
        final height = constraints.maxHeight.roundToDouble();

        // 展开位移：必须和 _buildPlaybackCardLayout 内部同一套基准（constraints
        // 尺寸），否则面板会停在偏一点的 y 上。
        final double portraitControlsExpandDy = -(
            widget.lyricsBottomTabBarHeight +
            widget.lyricsBottomSpacerHeight +
            16.0 +
            math.max(
              110.0,
              pNormalControlsBaseIdealHeight *
                  PlaybackHeroCardUiTuning.portraitControlsScale(
                    width,
                    height: height,
                    isSmallWindow: isSmallWindow,
                  ),
            ));

        final bool tickerEnabled = TickerMode.valuesOf(context).enabled;
        final flightController = ref.watch(
          playbackCoverFlightControllerProvider,
        );
        final Offset resolvedCardOrigin = Offset(
          widget.cardOriginOffset.dx + (constraints.maxWidth - width) / 2.0,
          widget.cardOriginOffset.dy + (constraints.maxHeight - height) / 2.0,
        );
        final landAnimDuration =
            (_animateLandscapeTransition && tickerEnabled)
            ? animDuration
            : Duration.zero;
        final double targetLand = effectiveIsLandscape ? 1.0 : 0.0;
        final double targetLyrics = effectiveIsLyricsMode ? 1.0 : 0.0;

        return TweenAnimationBuilder<double>(
          duration: landAnimDuration,
          curve: animCurve,
          tween: Tween<double>(
            begin: (_animateLandscapeTransition && tickerEnabled)
                ? null
                : targetLand,
            end: targetLand,
          ),
          child: lyricsPanelWidget,
          builder: (context, rawTLand, child) {
            final double tLand = (_animateLandscapeTransition && tickerEnabled)
                ? rawTLand
                : targetLand;
            final coverNormalLayout = _buildPlaybackCardLayout(
              context,
              width: width,
              height: height,
              tLyrics: 0.0,
              tLand: tLand,
              progressBarStyle: progressBarStyle,
              isSmallWindow: isSmallWindow,
              collapseButtonsInLandscapeLyrics:
                  collapseButtonsInLandscapeLyrics,
              uiScale: settings.uiScale,
              lyricsBottomTabBarHeight: widget.lyricsBottomTabBarHeight,
              lyricsBottomSpacerHeight: widget.lyricsBottomSpacerHeight,
              showAudioInfo: showAudioInfo,
            );

            final endLayout = _buildPlaybackCardLayout(
              context,
              width: width,
              height: height,
              tLyrics: 1.0,
              tLand: tLand,
              progressBarStyle: progressBarStyle,
              isSmallWindow: isSmallWindow,
              collapseButtonsInLandscapeLyrics:
                  collapseButtonsInLandscapeLyrics,
              uiScale: settings.uiScale,
              lyricsBottomTabBarHeight: widget.lyricsBottomTabBarHeight,
              lyricsBottomSpacerHeight: widget.lyricsBottomSpacerHeight,
              showAudioInfo: showAudioInfo,
            );

            bool lyricsTopRowActive(double expandProgressValue) =>
                effectiveIsLyricsMode &&
                (_isPortraitLyricsControlsExpanded || expandProgressValue > 0.0);

            Widget buildPortraitControls(double expandProgressValue) =>
                SizedBox(
                    key: const ValueKey(
                      'controls_sizing_box',
                    ),
                    width: coverNormalLayout.controls.width,
                    child: SizeLogger(
                      name: 'Controls',
                      child: PlaybackControls(
                        width: width,
                        layoutWidth: coverNormalLayout.controls.width,
                        controlsScale: coverNormalLayout.controlsScale,
                        tLyrics: lyricsTopRowActive(expandProgressValue)
                            ? 1.0
                            : 0.0,
                        topButtonsCollapseT: lyricsTopRowActive(
                          expandProgressValue,
                        )
                            ? expandProgressValue.clamp(0.0, 1.0)
                            : 0.0,
                        isLandscape: false,
                        isTransitioning: false,
                        showVisualizerToggle:
                            widget.showVisualizerToggle,
                        overrideProgress:
                            widget.overrideProgress,
                        overridePosition:
                            widget.overridePosition,
                        overrideWaveform:
                            widget.overrideWaveform,
                        scrubProgressListenable:
                            widget.scrubProgressListenable,
                        onShowMoreMenu:
                            widget.onShowMoreMenu,
                        onCyclePlaylistMode:
                            widget.onCyclePlaylistMode,
                        onShowPlaylistModeSelector:
                            widget.onShowPlaylistModeSelector,
                        onScrubbing: widget.onScrubbing,
                        onSeek: widget.onSeek,
                        onToggleVisualizer:
                            widget.onToggleVisualizer,
                        onTagCompletionTap:
                            widget.onTagCompletionTap,
                        onTagCompletionLongPress:
                            widget.onTagCompletionLongPress,
                        onSleepTimerTap:
                            widget.onSleepTimerTap,
                        onEqualizerTap:
                            widget.onEqualizerTap,
                        onPrevious: widget.onPrevious,
                        onPlayPause: widget.onPlayPause,
                        onNext: widget.onNext,
                        onVolumeTap: widget.onVolumeTap,
                        onVolumeDrag: widget.onVolumeDrag,
                        onVolumeScroll:
                            widget.onVolumeScroll,
                      ),
                    ),
                  );

            return TweenAnimationBuilder<double>(
              duration: (widget.animateLyricsTransition && tickerEnabled)
                  ? lyricsAnimDuration
                  : Duration.zero,
              curve: animCurve,
              tween: Tween<double>(
                begin: (widget.animateLyricsTransition && tickerEnabled)
                    ? null
                    : targetLyrics,
                end: targetLyrics,
              ),
              child: child,
              builder: (context, rawTLyrics, child) {
                final double tLyrics =
                    (widget.animateLyricsTransition && tickerEnabled)
                        ? rawTLyrics
                        : targetLyrics;
                final bool isTransitioning =
                    (tLyrics > 0.0 && tLyrics < 1.0) ||
                    (tLand > 0.0 && tLand < 1.0);
                if (_lyricsPanelTransitioning.value != isTransitioning) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted &&
                        _lyricsPanelTransitioning.value != isTransitioning) {
                      _lyricsPanelTransitioning.value = isTransitioning;
                    }
                  });
                }
                final bool isEnteringLyricsMode =
                    effectiveIsLyricsMode && (tLyrics > 0.0 && tLyrics < 1.0);
                final bool optimize = isTransitioning && isLowMidEnd;

                final double targetTLyrics =
                    effectiveIsLyricsMode ? 1.0 : 0.0;

                final layout = _lerpPlaybackCardLayout(
                  coverNormalLayout,
                  endLayout,
                  tLyrics,
                );

                final targetLayout =
                    targetTLyrics == 1.0 ? endLayout : coverNormalLayout;

                final double translationX =
                    layout.lyrics.left - endLayout.lyrics.left;
                final double translationY =
                    layout.lyrics.top - endLayout.lyrics.top;

                return ExcludeSemantics(
                  excluding: isTransitioning,
                  child: Listener(
                  onPointerSignal: (pointerSignal) {
                    if (!effectiveIsLandscape &&
                        effectiveIsLyricsMode &&
                        expandPortraitLyricsControlsOnScroll) {
                      if (pointerSignal is PointerScrollEvent) {
                        _handleLyricsScrollDelta(
                            pointerSignal.scrollDelta.dy);
                      }
                    }
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (!effectiveIsLandscape &&
                          effectiveIsLyricsMode &&
                          expandPortraitLyricsControlsOnScroll) {
                        if (notification is ScrollStartNotification) {
                          _lyricsScrollDeltaAccumulator = 0.0;
                        } else if (notification is ScrollUpdateNotification) {
                          if (notification.dragDetails != null &&
                              notification.scrollDelta != null) {
                            _handleLyricsScrollDelta(
                                notification.scrollDelta!);
                          }
                        } else if (notification is ScrollEndNotification) {
                          _lyricsScrollDeltaAccumulator = 0.0;
                        } else if (notification is UserScrollNotification) {
                          if (notification.direction ==
                              ScrollDirection.idle) {
                            _lyricsScrollDeltaAccumulator = 0.0;
                          }
                        }
                      }
                      return false;
                    },
                    child: SizedBox(
                    width: width,
                    height: height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: endLayout.lyrics.top,
                          left: endLayout.lyrics.left,
                          width: endLayout.lyrics.width,
                          height: endLayout.lyrics.height,
                          child: ExcludeSemantics(
                            excluding: isTransitioning,
                            child: RepaintBoundary(
                              child: Transform.translate(
                                offset: Offset(translationX, translationY),
                                child: IgnorePointer(
                                  ignoring: layout.lyrics.opacity < 0.5,
                                  child: RepaintBoundary(
                                    child: Consumer(
                                      builder: (context, ref, childWidget) {
                                        if (isTransitioningNotifier.value !=
                                            optimize) {
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                if (!mounted) return;
                                                isTransitioningNotifier.value =
                                                    optimize;
                                              });
                                        }
                                        final bool isOffstage =
                                            tLyrics == 0.0 &&
                                            !effectiveIsLyricsMode;
                                        final Widget lyricsWidget =
                                            widget.lyricsKey != null
                                                ? KeyedSubtree(
                                                    key: widget.lyricsKey,
                                                    child: child!,
                                                  )
                                                : child!;
                                        return Offstage(
                                          offstage: isOffstage,
                                          child: TickerMode(
                                            enabled: !isOffstage,
                                            child: lyricsWidget,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
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
                                final containerHeight =
                                    constraints.maxHeight;
                                final fadeStop = containerHeight > 0
                                    ? (48.0 / containerHeight).clamp(
                                        0.0,
                                        1.0,
                                      )
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
                                      color: Colors.black.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        if (!effectiveIsLandscape)
                          Positioned(
                            top: coverNormalLayout.controls.top,
                            left: coverNormalLayout.controls.left,
                            width: coverNormalLayout.controls.width,
                            height: coverNormalLayout.controls.height,
                            child: ExcludeSemantics(
                              excluding: isTransitioning,
                              child: AnimatedBuilder(
                                animation: expandProgress,
                                builder: (context, _) {
                                  final double expandT = expandProgress.value;
                                  return Transform.translate(
                                    offset: Offset(
                                      layout.controls.left -
                                          coverNormalLayout.controls.left,
                                      layout.controls.top -
                                          coverNormalLayout.controls.top +
                                          tLyrics *
                                              expandT *
                                              portraitControlsExpandDy,
                                    ),
                                    child: RepaintBoundary(
                                      child: IgnorePointer(
                                        ignoring:
                                            layout.controls.opacity < 0.05 &&
                                            expandT < 0.05,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.topCenter,
                                          child: buildPortraitControls(
                                            expandT,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          )
                        else
                          Positioned(
                            top: layout.controls.top,
                            left: layout.controls.left,
                            width: layout.controls.width,
                            height: layout.controls.height +
                                (effectiveIsLandscape ? 36.0 : 0.0),
                            child: IgnorePointer(
                              ignoring: layout.controls.opacity < 0.05,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: effectiveIsLandscape
                                    ? Alignment.center
                                    : Alignment.topCenter,
                                child: Consumer(
                                  builder: (context, ref, child) {
                                    final double layoutWidth =
                                        (effectiveIsLandscape && optimize)
                                            ? targetLayout.controls.width
                                            : layout.controls.width;
                                    return SizedBox(
                                      key: const ValueKey(
                                        'controls_sizing_box',
                                      ),
                                      width: layoutWidth,
                                      child: SizeLogger(
                                        name: 'Controls',
                                        child: PlaybackControls(
                                          width: width,
                                          layoutWidth: layoutWidth,
                                          controlsScale:
                                              (effectiveIsLandscape &&
                                                      optimize)
                                                  ? targetLayout
                                                      .controlsScale
                                                  : layout.controlsScale,
                                          tLyrics: (effectiveIsLandscape &&
                                                  optimize)
                                              ? targetTLyrics
                                              : tLyrics,
                                          topButtonsCollapseT: 0.0,
                                          isLandscape: effectiveIsLandscape,
                                          isTransitioning:
                                              isEnteringLyricsMode,
                                          showVisualizerToggle:
                                              widget.showVisualizerToggle,
                                          overrideProgress:
                                              widget.overrideProgress,
                                          overridePosition:
                                              widget.overridePosition,
                                          overrideWaveform:
                                              widget.overrideWaveform,
                                          scrubProgressListenable: widget
                                              .scrubProgressListenable,
                                          onShowMoreMenu:
                                              widget.onShowMoreMenu,
                                          onCyclePlaylistMode:
                                              widget.onCyclePlaylistMode,
                                          onShowPlaylistModeSelector: widget
                                              .onShowPlaylistModeSelector,
                                          onScrubbing: widget.onScrubbing,
                                          onSeek: widget.onSeek,
                                          onToggleVisualizer:
                                              widget.onToggleVisualizer,
                                          onTagCompletionTap:
                                              widget.onTagCompletionTap,
                                          onTagCompletionLongPress: widget
                                              .onTagCompletionLongPress,
                                          onSleepTimerTap:
                                              widget.onSleepTimerTap,
                                          onEqualizerTap:
                                              widget.onEqualizerTap,
                                          onPrevious: widget.onPrevious,
                                          onPlayPause: widget.onPlayPause,
                                          onNext: widget.onNext,
                                          onVolumeTap: widget.onVolumeTap,
                                          onVolumeDrag: widget.onVolumeDrag,
                                          onVolumeScroll:
                                              widget.onVolumeScroll,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          top: layout.info.top,
                          left: layout.info.left,
                          width: layout.info.width,
                          height: layout.info.height +
                              (effectiveIsLandscape ? 24.0 : 0.0),
                          child: Builder(
                            builder: (context) {
                              final Alignment targetInfoAlignment =
                                  (collapseButtonsInLandscapeLyrics ||
                                          !effectiveIsLandscape)
                                      ? Alignment.centerLeft
                                      : Alignment.center;
                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.lerp(
                                  Alignment.center,
                                  Alignment.lerp(
                                    Alignment.center,
                                    targetInfoAlignment,
                                    tLyrics,
                                  )!,
                                  tLand,
                                )!,
                                child: SizedBox(
                                  width: layout.info.width,
                                  child: RepaintBoundary(
                                    child: SizeLogger(
                                      name: 'TrackInfo',
                                      child: PlaybackTrackInfo(
                                        currentMusic: currentMusic,
                                        align: layout.trackInfoAlign,
                                        lyricsModeT: tLyrics,
                                        landscapeT: tLand,
                                        controlsScale: layout.controlsScale,
                                        showVisualizerToggle:
                                            widget.showVisualizerToggle,
                                        onShowMoreMenu:
                                            widget.onShowMoreMenu,
                                        onCyclePlaylistMode:
                                            widget.onCyclePlaylistMode,
                                        onToggleVisualizer:
                                            widget.onToggleVisualizer,
                                        onTagCompletionTap:
                                            widget.onTagCompletionTap,
                                        onSleepTimerTap:
                                            widget.onSleepTimerTap,
                                        onEqualizerTap:
                                            widget.onEqualizerTap,
                                        onVolumeTap: widget.onVolumeTap,
                                        onVolumeScroll:
                                            widget.onVolumeScroll,
                                        onVolumeDrag: widget.onVolumeDrag,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (layout.cover.width > 0 && layout.cover.height > 0)
                          Positioned(
                            top: layout.cover.top,
                            left: layout.cover.left,
                            width: layout.cover.width,
                            height: layout.cover.height,
                            child: Builder(
                              builder: (context) {
                                final Rect coverEndRect = Rect.fromLTWH(
                                  resolvedCardOrigin.dx + layout.cover.left,
                                  resolvedCardOrigin.dy + layout.cover.top,
                                  layout.cover.width,
                                  layout.cover.height,
                                );
                                final double currentSize = optimize
                                    ? coverNormalLayout.cover.width
                                    : layout.cover.width;
                                final Widget coverWidget = RepaintBoundary(
                                  child: SizeLogger(
                                    name: 'Cover',
                                    child: PlaybackAlbumArt(
                                      currentSize: currentSize,
                                      cacheWidthSize:
                                          coverNormalLayout.cover.width,
                                      endRect: coverEndRect,
                                      isLandscape: effectiveIsLandscape,
                                      isNext: widget.isNext,
                                      onCoverTap: widget.onCoverTap,
                                      onCarouselAnimationComplete:
                                          widget.onCarouselAnimationComplete,
                                    ),
                                  ),
                                );
                                final Widget keyedCover = optimize
                                    ? KeyedSubtree(
                                        key: widget.coverKey,
                                        child: FittedBox(
                                          fit: BoxFit.fill,
                                          child: SizedBox(
                                            width:
                                                coverNormalLayout.cover.width,
                                            height:
                                                coverNormalLayout.cover.height,
                                            child: coverWidget,
                                          ),
                                        ),
                                      )
                                    : KeyedSubtree(
                                        key: widget.coverKey,
                                        child: coverWidget,
                                      );
                                return _CoverFlightTransformWrapper(
                                  flightController: flightController,
                                  endRect: coverEndRect,
                                  enabled: !isSmallWindow && widget.enableHero,
                                  child: keyedCover,
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
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
    required ProgressBarStyle progressBarStyle,
    required bool isSmallWindow,
    bool collapseButtonsInLandscapeLyrics = true,
    double uiScale = 1.0,
    double portraitControlsExpandProgress = 0.0,
    double lyricsBottomTabBarHeight = 0.0,
    double lyricsBottomSpacerHeight = 0.0,
    bool showAudioInfo = true,
  }) {
    final bool isWaveformEnabled =
        progressBarStyle != ProgressBarStyle.standard;
    final bool isScrollingWaveform =
        progressBarStyle == ProgressBarStyle.scrollingWaveform;
    final bool isFullWaveform =
        progressBarStyle == ProgressBarStyle.fullWaveform;
    final bool isOverlayStyle = isScrollingWaveform;

    final double audioInfoHeight = showAudioInfo
        ? (PlaybackHeroCardUiTuning.audioInfoGap +
            PlaybackHeroCardUiTuning.audioInfoHeight)
        : 0.0;
    final pNormalControlsBaseIdealHeight =
        PlaybackHeroCardUiTuning.controlsTopButtonsHeight +
        (isOverlayStyle
            ? PlaybackHeroCardUiTuning.waveformStandardTimeRowSpacing
            : PlaybackHeroCardUiTuning.controlsRowPortraitGap) +
        (isOverlayStyle
            ? PlaybackHeroCardUiTuning.waveformOverlayHeight
            : (isFullWaveform
                ? PlaybackHeroCardUiTuning.waveformStaticPortraitHeight
                : 48.0)) +
        (isOverlayStyle
            ? 0.0
            : (8.0 +
                  PlaybackHeroCardUiTuning.controlsTimeRowHeight +
                  PlaybackHeroCardUiTuning.controlsRowPortraitGap +
                  PlaybackHeroCardUiTuning.controlsMainButtonsHeight)) +
        audioInfoHeight;

    final pNormalControlsWidth =
        width * PlaybackHeroCardUiTuning.portraitControlsWidthFactor;
    final pNormalScale = PlaybackHeroCardUiTuning.portraitControlsScale(
      width,
      height: height,
      isSmallWindow: isSmallWindow,
    );

    final double maxControlsHeightFactor = isSmallWindow
        ? 0.85
        : PlaybackHeroCardUiTuning.pControlsHeightFactor;

    final pNormalControlsHeight =
        (pNormalControlsBaseIdealHeight * pNormalScale)
            .clamp(0.0, height * maxControlsHeightFactor)
            .ceilToDouble();
    final pNormalInfoHeight =
        PlaybackHeroCardUiTuning.pInfoHeight * pNormalScale;

    final pNormalBottomLimit = isSmallWindow
        ? (height - PlaybackHeroCardUiTuning.portraitBottomReservedSpace)
        : (height -
            lyricsBottomTabBarHeight -
            PlaybackHeroCardUiTuning.portraitBottomReservedSpace);

    const pNormalCoverTop = 0.0;

    final pNormalTotalContentHeight = pNormalInfoHeight + pNormalControlsHeight;

    final pNormalCoverSide = isSmallWindow
        ? 0.0
        : math
              .min(
                math.min(
                  width,
                  height * PlaybackHeroCardUiTuning.pCoverMaxHeightFactor,
                ),
                pNormalBottomLimit -
                    pNormalTotalContentHeight -
                    PlaybackHeroCardUiTuning.pNormalCoverInfoMinGap,
              )
              .clamp(0.0, PlaybackHeroCardUiTuning.pCoverMaxSide)
              .toDouble();

    final double pNormalInfoTop;
    final double pNormalControlsTop;

    if (isSmallWindow) {
      const double bottomPadding = 12.0;
      pNormalControlsTop =
          pNormalBottomLimit - pNormalControlsHeight - bottomPadding;
      pNormalInfoTop = pNormalControlsTop - pNormalInfoHeight - 4.0;
    } else {
      final pNormalAvailableHeight = pNormalBottomLimit - pNormalCoverSide;
      final pNormalContentTop =
          pNormalCoverSide +
          (pNormalAvailableHeight - pNormalTotalContentHeight) / 2;

      pNormalInfoTop = pNormalContentTop;
      pNormalControlsTop = pNormalInfoTop + pNormalInfoHeight;
    }

    final pLyricsCoverSide = PlaybackHeroCardUiTuning.pLyricsCoverSide;
    final pLyricsCoverTop = PlaybackHeroCardUiTuning.pLyricsCoverTop;
    final pLyricsCoverLeft = PlaybackHeroCardUiTuning.pLyricsCoverLeft;

    final pLyricsInfoHeight = pLyricsCoverSide;
    final pLyricsInfoTop = pLyricsCoverTop;
    final pLyricsInfoLeft = pLyricsCoverLeft + pLyricsCoverSide + 16.0;

    final lNormalContentWidth = width
        .clamp(0.0, math.max(1600.0, height * 2.5).toDouble())
        .toDouble();
    final lNormalOffsetX = (width - lNormalContentWidth) / 2;

    final lColumnWidth = lNormalContentWidth * 0.5;

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
    final lRemainingSpace = math.max(0.0, lContentRightEdge - lNormalCoverRightEdge);

    final lNormalControlsWidth = ((lNormalContentWidth * 0.24 + 72) *
            math.max(1.0, uiScale * 0.95))
        .clamp(
          PlaybackHeroCardUiTuning.lControlsMinWidth,
          PlaybackHeroCardUiTuning.lControlsMaxWidth * math.max(1.0, uiScale),
        )
        .clamp(0.0, lRemainingSpace);

    final lNormalControlsLeft =
        lNormalCoverRightEdge + (lRemainingSpace - lNormalControlsWidth) / 2;

    final double lNormalControlsScale =
        ((lNormalControlsWidth / PlaybackHeroCardUiTuning.lControlsScaleBase) *
                uiScale)
            .clamp(0.85, 1.8 * uiScale);
    final double lNormalSingleButtonWidth =
        PlaybackHeroCardUiTuning.controlsTopButtonsHeight *
        lNormalControlsScale;
    final double lNormalGapWidth =
        PlaybackHeroCardUiTuning.topButtonsInnerGap * lNormalControlsScale;
    final double lNormalButtonsRowWidth =
        7 * lNormalSingleButtonWidth + 6 * lNormalGapWidth;

    const double gapStartShrink = 80.0;
    const double gapEndShrink = 0.0;
    final double gap = lNormalControlsLeft - lNormalCoverRightEdge;
    final double lNormalInfoWidthFactor =
        ((gap - gapEndShrink) / (gapStartShrink - gapEndShrink)).clamp(
          0.0,
          1.0,
        );
    final double lNormalInfoWidthAdjusted =
        lNormalButtonsRowWidth +
        (lNormalControlsWidth - lNormalButtonsRowWidth) *
            lNormalInfoWidthFactor;

    final double lNormalInfoLeftAdjusted =
        lNormalControlsLeft +
        (lNormalControlsWidth - lNormalInfoWidthAdjusted) / 2;

    final lNormalControlsBaseIdealHeight =
        PlaybackHeroCardUiTuning.controlsTopButtonsHeight +
        PlaybackHeroCardUiTuning.controlsRowLandscapeGap +
        (isWaveformEnabled
            ? PlaybackHeroCardUiTuning.waveformLandscapeHeight
            : 48.0) +
        PlaybackHeroCardUiTuning.controlsTimeGap +
        16.0 + // 实际时间行高度 (在 controlsScale 缩放前，实际 Text 高度约为 16.0)
        PlaybackHeroCardUiTuning.controlsRowLandscapeMainGap +
        60.0 + // 实际主播放按钮行高度
        audioInfoHeight;

    final double maxControlsHeight = math.max(
      height * 0.65,
      height - 80.0,
    );

    final lNormalControlsHeight =
        (lNormalControlsBaseIdealHeight * lNormalControlsScale)
            .clamp(0.0, maxControlsHeight)
            .ceilToDouble();

    final lNormalInfoHeight =
        (PlaybackHeroCardUiTuning.landscapeInfoHeightBase * lNormalControlsScale)
            .ceilToDouble();

    final lNormalGap =
        (PlaybackHeroCardUiTuning.landscapeInfoControlsGap * lNormalControlsScale)
            .ceilToDouble();
    final lNormalTotalRightHeight =
        lNormalInfoHeight + lNormalControlsHeight + lNormalGap;
    final lNormalInfoTop = (height * 0.5 - lNormalTotalRightHeight / 2)
        .clamp(8.0, math.max(8.0, height - lNormalTotalRightHeight - 8.0))
        .roundToDouble();
    final lNormalControlsTop = lNormalInfoTop + lNormalInfoHeight + lNormalGap;

    final double highResControlsScale = (width > 1920.0 && height > 600.0)
        ? (1.0 + (width - 1920.0) * 0.00018).clamp(1.0, 1.35)
        : 1.0;

    final double spaceFactor = ((width - 960.0) / 720.0).clamp(0.0, 1.0);

    final double lLyricsPreferredCoverSide =
        (PlaybackHeroCardUiTuning.lLyricsPreferredCoverSide +
                spaceFactor * PlaybackHeroCardUiTuning.lLyricsMaxCoverExpansion) *
        highResControlsScale *
        math.max(1.0, uiScale * 0.95);
    final double lLyricsSpaceControlsScale = collapseButtonsInLandscapeLyrics
        ? (highResControlsScale *
            PlaybackHeroCardUiTuning.lLyricsBaseControlsScale *
            uiScale)
        : lNormalControlsScale;

    final double minVerticalReservedSpace =
        PlaybackHeroCardUiTuning.lLyricsVerticalMargin * 2.0;
    final lLyricsAvailableHeight = math.max(
      0.0,
      height - minVerticalReservedSpace,
    );

    final double rightRatio =
        PlaybackHeroCardUiTuning.appleLyricsRightPanelRatio;
    final double leftRatio = 1.0 - rightRatio;
    final double lLyricsColumnWidth = width * leftRatio;
    final double lLyricsLyricsLeft = width * leftRatio + 24.0;
    final double lLyricsLyricsWidth =
        math.max(0.0, width * rightRatio - 24.0 - 48.0);

    final double lLyricsInfoControlsScale = lLyricsSpaceControlsScale;
    final double lLyricsInfoHeight =
        (collapseButtonsInLandscapeLyrics
            ? PlaybackHeroCardUiTuning.landscapeLyricsInfoHeightBase
            : PlaybackHeroCardUiTuning.landscapeInfoHeightBase) *
        lLyricsInfoControlsScale;

    final double lLyricsControlsBaseIdealHeight =
        (collapseButtonsInLandscapeLyrics
            ? ((isWaveformEnabled
                    ? PlaybackHeroCardUiTuning.waveformLandscapeHeight
                    : 48.0) +
                PlaybackHeroCardUiTuning.controlsTimeGap +
                16.0 + // 实际时间行高度
                PlaybackHeroCardUiTuning.controlsRowLandscapeGap +
                60.0) // 实际主播放按钮行高度 (60.0)
            : (PlaybackHeroCardUiTuning.controlsTopButtonsHeight +
                PlaybackHeroCardUiTuning.controlsRowLandscapeGap +
                (isWaveformEnabled
                    ? PlaybackHeroCardUiTuning.waveformLandscapeHeight
                    : 48.0) +
                PlaybackHeroCardUiTuning.controlsTimeGap +
                16.0 + // 实际时间行高度
                PlaybackHeroCardUiTuning.controlsRowLandscapeGap + // 歌词模式下 gap 为 controlsRowLandscapeGap (12.0)
                60.0)) + // 实际主播放按钮行高度
        audioInfoHeight;
    final double lLyricsControlsHeight =
        lLyricsControlsBaseIdealHeight * lLyricsSpaceControlsScale;

    final double lLyricsCoverInfoSpacing =
        PlaybackHeroCardUiTuning.landscapeLyricsCoverInfoGapBase *
        lLyricsSpaceControlsScale;
    final double lLyricsInfoControlsSpacing =
        (collapseButtonsInLandscapeLyrics
            ? PlaybackHeroCardUiTuning.landscapeLyricsInfoControlsGapCollapsed
            : PlaybackHeroCardUiTuning.landscapeLyricsInfoControlsGap) *
        lLyricsSpaceControlsScale;

    final double maxHorizontalSpace =
        math.max(120.0, lLyricsColumnWidth - 48.0);

    final double nonCoverHeight =
        lLyricsInfoHeight +
        lLyricsControlsHeight +
        lLyricsCoverInfoSpacing +
        lLyricsInfoControlsSpacing;

    // 左侧控件区高度上限以「显示器逻辑高度」为基准。各平台 Display.size 的量纲
    // 不同（Linux 已是逻辑像素，Windows/macOS/移动端是物理像素），统一走
    // [logicalDisplaySizeOf] 换算，失败时退回当前窗口高度。
    final double screenHeight = logicalDisplaySizeOf(context)?.height ?? height;

    final double maxLeftAreaTotalHeight = math.min(
      lLyricsAvailableHeight,
      screenHeight * PlaybackHeroCardUiTuning.lLyricsMaxHeightFactor,
    );
    final double maxCoverHeightByTotalLimit =
        maxLeftAreaTotalHeight - nonCoverHeight;

    final double maxCoverSide = math.min(
      lLyricsPreferredCoverSide,
      math.min(math.max(140.0, maxCoverHeightByTotalLimit), maxHorizontalSpace),
    );
    final double availableCoverHeight =
        maxLeftAreaTotalHeight - nonCoverHeight;

    final double lLyricsCoverSide = availableCoverHeight.clamp(
      math.min(140.0, maxCoverSide),
      maxCoverSide,
    );

    final double minControlsWidth =
        (collapseButtonsInLandscapeLyrics ? 280.0 : 360.0) *
            lLyricsSpaceControlsScale;
    final double lLyricsItemWidth = lLyricsCoverSide.clamp(
      math.min(minControlsWidth, maxHorizontalSpace),
      maxHorizontalSpace,
    );

    final double lLyricsTotalContentHeight =
        lLyricsCoverSide +
        lLyricsCoverInfoSpacing +
        lLyricsInfoHeight +
        lLyricsInfoControlsSpacing +
        lLyricsControlsHeight;

    // AppLog.log(
    //   '[Playback-Detail] lLyricsCoverSide: ${lLyricsCoverSide.toStringAsFixed(2)}, '
    //   'lLyricsCoverInfoSpacing: ${lLyricsCoverInfoSpacing.toStringAsFixed(2)}, '
    //   'lLyricsInfoHeight: ${lLyricsInfoHeight.toStringAsFixed(2)}, '
    //   'lLyricsInfoControlsSpacing: ${lLyricsInfoControlsSpacing.toStringAsFixed(2)}, '
    //   'lLyricsControlsHeight: ${lLyricsControlsHeight.toStringAsFixed(2)}, '
    //   'lLyricsTotalContentHeight: ${lLyricsTotalContentHeight.toStringAsFixed(2)}, '
    //   'maxLeftAreaTotalHeight: ${maxLeftAreaTotalHeight.toStringAsFixed(2)}, '
    //   'maxCoverSide: ${maxCoverSide.toStringAsFixed(2)}, '
    //   'maxHorizontalSpace: ${maxHorizontalSpace.toStringAsFixed(2)}, '
    //   'nonCoverHeight: ${nonCoverHeight.toStringAsFixed(2)}',
    //   mirrorToConsole: true,
    // );

    final double lLyricsCoverTop = math.max(
      PlaybackHeroCardUiTuning.lLyricsVerticalMargin,
      (height - lLyricsTotalContentHeight) / 2,
    );

    final currentControlsScale =
        _lerp2DSmooth(
          PlaybackHeroCardUiTuning.portraitControlsScale(
            width,
            height: height,
            isSmallWindow: isSmallWindow,
          ),
          PlaybackHeroCardUiTuning.portraitControlsScale(
            width,
            height: height,
            isSmallWindow: isSmallWindow,
          ),
          lNormalControlsScale,
          lLyricsSpaceControlsScale,
          tLyrics,
          tLand,
        );

    final double lLyricsCoverLeft;
    final double lLyricsInfoLeft;
    final double lLyricsControlsLeft;

    const double leftColumnStart = 0.0;
    final double leftAreaCenter = leftColumnStart + lLyricsColumnWidth / 2;
    const double minLeftMargin = 24.0;

    lLyricsCoverLeft = (leftAreaCenter - lLyricsCoverSide / 2).clamp(
      minLeftMargin,
      math.max(
        minLeftMargin,
        leftColumnStart + lLyricsColumnWidth - lLyricsCoverSide - minLeftMargin,
      ),
    );
    final double itemLeft = (leftAreaCenter - lLyricsItemWidth / 2).clamp(
      minLeftMargin,
      math.max(
        minLeftMargin,
        leftColumnStart + lLyricsColumnWidth - lLyricsItemWidth - minLeftMargin,
      ),
    );
    lLyricsInfoLeft = itemLeft;
    lLyricsControlsLeft = itemLeft;

    final lLyricsInfoTop =
        lLyricsCoverTop + lLyricsCoverSide + lLyricsCoverInfoSpacing;

    final lLyricsControlsTop =
        lLyricsInfoTop + lLyricsInfoHeight + lLyricsInfoControlsSpacing;

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
        width: math.max(0.0, width - pLyricsInfoLeft - 24.0),
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

    final double expandedControlsHeight = math.max(
      110.0,
      pNormalControlsBaseIdealHeight * pNormalScale,
    );
    const double pLyricsControlsBottomMargin = 16.0;
    final double pLyricsControlsExpandedTop = height -
        lyricsBottomTabBarHeight -
        lyricsBottomSpacerHeight -
        pLyricsControlsBottomMargin -
        expandedControlsHeight;
    final double pLyricsControlsCollapsedTop = height;

    final double pLyricsControlsTop = lerpDouble(
      pLyricsControlsCollapsedTop,
      pLyricsControlsExpandedTop,
      portraitControlsExpandProgress,
    )!;
    final double pLyricsControlsOpacity =
        portraitControlsExpandProgress.clamp(0.0, 1.0);

    final double pLyricsControlsHeight = pNormalControlsHeight;

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
        top: pLyricsControlsTop,
        left: (width - math.min(width, pNormalControlsWidth)) / 2,
        width: math.min(width, pNormalControlsWidth),
        height: pLyricsControlsHeight,
        opacity: pLyricsControlsOpacity,
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

    final lyrics = _lerpPane(
      context,
      pNormal: _PlaybackPaneLayout(
        top: height + 80.0,
        left: 24.0,
        width: math.max(0.0, width - 48.0),
        height: math.max(
          0.0,
          height - (pLyricsCoverTop + pLyricsCoverSide + 16.0),
        ),
        opacity: 0.0,
      ),
      pLyrics: _PlaybackPaneLayout(
        top: pLyricsCoverTop + pLyricsCoverSide + 16.0,
        left: 24.0,
        width: math.max(0.0, width - 48.0),
        height: math.max(
          0.0,
          height - (pLyricsCoverTop + pLyricsCoverSide + 16.0),
        ),
        opacity: 1.0,
      ),
      lNormal: _PlaybackPaneLayout(
        top: 16.0,
        left: width + 80.0,
        width: lLyricsLyricsWidth,
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

    final trackInfoAlign = widget.isLandscape
        ? TextAlign.center
        : (widget.isLyricsMode ? TextAlign.left : TextAlign.center);

    return _PlaybackCardLayout(
      cover: cover,
      info: info,
      controls: controls,
      lyrics: lyrics,
      trackInfoAlign: trackInfoAlign,
      controlsScale: currentControlsScale,
      leftAreaTotalHeight: lLyricsTotalContentHeight,
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
}

class _LyricsPanelTransitionWrapper extends StatefulWidget {
  final ValueNotifier<bool> isTransitioning;
  final bool isLyricsMode;
  final double lyricsBottomSpacerHeight;
  final double lyricsBottomReserveBase;
  final Animation<double> lyricsBottomReserveProgress;
  final double lyricsBottomReserveDelta;
  final double lyricsBottomTabBarHeight;

  const _LyricsPanelTransitionWrapper({
    required this.isTransitioning,
    required this.isLyricsMode,
    required this.lyricsBottomSpacerHeight,
    required this.lyricsBottomReserveBase,
    required this.lyricsBottomReserveProgress,
    required this.lyricsBottomReserveDelta,
    required this.lyricsBottomTabBarHeight,
  });

  @override
  State<_LyricsPanelTransitionWrapper> createState() =>
      _LyricsPanelTransitionWrapperState();
}

class _LyricsPanelTransitionWrapperState
    extends State<_LyricsPanelTransitionWrapper> {
  late bool _isTransitioning;

  @override
  void initState() {
    super.initState();
    _isTransitioning = widget.isTransitioning.value;
    widget.isTransitioning.addListener(_handleTransitionChange);
  }

  @override
  void didUpdateWidget(_LyricsPanelTransitionWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isTransitioning != widget.isTransitioning) {
      oldWidget.isTransitioning.removeListener(_handleTransitionChange);
      widget.isTransitioning.addListener(_handleTransitionChange);
      _isTransitioning = widget.isTransitioning.value;
    }
  }

  @override
  void dispose() {
    widget.isTransitioning.removeListener(_handleTransitionChange);
    super.dispose();
  }

  void _handleTransitionChange() {
    if (mounted && _isTransitioning != widget.isTransitioning.value) {
      setState(() {
        _isTransitioning = widget.isTransitioning.value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final currentIndex = ref.watch(audioCurrentIndexProvider);
        final currentMusic = ref.watch(audioCurrentMusicProvider);
        final position = (widget.isLyricsMode || _isTransitioning)
            ? ref.watch(audioPositionProvider)
            : ref.read(audioPositionProvider);
        final currentThemeColorsMap = ref.watch(
          audioCurrentThemeColorsMapProvider,
        );
        final accent =
            currentThemeColorsMap['darkVibrant'] ??
            currentThemeColorsMap['darkMuted'] ??
            Colors.white;

        return LyricsPanel(
          key: ValueKey('$currentIndex:${currentMusic?.path ?? 'no-track'}'),
          lyrics: currentMusic?.lyrics,
          position: position,
          accentColor: accent,
          bottomSpacerHeight: widget.lyricsBottomSpacerHeight,
          bottomTabBarHeight: widget.lyricsBottomTabBarHeight,
          bottomReserveBase: widget.lyricsBottomReserveBase,
          bottomReserveProgress: widget.lyricsBottomReserveProgress,
          bottomReserveDelta: widget.lyricsBottomReserveDelta,
          isTransitioning: _isTransitioning,
        );
      },
    );
  }
}

class _CoverFlightTransformWrapper extends StatelessWidget {
  const _CoverFlightTransformWrapper({
    required this.flightController,
    required this.endRect,
    required this.enabled,
    required this.child,
  });

  final PlaybackCoverFlightController flightController;
  final Rect endRect;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return AnimatedBuilder(
      animation: Listenable.merge([
        flightController.progressNotifier,
        flightController.originNotifier,
      ]),
      child: child,
      builder: (context, childWidget) {
        final double progress = flightController.progressNotifier.value;
        final origin = flightController.originNotifier.value;
        if (progress >= 0.9999 || origin == null) return childWidget!;

        final double endRadius = math.min(24.0, endRect.width * 0.2);
        final flight = PlaybackCoverFlightGeometry.computeCoverFlightTransform(
          startRect: origin.rect,
          startBorderRadius: origin.borderRadius,
          endRect: endRect,
          endBorderRadius: endRadius,
          progress: progress,
          sheetOffsetY: flightController.currentSheetOffsetY,
        );
        return IgnorePointer(
          ignoring: progress < 0.95,
          child: Transform(
            alignment: Alignment.topLeft,
            transform: flight.transform,
            child: childWidget,
          ),
        );
      },
    );
  }
}

class SizeLogger extends StatefulWidget {
  final String name;
  final Widget child;
  const SizeLogger({required this.name, required this.child, super.key});
  @override
  State<SizeLogger> createState() => _SizeLoggerState();
}

class _SizeLoggerState extends State<SizeLogger> {
  @override
  Widget build(BuildContext context) {
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (mounted) {
    //     final renderBox = context.findRenderObject() as RenderBox?;
    //     if (renderBox != null && renderBox.hasSize) {
    //       AppLog.log(
    //         '[SizeLogger] ${widget.name} size: ${renderBox.size.width.toStringAsFixed(2)} x ${renderBox.size.height.toStringAsFixed(2)}',
    //         mirrorToConsole: true,
    //       );
    //     }
    //   }
    // });
    return widget.child;
  }
}
