import 'dart:ui';
import 'package:flutter/material.dart';

/// 全局毛玻璃与模糊效果设计规范常量 (Design Tokens)
abstract final class AppBlur {
  // ── 1. 模糊强度 (Blur Sigma) ──

  /// 微弱模糊：新手引导全屏背景遮罩等极轻量场景 (3.0)
  static const double subtle = 3.0;

  /// 轻度模糊：微型角标、轻量提示、小卡片等小面积组件 (6.0)
  static const double light = 6.0;

  /// 中度模糊：对话框、桌面标题栏、设置弹窗、音量滑块等 (16.0)
  static const double medium = 10.0;

  /// 深度磨砂：常驻浮动底栏 (Dock)、Mini 播放卡片、底部抽屉 (BottomSheet)、播放队列面板等 (24.0)
  static const double heavy = 16.0;

  /// 便捷创建双轴相等的 [ImageFilter.blur]
  static ImageFilter filter(double sigma) =>
      ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);

  /// 微弱模糊 Filter
  static ImageFilter get subtleFilter => filter(subtle);

  /// 轻度模糊 Filter
  static ImageFilter get lightFilter => filter(light);

  /// 中度模糊 Filter
  static ImageFilter get mediumFilter => filter(medium);

  /// 深度磨砂 Filter
  static ImageFilter get heavyFilter => filter(heavy);

  // ── 2. 背景不透明度规范 (Alpha) ──

  /// 深度磨砂常驻浮层（Dock、MiniPlayer、列表顶栏）：暗色 66%，亮色 80%
  static double heavyAlpha(bool isDark) => isDark ? 0.50 : 0.60;

  /// 对话框与表单抽屉（Sheet、Dialog）：暗色 88%，亮色 95%
  static double dialogAlpha(bool isDark) => isDark ? 0.88 : 0.95;

  /// 微型角标/悬浮提示胶囊：固定 50%
  static const double badgeAlpha = 0.50;

  // ── 3. 颜色与微光描边 (Surface & Border) ──

  /// 自动适配亮暗色的常驻浮层背景色
  static Color heavySurface(BuildContext context, {double? overrideAlpha}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final alpha = overrideAlpha ?? heavyAlpha(isDark);
    return theme.colorScheme.surface.withValues(alpha: alpha);
  }

  /// 自动适配亮暗色的对话框与抽屉背景色
  static Color dialogSurface(BuildContext context, {double? overrideAlpha}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final alpha = overrideAlpha ?? dialogAlpha(isDark);
    return isDark
        ? Colors.black.withValues(alpha: alpha)
        : theme.colorScheme.surface.withValues(alpha: alpha);
  }

  /// 自动适配亮暗色的毛玻璃高光微描边（增强边缘立体感）
  static Border glassBorder(
    BuildContext context, {
    double width = 0.8,
    double? overrideAlpha,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alpha = overrideAlpha ?? (isDark ? 0.15 : 0.08);
    final color =
        (isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
    return Border.all(color: color, width: width);
  }

  // ── 4. 环境浮动漫反射阴影 (Ambient Shadow) ──

  /// 毛玻璃悬浮容器的标准柔和阴影
  static List<BoxShadow> glassShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.08),
        blurRadius: 20,
        offset: const Offset(0, 4),
        spreadRadius: 0,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.05),
        blurRadius: 8,
        offset: const Offset(0, 2),
        spreadRadius: 0,
      ),
    ];
  }

  // ── 5. 开箱即用的一体化卡片材质装饰 (BoxDecoration) ──

  /// 常驻浮层（Dock、MiniPlayer等）的一体化毛玻璃装饰盒
  static BoxDecoration heavyDecoration(
    BuildContext context, {
    BorderRadiusGeometry? borderRadius,
    bool showBorder = true,
    bool showShadow = true,
    double? overrideAlpha,
    double borderWidth = 0.8,
  }) {
    return BoxDecoration(
      color: heavySurface(context, overrideAlpha: overrideAlpha),
      borderRadius: borderRadius,
      border: showBorder ? glassBorder(context, width: borderWidth) : null,
      boxShadow: showShadow ? glassShadow(context) : null,
    );
  }

  /// 对话框与抽屉的一体化毛玻璃装饰盒
  static BoxDecoration dialogDecoration(
    BuildContext context, {
    BorderRadiusGeometry? borderRadius,
    bool showBorder = true,
    bool showShadow = true,
    double? overrideAlpha,
    double borderWidth = 0.8,
  }) {
    return BoxDecoration(
      color: dialogSurface(context, overrideAlpha: overrideAlpha),
      borderRadius: borderRadius,
      border: showBorder ? glassBorder(context, width: borderWidth) : null,
      boxShadow: showShadow ? glassShadow(context) : null,
    );
  }
}
