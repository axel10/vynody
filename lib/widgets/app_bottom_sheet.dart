import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

/// 统一的抽屉顶部药丸状横条（Drag Handle / Grabber）
class AppDragHandle extends StatelessWidget {
  /// 点击横条的回调，默认行为为关闭当前弹出的抽屉 [Navigator.pop]
  final VoidCallback? onTap;

  /// 横条的颜色，未指定时自适应亮色/暗色主题
  final Color? color;

  /// 横条宽度，默认 36
  final double width;

  /// 横条高度，默认 4
  final double height;

  /// 外层点击热区内边距，默认 vertical: 8, horizontal: 24
  final EdgeInsetsGeometry padding;

  const AppDragHandle({
    super.key,
    this.onTap,
    this.color,
    this.width = 36,
    this.height = 4,
    this.padding = const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final handleColor = color ??
        (isDark
            ? Colors.white.withValues(alpha: 0.25)
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35));

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap ?? () => Navigator.of(context).pop(),
        child: Padding(
          padding: padding,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: handleColor,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一的带毛玻璃、圆角和顶部横条的底部抽屉容器
class AppBottomSheet extends StatelessWidget {
  /// 抽屉的主体内容
  final Widget child;

  /// 竖屏（Portrait）或小屏下的最大宽度约束，默认 720
  final double maxWidth;

  /// 横屏（Landscape）或桌面大屏下的最大宽度约束，默认 960（横屏下空间更开阔）
  final double landscapeMaxWidth;

  /// 是否显示顶部横条，默认 true
  final bool showDragHandle;

  /// 点击顶部横条时的回调，默认直接 pop 关闭抽屉
  final VoidCallback? onDragHandleTap;

  /// 内容区域外围内边距
  final EdgeInsetsGeometry? padding;

  /// 卡片背景色，默认自适应毛玻璃半透明背景
  final Color? backgroundColor;

  /// 边框颜色，默认自适应半透明描边
  final Color? borderColor;

  /// 毛玻璃模糊度，默认 20
  final double blurSigma;

  /// 顶部圆角半径，默认 32
  final double topRadius;

  /// 最大高度占屏幕的比例（0.0 ~ 1.0），防止内容溢出屏幕，默认 0.9
  final double maxHeightFactor;

  /// 点击抽屉外部空白区域是否自动关闭，默认 true
  final bool barrierDismissible;

  const AppBottomSheet({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.landscapeMaxWidth = 960,
    this.showDragHandle = true,
    this.onDragHandleTap,
    this.padding = const EdgeInsets.fromLTRB(24, 0, 24, 32),
    this.backgroundColor,
    this.borderColor,
    this.blurSigma = 20,
    this.topRadius = 32,
    this.maxHeightFactor = 0.9,
    this.barrierDismissible = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);

    // 判断是否处于横屏模式（横屏或大屏桌面端通常宽度大于高度）
    final isLandscape = media.orientation == Orientation.landscape;
    final targetMaxWidth = isLandscape ? landscapeMaxWidth : maxWidth;
    final effectiveMaxWidth = math.min(targetMaxWidth, media.size.width);
    final effectiveMaxHeight = media.size.height * maxHeightFactor;

    final defaultBgColor = isDark
        ? Colors.black.withValues(alpha: 0.78)
        : theme.colorScheme.surface.withValues(alpha: 0.95);

    final defaultBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.3);

    Widget sheetCard = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // 拦截卡片区域内的点击事件，避免误触外部关闭
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: effectiveMaxWidth,
          maxHeight: effectiveMaxHeight,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor ?? defaultBgColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
            border: Border.all(
              color: borderColor ?? defaultBorderColor,
              width: 1,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDragHandle)
                  AppDragHandle(onTap: onDragHandleTap),
                Flexible(
                  child: Padding(
                    padding: padding ?? EdgeInsets.zero,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: barrierDismissible ? () => Navigator.of(context).pop() : null,
      child: blurSigma > 0
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: sheetCard,
              ),
            )
          : Align(
              alignment: Alignment.bottomCenter,
              child: sheetCard,
            ),
    );
  }
}

/// 弹出统一样式的 Modal Bottom Sheet 的便捷方法
Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = true,
  bool isDismissible = true,
  bool enableDrag = true,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    builder: builder,
  );
}
