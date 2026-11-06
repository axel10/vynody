import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/utils/blur_constants.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/utils/app_orientation_manager.dart';
import 'package:vynody/utils/playback_utils.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/widgets/animated_play_pause_button.dart';
import 'package:vynody/widgets/app_tooltip.dart';
import 'package:vynody/widgets/mini_player_widgets.dart';

// ---------------------------------------------------------------------------
// 折叠形变的几何基准
//
// 收起动画里「多个 Tab 图标合成胶囊里的那一个」依赖几个固定锚点：header 高度、
// 胶囊图标的水平留白与宽度、进度条条带高度。以前这些数字在 header 与 tab 栏里
// 各写一份，合并轨迹要按它们派生目标点，所以统一收敛到下面这组函数/常量，
// 禁止在各处再写字面量。
// ---------------------------------------------------------------------------

/// Mini 顶栏（含收起态胶囊）在收起进度 [t] 时的高度
double _dockHeaderHeight({required bool isTablet, required double t}) =>
    isTablet ? (64.0 - 6.0 * t) : (54.0 - 2.0 * t);

/// Mini 顶栏内容区的水平内边距
double _dockHeaderPaddingH(bool isTablet) => isTablet ? 10.0 : 8.0;

/// 收起态胶囊里那个单图标的点击区宽度
double _dockCapsuleIconWidth(bool isTablet) => isTablet ? 56.0 : 48.0;

/// 实时播放进度条条带的固定高度
const double _kDockProgressStripHeight = 28.0;

/// 一体化悬浮底部面板（Mini播放器 + 实时进度条分割线 + Tab栏）
class FloatingDockBottomBar extends ConsumerStatefulWidget {
  const FloatingDockBottomBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.isPlayback,
    required this.isHidden,
    this.hideMiniPlayer = false,
    this.additionalBottomOffset = 0.0,
    this.rightDrawerWidth = 0.0,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool isPlayback;
  final bool isHidden;
  final bool hideMiniPlayer;
  final double additionalBottomOffset;
  final double rightDrawerWidth;

  @override
  ConsumerState<FloatingDockBottomBar> createState() =>
      _FloatingDockBottomBarState();
}

class _FloatingDockBottomBarState extends ConsumerState<FloatingDockBottomBar> {
  bool _isDragging = false;
  double _dragProgress = 0.0;

  /// 诊断用：记录上一次 build 时的收起相关状态，变化时打点，
  /// 用来区分「provider 标志位变了」与「标志位没变但视觉变了」
  bool? _lastTracedCollapsedState;
  bool? _lastTracedShowMini;
  double? _lastTracedProgress;
  int? _lastTracedIndex;

  void _traceDockState(
    bool isCollapsedState,
    bool showMini,
    double prepProgress,
  ) {
    if (!FloatingDockScrollHelper.traceEnabled) return;
    final changed =
        _lastTracedCollapsedState != isCollapsedState ||
        _lastTracedShowMini != showMini ||
        _lastTracedProgress != prepProgress ||
        _lastTracedIndex != widget.currentIndex;
    if (!changed) return;
    // AppLog.log(
    //   '[DockTrace] dock.build collapsed=$isCollapsedState showMini=$showMini '
    //   'prep=${prepProgress.toStringAsFixed(2)} index=${widget.currentIndex} '
    //   'isPlayback=${widget.isPlayback} isHidden=${widget.isHidden} '
    //   'hideMini=${widget.hideMiniPlayer}',
    //   mirrorToConsole: true,
    // );
    _lastTracedCollapsedState = isCollapsedState;
    _lastTracedShowMini = showMini;
    _lastTracedProgress = prepProgress;
    _lastTracedIndex = widget.currentIndex;
  }

  @override
  Widget build(BuildContext context) {
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final isPlaying = ref.watch(audioIsPlayingProvider);
    final isBuffering = ref.watch(audioIsBufferingProvider);
    final progress = ref.watch(audioProgressProvider);
    final position = ref.watch(audioPositionProvider);
    final duration = ref.watch(audioDurationProvider);
    final audio = ref.watch(audioServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = viewInsetsBottom > 0;
    final isEffectivelyHidden = widget.isHidden || isKeyboardVisible;

    // 当有正在播放的歌曲且不在全屏播放页且未被多选屏蔽且未隐藏时，展开 Mini 播放器
    final showMini =
        currentMusic != null &&
        !widget.isPlayback &&
        !widget.hideMiniPlayer &&
        !isEffectivelyHidden;

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final isTablet =
        MediaQuery.sizeOf(context).shortestSide >=
        AppOrientationManager.tabletShortestSideBreakpoint;

    // iPad / 平板端：在底部安全区（Home 条）之上预留 8pt 呼吸感，无安全区时保底 28pt；
    // iPhone 端：34 - 14 = 20pt（与 Apple Music 底部高度一致）；无安全区保底 12pt；
    // Android / 其它手机端：取小白条高度(16~20)，无小白条保底 12dp。
    final double safeBottom;
    if (isTablet) {
      safeBottom = bottomPadding > 0 ? (bottomPadding + 8.0) : 28.0;
    } else if (isIOS) {
      safeBottom = bottomPadding > 0
          ? (bottomPadding - 14.0).clamp(12.0, double.infinity)
          : 12.0;
    } else {
      safeBottom = bottomPadding > 0 ? bottomPadding : 12.0;
    }
    final totalBottomOffset = safeBottom + widget.additionalBottomOffset;
    final totalRightOffset = 16.0 + widget.rightDrawerWidth;

    final isCollapsedState = ref.watch(floatingDockCollapsedProvider);
    final isCollapsed = showMini && isCollapsedState;
    final collapsePrepProgress = ref.watch(
      floatingDockCollapseProgressProvider,
    );
    _traceDockState(isCollapsedState, showMini, collapsePrepProgress);
    final double prepScale = isCollapsed
        ? 1.0
        : (1.0 - (0.05 * collapsePrepProgress));

    final tabs = [
      _TabItem(
        index: 0,
        label: l10n.scanDirectory,
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder,
      ),
      _TabItem(
        index: 2,
        label: l10n.list,
        icon: Icons.playlist_play_outlined,
        selectedIcon: Icons.playlist_play,
      ),
      _TabItem(
        index: 3,
        label: l10n.queueTab,
        icon: Icons.queue_music_outlined,
        selectedIcon: Icons.queue_music,
      ),
      _TabItem(
        index: 4,
        label: l10n.share,
        icon: Icons.share_outlined,
        selectedIcon: Icons.share,
      ),
      _TabItem(
        index: 5,
        label: l10n.settings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
      ),
    ];

    final currentTab = tabs.firstWhere(
      (t) => t.index == widget.currentIndex,
      orElse: () => tabs[0],
    );

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      left: 16.0,
      right: totalRightOffset,
      bottom: isEffectivelyHidden
          ? -(200.0 + bottomPadding + viewInsetsBottom)
          : totalBottomOffset,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          opacity: isEffectivelyHidden ? 0.0 : 1.0,
          child: IgnorePointer(
            ignoring: isEffectivelyHidden,
            child: AnimatedScale(
              scale: prepScale,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                constraints: BoxConstraints(
                  maxWidth: isCollapsed
                      ? (isTablet ? 480 : 420)
                      : (isTablet ? 620 : 580),
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isTablet ? 32 : 28),
                  boxShadow: widget.isPlayback
                      ? const []
                      : AppBlur.glassShadow(context),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isTablet ? 32 : 28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: widget.isPlayback ? 0 : AppBlur.heavy,
                      sigmaY: widget.isPlayback ? 0 : AppBlur.heavy,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: widget.isPlayback
                            ? Colors.transparent
                            : AppBlur.heavySurface(context),
                        borderRadius: BorderRadius.circular(isTablet ? 32 : 28),
                        border: widget.isPlayback
                            ? null
                            : AppBlur.glassBorder(context),
                      ),
                      child: TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        tween: Tween<double>(
                          // A newly pushed detail page must start from the
                          // shared collapse state. Using a fixed zero here
                          // makes every new Dock animate from expanded before
                          // settling into the inherited state.
                          begin: isCollapsed ? 1.0 : 0.0,
                          end: isCollapsed ? 1.0 : 0.0,
                        ),
                        builder: (context, t, child) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 1. 上半部：Mini 播放器 / 收起态胶囊顶栏（随折叠平滑形变）
                              AnimatedSize(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                child: showMini
                                    ? _buildMorphingHeader(
                                        context,
                                        ref,
                                        l10n: l10n,
                                        theme: theme,
                                        isDark: isDark,
                                        currentMusic: currentMusic,
                                        isPlaying: isPlaying,
                                        isBuffering: isBuffering,
                                        audio: audio,
                                        position: position,
                                        duration: duration,
                                        currentTab: currentTab,
                                        collapseProgress: t,
                                        isTablet: isTablet,
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              // 2. 中间：实时播放进度条（折叠时平滑向上折叠收缩并淡出）
                              AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                child: showMini
                                    ? ClipRect(
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          heightFactor: (1.0 - t).clamp(
                                            0.0,
                                            1.0,
                                          ),
                                          child: Opacity(
                                            opacity: (1.0 - t * 1.5).clamp(
                                              0.0,
                                              1.0,
                                            ),
                                            child: _FloatingDockProgressBar(
                                              theme: theme,
                                              isDark: isDark,
                                              progress: progress,
                                              isDragging: _isDragging,
                                              dragProgress: _dragProgress,
                                              onDragStart: (val) {
                                                setState(() {
                                                  _isDragging = true;
                                                  _dragProgress = val;
                                                });
                                              },
                                              onDragUpdate: (val) {
                                                setState(() {
                                                  _isDragging = true;
                                                  _dragProgress = val;
                                                });
                                              },
                                              onDragEnd: (val) {
                                                final seekProgress = val.clamp(
                                                  0.0,
                                                  1.0,
                                                );
                                                if (duration.inMilliseconds >
                                                    0) {
                                                  audio.seek(
                                                    Duration(
                                                      milliseconds:
                                                          (duration.inMilliseconds *
                                                                  seekProgress)
                                                              .toInt(),
                                                    ),
                                                  );
                                                }
                                                setState(() {
                                                  _isDragging = false;
                                                });
                                              },
                                              onDragCancel: () {
                                                setState(() {
                                                  _isDragging = false;
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              // 3. 下半部：Tab 导航栏（折叠时各图标飞向左上角的
                              //    单图标槽位并收敛，整行高度同步收到 0）
                              //
                              //    这里刻意不再套 ClipRect：旧实现靠裁剪把这一行
                              //    从下往上"抹"掉，观感是整行图标上下位移；现在图标
                              //    是各自平移出这一行的（Align 不裁剪，只压缩布局高度），
                              //    越界部分由最外层 ClipRRect 兜底。
                              IgnorePointer(
                                ignoring: t > 0.2,
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  heightFactor: (1.0 - t).clamp(0.0, 1.0),
                                  child: _buildBottomTabs(
                                    context,
                                    theme,
                                    isDark,
                                    l10n,
                                    tabs: tabs,
                                    isPlayback: widget.isPlayback,
                                    isTablet: isTablet,
                                    collapseProgress: t,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 一体化平滑形变 Mini 播放器顶栏：
  /// - 展开态 (collapseProgress = 0.0)：标准两行展开 Mini 播放器，最左侧无 Tab 图标，显示上一首按钮；
  /// - 收起态 (collapseProgress = 1.0)：单行胶囊，最左侧展开 Tab 图标，封面和歌曲信息平滑右移至对应槽位，上一首按钮平滑收折；
  /// - 过渡态：左侧 Tab 展开推移封面与文字，各元素尺寸与透明度连续插值。
  Widget _buildMorphingHeader(
    BuildContext context,
    WidgetRef ref, {
    required AppLocalizations l10n,
    required ThemeData theme,
    required bool isDark,
    required dynamic currentMusic,
    required bool isPlaying,
    required bool isBuffering,
    required AudioService audio,
    required Duration position,
    required Duration duration,
    required _TabItem currentTab,
    required double collapseProgress,
    bool isTablet = false,
  }) {
    final displayPosition = _isDragging
        ? Duration(
            milliseconds:
                (duration.inMilliseconds * _dragProgress.clamp(0.0, 1.0))
                    .toInt(),
          )
        : position;

    final double prevNextIconSize = isTablet ? 26.0 : 20.0;
    final double playPauseIconSize = isTablet
        ? (32.0 - 2.0 * collapseProgress)
        : 26.0;
    final EdgeInsets buttonPadding = isTablet
        ? const EdgeInsets.all(8.0)
        : const EdgeInsets.all(4.0);
    final double buttonSpacing = isTablet
        ? (8.0 - 2.0 * collapseProgress)
        : 2.0;

    final double headerHeight = _dockHeaderHeight(
      isTablet: isTablet,
      t: collapseProgress,
    );
    final double headerPaddingH = _dockHeaderPaddingH(isTablet);
    // 胶囊图标延后出现：让下方飞上来的图标先落到位，再由它"接管"
    final double capsuleIconOpacity = ((collapseProgress - 0.28) / 0.6).clamp(
      0.0,
      1.0,
    );

    final activeColor = (widget.isPlayback || isDark)
        ? Colors.white
        : Colors.black87;

    return SizedBox(
      height: headerHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 0. 背景频谱动画（开关由 MiniSpectrumBackground 内部统一判定）
          Positioned.fill(child: MiniSpectrumBackground(audio: audio)),

          // 1. 歌曲信息与按钮区域（拖动进度条时高斯模糊并淡出）
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: headerPaddingH,
              vertical: 4.0,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 200),
                    tween: Tween<double>(
                      begin: 0,
                      end: _isDragging ? 5.0 : 0.0,
                    ),
                    builder: (context, blur, child) {
                      return ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: blur,
                          sigmaY: blur,
                        ),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _isDragging ? 0.25 : 1.0,
                          child: IgnorePointer(
                            ignoring: _isDragging,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        // ① 最左侧：收起态出现的当前 Tab 图标按钮（点击展开 Dock 栏）
                        // 展开态宽度为 0，收起态平滑展开并向右推移封面和标题
                        ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: collapseProgress.clamp(0.0, 1.0),
                            child: Opacity(
                              opacity: capsuleIconOpacity,
                              child: Transform.scale(
                                scale: 0.7 + 0.3 * collapseProgress,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppTooltip(
                                      message: currentTab.label,
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: Material(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            onTap: collapseProgress > 0.2
                                                ? () {
                                                    ref
                                                        .read(
                                                          floatingDockCollapsedProvider
                                                              .notifier,
                                                        )
                                                        .setCollapsed(false);
                                                  }
                                                : null,
                                            child: SizedBox(
                                              width: _dockCapsuleIconWidth(
                                                isTablet,
                                              ),
                                              height: isTablet ? 48.0 : 44.0,
                                              child: Center(
                                                child: Icon(
                                                  currentTab.selectedIcon,
                                                  size: isTablet ? 26.0 : 22.0,
                                                  color: activeColor,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: isTablet ? 8.0 : 6.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // ② 中间：封面 + 歌曲名/歌手（随左侧 Tab 展开平滑移动到收起目标位置）
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => widget.onDestinationSelected(1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0,
                                  vertical: 2.0,
                                ),
                                child: Row(
                                  children: [
                                    MiniArtwork(
                                      size: isTablet
                                          ? (42.0 - 2.0 * collapseProgress)
                                          : 36.0,
                                      borderRadius: isTablet ? 8.0 : 6.0,
                                    ),
                                    SizedBox(width: isTablet ? 10.0 : 8.0),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            currentMusic.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: isTablet
                                                  ? (15.0 -
                                                        1.0 * collapseProgress)
                                                  : 13.0,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                              height: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            currentMusic.artist ??
                                                l10n.unknownArtist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: isTablet ? 12.0 : 11.0,
                                              color: isDark
                                                  ? Colors.white60
                                                  : Colors.black54,
                                              height: 1.1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // ③ 右侧：播放控制按钮
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 上一首：展开态可见，收起态平滑收折宽度并淡出
                            ClipRect(
                              child: Align(
                                alignment: Alignment.centerRight,
                                widthFactor: (1.0 - collapseProgress).clamp(
                                  0.0,
                                  1.0,
                                ),
                                child: Opacity(
                                  opacity: (1.0 - collapseProgress).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      MiniControlButton(
                                        icon: Icons.skip_previous_rounded,
                                        iconSize: prevNextIconSize,
                                        padding: buttonPadding,
                                        onPressed: audio.previous,
                                        tooltip: l10n.previous,
                                      ),
                                      SizedBox(width: buttonSpacing),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            AnimatedPlayPauseButton(
                              isPlaying: isPlaying,
                              isLoading: isBuffering,
                              onPressed: audio.togglePlay,
                              color: isDark ? Colors.white : Colors.black87,
                              size: playPauseIconSize,
                              padding: buttonPadding,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              tooltip: isPlaying ? l10n.pause : l10n.play,
                            ),
                            SizedBox(width: buttonSpacing),
                            MiniControlButton(
                              icon: Icons.skip_next_rounded,
                              iconSize: prevNextIconSize,
                              padding: buttonPadding,
                              onPressed: audio.next,
                              tooltip: l10n.next,
                            ),
                            SizedBox(
                              width: isTablet
                                  ? (8.0 - 2.0 * collapseProgress)
                                  : 2.0,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. 拖拽时浮现的时间指示层（左侧当前拖拽进度时间，右侧歌曲总时长）
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isDragging ? 1.0 : 0.0,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 18.0 : 14.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              formatDuration(displayPosition),
                              style: TextStyle(
                                fontSize: isTablet ? 14.0 : 13.0,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              formatDuration(duration),
                              style: TextStyle(
                                fontSize: isTablet ? 14.0 : 13.0,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
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

  /// 下半部 Tab 导航项。
  ///
  /// 收起/展开不做「整行上下位移」，而是每个图标各自沿一条轨迹飞向收起态胶囊
  /// 里那个单图标的位置：左移 + 上移 + 缩小 + 淡出，多个图标合流到一点；
  /// 展开时同一条轨迹反向播放，就是一个图标向外铺开成多个。
  Widget _buildBottomTabs(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    AppLocalizations l10n, {
    required List<_TabItem> tabs,
    required bool isPlayback,
    bool isTablet = false,
    double collapseProgress = 0.0,
  }) {
    final double t = collapseProgress.clamp(0.0, 1.0);
    final double rowHeight = isTablet ? 56.0 : 52.0;
    final double horizontalPadding = isTablet ? 10.0 : 6.0;
    final double slotCenterY = rowHeight / 2;
    final double slotCenterTargetY =
        -(_kDockProgressStripHeight * (1.0 - t) +
            _dockHeaderHeight(isTablet: isTablet, t: t) / 2);

    // 合流目标：收起态胶囊里那个单图标的中心，坐标相对本行左上角。
    // 纵向必须跟着「进度条 + header」在收起过程中的实际高度走，
    // 否则图标会落在空处而不是落进那个图标里。
    final double mergeTargetX =
        _dockHeaderPaddingH(isTablet) + _dockCapsuleIconWidth(isTablet) / 2;

    // 外层 morph 用的是 easeOutCubic（前 1/3 时间就走掉大半进度），
    // 所以这里的位移要尽早收完，把后段留给「停在那一个图标上慢慢溶掉」，
    // 否则会出现「刚开始飞就已经看不见了」的闪烁感。
    final double converge = Curves.easeInOutCubic.transform(
      (t / 0.62).clamp(0.0, 1.0),
    );
    // 普通图标落位之后才开始隐去
    final double flyOpacity = (1.0 - (t - 0.30) / 0.42).clamp(0.0, 1.0);
    // 当前 Tab 的图标与胶囊图标同形，留到最后再淡：读起来像是它们被这一个吸收
    final double selectedOpacity = (1.0 - (t - 0.42) / 0.52).clamp(0.0, 1.0);

    return SizedBox(
      width: double.infinity,
      height: rowHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double slotWidth =
              (constraints.maxWidth - horizontalPadding * 2) / tabs.length;

          // 绘制顺序：当前 Tab 的图标放最后画。合流后它压在其余图标之上，
          // 淡出时读起来像是「别的图标被它吸收」，而不是被无关图标盖住。
          final int selectedPos = tabs.indexWhere(
            (e) => e.index == widget.currentIndex,
          );
          final List<int> paintOrder = [
            for (var i = 0; i < tabs.length; i++)
              if (i != selectedPos) i,
            if (selectedPos >= 0) selectedPos,
          ];

          return Stack(
            clipBehavior: Clip.none,
            children: paintOrder.map((i) {
              final _TabItem tab = tabs[i];
              final bool isSelected = i == selectedPos;
              final double slotCenterX =
                  horizontalPadding + slotWidth * (i + 0.5);

              final double dx = (mergeTargetX - slotCenterX) * converge;
              final double dy = (slotCenterTargetY - slotCenterY) * converge;
              final double opacity = isSelected ? selectedOpacity : flyOpacity;

              if (opacity <= 0.001) return const SizedBox.shrink();

              return Positioned(
                left: horizontalPadding + slotWidth * i,
                top: 0,
                width: slotWidth,
                height: rowHeight,
                child: Transform.translate(
                  offset: Offset(dx, dy),
                  child: Transform.scale(
                    scale: 1.0 - 0.45 * converge,
                    child: Opacity(
                      opacity: opacity,
                      child: _TabButton(
                        item: tab,
                        isSelected: isSelected,
                        isPlayback: isPlayback,
                        isDark: isDark,
                        isTablet: isTablet,
                        onTap: () => widget.onDestinationSelected(tab.index),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _TabItem {
  final int index;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _TabItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.isSelected,
    required this.isPlayback,
    required this.isDark,
    required this.onTap,
    this.isTablet = false,
  });

  final _TabItem item;
  final bool isSelected;
  final bool isPlayback;
  final bool isDark;
  final VoidCallback onTap;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    final activeColor = (isPlayback || isDark) ? Colors.white : Colors.black87;
    final inactiveColor = (isPlayback || isDark)
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.38);

    return AppTooltip(
      message: item.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: SizedBox(
                  width: isTablet ? 58.0 : 52.0,
                  height: isTablet ? 38.0 : 34.0,
                  child: Center(
                    child: AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      firstCurve: Curves.easeOutCubic,
                      secondCurve: Curves.easeOutCubic,
                      crossFadeState: isSelected
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: Icon(
                        item.icon,
                        size: isTablet ? 24.0 : 22.0,
                        color: inactiveColor,
                      ),
                      secondChild: Icon(
                        item.selectedIcon,
                        size: isTablet ? 24.0 : 22.0,
                        color: activeColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 具备可拖动胶囊滑块的实时播放进度条
class _FloatingDockProgressBar extends StatelessWidget {
  const _FloatingDockProgressBar({
    required this.theme,
    required this.isDark,
    required this.progress,
    required this.isDragging,
    required this.dragProgress,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final ThemeData theme;
  final bool isDark;
  final double progress;
  final bool isDragging;
  final double dragProgress;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onDragCancel;

  void _handleUpdate(double localX, double totalWidth, bool isStart) {
    if (totalWidth <= 0) return;
    final newProgress = (localX / totalWidth).clamp(0.0, 1.0);
    if (isStart) {
      onDragStart(newProgress);
    } else {
      onDragUpdate(newProgress);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = (isDragging ? dragProgress : progress).clamp(
      0.0,
      1.0,
    );
    const barHeight = 8.0;
    final thumbWidth = isDragging ? 20.0 : 16.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final progressWidth = totalWidth * effectiveProgress;
          final thumbLeft = (progressWidth - thumbWidth / 2).clamp(
            0.0,
            totalWidth - thumbWidth,
          );

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) =>
                _handleUpdate(details.localPosition.dx, totalWidth, true),
            onHorizontalDragUpdate: (details) =>
                _handleUpdate(details.localPosition.dx, totalWidth, false),
            onHorizontalDragEnd: (details) => onDragEnd(dragProgress),
            onHorizontalDragCancel: onDragCancel,
            onTapDown: (details) =>
                _handleUpdate(details.localPosition.dx, totalWidth, true),
            onTapUp: (details) {
              if (totalWidth <= 0) return;
              final newProgress = (details.localPosition.dx / totalWidth).clamp(
                0.0,
                1.0,
              );
              onDragEnd(newProgress);
            },
            onTapCancel: onDragCancel,
            child: Container(
              height: _kDockProgressStripHeight, // 扩张手势触控热区（上下各延伸），大幅提升手机端命中率
              alignment: Alignment.center,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  // 1. 底层轨道 (与滑块同高，背景色与 dock 背景有轻微对比区分)
                  Container(
                    height: barHeight,
                    width: totalWidth,
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withValues(
                        alpha: isDark ? 0.16 : 0.08,
                      ),
                      borderRadius: BorderRadius.circular(barHeight / 2),
                    ),
                  ),

                  // 2. 已播放高亮轨道（中性色风格，不与底部 Tab 栏主题色争抢视觉重心）
                  Container(
                    height: barHeight,
                    width: progressWidth,
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black87)
                          .withValues(alpha: isDark ? 0.80 : 0.68),
                      borderRadius: BorderRadius.circular(barHeight / 2),
                    ),
                  ),

                  // 3. 可拖拽胶囊形状滑块 (Capsule Thumb，高度与进度条轨道一致)
                  Positioned(
                    left: thumbLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: thumbWidth,
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(barHeight / 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.45 : 0.25,
                            ),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
