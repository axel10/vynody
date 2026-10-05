import 'package:flutter/material.dart';

import '../widgets/app_bottom_sheet.dart';

/// 单个歌词操作选项
class LyricsOptionItem {
  final String value;
  final String label;
  final IconData icon;
  final bool enabled;
  final Color? iconColor;
  final bool isDestructive;

  const LyricsOptionItem({
    required this.value,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.iconColor,
    this.isDestructive = false,
  });
}

/// 歌词选项分组
class LyricsOptionGroup {
  final String? title;
  final List<LyricsOptionItem> items;

  const LyricsOptionGroup({
    this.title,
    required this.items,
  });
}

/// 显示自适应歌词操作面板（移动端为底部抽屉，宽屏下为居中弹窗）
Future<String?> showLyricsOptionsSheet(
  BuildContext context, {
  required List<LyricsOptionGroup> groups,
  String? title,
  String? subtitle,
}) async {
  return showAppAdaptiveModal<String?>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => LyricsOptionsSheet(
      groups: groups,
      title: title,
      subtitle: subtitle,
    ),
  );
}

/// 歌词选项自适应弹窗组件
class LyricsOptionsSheet extends StatelessWidget {
  const LyricsOptionsSheet({
    super.key,
    required this.groups,
    this.title,
    this.subtitle,
  });

  final List<LyricsOptionGroup> groups;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validGroups = groups.where((g) => g.items.isNotEmpty).toList();

    return AppAdaptiveSheet(
      sheetMaxWidth: 600,
      dialogMaxWidth: 520,
      landscapeMaxWidth: 720,
      title: title,
      subtitle: subtitle,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 24, left: 16, right: 16),
        itemCount: validGroups.length,
        separatorBuilder: (context, index) => Divider(
          height: 16,
          thickness: 0.5,
          indent: 8,
          endIndent: 8,
          color: theme.dividerColor.withValues(alpha: 0.15),
        ),
        itemBuilder: (context, groupIndex) {
          final group = validGroups[groupIndex];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (group.title != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: Text(
                    group.title!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              ...group.items.map((item) {
                final effectiveIconColor = !item.enabled
                    ? theme.disabledColor
                    : item.isDestructive
                        ? theme.colorScheme.error
                        : (item.iconColor ?? theme.colorScheme.onSurfaceVariant);

                final effectiveTextColor = !item.enabled
                    ? theme.disabledColor
                    : item.isDestructive
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface;

                return Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Icon(
                      item.icon,
                      size: 22,
                      color: effectiveIconColor,
                    ),
                    title: Text(
                      item.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: effectiveTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    enabled: item.enabled,
                    onTap: item.enabled
                        ? () => Navigator.of(context).pop(item.value)
                        : null,
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
