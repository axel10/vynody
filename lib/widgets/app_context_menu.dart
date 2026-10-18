import 'package:flutter/material.dart';

/// Centralized utility for presenting context menus and bottom sheets
/// across the entire application with unified top-level layering, position
/// calculations, and consistent visual styling.
class AppContextMenu {
  AppContextMenu._();

  /// Default rounded corners for all context popup menus.
  static final ShapeBorder defaultMenuShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );

  /// Shows a context menu at [position] guaranteeing that:
  /// 1. The menu renders on the root [Navigator] layer ([useRootNavigator: true])
  ///    so it is never covered by floating overlays, docks, or mini players.
  /// 2. The coordinate calculation uses the root [Overlay] ([rootOverlay: true]).
  static Future<T?> show<T>({
    required BuildContext context,
    required Offset position,
    required List<PopupMenuEntry<T>> items,
    T? initialValue,
    double? elevation,
    ShapeBorder? shape,
    Color? color,
    Color? shadowColor,
    Color? surfaceTintColor,
    BoxConstraints? constraints,
  }) async {
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    if (overlay == null) return null;

    return showMenu<T>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: items,
      initialValue: initialValue,
      elevation: elevation ?? 8.0,
      shape: shape ?? defaultMenuShape,
      color: color,
      shadowColor: shadowColor,
      surfaceTintColor: surfaceTintColor,
      constraints: constraints,
    );
  }

  /// Builds a standard popup menu item with an icon and label adhering to
  /// the app's theme and disabled states.
  static PopupMenuItem<T> buildItem<T>({
    required T value,
    required String label,
    required IconData icon,
    required BuildContext context,
    bool enabled = true,
    Color? iconColor,
    TextStyle? textStyle,
  }) {
    final theme = Theme.of(context);
    final defaultIconColor = theme.colorScheme.onSurfaceVariant;
    return PopupMenuItem<T>(
      value: value,
      enabled: enabled,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 20,
            color: enabled
                ? (iconColor ?? defaultIconColor)
                : defaultIconColor.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle ??
                  theme.textTheme.bodyMedium?.copyWith(
                    color: enabled
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows a modal bottom sheet guaranteeing top-level root navigator display.
  static Future<T?> showModalSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    Color backgroundColor = Colors.transparent,
    double elevation = 0,
    bool enableDrag = true,
    bool isDismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor,
      elevation: elevation,
      enableDrag: enableDrag,
      isDismissible: isDismissible,
      builder: builder,
    );
  }
}

/// A single menu action shared by the popup context menu (right click) and the
/// long-press bottom sheet, so both surfaces are configured in one place.
class ContextMenuAction {
  const ContextMenuAction({
    required this.value,
    required this.label,
    required this.icon,
    this.enabled = true,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool enabled;
}

/// Builds popup menu entries from grouped [actions]. A divider is inserted
/// between consecutive non-empty groups.
List<PopupMenuEntry<String>> buildContextMenuPopupItems(
  BuildContext context,
  List<List<ContextMenuAction>> actions,
) {
  final entries = <PopupMenuEntry<String>>[];
  var isFirstGroup = true;
  for (final group in actions) {
    if (group.isEmpty) continue;
    if (!isFirstGroup) entries.add(const PopupMenuDivider());
    isFirstGroup = false;
    for (final action in group) {
      entries.add(
        AppContextMenu.buildItem<String>(
          value: action.value,
          label: action.label,
          icon: action.icon,
          enabled: action.enabled,
          context: context,
        ),
      );
    }
  }
  return entries;
}

/// Builds bottom sheet rows from grouped [actions]. Groups are flattened
/// (the sheet has no group dividers).
List<Widget> buildContextMenuSheetItems(
  BuildContext context,
  List<List<ContextMenuAction>> actions,
) {
  final theme = Theme.of(context);
  return [
    for (final group in actions)
      for (final action in group)
        ListTile(
          leading: Icon(
            action.icon,
            color: action.enabled
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          title: Text(
            action.label,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: action.enabled
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          enabled: action.enabled,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: () => Navigator.pop(context, action.value),
        ),
  ];
}
