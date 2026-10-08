/// 全局页面与内容区域最大宽度布局常量规范
library;

import 'dart:io';
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

/// 判断当前是否处于窗口化运行环境（桌面端或平板多任务/窗口模式，如 iPadOS 台前调度 Stage Manager、分屏）
bool isWindowedEnvironment(BuildContext context) {
  final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  if (isDesktop) return true;

  try {
    final view = View.of(context);
    final windowSize = view.physicalSize;
    final displaySize = view.display.size;

    // 当物理显示器尺寸有效时比对窗口与物理屏幕（长宽对比，支持横竖屏旋转，容差 2.0 物理像素）
    if (displaySize.width > 0 && displaySize.height > 0) {
      final isFullScreen =
          (windowSize.width >= displaySize.width - 2.0 &&
              windowSize.height >= displaySize.height - 2.0) ||
          (windowSize.width >= displaySize.height - 2.0 &&
              windowSize.height >= displaySize.width - 2.0);
      return !isFullScreen;
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

