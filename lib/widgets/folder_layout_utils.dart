import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart'
    hide kGridCrossAxisSpacing, kGridMainAxisSpacing, kGridHorizontalPadding;

import 'folder_nav_bar_scaffold.dart';

/// 档位缩放的布局引擎、条目脚手架（`ZoomItemScaffold` / `ZoomItemCover`）、
/// 捏合控制器与档位图标统一由 `zoomable_sliver_grid` 提供。
///
/// 这里只做转出，让二十多个调用点继续以 `folder_layout_utils.dart` 为入口，
/// 不必逐个改 import；项目自有的内容（标题横幅高度、权限提示高度）留在下面。
///
/// 一页里挂多个网格（目录 + 歌曲、根目录 + 云服务器 + 歌曲）时，页面自己在
/// `CustomScrollView` 之上放**一个** [FolderZoomSliverBuilder]，各段用
/// [FolderZoomSectionHost] 包住、靠 `SliverAnimatedZoomGridDelegate.section`
/// 区分身份；度量的下发由包内的 `FolderZoomMetricsScope` 负责，段组件不再需要
/// `metrics` 参数。
///
/// 层级顺序必须是 `FolderZoomGestureLayer` → [FolderZoomSliverBuilder] →
/// `ScrollView`：手势层放在 builder 里面会拿不到 `FolderZoomPinchScope`（捏合不跟手）。
///
/// 各段不能自己建 builder：换档时滚动补偿按「页面坐标」结算，上游网格的高度变化
/// （`ΔH`）要先算出下游网格整体被推走了多少。各自建 builder 时上游那一段在下游的
/// tracker 里**根本不存在**，下游只会按自己的局部坐标补偿，换档瞬间被顶走一个 `ΔH`；
/// 顺带两个 builder 还会同时往同一个 `ScrollPosition` 写像素值，最后谁慢谁赢。
///
/// 栅格间距三个常量包内也有一份（数值与 [layout_constants.dart] 相同），
/// 这里 hide 掉包的那份，避免同名 export 冲突，也让全项目继续只有一个来源。
export 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart'
    hide kGridCrossAxisSpacing, kGridMainAxisSpacing, kGridHorizontalPadding;
export '../utils/layout_constants.dart';

/// 标题横幅高度的兜底值：测不到实测高度时使用（首帧、或横幅已滚出缓存区）。
const double kFolderHeaderBannerFallbackHeight = 190.0;

/// 目录页条目封面（`SongThumbnail`）的解码尺寸（dp）。
///
/// 网格态的封面边长不是常量，而是**网格卡片宽度**：`ZoomItemScaffold` 里
/// `gridCoverSize = min(W, H - 文字区高度)`，其中 W 就是列宽；而横屏列数是写死的
/// 6/7/8 列、与窗口宽度无关，所以 macOS 上 1200~1728dp 的窗口会把卡片撑到
/// 180~270dp。此前条目统一按 `kZoomItemThumbnailSize`（120）解码，2x 屏上只有
/// 240px 纹理，却被铺到 460px 见方，放大近两倍 —— 这就是桌面端目录页缩略图发糊
/// 的根因（专辑页的 `album_zoom_item.dart` 一直用 250，所以没这个毛病）。
///
/// 判据取 [FolderZoomLayoutMetrics.isGridTarget]：它在换档动画期间恒等于**目标**
/// 档位，因此一次换档只会切换一次解码尺寸，不会在捏合过程中反复跨桶重解码。
/// 列表态封面只有 40dp 上下，按 `getFolderListCoverSize` 走小桶即可。
double zoomItemThumbnailSizeFor(FolderZoomLayoutMetrics metrics) {
  final listCoverSize = getFolderListCoverSize(metrics.targetZoomScale);
  if (!metrics.isGridTarget) return listCoverSize;
  return math.max(listCoverSize, metrics.targetCardWidth);
}

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
