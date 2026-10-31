import 'package:flutter/material.dart';

import 'folder_nav_bar_scaffold.dart';

/// 档位缩放的布局引擎、条目脚手架（`ZoomItemScaffold` / `ZoomItemCover`）、
/// 捏合控制器与档位图标统一由 `zoomable_sliver_grid` 提供。
///
/// 这里只做转出，让二十多个调用点继续以 `folder_layout_utils.dart` 为入口，
/// 不必逐个改 import；项目自有的内容（标题横幅高度、权限提示高度）留在下面。
///
/// 栅格间距三个常量包内也有一份（数值与 [layout_constants.dart] 相同），
/// 这里 hide 掉包的那份，避免同名 export 冲突，也让全项目继续只有一个来源。
export 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart'
    hide kGridCrossAxisSpacing, kGridMainAxisSpacing, kGridHorizontalPadding;
export '../utils/layout_constants.dart';

/// 标题横幅高度的兜底值：测不到实测高度时使用（首帧、或横幅已滚出缓存区）。
const double kFolderHeaderBannerFallbackHeight = 190.0;

/// 内容区上方「无权限访问」提示块的估算高度（`folder.path == 'system'` 且未授权时）。
const double kFolderPermissionWarningHeight = 200.0;

/// 「定位当前播放」要加在行偏移上的内容区上方高度：顶栏 + 标题横幅（+ 权限提示）。
///
/// 横幅高度不是常量——它随系统文字缩放、搜索框展开而变，所以优先用 [bannerKey]
/// 实测（key 挂在横幅上）；横幅已经滚出缓存区、element 被卸载时回落到
/// [kFolderHeaderBannerFallbackHeight]。
///
/// 竖屏时顶栏高度已包含在横幅的 `topHeader` 里，因此不再单独叠加。
double folderContentTopOffset({
  required BuildContext context,
  required bool isPortrait,
  GlobalKey? bannerKey,
  bool hasPermissionWarning = false,
}) {
  final bannerHeight = _measuredBannerHeight(bannerKey);
  final barHeight =
      isPortrait ? 0.0 : FolderNavBarScaffold.getBarHeight(context);
  return barHeight +
      bannerHeight +
      (hasPermissionWarning ? kFolderPermissionWarningHeight : 0.0);
}

double _measuredBannerHeight(GlobalKey? key) {
  final renderObject = key?.currentContext?.findRenderObject();
  if (renderObject is RenderBox &&
      renderObject.hasSize &&
      renderObject.size.height > 0) {
    return renderObject.size.height;
  }
  return kFolderHeaderBannerFallbackHeight;
}
