import 'package:flutter/material.dart';
import '../../../widgets/library_action_bar.dart';
import '../../../widgets/library_toolbar_buttons.dart';
import '../../../widgets/library_zoom_popover.dart';

/// 远程媒体库各 tab 共用的动作行外壳。
///
/// 横竖屏判据、搜索框规格、按钮规格、竖屏「更多」折叠全部由
/// [LibraryActionBar] 一处决定；各 tab 只提供搜索参数、次要动作与播放回调。
/// 此前每个 tab 自己写 LayoutBuilder / 600·740 阈值 / 32dp 按钮，
/// 同一个窗口宽度下顶部区域排布各不相同。
class RemoteLibraryActionBar extends StatelessWidget {
  const RemoteLibraryActionBar({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchCleared,
    this.searchHintText,
    this.searchFocusNode,
    this.onPlayAll,
    this.onShufflePlay,
    this.actions = const <LibraryToolbarAction>[],
    this.countLabel,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final String? searchHintText;
  final FocusNode? searchFocusNode;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final List<LibraryToolbarAction> actions;
  final String? countLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => LibraryActionBar(
        isWide: libraryToolbarIsWide(
          isLandscape:
              MediaQuery.orientationOf(context) == Orientation.landscape,
          maxWidth: constraints.maxWidth,
        ),
        searchController: searchController,
        searchQuery: searchQuery,
        onSearchChanged: onSearchChanged,
        onSearchCleared: onSearchCleared,
        searchHintText: searchHintText,
        searchFocusNode: searchFocusNode,
        onPlayAll: onPlayAll,
        onShufflePlay: onShufflePlay,
        actions: actions,
        countLabel: countLabel,
      ),
    );
  }
}

/// 排序弹窗的一个选项。横屏走弹出菜单，竖屏走「更多」里的一组条目。
class RemoteSortOption {
  const RemoteSortOption({
    required this.value,
    required this.label,
    required this.icon,
    this.selected = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool selected;
}

/// [LibraryToolbarMetrics] 规格的排序图标弹出按钮。横屏动作行与远程艺术家页
/// 的横屏左栏（分栏紧凑形态）共用，避免两处各写一份弹窗。
Widget remoteSortPopupButton({
  required String label,
  required List<RemoteSortOption> options,
  required ValueChanged<String> onSelected,
}) {
  return PopupMenuButton<String>(
    tooltip: label,
    padding: EdgeInsets.zero,
    onSelected: onSelected,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    itemBuilder: (context) => <PopupMenuEntry<String>>[
      for (final option in options)
        PopupMenuItem<String>(
          value: option.value,
          child: Row(
            children: [
              Icon(option.icon, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(option.label, maxLines: 1)),
              if (option.selected) const Icon(Icons.check_rounded, size: 16),
            ],
          ),
        ),
    ],
    child: SizedBox(
      width: LibraryToolbarMetrics.buttonSize,
      height: LibraryToolbarMetrics.buttonSize,
      child: Icon(
        Icons.sort_rounded,
        size: LibraryToolbarMetrics.iconSize,
      ),
    ),
  );
}

/// 统一的「排序」动作：横屏是图标弹出按钮，竖屏把选项展开进「更多」，
/// 不再用带文字标签的下拉胶囊。
LibraryToolbarAction remoteSortAction({
  required String label,
  required List<RemoteSortOption> options,
  required ValueChanged<String> onSelected,
}) {
  return LibraryToolbarAction(
    icon: Icons.sort_rounded,
    label: label,
    wideButton: remoteSortPopupButton(
      label: label,
      options: options,
      onSelected: onSelected,
    ),
    menuEntries: (ctx) => [
      for (final option in options)
        libraryToolbarMenuEntry(
          context: ctx,
          icon: option.icon,
          label: option.label,
          selected: option.selected,
          onTap: () => onSelected(option.value),
        ),
    ],
  );
}

/// 统一的「只看收藏」动作。竖屏不进「更多」，留在「更多」按钮左边。
LibraryToolbarAction remoteStarAction({
  required bool active,
  required String label,
  required ValueChanged<bool> onToggle,
}) {
  return LibraryToolbarAction(
    icon: active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
    label: label,
    color: active ? Colors.redAccent : null,
    keepInNarrow: true,
    onPressed: () => onToggle(!active),
  );
}

/// 统一的「视图档位」动作。横屏平铺原按钮；竖屏进「更多」——此前歌曲 tab
/// 在竖屏直接隐藏了这个按钮，只能靠捏合手势，现在从菜单里加回来。
LibraryToolbarAction remoteZoomAction({
  required String label,
  required LibraryZoomScope scope,
}) {
  return LibraryToolbarAction(
    icon: Icons.grid_view_rounded,
    label: label,
    wideButton: LibraryZoomButton(
      scope: scope,
      buttonSize: LibraryToolbarMetrics.buttonSize,
    ),
    menuEntries: (ctx) => [
      libraryToolbarMenuEntry(
        context: ctx,
        icon: Icons.grid_view_rounded,
        label: label,
        onTap: () => showLibraryZoomPopover(ctx, scope: scope),
      ),
    ],
  );
}

/// 远程详情页 / 全局搜索页仍在用的紧凑搜索框。
///
/// 各 tab 的顶部动作行已统一改走 [LibraryActionBar] 内的 `LibrarySearchField`，
/// 这里只保留详情页与搜索页需要的 `trailing` 加载指示能力。
class RemoteSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final Widget? trailing;
  final Color? fillColor;
  final double height;

  const RemoteSearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hintText,
    this.searchQuery = '',
    required this.onChanged,
    required this.onClear,
    this.trailing,
    this.fillColor,
    this.height = 32.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = searchQuery.isNotEmpty || controller.text.isNotEmpty;

    Widget? suffix;
    if (trailing != null) {
      suffix = trailing;
    } else if (hasText) {
      suffix = IconButton(
        icon: const Icon(Icons.clear_rounded, size: 16),
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          minWidth: height,
          minHeight: height,
        ),
        onPressed: onClear,
      );
    }

    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          prefixIconConstraints: BoxConstraints(
            minWidth: height,
            minHeight: height,
          ),
          suffixIcon: suffix,
          suffixIconConstraints: BoxConstraints(
            minWidth: height,
            minHeight: height,
          ),
          filled: true,
          fillColor: fillColor,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 0,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
