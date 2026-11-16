import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vynody/player/audio/audio_riverpod.dart'
    show isBlurEffectEnabledProvider;
import 'package:vynody/utils/blur_constants.dart';

/// 向子树中的 [FrostedHeaderBar] 传递顶部安全避让高度（如状态栏 / 窗口标题栏高度）。
///
/// 在 `Stack` 叠层页头中，毛玻璃背景需要延伸到页面最顶端 `top: 0`，而内部内容需避让
/// 顶部系统区域；通过本作用域透传，无需修改所有调用方的页头构造函数即可无缝衔接。
class FrostedHeaderTopPadding extends InheritedWidget {
  const FrostedHeaderTopPadding({
    super.key,
    required this.topPadding,
    required super.child,
  });

  final double topPadding;

  static double of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<FrostedHeaderTopPadding>()
            ?.topPadding ??
        0.0;
  }

  @override
  bool updateShouldNotify(FrostedHeaderTopPadding oldWidget) {
    return topPadding != oldWidget.topPadding;
  }
}

/// 与队列页同款的半透明毛玻璃页头容器。
///
/// 使用 [AppBackdropFilter]（[AppBlur.heavyFilter]）与 [AppBlur.heavySurface]，
/// 配合底部细分割线；当传入非空的 [backgroundColor]（例如 3D Cover Flow 透明顶栏）
/// 或 [frosted] 为 `false` 时，退化为普通 [Container] 以保留调用方自定义底色。
class FrostedHeaderBar extends ConsumerWidget {
  const FrostedHeaderBar({
    super.key,
    required this.child,
    this.topPadding,
    this.padding = EdgeInsets.zero,
    this.hasBorder = true,
    this.backgroundColor,
    this.borderColor,
    this.frosted = true,
  });

  final Widget child;

  /// 顶部额外避让高度；为 `null` 时自动读取 [FrostedHeaderTopPadding]。
  final double? topPadding;

  /// 内部内容边距（不含 [topPadding]）。
  final EdgeInsetsGeometry padding;

  /// 是否显示底部分割线。
  final bool hasBorder;

  /// 自定义背景色；非空时不启用毛玻璃滤镜。
  final Color? backgroundColor;

  /// 自定义底部分割线颜色。
  final Color? borderColor;

  /// 是否启用毛玻璃效果。
  final bool frosted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final effectiveTopPadding =
        topPadding ?? FrostedHeaderTopPadding.of(context);
    final effectivePadding = effectiveTopPadding > 0
        ? padding.add(EdgeInsets.only(top: effectiveTopPadding))
        : padding;

    bool isBlurEnabled;
    try {
      isBlurEnabled = ref.watch(isBlurEffectEnabledProvider);
    } catch (_) {
      isBlurEnabled = true;
    }

    final useFrosted = frosted && backgroundColor == null;
    final border = hasBorder
        ? Border(
            bottom: BorderSide(
              color: borderColor ??
                  (useFrosted
                      ? theme.dividerColor.withValues(alpha: 0.12)
                      : theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.25)),
              width: useFrosted ? 0.8 : 1.0,
            ),
          )
        : null;

    if (!useFrosted) {
      return Container(
        padding: effectivePadding,
        decoration: BoxDecoration(
          color: backgroundColor ?? theme.colorScheme.surface,
          border: border,
        ),
        child: child,
      );
    }

    return ClipRect(
      child: AppBackdropFilter(
        enabled: isBlurEnabled,
        filter: AppBlur.heavyFilter,
        child: Container(
          padding: effectivePadding,
          decoration: BoxDecoration(
            color: AppBlur.heavySurface(
              context,
              isBlurEnabled: isBlurEnabled,
            ),
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 监听子组件渲染高度并在变化时通过 [onHeightChanged] 回调。
class HeaderSizeReporter extends SingleChildRenderObjectWidget {
  const HeaderSizeReporter({
    super.key,
    required this.onHeightChanged,
    required super.child,
  });

  final ValueChanged<double> onHeightChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderHeaderSizeReporter(onHeightChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderObject renderObject,
  ) {
    (renderObject as _RenderHeaderSizeReporter).onHeightChanged =
        onHeightChanged;
  }
}

class _RenderHeaderSizeReporter extends RenderProxyBox {
  _RenderHeaderSizeReporter(this.onHeightChanged);

  ValueChanged<double> onHeightChanged;
  double? _lastHeight;

  @override
  void performLayout() {
    super.performLayout();
    final newHeight = size.height;
    if (_lastHeight == null || (newHeight - _lastHeight!).abs() > 0.5) {
      _lastHeight = newHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onHeightChanged(newHeight);
      });
    }
  }
}

/// 将 [header] 悬浮叠放在 [bodyBuilder] 构建的滚动区之上，实现滚动内容透出毛玻璃效果。
///
/// 会自动测量 [header] 的实际渲染高度并回传给 [bodyBuilder]，供底层滚动区在顶部预留
/// 精确的内边距或占位 Sliver，避免首行内容被顶部栏遮挡。
class FrostedOverlayHeaderStack extends StatefulWidget {
  const FrostedOverlayHeaderStack({
    super.key,
    required this.header,
    required this.bodyBuilder,
    this.topPadding = 0.0,
    this.initialHeaderHeight = 76.0,
  });

  final Widget header;
  final Widget Function(BuildContext context, double headerHeight) bodyBuilder;
  final double topPadding;
  final double initialHeaderHeight;

  @override
  State<FrostedOverlayHeaderStack> createState() =>
      _FrostedOverlayHeaderStackState();
}

class _FrostedOverlayHeaderStackState extends State<FrostedOverlayHeaderStack> {
  late final ValueNotifier<double> _headerHeight;

  @override
  void initState() {
    super.initState();
    _headerHeight =
        ValueNotifier<double>(widget.topPadding + widget.initialHeaderHeight);
  }

  @override
  void didUpdateWidget(covariant FrostedOverlayHeaderStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topPadding != widget.topPadding) {
      final delta = widget.topPadding - oldWidget.topPadding;
      _headerHeight.value = (_headerHeight.value + delta).clamp(0.0, 600.0);
    }
  }

  @override
  void dispose() {
    _headerHeight.dispose();
    super.dispose();
  }

  void _onHeaderHeightChanged(double height) {
    if (!mounted) return;
    if ((_headerHeight.value - height).abs() > 0.5) {
      _headerHeight.value = height;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _headerHeight,
            builder: (context, height, _) => widget.bodyBuilder(context, height),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: FrostedHeaderTopPadding(
            topPadding: widget.topPadding,
            child: HeaderSizeReporter(
              onHeightChanged: _onHeaderHeightChanged,
              child: widget.header,
            ),
          ),
        ),
      ],
    );
  }
}
