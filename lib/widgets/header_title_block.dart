import 'package:flutter/material.dart';

/// 页面页头共用的「主标题 + 统计信息副标题」纵向排布组件。
///
/// 统一将统计信息或副标题置于主标题正下方，并保持与队列页一致的间距与字色：
/// - 主标题默认使用 [TextTheme.headlineSmall] + `FontWeight.w800`；
/// - 统计信息默认使用 [TextTheme.bodyMedium] + `colorScheme.onSurfaceVariant`，
///   单行省略；
/// - 如需在副标题行嵌入交互控件（例如队列页随机模式下的视图切换器），
///   可通过 [subtitleWidget] 传入自定义组件。
class HeaderTitleBlock extends StatelessWidget {
  const HeaderTitleBlock({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.titleStyle,
    this.subtitleStyle,
    this.spacing = 4.0,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.titleMaxLines,
    this.titleOverflow,
  });

  /// 主标题文字。
  final String title;

  /// 统计信息或副标题文字；当 [subtitleWidget] 非空时忽略本字段。
  final String? subtitle;

  /// 自定义副标题组件（优先级高于 [subtitle]）。
  final Widget? subtitleWidget;

  /// 主标题文字样式，缺省使用 [TextTheme.headlineSmall] + `w800`。
  final TextStyle? titleStyle;

  /// 副标题文字样式，缺省使用 [TextTheme.bodyMedium] + `onSurfaceVariant`。
  final TextStyle? subtitleStyle;

  /// 主标题与副标题之间的纵向间距，缺省为 `4.0`。
  final double spacing;

  /// 纵向主轴对齐方式，缺省为 [MainAxisAlignment.center]。
  final MainAxisAlignment mainAxisAlignment;

  /// 主标题最大行数，缺省不限制。
  final int? titleMaxLines;

  /// 主标题溢出处理方式。
  final TextOverflow? titleOverflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final effectiveTitleStyle = titleStyle ??
        theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
        );

    final effectiveSubtitleStyle = subtitleStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );

    final Widget? resolvedSubtitle;
    if (subtitleWidget != null) {
      resolvedSubtitle = subtitleWidget;
    } else if (subtitle != null && subtitle!.isNotEmpty) {
      resolvedSubtitle = Text(
        subtitle!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: effectiveSubtitleStyle,
      );
    } else {
      resolvedSubtitle = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: titleMaxLines,
          overflow: titleOverflow,
          style: effectiveTitleStyle,
        ),
        if (resolvedSubtitle != null) ...[
          SizedBox(height: spacing),
          resolvedSubtitle,
        ],
      ],
    );
  }
}
