import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/platform/right_queue_drawer_controller.dart';
import '../utils/layout_constants.dart';
import 'auto_hide_header.dart';
import 'detail_page_shell.dart';
import 'mini_player_wrapper.dart';
import 'scroll_past_top.dart';

/// 顶栏构建器。
///
/// [isHeaderVisible] 来自 [AutoHideHeaderScope]，用于顶栏自身的显隐动画；
/// [isPastTop] 是「列表已滚过 [kHeaderFloatingCapsuleThreshold]」，供
/// `AppTopNavBar` 这类支持浮动胶囊形态的顶栏切换外观。
/// 用 `scrollProgress` 驱动的顶栏（如 `AlbumDetailNavBar`）忽略后两个参数即可。
typedef RemoteNavBarBuilder =
    Widget Function(
      BuildContext context,
      bool isHeaderVisible,
      bool isPastTop,
    );

/// 远程媒体库各页面的统一外壳。
///
/// 抽取自 5 个页面各自手写的一份「透明可自动隐藏顶栏 + Stack 覆盖 + 底部多选
/// 面板 + MiniPlayer 包裹」结构（专辑详情 / 艺术家详情 / 歌单详情 / 流派详情 /
/// 远程库主页）。与本地详情页的 [DetailPageShell] 是同一条思路，差别在于：
///
/// * 顶栏不内建，由 [navBarBuilder] 提供 —— 远程各页的顶栏分 `AlbumDetailNavBar`
///   （吃滚动进度与封面显隐动画）与 `AppTopNavBar`（吃 `isPastTop`）两类，
///   把参数塞进外壳会把接口撑爆；
/// * 多选面板作为 [selectionPanel] 直接交给外壳，不再各页手写
///   `AnimatedSelectionPanel + LibrarySelectionPanel`；
/// * 可选 [popScopeCanPop]：多选态下拦截系统返回（歌单详情需要）；
/// * 可选 [avoidRail]：横屏避让左侧 Rail。**默认关闭** —— 远程库当前挂在
///   「目录」tab 的嵌套 Navigator 内，渲染位置本就在 Rail 右侧的内容区，外层
///   `MainLayout._buildCurrentPage` 已经用 `Padding(left: railWidth)` 让过一次位，
///   这里再让一次会多空出一整条。等远程库提为独立一级 tab、外层改为
///   `Padding(left: 0)` 后再开启。
class RemotePageShell extends ConsumerStatefulWidget {
  const RemotePageShell({
    super.key,
    required this.contentBuilder,
    required this.navBarBuilder,
    this.selectionPanel,
    this.forceHeaderVisible = false,
    this.enableFloatingCapsule = true,
    this.wrapWithMiniPlayer = true,
    this.avoidRail = false,
    this.windowTopInset = false,
    this.popScopeCanPop,
    this.onPopBlocked,
  });

  /// 内容区。页面自行用 `XxxNavBar.getBarHeight(context)` 计算顶部让位。
  final Widget Function(BuildContext context) contentBuilder;

  /// 顶栏。外壳负责用 [AutoHideHeader] 包裹并定位到顶部。
  final RemoteNavBarBuilder navBarBuilder;

  /// 底部多选面板。
  ///
  /// 必须是 [Stack] 的直接子元素（通常就是 `AnimatedSelectionPanel`，它自身
  /// 返回 `Positioned`）。为 `null` 时不渲染。
  final Widget? selectionPanel;

  /// 强制顶栏常显（多选态 / 搜索态），对应 [AutoHideHeaderScope.forceVisible]。
  final bool forceHeaderVisible;

  /// 是否监听纵向滚动并计算 `isPastTop`。
  ///
  /// 顶栏自带滚动进度联动（`AlbumDetailNavBar`）时可置 false，省掉一次
  /// `setState` 的可能。
  final bool enableFloatingCapsule;

  final bool wrapWithMiniPlayer;

  /// 横屏避让左侧 Rail。见类文档，默认关闭。
  final bool avoidRail;

  /// 窗口化环境（桌面端 / 台前调度 / 分屏）下顶部额外避让
  /// [kWindowedPageTopInset]，免得内容压进窗口标题栏。
  final bool windowTopInset;

  /// 非空时用 [PopScope] 包裹整页；值为 `canPop`。
  final bool? popScopeCanPop;

  /// [PopScope] 拦住返回时的回调（通常是取消多选）。
  final VoidCallback? onPopBlocked;

  @override
  ConsumerState<RemotePageShell> createState() => _RemotePageShellState();
}

class _RemotePageShellState extends ConsumerState<RemotePageShell> {
  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double leftPadding = widget.avoidRail
        ? ref.watch(effectiveSidebarRailWidthProvider(size))
        : 0.0;
    final double topPadding =
        widget.windowTopInset && isWindowedEnvironment(context)
        ? kWindowedPageTopInset
        : 0.0;

    Widget content = ScrollPastTopScope(
      enabled: widget.enableFloatingCapsule,
      builder: (context, isPastTop) => AutoHideHeaderScope(
        enabled: false,
        forceVisible: widget.forceHeaderVisible,
        builder: (context, isHeaderVisible) => Scaffold(
          body: Padding(
            padding: EdgeInsets.only(left: leftPadding, top: topPadding),
            child: Stack(
              children: [
                widget.contentBuilder(context),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AutoHideHeader(
                    isVisible: isHeaderVisible,
                    child: widget.navBarBuilder(
                      context,
                      isHeaderVisible,
                      isPastTop,
                    ),
                  ),
                ),
                if (widget.selectionPanel != null) widget.selectionPanel!,
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.wrapWithMiniPlayer) {
      content = MiniPlayerWrapper(child: content);
    }

    final bool? canPop = widget.popScopeCanPop;
    if (canPop != null) {
      content = PopScope(
        canPop: canPop,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          widget.onPopBlocked?.call();
        },
        child: content,
      );
    }

    return content;
  }
}
