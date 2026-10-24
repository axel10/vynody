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

/// Builds a standard popup menu item with an icon and label adhering to the
/// app's theme and disabled states.
///
/// This is the single constructor for popup menu rows across the app; every
/// context menu (song, album, artist, genre, year, folder, remote) goes through
/// it so a styling change only has to happen here.
PopupMenuItem<T> buildContextMenuItem<T>({
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

/// A single menu action shared by the popup context menu (right click) and the
/// long-press bottom sheet, so both surfaces are configured in one place.
class ContextMenuAction {
  const ContextMenuAction({
    required this.value,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.accentColor,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool enabled;

  /// 强调色（如「删除」用 error、会员项用品牌色）。
  ///
  /// 弹窗只给图标上色，底部面板图标与文字同色——两者各自沿用历史观感，
  /// 所以这里只描述颜色，不描述落在哪个位置。
  final Color? accentColor;
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
        buildContextMenuItem<String>(
          value: action.value,
          label: action.label,
          icon: action.icon,
          enabled: action.enabled,
          iconColor: action.accentColor,
          context: context,
        ),
      );
    }
  }
  return entries;
}

/// 底部操作面板的单行。
///
/// 全应用的面板行都从这里出：歌曲、文件夹、远程实体、本地实体各自造过一份
/// 一模一样的 ListTile，差异只是图标颜色与行高。
///
/// [dense] 压缩行高与左右内边距，用于条目较多的面板（歌曲菜单最多十几项）。
Widget buildContextMenuSheetItem(
  BuildContext context,
  ContextMenuAction action, {
  bool dense = false,
}) {
  final theme = Theme.of(context);
  final accent = action.accentColor;
  final baseColor = accent ?? theme.colorScheme.onSurfaceVariant;
  return ListTile(
    leading: Icon(
      action.icon,
      size: dense ? 22 : null,
      color: action.enabled ? baseColor : baseColor.withValues(alpha: 0.4),
    ),
    title: Text(
      action.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: action.enabled
            ? (accent ?? theme.colorScheme.onSurface)
            : theme.colorScheme.onSurface.withValues(alpha: 0.4),
      ),
    ),
    enabled: action.enabled,
    contentPadding: dense
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
        : null,
    visualDensity: dense
        ? const VisualDensity(horizontal: 0, vertical: -1)
        : null,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    onTap: () => Navigator.pop(context, action.value),
  );
}

/// Builds bottom sheet rows from grouped [actions]. Groups are flattened
/// (the sheet has no group dividers).
List<Widget> buildContextMenuSheetItems(
  BuildContext context,
  List<List<ContextMenuAction>> actions, {
  bool dense = false,
}) {
  return [
    for (final group in actions)
      for (final action in group)
        buildContextMenuSheetItem(context, action, dense: dense),
  ];
}

/// 底部操作面板的外壳（圆角浮层 + 头部 + 动作列表）。
///
/// 四个面板各自手抄过同一段外壳：实体菜单、远程文件夹、本地文件夹、歌曲菜单。
/// 这里统一，屏宽上限、圆角、点击遮罩关闭、头部与列表间距都只有一处定义。
///
/// [itemsBuilder] 拿到的是面板自己的 [BuildContext]，行内的 `Navigator.pop`
/// 必须用它——用外层页面的 context 会 pop 到页面所在的嵌套 Navigator 上，
/// 面板本身不会被关掉（歌曲菜单此前正是这个问题）。
Future<T?> showAppActionSheet<T>({
  required BuildContext context,
  required Widget header,
  required List<Widget> Function(BuildContext sheetContext) itemsBuilder,
  double maxWidth = 680,
  bool scrollable = false,
}) {
  final theme = Theme.of(context);
  return AppContextMenu.showModalSheet<T>(
    context: context,
    builder: (sheetContext) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(sheetContext),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: GestureDetector(
                onTap: () {},
                child: Material(
                  elevation: 16,
                  color: theme.colorScheme.surface,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        header,
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        if (scrollable)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.sizeOf(sheetContext).height * 0.6,
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: itemsBuilder(sheetContext),
                              ),
                            ),
                          )
                        else
                          ...itemsBuilder(sheetContext),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 底部操作面板的头部：可选 52pt 缩略图 + 标题 + 副标题。
class ActionSheetHeader extends StatelessWidget {  const ActionSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = subtitle;
    return Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (secondary != null) ...[
                const SizedBox(height: 4),
                Text(
                  secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 底部操作面板头部左侧的方形图标（52pt）。
///
/// 用于没有封面、但类型明确的条目（文件夹、远程文件）。原先本地文件夹面板与
/// 远程文件夹面板各写了一份同样的圆角容器。
class ActionSheetSquareIcon extends StatelessWidget {
  const ActionSheetSquareIcon({
    super.key,
    required this.icon,
    this.color,
    this.radius = 14,
  });

  final IconData icon;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: 52,
        height: 52,
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        child: Icon(icon, size: 30, color: color),
      ),
    );
  }
}
