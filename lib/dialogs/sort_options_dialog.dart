import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 打开「排序方式」弹窗的统一入口（本地库与远程库共用）。
///
/// 返回 null 表示用户取消；否则携带新的「字段 + 升降序」。
/// 各调用点只负责提供标题、当前值与选项清单，不再各自写 showDialog 样板。
Future<SortResult<T>?> showSortOptionsDialog<T>({
  required BuildContext context,
  required String title,
  required T currentField,
  required bool sortAscending,
  required List<SortOptionItem<T>> options,
  bool Function(T field)? ascendingToggleEnabled,
  bool showDirectionToggle = true,
}) {
  return showDialog<SortResult<T>>(
    context: context,
    builder: (dialogContext) => SortOptionsDialog<T>(
      title: title,
      currentField: currentField,
      sortAscending: sortAscending,
      options: options,
      ascendingToggleEnabled: ascendingToggleEnabled,
      showDirectionToggle: showDirectionToggle,
    ),
  );
}

class SortOptionItem<T> {
  final T value;
  final String label;
  final IconData icon;

  const SortOptionItem({
    required this.value,
    required this.label,
    required this.icon,
  });
}

class SortResult<T> {
  final T field;
  final bool sortAscending;

  const SortResult({
    required this.field,
    required this.sortAscending,
  });
}

class SortOptionsDialog<T> extends StatefulWidget {
  const SortOptionsDialog({
    super.key,
    required this.title,
    required this.options,
    required this.currentField,
    required this.sortAscending,
    this.onChanged,
    this.ascendingToggleEnabled,
    this.showDirectionToggle = true,
  });

  final String title;
  final List<SortOptionItem<T>> options;
  final T currentField;
  final bool sortAscending;
  final void Function(T field, bool sortAscending)? onChanged;

  /// 某些排序字段没有升降序之分（例如「服务端原序」），此时禁用降序开关。
  /// 不传则所有字段都允许切换，保持既有调用点的行为。
  final bool Function(T field)? ascendingToggleEnabled;

  /// 某些排序（如远程服务端的 sortType）整个没有方向概念，此时连
  /// 降序开关行都不渲染。默认 true 保持既有行为。
  final bool showDirectionToggle;

  @override
  State<SortOptionsDialog<T>> createState() => _SortOptionsDialogState<T>();
}

class _SortOptionsDialogState<T> extends State<SortOptionsDialog<T>> {
  late T _selectedField;
  late bool _isDescending;

  @override
  void initState() {
    super.initState();
    _selectedField = widget.currentField;
    _isDescending = !widget.sortAscending;
  }

  void _notifyChange() {
    widget.onChanged?.call(_selectedField, !_isDescending);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final toggleEnabled =
        widget.ascendingToggleEnabled?.call(_selectedField) ?? true;

    Widget buildDirectionSection() {
      if (!widget.showDirectionToggle) {
        return const SizedBox.shrink();
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          CheckboxListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              l10n.enableDescending,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight:
                    _isDescending ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              (!toggleEnabled || !_isDescending)
                  ? l10n.currentlyAscending
                  : l10n.currentlyDescending,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            value: _isDescending && toggleEnabled,
            onChanged: toggleEnabled
                ? (val) {
                    setState(() {
                      _isDescending = val ?? false;
                    });
                    _notifyChange();
                  }
                : null,
          ),
        ],
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.sort_rounded,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Text(widget.title),
        ],
      ),
      content: SizedBox(
        width: 320,
        // 矮窗口（横屏手机、小屏分栏）下选项多时整列放不下，必须可滚动。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            ...widget.options.map((option) {
              final isSelected = option.value == _selectedField;
              return RadioListTile<T>(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                secondary: Icon(
                  option.icon,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  option.label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                value: option.value,
                groupValue: _selectedField,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedField = val;
                    });
                    _notifyChange();
                  }
                },
              );
            }),
            buildDirectionSection(),
          ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              SortResult<T>(
                field: _selectedField,
                sortAscending: !_isDescending,
              ),
            );
          },
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}
