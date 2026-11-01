import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'library_search_field.dart';

/// 横屏主从分栏时，贴在左栏顶部的那一行工具条。
///
/// 搜索与排序都只作用于左边这条列表，却被栏宽拆到两栏两侧会很别扭：
/// 远程媒体库（`remote_library_artists_tab.dart` 的 `landscapeToolbar`）
/// 早就把整条工具条收进左栏；本地分类此前只把搜索框收进左栏，
/// 排序按钮仍留在横跨两栏的页头右端，按下去改的却是左栏。
/// 统一收到这里：搜索与排序成组，右栏顶部也腾干净。
///
/// 竖屏不使用——竖屏没有分栏，搜索与排序都留在页头即可。
class LibraryMasterPaneHeader extends StatelessWidget {
  const LibraryMasterPaneHeader({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchCleared,
    this.searchHintText,
    this.onSortPressed,
  });

  final TextEditingController searchController;

  /// 当前生效的搜索词，仅用于决定是否显示清除按钮。
  final String searchQuery;

  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final String? searchHintText;

  /// 列表排序入口；为 null 时不渲染排序按钮。
  final VoidCallback? onSortPressed;

  /// 与远程媒体库工具条一致的 32dp 紧凑图标按钮，避免把左栏这一行撑高。
  static final ButtonStyle _compactIconStyle = IconButton.styleFrom(
    minimumSize: const Size(32, 32),
    fixedSize: const Size(32, 32),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Row(
      children: [
        Expanded(
          child: LibrarySearchField(
            controller: searchController,
            hintText: searchHintText,
            query: searchQuery,
            onChanged: onSearchChanged,
            onClear: onSearchCleared,
          ),
        ),
        if (onSortPressed != null) ...[
          const SizedBox(width: 6),
          IconButton(
            style: _compactIconStyle,
            tooltip: l10n.sort,
            onPressed: onSortPressed,
            iconSize: 20,
            icon: const Icon(Icons.sort_rounded),
          ),
        ],
      ],
    );
  }
}
