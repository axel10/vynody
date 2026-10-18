import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// 洞察页（最近播放 / 最多播放 / 最近添加）行尾的指标文案：
/// 主行粗体（播放次数、入库日期等），副行灰色补充说明。
class InsightMetricText extends StatelessWidget {
  const InsightMetricText({super.key, required this.primary, this.secondary});

  final String primary;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          primary,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.right,
        ),
        if (secondary != null) ...[
          const SizedBox(height: 2),
          Text(
            secondary!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ],
    );
  }
}

String formatInsightDate(BuildContext context, int? millis) {
  if (millis == null) return '';
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMd(
    locale,
  ).format(DateTime.fromMillisecondsSinceEpoch(millis));
}

String formatRelativeInsightDate(BuildContext context, int? millis) {
  if (millis == null) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final difference = now.difference(date);
  final l10n = AppLocalizations.of(context);

  if (difference.inSeconds < 60 && difference.inSeconds >= 0) {
    return l10n?.justNow ?? 'Just now';
  } else if (difference.inMinutes < 60 && difference.inMinutes >= 1) {
    return l10n?.minutesAgo(difference.inMinutes) ?? '${difference.inMinutes}m ago';
  } else if (difference.inHours < 24 && difference.inHours >= 1 && now.day == date.day) {
    final timeStr = DateFormat.Hm(Localizations.localeOf(context).toLanguageTag()).format(date);
    return l10n?.todayTime(timeStr) ?? 'Today $timeStr';
  } else if (now.year == date.year && now.subtract(const Duration(days: 1)).day == date.day && now.subtract(const Duration(days: 1)).month == date.month) {
    final timeStr = DateFormat.Hm(Localizations.localeOf(context).toLanguageTag()).format(date);
    return l10n?.yesterdayTime(timeStr) ?? 'Yesterday $timeStr';
  } else if (now.year == date.year) {
    return DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag()).format(date);
  } else {
    return DateFormat.yMd(Localizations.localeOf(context).toLanguageTag()).format(date);
  }
}
