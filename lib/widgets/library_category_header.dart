import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dialogs/library_source_filter_dialog.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/player/library/library_source_filter.dart';

/// 本地媒体库二级分类列表（专辑、艺术家、流派、年份等）的轻量统一工具栏。
///
/// 标题统一由外层顶部导航栏（[AppTopNavBar]）承载，本组件专注于内容区操作：
/// - 横屏（宽屏）：单行排列，左侧可选展示条目数量信息，中间常驻搜索输入框，右侧操作按钮区。
/// - 竖屏（窄屏）：单行轻量排列（播放全部、随机播放、排序、数量信息、搜索、扩展项、来源筛选）。
///   点击搜索按钮后，动画平滑切换为全宽搜索框与关闭按钮。
class LibraryCategoryHeader extends ConsumerStatefulWidget {
  const LibraryCategoryHeader({
    super.key,
    this.title,
    this.countLabel,
    required this.isWide,
    required this.searchController,
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
  });

  final String? title;
  final String? countLabel;
  final bool isWide;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final String? searchHintText;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final VoidCallback? onSortPressed;
  final bool showSourceFilter;
  final List<Widget>? extraActions;
  final Color? backgroundColor;
  final bool hasBorder;

  @override
  ConsumerState<LibraryCategoryHeader> createState() => _LibraryCategoryHeaderState();
}

class _LibraryCategoryHeaderState extends ConsumerState<LibraryCategoryHeader> {
  late bool _isSearching;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _isSearching = widget.searchQuery.isNotEmpty;
  }

  @override
  void didUpdateWidget(LibraryCategoryHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery.isNotEmpty && !_isSearching) {
      _isSearching = true;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildSearchField(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    final hint = widget.searchHintText ?? l10n.search;
    return TextField(
      controller: widget.searchController,
      focusNode: _focusNode,
      onChanged: widget.onSearchChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.6),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
          size: 20,
        ),
        suffixIcon: widget.searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  widget.onSearchCleared();
                },
                icon: Icon(
                  Icons.close_rounded,
                  color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
                  size: 18,
                ),
              ),
        filled: true,
        fillColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      style: TextStyle(
        color: theme.colorScheme.onSecondaryContainer,
        fontSize: 14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final currentFilter = ref.watch(librarySourceFilterProvider);
    final isFiltered = currentFilter.type != LibrarySourceType.all;

    final filterButton = widget.showSourceFilter
        ? IconButton(
            tooltip: isZh ? '渠道与来源筛选' : 'Filter by Source',
            onPressed: () => showLibrarySourceFilterDialog(context),
            icon: Badge(
              isLabelVisible: isFiltered,
              smallSize: 8,
              child: Icon(
                Icons.tune_rounded,
                color: isFiltered ? theme.colorScheme.primary : null,
              ),
            ),
          )
        : null;

    final hasTitle = widget.title != null && widget.title!.isNotEmpty;

    final largeTitleBlock = hasTitle
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title!,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              if (widget.countLabel != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.countLabel!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          )
        : null;

    final countText = widget.countLabel != null
        ? Text(
            widget.countLabel!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          )
        : null;

    final sortButton = widget.onSortPressed != null
        ? IconButton(
            tooltip: l10n.sort,
            onPressed: widget.onSortPressed,
            icon: const Icon(Icons.sort_rounded),
          )
        : null;

    final playAllButton = widget.onPlayAll != null
        ? IconButton(
            tooltip: l10n.playAll,
            onPressed: widget.onPlayAll,
            icon: const Icon(Icons.play_arrow_rounded),
          )
        : null;

    final shufflePlayButton = widget.onShufflePlay != null
        ? IconButton(
            tooltip: l10n.shufflePlay,
            onPressed: widget.onShufflePlay,
            icon: const Icon(Icons.shuffle_rounded),
          )
        : null;

    final border = widget.hasBorder
        ? Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          )
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? theme.colorScheme.surface,
        border: border,
      ),
      child: widget.isWide
          ? Row(
              children: [
                if (largeTitleBlock != null) ...[
                  largeTitleBlock,
                  const SizedBox(width: 20),
                ] else if (countText != null) ...[
                  countText,
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: _buildSearchField(context, theme, l10n),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?playAllButton,
                    ?shufflePlayButton,
                    ?sortButton,
                    ...?widget.extraActions,
                    ?filterButton,
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (largeTitleBlock != null) ...[
                  largeTitleBlock,
                  const SizedBox(height: 8),
                ],
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: _isSearching
                      ? Row(
                          key: const ValueKey('header_search_active'),
                          children: [
                            Expanded(
                              child: _buildSearchField(context, theme, l10n),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: l10n.cancel,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                widget.searchController.clear();
                                widget.onSearchCleared();
                                setState(() {
                                  _isSearching = false;
                                });
                              },
                            ),
                          ],
                        )
                      : Row(
                          key: const ValueKey('header_actions_normal'),
                          children: [
                            ?playAllButton,
                            ?shufflePlayButton,
                            ?sortButton,
                            const Spacer(),
                            if (largeTitleBlock == null && countText != null) ...[
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: countText,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            IconButton(
                              tooltip: l10n.search,
                              icon: const Icon(Icons.search_rounded),
                              onPressed: () {
                                setState(() {
                                  _isSearching = true;
                                });
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    _focusNode.requestFocus();
                                  }
                                });
                              },
                            ),
                            ...?widget.extraActions,
                            ?filterButton,
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}
