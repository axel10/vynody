import 'package:flutter/material.dart';

/// 顶部浮动胶囊的显隐过渡：上滑淡出 + 隐藏时让出点击。
///
/// 只管过渡，不管定位 —— 调用方自己包 `Positioned`（各页面的 left/height/
/// 安全区避让各不相同，塞进来接口会被撑胖）。
///
/// 媒体库两个二级宿主此前各手写了一份 `AnimatedSlide + AnimatedOpacity +
/// IgnorePointer`，条件里还要叠「横屏 / 多选 / 详情页压栈」，同一套东西出现
/// 两份就等于两份可以各自漂移的显隐规则。
class FloatingCapsuleHeader extends StatelessWidget {
  const FloatingCapsuleHeader({
    super.key,
    required this.visible,
    required this.child,
    this.duration = const Duration(milliseconds: 250),
  });

  /// 是否显示。由调用方算（各页面的排除条件不同，这里只认结果）。
  final bool visible;

  final Widget child;

  /// 让位给详情页时必须传 [Duration.zero]：详情页顶栏本来就在同一位置，
  /// 播一段淡出只会让两个标题交叠闪一下。
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, -1.0),
      duration: duration,
      curve: Curves.easeInOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: duration,
        curve: Curves.easeInOutCubic,
        child: IgnorePointer(
          ignoring: !visible,
          child: child,
        ),
      ),
    );
  }
}
