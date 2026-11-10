import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

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
  });

  final String title;
  final List<SortOptionItem<T>> options;
  final T currentField;
  final bool sortAscending;
  final void Function(T field, bool sortAscending)? onChanged;

  /// 某些排序字段没有升降序之分（例如「服务端原序」），此时禁用降序开关。
  /// 不传则所有字段都允许切换，保持既有调用点的行为。
  final bool Function(T field)? ascendingToggleEnabled;

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
                  fontWeight: _isDescending ? FontWeight.w600 : FontWeight.normal,
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
