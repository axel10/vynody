import 'dart:ui';

/// 全局毛玻璃与模糊效果设计规范常量 (Design Tokens)
abstract final class AppBlur {
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
}
