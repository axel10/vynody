import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_root_tooltip.dart';

/// 全局统一的纯色/微半透圆底返回按钮（类似 Apple Music / macOS 经典悬浮返回钮）
/// 适用于媒体库二级分类宿主页及三级详情页（专辑、艺人等），固定在顶部左侧。
class AppCircularBackButton extends StatelessWidget {
  const AppCircularBackButton({
    super.key,
    this.onPressed,
    this.tooltip,
    this.size = 34.0,
    this.iconSize = 18.0,
    this.icon = Icons.arrow_back_ios_new_rounded,
    this.backgroundColor,
    this.foregroundColor,
  });

  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final IconData icon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    // 默认纯色背景：浅色模式下为精致浅灰 (匹配 Apple Music)，深色模式下为深灰半透
    final effectiveBg = backgroundColor ??
        (isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.95));

    final effectiveFg = foregroundColor ?? theme.colorScheme.onSurface;

    return AppRootTooltip(
      message: tooltip ?? l10n?.goBack ?? '返回',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed ?? () => Navigator.of(context).maybePop(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: effectiveBg,
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: isDark ? 0.18 : 0.08),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
                  blurRadius: 5,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                icon,
                size: iconSize,
                color: effectiveFg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
