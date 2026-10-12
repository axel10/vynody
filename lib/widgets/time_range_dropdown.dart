import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/player/library/library_insights_service.dart';

class TimeRangeDropdown extends StatelessWidget {
  const TimeRangeDropdown({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final LibraryTimeRange selected;
  final ValueChanged<LibraryTimeRange> onChanged;

  static String formatRangeLabel(AppLocalizations l10n, LibraryTimeRange range) {
    return switch (range) {
      LibraryTimeRange.allTime => l10n.allTime,
      LibraryTimeRange.last7Days => l10n.pastWeek,
      LibraryTimeRange.last30Days => l10n.pastMonth,
      LibraryTimeRange.last90Days => l10n.past90Days,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = theme.colorScheme;

    return PopupMenuButton<LibraryTimeRange>(
      initialValue: selected,
      tooltip: formatRangeLabel(l10n, selected),
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (context) => LibraryTimeRange.values.map((range) {
        final isSelected = range == selected;
        return PopupMenuItem<LibraryTimeRange>(
          value: range,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 18,
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                formatRangeLabel(l10n, range),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? colorScheme.primary : null,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 12),
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ],
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              formatRangeLabel(l10n, selected),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
