import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class QueryConditionChip extends StatelessWidget {
  const QueryConditionChip({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
    this.onEdit,
    this.maxWidth = 260,
    this.activeBackgroundColor,
    this.inactiveBackgroundColor,
    this.activeBorderColor,
    this.inactiveBorderColor,
    this.activeTextColor,
    this.inactiveTextColor,
    this.activeIconColor,
    this.inactiveIconColor,
    this.editTooltip,
  });

  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final double maxWidth;
  final Color? activeBackgroundColor;
  final Color? inactiveBackgroundColor;
  final Color? activeBorderColor;
  final Color? inactiveBorderColor;
  final Color? activeTextColor;
  final Color? inactiveTextColor;
  final Color? activeIconColor;
  final Color? inactiveIconColor;
  final String? editTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final isEnabled = enabled;
    final backgroundColor = isEnabled
        ? activeBackgroundColor ??
              colorScheme.primaryContainer.withValues(alpha: 0.72)
        : inactiveBackgroundColor ?? colorScheme.surfaceContainerHighest;
    final borderColor = isEnabled
        ? activeBorderColor ?? colorScheme.primary.withValues(alpha: 0.28)
        : inactiveBorderColor ?? colorScheme.outlineVariant;
    final textColor = isEnabled
        ? activeTextColor ?? colorScheme.onPrimaryContainer
        : inactiveTextColor ?? colorScheme.onSurfaceVariant;
    final iconColor = isEnabled
        ? activeIconColor ?? colorScheme.primary
        : inactiveIconColor ?? colorScheme.onSurfaceVariant;
    final textDecoration = isEnabled
        ? TextDecoration.none
        : TextDecoration.lineThrough;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isEnabled
                  ? Icons.check_circle_outline_rounded
                  : Icons.block_rounded,
              size: 13,
              color: iconColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$label: $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  decoration: textDecoration,
                ),
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: onEdit,
                style: IconButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                icon: Icon(
                  Icons.edit_rounded,
                  size: 13,
                  color: isEnabled
                      ? iconColor.withValues(alpha: 0.82)
                      : iconColor.withValues(alpha: 0.55),
                ),
                tooltip: editTooltip ?? l10n?.editQueryCondition,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
