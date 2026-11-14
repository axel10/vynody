import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/platform/right_queue_drawer_controller.dart';
import '../utils/layout_constants.dart';
import 'app_top_nav_bar.dart';
import 'floating_capsule_header.dart';
import 'library_action_bar.dart';
import 'library_header_actions.dart';

/// 本地与远程媒体库二级宿主共用的安全边距与横竖屏计算结果。
///
/// 统一由 [isEffectiveLandscapeProvider]、[getTitleBarTopPadding] 与
/// [effectiveSidebarRailWidthProvider] 计算，避免桌面端自定义标题栏避让或
/// 横竖屏判据在两边各自漂移。
class LibrarySubHostInsets {
  const LibrarySubHostInsets({
    required this.isLandscape,
    required this.topPadding,
    required this.railWidth,
  });

  final bool isLandscape;
  final double topPadding;
  final double railWidth;

  /// 根据当前路由/宿主 [context] 计算二级分类根页面应避让的安全边距。
  static LibrarySubHostInsets of(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = ref.watch(isEffectiveLandscapeProvider(size));
    final safeTop = getTitleBarTopPadding(
      context,
      defaultWindowPadding: isLandscape ? 32.0 : 36.0,
    );
    return LibrarySubHostInsets(
      isLandscape: isLandscape,
      topPadding: isLandscape ? (safeTop + 8.0) : safeTop,
      railWidth: ref.watch(effectiveSidebarRailWidthProvider(size)),
    );
  }
}

/// 本地与远程媒体库二级宿主共用的顶部浮动返回胶囊层。
///
/// 统一处理 `Positioned` 定位、`AppTopNavBar.getBarHeight` 高度约束、
/// 详情页压栈瞬时让位动画以及 [LibraryTopNavCapsule] 包装，确保两边在竖屏
/// 滚离顶部后浮出的胶囊位置、尺寸和过渡节奏完全一致。
class LibraryFloatingNavCapsuleOverlay extends StatelessWidget {
  const LibraryFloatingNavCapsuleOverlay({
    super.key,
    required this.railWidth,
    required this.visible,
    required this.tabHasChildRoute,
    required this.controller,
    required this.onBack,
    this.extraActions = const <LibraryToolbarAction>[],
    this.capsuleKey,
  });

  final double railWidth;
  final bool visible;
  final bool tabHasChildRoute;
  final LibraryHeaderActionsController controller;
  final VoidCallback onBack;
  final List<LibraryToolbarAction> extraActions;
  final Key? capsuleKey;

  @override
  Widget build(BuildContext context) {
    final double headerHeight = AppTopNavBar.getBarHeight(context);
    final Duration duration = tabHasChildRoute
        ? Duration.zero
        : const Duration(milliseconds: 250);

    return Positioned(
      top: 0,
      left: railWidth,
      right: 0,
      height: headerHeight,
      child: FloatingCapsuleHeader(
        visible: visible,
        duration: duration,
        child: LibraryTopNavCapsule(
          key: capsuleKey,
          controller: controller,
          onBack: onBack,
          extraActions: extraActions,
        ),
      ),
    );
  }
}
