import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// 自适应头部固定滚动组件。
///
/// 在横屏（或桌面宽屏）环境下，将 [header] 置于 [Column] 顶部固定展示，
/// 仅让下方的 [slivers] 在 [Expanded] 内独立滚动；
/// 在竖屏环境下，自动将 [header] 作为首个 Sliver 置于 [CustomScrollView] 顶部，
/// 随内容一起滚动，最大化小屏幕上的内容可视面积。
class AdaptivePinnedHeaderScrollView extends StatelessWidget {
  const AdaptivePinnedHeaderScrollView({
    super.key,
    this.header,
    required this.slivers,
    this.topPadding = 0.0,
    this.controller,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.onRefresh,
    this.isLandscape,
    this.scrollCacheExtent,
    this.scrollViewKey,
    this.headerSlotBuilder,
  });

  /// 顶部区域组件（如分类工具栏、搜索栏等）。为 null 时不渲染头部。
  final Widget? header;

  /// 滚动内容 Sliver 列表。
  final List<Widget> slivers;

  /// 顶部避让高度（如状态栏或窗口标题栏让位）。
  final double topPadding;

  /// 滚动控制器。
  final ScrollController? controller;

  /// 滚动物理机制。
  final ScrollPhysics? physics;

  /// 下拉刷新回调；为 null 时不包裹 [RefreshIndicator]。
  final RefreshCallback? onRefresh;

  /// 显式指定是否使用横屏固定模式；未提供时默认通过 [MediaQuery.orientationOf] 计算。
  final bool? isLandscape;

  /// 滚动视图的预加载缓存区域。
  final ScrollCacheExtent? scrollCacheExtent;

  /// 传递给内部 [CustomScrollView] 的 Key。
  final Key? scrollViewKey;

  /// 自定义头部在普通布局（横屏）和 Sliver 布局（竖屏）下的包装逻辑。
  /// [isSliver] 为 true 时表示用于竖屏 CustomScrollView，需返回 Sliver 组件。
  final Widget Function(BuildContext context, Widget header, bool isSliver)?
      headerSlotBuilder;

  @override
  Widget build(BuildContext context) {
    final bool effectiveLandscape = isLandscape ??
        (MediaQuery.orientationOf(context) == Orientation.landscape);

    if (effectiveLandscape) {
      Widget scrollArea = CustomScrollView(
        key: scrollViewKey,
        controller: controller,
        physics: physics,
        scrollCacheExtent: scrollCacheExtent,
        slivers: slivers,
      );

      if (onRefresh != null) {
        scrollArea = RefreshIndicator(
          onRefresh: onRefresh!,
          child: scrollArea,
        );
      }

      Widget? effectiveHeader;
      if (header != null) {
        effectiveHeader = headerSlotBuilder != null
            ? headerSlotBuilder!(context, header!, false)
            : header!;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          ?effectiveHeader,
          Expanded(child: scrollArea),
        ],
      );
    } else {
      Widget? sliverHeader;
      if (header != null) {
        sliverHeader = headerSlotBuilder != null
            ? headerSlotBuilder!(context, header!, true)
            : SliverToBoxAdapter(child: header!);
      }

      final fullSlivers = <Widget>[
        if (topPadding > 0)
          SliverToBoxAdapter(
            child: SizedBox(height: topPadding),
          ),
        ?sliverHeader,
        ...slivers,
      ];

      Widget scrollArea = CustomScrollView(
        key: scrollViewKey,
        controller: controller,
        physics: physics,
        scrollCacheExtent: scrollCacheExtent,
        slivers: fullSlivers,
      );

      if (onRefresh != null) {
        scrollArea = RefreshIndicator(
          onRefresh: onRefresh!,
          child: scrollArea,
        );
      }

      return scrollArea;
    }
  }
}
