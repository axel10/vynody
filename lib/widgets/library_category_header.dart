import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dialogs/library_source_filter_dialog.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/player/library/library_source_filter.dart';
import 'library_action_bar.dart';
import 'library_large_title.dart';

/// 本地媒体库二级分类列表（专辑、艺术家、流派、年份、歌单）的统一页头。
///
/// 动作行的排布与折叠交给 [LibraryActionBar]：
/// - 横屏：单行，标题在左，右侧依次是搜索框 → 播放全部 / 随机播放 → 其余按钮；
/// - 竖屏：标题一行，下面「播放全部 / 随机播放 / 搜索」左对齐，其余全进右侧「更多」。
///
/// 横屏主从分栏时（艺术家 / 流派 / 年份）调用方会置 `showSearch: false` 与
/// `showSortActionInWide: false`，把搜索和排序让给左栏顶部，本行不重复渲染。
class LibraryCategoryHeader extends ConsumerWidget {
  const LibraryCategoryHeader({
    super.key,
    this.title,
    this.countLabel,
    required this.isWide,
    required this.searchController,
    this.searchFocusNode,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchCleared,
    this.searchHintText,
    this.onPlayAll,
    this.onShufflePlay,
    this.onSortPressed,
    this.showSourceFilter = true,
    this.extraActions,
    this.backgroundColor,
    this.hasBorder = true,
    this.showSearch = true,
    this.showSortActionInWide = true,
    this.showBackButton = true,
    this.onBack,
  });

  final String? title;
  final String? countLabel;
  final bool isWide;
  final TextEditingController searchController;

  /// 搜索框焦点节点。远程各 tab 需要「切到该分类时保持输入焦点」，
  /// 本地页头原先没有暴露，这里补上并透传给 [LibraryActionBar]。
  final FocusNode? searchFocusNode;

  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final String? searchHintText;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final VoidCallback? onSortPressed;
  final bool showSourceFilter;

  /// 各分类页特有的次要动作。横屏平铺、竖屏进「更多」，由 [LibraryActionBar]
  /// 一处决定，调用方不要再按 `isWide` 自行增删按钮。
  final List<LibraryToolbarAction>? extraActions;

  final Color? backgroundColor;
  final bool hasBorder;

  /// 是否在本组件内渲染搜索框。横屏主从分栏时搜索框收进左栏顶部，本行置 false。
  final bool showSearch;

  /// 横屏时是否在本组件内渲染排序按钮。主从分栏时排序只作用于左栏列表，
  /// 会随搜索框一起收进左栏顶部，这里置 false 让它只出现在竖屏的「更多」里。
  final bool showSortActionInWide;
  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final currentFilter = ref.watch(librarySourceFilterProvider);
    final isFiltered = currentFilter.type != LibrarySourceType.all;

    final actions = <LibraryToolbarAction>[
      if (onSortPressed != null)
        LibraryToolbarAction(
          icon: Icons.sort_rounded,
          label: l10n.sort,
          onPressed: onSortPressed!,
          hideInWide: !showSortActionInWide,
        ),
      ...?extraActions,
      if (showSourceFilter)
        LibraryToolbarAction(
          icon: Icons.tune_rounded,
          label: isZh ? '渠道与来源筛选' : 'Filter by Source',
          onPressed: () => showLibrarySourceFilterDialog(context),
          color: isFiltered ? theme.colorScheme.primary : null,
          showBadge: isFiltered,
        ),
    ];

    final hasTitle = title != null && title!.isNotEmpty;
    final largeTitleBlock = hasTitle
        ? LibraryLargeTitle(
            title: title!,
            countLabel: countLabel,
            showBackButton: showBackButton,
            onBack: onBack,
          )
        : null;

    final border = hasBorder
        ? Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          )
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface,
        border: border,
      ),
      // 横屏保持「标题在左、搜索框与按钮组在右」的单行页头；竖屏才拆成
      // 标题一行、动作行一行。数量信息在有标题时已归 LibraryLargeTitle，
      // 这里不再重复一份。
      child: isWide
          ? LibraryActionBar(
              isWide: true,
              leading: largeTitleBlock,
              searchController: searchController,
              searchFocusNode: searchFocusNode,
              searchQuery: searchQuery,
              onSearchChanged: onSearchChanged,
              onSearchCleared: onSearchCleared,
              searchHintText: searchHintText,
              showSearch: showSearch,
              onPlayAll: onPlayAll,
              onShufflePlay: onShufflePlay,
              actions: actions,
              countLabel: largeTitleBlock == null ? countLabel : null,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (largeTitleBlock != null) ...[
                  largeTitleBlock,
                  const SizedBox(height: 8),
                ],
                LibraryActionBar(
                  isWide: false,
                  searchController: searchController,
                  searchFocusNode: searchFocusNode,
                  searchQuery: searchQuery,
                  onSearchChanged: onSearchChanged,
                  onSearchCleared: onSearchCleared,
                  searchHintText: searchHintText,
                  showSearch: showSearch,
                  onPlayAll: onPlayAll,
                  onShufflePlay: onShufflePlay,
                  actions: actions,
                  countLabel: largeTitleBlock == null ? countLabel : null,
                ),
              ],
            ),
    );
  }
}
