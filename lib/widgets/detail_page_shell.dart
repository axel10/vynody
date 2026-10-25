import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/platform/right_queue_drawer_controller.dart';
import 'app_top_nav_bar.dart';
import 'auto_hide_header.dart';
import 'mini_player_wrapper.dart';

/// 艺术家 / 流派 / 年份等实体详情页的统一外壳。
///
/// 负责：透明可自动隐藏的顶部导航栏、横屏下避让左侧 Rail 的左侧内边距、
/// 以及底部迷你播放器的包裹。内容区只需关心「从顶部导航栏下沿开始」的滚动内容。
class DetailPageShell extends ConsumerStatefulWidget {
  const DetailPageShell({
    super.key,
    required this.title,
    required this.titleKey,
    required this.contentBuilder,
    this.onGoBack,
  });

  final String title;
  final Key titleKey;

  /// 未提供时走默认返回逻辑。
  final VoidCallback? onGoBack;

  /// 内容区构建器：传入滚动控制器与内容顶部内边距（避让导航栏）。
  final Widget Function(
    BuildContext context,
    ScrollController scrollController,
    double topPadding,
  ) contentBuilder;

  static double getBarHeight(BuildContext context) =>
      AppTopNavBar.getBarHeight(context);

  @override
  ConsumerState<DetailPageShell> createState() => _DetailPageShellState();
}

class _DetailPageShellState extends ConsumerState<DetailPageShell> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double barHeight = DetailPageShell.getBarHeight(context);
    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final double leftPadding =
        isLandscape ? ref.watch(sidebarRailWidthProvider(MediaQuery.sizeOf(context).width)) : 0.0;

    return AutoHideHeaderScope(
      builder: (context, isHeaderVisible) {
        final Widget content = Scaffold(
          body: Padding(
            padding: EdgeInsets.only(left: leftPadding),
            child: Stack(
              children: [
                widget.contentBuilder(
                  context,
                  _scrollController,
                  barHeight + 8,
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AutoHideHeader(
                    isVisible: isHeaderVisible,
                    child: AppTopNavBar(
                      title: widget.title,
                      titleKey: widget.titleKey,
                      onBack:
                          widget.onGoBack ?? () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        return MiniPlayerWrapper(child: content);
      },
    );
  }
}
