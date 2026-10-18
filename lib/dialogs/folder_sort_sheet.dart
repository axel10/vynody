import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../player/scanner/scanner_service.dart';
import '../player/scanner/scanner_sorting.dart';
import '../widgets/app_bottom_sheet.dart';

/// 弹出「目录排序」自适应浮层：
/// - 窄屏 / 竖屏：底部抽屉
/// - 宽屏 / 横屏 / 桌面端：居中弹窗
///
/// 选项即时生效（写入 [ScannerService] 的排序设置），无需二次确认。
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
class FolderSortSheet extends StatefulWidget {
  const FolderSortSheet({
    super.key,
    required this.scanner,
    required this.folderPath,
  });

  final ScannerService scanner;

  /// 当前所在目录（用于「当前目录」作用域读写）
  final String folderPath;

  @override
  State<FolderSortSheet> createState() => _FolderSortSheetState();
}

class _FolderSortSheetState extends State<FolderSortSheet> {
  late SortScope _scope;
  late SortCriteria _criteria;
  late SortOrder _order;

  @override
  void initState() {
    super.initState();
    _scope = widget.scanner.hasSortOverrideForFolder(widget.folderPath)
        ? SortScope.currentFolder
        : SortScope.global;
    final settings = _settingsFor(_scope);
    _criteria = settings.criteria;
    _order = settings.order;
  }

  FolderSortSettings _settingsFor(SortScope scope) {
    return scope == SortScope.currentFolder
        ? widget.scanner.getSortSettingsForFolder(widget.folderPath)
        : widget.scanner.getGlobalSortSettings();
  }

  /// 切换作用域只切换「正在编辑哪一份设置」，不立刻写库
  void _selectScope(SortScope scope) {
    if (scope == _scope) return;
    final settings = _settingsFor(scope);
    setState(() {
      _scope = scope;
      _criteria = settings.criteria;
      _order = settings.order;
    });
  }

  void _selectCriteria(SortCriteria criteria) {
    if (criteria == _criteria) return;
    setState(() => _criteria = criteria);
    widget.scanner.setSortCriteria(
      criteria,
      scope: _scope,
      folderPath: widget.folderPath,
    );
  }

  void _selectOrder(SortOrder order) {
    if (order == _order) return;
    setState(() => _order = order);
    widget.scanner.setSortOrder(
      order,
      scope: _scope,
      folderPath: widget.folderPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AppAdaptiveSheet(
      sheetMaxWidth: 600,
      dialogMaxWidth: 520,
      landscapeMaxWidth: 720,
      title: l10n.sortBy,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SortOptionGroup<SortScope>(
              title: l10n.sortScope,
              groupValue: _scope,
              onChanged: _selectScope,
              options: [
                _SortOption(
                  value: SortScope.currentFolder,
                  label: l10n.currentFolderScope,
                  icon: Icons.folder_outlined,
                ),
                _SortOption(
                  value: SortScope.global,
                  label: l10n.globalScope,
                  icon: Icons.public_rounded,
                ),
              ],
            ),
            const SizedBox(height: 20),
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
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.done),
            ),
          ],
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
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.025),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
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
