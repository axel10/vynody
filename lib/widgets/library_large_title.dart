import 'package:flutter/material.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/utils/app_icons.dart';
import 'app_tooltip.dart';

/// 媒体库二级分类宿主环境上下文。
///
/// 由 [LibrarySubHostPage] 在子分类路由树根节点处提供，向下传递避让边距与统一的
/// 返回上一级（仪表盘）回调，避免所有子分类 Tab 逐层手动透传。
class LibrarySubHostScope extends InheritedWidget {
  const LibrarySubHostScope({
    super.key,
    this.onBack,
    this.topPadding = 0.0,
    this.leftPadding = 0.0,
    required super.child,
  });

  /// 退出二级宿主、返回媒体库首页仪表盘的回调。
  final VoidCallback? onBack;

  /// 内容区避让顶部状态栏/窗口栏的安全边距。
  final double topPadding;

  /// 内容区避让横屏侧边栏的左侧边距。
  final double leftPadding;

  static LibrarySubHostScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LibrarySubHostScope>();
  }

  static VoidCallback? onBackOf(BuildContext context) {
    return maybeOf(context)?.onBack;
  }

  @override
  bool updateShouldNotify(LibrarySubHostScope oldWidget) {
    return onBack != oldWidget.onBack ||
        topPadding != oldWidget.topPadding ||
        leftPadding != oldWidget.leftPadding;
  }
}

/// 本地媒体库二级页面统一的大标题组件。
///
/// 整合了左侧返回按钮、分类主标题与条目计数副标题：
/// - 左侧返回按钮自适应居中对齐，支持通过属性指定或自动从 [LibrarySubHostScope] 读取；
/// - 主标题与副标题之间保持基线对齐（[TextBaseline.alphabetic]），避免视觉高低不一。
class LibraryLargeTitle extends StatelessWidget {
  const LibraryLargeTitle({
    super.key,
    required this.title,
    this.countLabel,
    this.showBackButton = true,
    this.onBack,
    this.titleStyle,
    this.countStyle,
    this.buttonSpacing = 6.0,
  });

  /// 分类主标题文字（例如“专辑”、“艺术家”、“已评分”）。
  final String title;

  /// 条目数量或副标题信息（例如“128 张专辑”）。
  final String? countLabel;

  /// 是否展示左侧返回箭头按钮。
  final bool showBackButton;

  /// 自定义返回按钮点击回调。缺省时自动从 [LibrarySubHostScope] 获取，
  /// 若未处于作用域内则降级使用 [Navigator.maybePop]。
  final VoidCallback? onBack;

  /// 主标题文字样式，缺省使用 [TextTheme.headlineMedium]。
  final TextStyle? titleStyle;

  /// 计数副标题文字样式，缺省使用 [TextTheme.bodyMedium]。
  final TextStyle? countStyle;

  /// 返回按钮与大标题文字之间的横向间距，默认为 6.0。
  final double buttonSpacing;

  void _handleBack(BuildContext context) {
    if (onBack != null) {
      onBack!();
      return;
    }
    final scopeOnBack = LibrarySubHostScope.onBackOf(context);
    if (scopeOnBack != null) {
      scopeOnBack();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final effectiveTitleStyle = titleStyle ??
        theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        );

    final effectiveCountStyle = countStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        );

    final titleWithCount = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: effectiveTitleStyle,
        ),
        if (countLabel != null && countLabel!.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              countLabel!,
              style: effectiveCountStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    final backButton = showBackButton
        ? Padding(
            padding: EdgeInsets.only(right: buttonSpacing),
            // 横屏下本按钮紧贴 Rail 栏右侧，而 Rail 在 MainLayout 的 Stack 里画在页面之后。
            // 默认 Tooltip 会插进页面自己那层 Overlay（二级宿主内还嵌了两级 Navigator），
            // 于是气泡左半边被 Rail 盖住；改走根 Overlay，让提示浮在整页之上。
            child: AppTooltip(
              message: l10n?.goBack ?? 'Back',
              useRootOverlay: true,
              child: IconButton(
                icon: const Icon(kAppBackIcon, size: 28),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                onPressed: () => _handleBack(context),
              ),
            ),
          )
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ?backButton,
        Flexible(child: titleWithCount),
      ],
    );
  }
}
