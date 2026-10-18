import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../player/scanner/scanner_service.dart';
import '../player/scanner/scanner_sorting.dart';
import '../widgets/app_bottom_sheet.dart';

/// 弹出「目录排序」自适应浮层：
/// - 窄屏 / 竖屏：底部抽屉
/// - 宽屏 / 横屏 / 桌面端：居中弹窗
///
/// 选项只改浮层内的待生效状态，点「确定」才写入 [ScannerService]；
/// 直接关闭（关闭按钮 / 点遮罩 / 下拉）等同于取消，不改任何设置。
Future<void> showFolderSortSheet({
  required BuildContext context,
  required ScannerService scanner,
  required String folderPath,
}) {
  return showAppAdaptiveModal<void>(
    context: context,
    builder: (_) => FolderSortSheet(scanner: scanner, folderPath: folderPath),
  );
}

/// 目录排序设置浮层
///
/// 「排序方式 / 排序顺序」始终作用于**当前生效**的那一份设置：
/// - 未开启「仅此目录」时写全局，此目录及所有未覆盖的目录一起变；
/// - 开启后写此目录的独立覆盖，其它目录不受影响。
class FolderSortSheet extends StatefulWidget {
  const FolderSortSheet({
    super.key,
    required this.scanner,
    required this.folderPath,
  });

  final ScannerService scanner;

  /// 当前所在目录
  final String folderPath;

  @override
  State<FolderSortSheet> createState() => _FolderSortSheetState();
}

class _FolderSortSheetState extends State<FolderSortSheet> {
  late bool _localized;
  late SortCriteria _criteria;
  late SortOrder _order;

  @override
  void initState() {
    super.initState();
    _localized = widget.scanner.hasSortOverrideForFolder(widget.folderPath);
    // 打开时一律展示「当前生效」的设置，而不是全局设置
    final settings = widget.scanner.getSortSettingsForFolder(widget.folderPath);
    _criteria = settings.criteria;
    _order = settings.order;
  }

  void _selectCriteria(SortCriteria criteria) {
    if (criteria == _criteria) return;
    setState(() => _criteria = criteria);
  }

  void _selectOrder(SortOrder order) {
    if (order == _order) return;
    setState(() => _order = order);
  }

  /// 开关只改待生效状态：关掉时把选项同步成全局值，因为确定后此目录跟随全局。
  void _toggleLocalized(bool value) {
    if (value == _localized) return;
    setState(() {
      _localized = value;
      if (!value) {
        final global = widget.scanner.getGlobalSortSettings();
        _criteria = global.criteria;
        _order = global.order;
      }
    });
  }

  /// 确定：把浮层里的选择一次性写下去，然后关闭。
  void _confirm() {
    widget.scanner.applySortSettings(
      widget.folderPath,
      localized: _localized,
      criteria: _criteria,
      order: _order,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AppAdaptiveSheet(
      sheetMaxWidth: 600,
      dialogMaxWidth: 520,
      landscapeMaxWidth: 720,
      title: l10n.sort,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SortOptionGroup<SortCriteria>(
              title: l10n.sortBy,
              groupValue: _criteria,
              onChanged: _selectCriteria,
              options: [
                _SortOption(
                  value: SortCriteria.title,
                  label: l10n.title,
                  icon: Icons.title_rounded,
                ),
                _SortOption(
                  value: SortCriteria.filename,
                  label: l10n.fileName,
                  icon: Icons.insert_drive_file_outlined,
                ),
                _SortOption(
                  value: SortCriteria.trackNumber,
                  label: l10n.trackNumber,
                  icon: Icons.format_list_numbered_rounded,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SortOptionGroup<SortOrder>(
              title: l10n.sortOrder,
              groupValue: _order,
              onChanged: _selectOrder,
              options: [
                _SortOption(
                  value: SortOrder.ascending,
                  label: l10n.ascending,
                  icon: Icons.arrow_upward_rounded,
                ),
                _SortOption(
                  value: SortOrder.descending,
                  label: l10n.descending,
                  icon: Icons.arrow_downward_rounded,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SortScopeCard(
              localized: _localized,
              onChanged: _toggleLocalized,
              title: l10n.sortOnlyThisFolder,
              subtitle: _localized
                  ? l10n.sortOnlyThisFolderHint
                  : l10n.sortFollowsGlobalHint,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _confirm,
                    child: Text(l10n.confirm),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 「仅此目录」开关卡片
class _SortScopeCard extends StatelessWidget {
  const _SortScopeCard({
    required this.localized,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final bool localized;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.025),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: SwitchListTile(
        value: localized,
        onChanged: onChanged,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: localized ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        secondary: Icon(
          localized ? Icons.folder_outlined : Icons.public_rounded,
          size: 20,
          color: localized
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 排序选项条目
class _SortOption<T> {
  const _SortOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

/// 一组单选排序选项（标题 + 圆角卡片内的若干行）
class _SortOptionGroup<T> extends StatelessWidget {
  const _SortOptionGroup({
    required this.title,
    required this.groupValue,
    required this.onChanged,
    required this.options,
  });

  final String title;
  final T groupValue;
  final ValueChanged<T> onChanged;
  final List<_SortOption<T>> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dividerColor = theme.dividerColor.withValues(alpha: 0.15);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Material(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.025),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: RadioGroup<T>(
            groupValue: groupValue,
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < options.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      indent: 16,
                      endIndent: 16,
                      color: dividerColor,
                    ),
                  _buildOptionTile(context, options[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionTile(BuildContext context, _SortOption<T> option) {
    final theme = Theme.of(context);
    final isSelected = option.value == groupValue;

    return RadioListTile<T>(
      value: option.value,
      selected: isSelected,
      dense: true,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      tileColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      title: Text(
        option.label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      secondary: Icon(
        option.icon,
        size: 20,
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
