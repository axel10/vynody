/// 全局页面与内容区域最大宽度布局常量规范
library;

import 'dart:io';
import 'dart:ui' show Display;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 单列内容区域（播放列表、队列、最近播放/榜单单曲、专辑与艺人详情页、设置与分享面板等）的标准最大宽度
const double kSingleColumnContentMaxWidth = 1080.0;

/// 多列网格视图（如专辑卡片网格）的标准最大宽度
const double kMultiColumnGridMaxWidth = 1600.0;

/// 文件夹树与远程文件浏览器视图的标准最大宽度
const double kFolderPageMaxWidth = 1700.0;

/// 桌面端或窗口化（如 iPadOS 台前调度 / 自由窗口模式）时窗口顶部的标准安全避让高度
const double kDefaultWindowCaptionHeight = 46.0;

/// 队列抽屉（Right Queue Panel）标准默认宽度
const double kDefaultRightQueueDrawerWidth = 340.0;

/// 队列抽屉最小与最大可拖拽宽度
const double kMinRightQueueDrawerWidth = 280.0;
const double kMaxRightQueueDrawerWidth = 600.0;

/// 队列抽屉宽度常量（向后兼容）
const double kRightQueueDrawerWidth = kDefaultRightQueueDrawerWidth;

/// 详情页顶部导航栏从「贴顶大标题」切换为「浮动胶囊」的滚动阈值。
///
/// 列表纵向滚动超过这个距离即认为已离开顶部，顶栏改画成悬浮胶囊。
/// 此前 `detail_page_shell` / `library_page` / `remote_playlist_detail_page` /
/// `remote_folder_browser_page` 各自写死了一份 `36.0`。
const double kHeaderFloatingCapsuleThreshold = 36.0;

/// 窗口化环境（桌面端、iPadOS 台前调度/分屏）下页面内容顶部的额外避让高度。
const double kWindowedPageTopInset = 32.0;

// ---------------------------------------------------------------------------
// 主页面（`MainLayout`）一级导航索引
// ---------------------------------------------------------------------------
//
// 这些值就是 `IndexedStack` 的槽序号。远程媒体库成为独立一级栏目时插在
// 「媒体源」之后，原来留给播放抽屉的 1 号空槽被让出，其后整体后移一位。
//
// 引用面：Rail 的 `destinations`、底部 dock 的 `tabs`、返回键分发
// （`_handleBackPressed`）、`_visitedTabs`、`mainTabIndexProvider` 的消费者。
// **禁止再写字面量** —— 上一次加栏目就是靠人肉数槽位顺移，漏一处就是
// 「点了图标去了别的页面」这种查起来极慢的 bug。
const int kMainTabFolders = 0;
const int kMainTabRemoteLibrary = 1;
const int kMainTabPlayback = 2;
const int kMainTabLibrary = 3;
const int kMainTabQueue = 4;
const int kMainTabSharing = 5;

/// 设置页是 push 出来的独立路由，不占 `IndexedStack` 槽位；
/// 但 Rail / dock 的「设置」条目和 `_onDestinationSelected` 需要同一个编号。
const int kMainTabSettings = 6;

/// `IndexedStack` 里实际存在的槽位数量（`kMainTabFolders` … `kMainTabSharing`）。
const int kMainTabSlotCount = 6;

/// 左侧导航栏（Rail）折叠态宽度：仅显示图标 + 悬浮提示
const double kSidebarRailWidthCollapsed = 80.0;

/// 左侧导航栏（Rail）默认展开态宽度：图标 + 文字，用于桌面端宽窗口
const double kDefaultSidebarRailWidthExtended = 216.0;
const double kSidebarRailWidthExtended = kDefaultSidebarRailWidthExtended;

/// 左侧导航栏展开态自定义调节范围（最小宽度维持原数值 216.0）
const double kMinSidebarRailWidthExtended = 216.0;
const double kMaxSidebarRailWidthExtended = 360.0;

/// 左侧导航栏切换到展开态（图标 + 文字）所需的最小窗口宽度
const double kSidebarRailExtendedMinWindowWidth = 900.0;

/// 按窗口宽度计算左侧导航栏实际宽度：
/// 窗口足够宽时展开为图标 + 文字，否则收回为纯图标，避免窄窗口挤压内容区。
double sidebarRailWidthFor(
  double windowWidth, {
  double? customExtendedWidth,
}) {
  if (windowWidth < kSidebarRailExtendedMinWindowWidth) {
    return kSidebarRailWidthCollapsed;
  }
  return (customExtendedWidth ?? kDefaultSidebarRailWidthExtended)
      .clamp(kMinSidebarRailWidthExtended, kMaxSidebarRailWidthExtended);
}

/// [Display.size] 在各平台的上报口径并不统一：
/// - Linux（GTK embedder）：取自 `gdk_monitor_get_geometry()`，返回的已经是
///   application / 逻辑像素，**不需要**再除以 [Display.devicePixelRatio]。
/// - Windows（`rcMonitor` 宽高）、macOS（`frame.size * backingScaleFactor`）、
///   Android/iOS：返回的都是物理像素，需要除以 [Display.devicePixelRatio]。
///
/// 若 Linux 上照搬「除以 dpr」的写法，HiDPI 屏会被二次缩小
/// （如 1920x1200 @2x 实际报成 960x600），横屏歌词模式左侧控件区因此被压扁。
bool get displaySizeReportedInLogicalPixels => !kIsWeb && Platform.isLinux;

/// 把显示器尺寸换算为逻辑像素（dp），[rawSize] 与 [devicePixelRatio] 取自 [Display]。
///
/// [sizeIsLogical] 为 `null` 时按当前运行平台自动判断口径。
Size logicalDisplaySizeFrom(
  Size rawSize,
  double devicePixelRatio, {
  bool? sizeIsLogical,
}) {
  final bool isLogical = sizeIsLogical ?? displaySizeReportedInLogicalPixels;
  if (isLogical || devicePixelRatio.isNaN || devicePixelRatio <= 0) {
    return rawSize;
  }
  return rawSize / devicePixelRatio;
}

/// 将 [Display.size] 统一换算为逻辑像素（dp）。
Size displayLogicalSize(Display display, {bool? sizeIsLogical}) =>
    logicalDisplaySizeFrom(
      display.size,
      display.devicePixelRatio,
      sizeIsLogical: sizeIsLogical,
    );

/// 当前视图所在显示器的逻辑尺寸；取不到显示器信息时返回 `null`。
Size? logicalDisplaySizeOf(BuildContext context) {
  try {
    return displayLogicalSize(View.of(context).display);
  } catch (_) {
    return null;
  }
}

/// 判断当前是否处于窗口化运行环境（桌面端或平板多任务/窗口模式，如 iPadOS 台前调度 Stage Manager、分屏）
bool isWindowedEnvironment(BuildContext context) {
  final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  if (isDesktop) return true;

  try {
    final view = View.of(context);
    final double dpr = view.devicePixelRatio;
    if (dpr > 0) {
      // 窗口逻辑尺寸与显示器逻辑尺寸同量纲比较（2.0dp 容差）
      final windowSize = view.physicalSize / dpr;
      final displaySize = displayLogicalSize(view.display);

      if (displaySize.width > 0 && displaySize.height > 0) {
        final isFullScreen =
            (windowSize.width >= displaySize.width - 2.0 &&
                windowSize.height >= displaySize.height - 2.0) ||
            (windowSize.width >= displaySize.height - 2.0 &&
                windowSize.height >= displaySize.width - 2.0);
        return !isFullScreen;
      }
    }
  } catch (_) {
    // 降级保护
  }

  return MediaQuery.of(context).padding.top == 0;
}

/// 获取顶部标题栏或导航栏的安全避让间距：
/// - 若处于窗口化环境（桌面端、iPadOS 台前调度 Stage Manager、分屏 Split View 等）：
///   * 若贴顶且带有系统状态栏（[statusBarHeight] > 0，如 iPad 分屏模式）：
///     系统会在状态栏下方叠加窗口控制胶囊/按钮，因此需要在状态栏基础上额外预留避让空间 [splitViewExtraPadding]；
///   * 若无状态栏（[statusBarHeight] == 0，如台前调度自由悬浮窗口或桌面端）：
///     预留标准窗口标题栏安全间距 [defaultWindowPadding]；
/// - 若处于常规全屏环境：
///   * 若有状态栏，使用状态栏高度加上偏移量 [statusBarOffset]；
///   * 否则降级返回 [defaultWindowPadding]。
double getTitleBarTopPadding(
  BuildContext context, {
  double defaultWindowPadding = kDefaultWindowCaptionHeight,
  double statusBarOffset = 0.0,
  double splitViewExtraPadding = 36.0,
}) {

  final statusBarHeight = MediaQuery.of(context).padding.top;
  final isWindowed = isWindowedEnvironment(context);

  if (isWindowed) {
    if (statusBarHeight > 0) {
      // 分屏多任务模式（如 iPadOS Split View 左右分屏）：
      // 顶部既有系统状态栏，又有系统在窗口顶部添加的控制按钮/胶囊，因此在状态栏基础上叠加避让高度
      return statusBarHeight + splitViewExtraPadding;
    }
    // 自由悬浮窗口模式（如 iPadOS 台前调度 Stage Manager 悬浮窗、桌面端）：
    return defaultWindowPadding;
  }

  if (statusBarHeight > 0) {
    return statusBarHeight + statusBarOffset;
  }
  return defaultWindowPadding;
}

// ---------------------------------------------------------------------------
// 网格布局规范与间距常量 (Grid Layout Constants & Helpers)
// ---------------------------------------------------------------------------

/// 网格视图的标准横向（列）间距
const double kGridCrossAxisSpacing = 16.0;

/// 网格视图的标准纵向（行）间距（呼吸感留白，参考 Apple Music 等现代排版）
const double kGridMainAxisSpacing = 24.0;

/// 网格视图的标准左右内边距
const double kGridHorizontalPadding = 16.0;

/// 根据容器可用宽度与列数，按照标准网格间距规范计算单个卡片的宽度
double calculateGridItemWidth({
  required double width,
  required int crossAxisCount,
  double horizontalPadding = kGridHorizontalPadding,
  double crossAxisSpacing = kGridCrossAxisSpacing,
}) {
  if (crossAxisCount <= 0 || width <= 0) return 0.0;
  final totalPadding = horizontalPadding * 2;
  final totalSpacing = (crossAxisCount - 1) * crossAxisSpacing;
  final itemWidth = (width - totalPadding - totalSpacing) / crossAxisCount;
  return itemWidth > 0 ? itemWidth : 0.0;
}

