import 'package:flutter/material.dart';

/// 多选整理态下条目右上角的通用排序手柄图标。
Widget buildZoomReorderHandle(BuildContext context) {
  return Icon(
    Icons.drag_handle_rounded,
    size: 18,
    color: Theme.of(context).colorScheme.primary,
  );
}

/// 多选整理态下多选条目收拢成合集时的通用拖拽浮层。
Widget buildZoomReorderPreview(
  BuildContext context, {
  required IconData icon,
  required int count,
}) {
  final theme = Theme.of(context);
  return Material(
    elevation: 8,
    borderRadius: BorderRadius.circular(14),
    color: theme.colorScheme.surfaceContainerHighest,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    ),
  );
}
