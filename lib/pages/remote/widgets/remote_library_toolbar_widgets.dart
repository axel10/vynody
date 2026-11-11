import 'package:flutter/material.dart';
import '../../../dialogs/sort_options_dialog.dart';
import '../../../widgets/library_action_bar.dart';
import '../../../widgets/library_category_header.dart';
import '../../../widgets/library_toolbar_buttons.dart';
import '../../../widgets/library_zoom_popover.dart';

/// 远程媒体库各 tab 共用的页头。
///
/// 横竖屏判据、搜索框规格、按钮规格、竖屏「更多」折叠全部由
/// [LibraryActionBar] 一处决定；各 tab 只提供搜索参数、次要动作与播放回调。
/// 此前每个 tab 自己写 LayoutBuilder / 600·740 阈值 / 32dp 按钮，
/// 同一个窗口宽度下顶部区域排布各不相同。
///
/// 页头实体是本地库的 [LibraryCategoryHeader]：大标题 + 条目计数 + 返回按钮
/// 与「播放全部 / 随机播放」完全同源，远程只关掉来源筛选
/// （那是本地文件库独有的概念）。这样两边的二级页在同一个窗口宽度下
/// 排布、字号、按钮尺寸、折叠规则都是同一套代码算出来的。
class RemoteLibraryActionBar extends StatelessWidget {
  const RemoteLibraryActionBar({
    super.key,
    this.title,
    this.onBack,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchCleared,
    this.searchHintText,
    this.searchFocusNode,
    this.onPlayAll,
    this.onShufflePlay,
    this.actions = const <LibraryToolbarAction>[],
    this.trailingActions = const <LibraryToolbarAction>[],
    this.countLabel,
    this.forceNarrow = false,
  });

  /// 分类大标题（「专辑」「艺术家」…）。为空时不渲染标题行，
  /// 返回按钮也随之不出现 —— 搜索页这种自带搜索行的页头走这条分支。
  final String? title;

  /// 返回概览页。远程库的二级分类在局部 Navigator 里，`maybePop()` 弹的是
  /// 分类栈而非外层页面栈，所以必须由父页显式给出「回概览」的动作。
  final VoidCallback? onBack;

  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final String? searchHintText;
  final FocusNode? searchFocusNode;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final List<LibraryToolbarAction> actions;

  /// 库级动作（定位当前播放、下载管理器）。
  ///
  /// 原先挂在二级宿主的浮动胶囊上，必须在滚动离开顶部后才能点到。页头改成
  /// 常驻大标题后，这些动作随各分类自己的页头一起出现，不滚也能进。
  /// 排在 [actions] 之后 —— 分类专属动作在前，库级动作在后。
  final List<LibraryToolbarAction> trailingActions;

  final String? countLabel;

  /// 强制使用竖屏（折行）布局。
  ///
  /// 横屏主从分栏的左栏只有 300 出头，`libraryToolbarIsWide` 只看屏幕朝向
  /// 会判成宽屏，把搜索框、播放组、动作按钮全塞进一行而溢出。左栏渲染页头
  /// 时必须显式要求窄布局 —— 与本地 `genres_tab` / `artists_tab` 左栏同一口径。
  final bool forceNarrow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => LibraryCategoryHeader(
        title: title,
        countLabel: countLabel,
        isWide: forceNarrow
            ? false
            : libraryToolbarIsWide(
                isLandscape:
                    MediaQuery.orientationOf(context) == Orientation.landscape,
                maxWidth: constraints.maxWidth,
              ),
        searchController: searchController,
        searchFocusNode: searchFocusNode,
        searchQuery: searchQuery,
        onSearchChanged: onSearchChanged,
        onSearchCleared: onSearchCleared,
        searchHintText: searchHintText,
        onPlayAll: onPlayAll,
        onShufflePlay: onShufflePlay,
        // 远程库没有「本地 / U 盘 / 网盘」这类来源概念，筛选入口一律不出现。
        showSourceFilter: false,
        showBackButton: onBack != null,
        onBack: onBack,
        extraActions: [...actions, ...trailingActions],
      ),
    );
  }
}

/// 统一的「排序」动作：横竖屏都是单按钮点开 [SortOptionsDialog]，与本地库
/// （专辑 / 流派 / 艺术家页）同款交互。横屏是图标按钮；竖屏收进「更多」菜单，
/// 仍打开同一个弹窗。排序状态由调用方持有（[currentField] / [sortAscending]），
/// 确认后经 [onSelected] 回写 —— 选项不再需要在菜单里自带 selected 勾选态。
LibraryToolbarAction remoteSortAction<T>({
  required BuildContext context,
  required String label,
  required T currentField,
  required bool sortAscending,
  required List<SortOptionItem<T>> options,
  required void Function(T field, bool sortAscending) onSelected,
  bool Function(T field)? ascendingToggleEnabled,

  /// 服务端 sortType 这类没有升降序概念的排序传 false，弹窗不渲染方向开关。
  bool showDirectionToggle = true,
}) {
  return LibraryToolbarAction(
    icon: Icons.sort_rounded,
    label: label,
    onPressed: () async {
      final result = await showSortOptionsDialog<T>(
        context: context,
        title: label,
        currentField: currentField,
        sortAscending: sortAscending,
        options: options,
        ascendingToggleEnabled: ascendingToggleEnabled,
        showDirectionToggle: showDirectionToggle,
      );
      if (result != null) {
        onSelected(result.field, result.sortAscending);
      }
    },
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
