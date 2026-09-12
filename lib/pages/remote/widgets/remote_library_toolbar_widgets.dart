import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

/// 统一的 32dp 紧凑图标按钮样式
final ButtonStyle kCompactIconButtonStyle = IconButton.styleFrom(
  minimumSize: const Size(32, 32),
  fixedSize: const Size(32, 32),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// 统一高度与规格的远程媒体库搜索输入框
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

/// 支持小屏响应式折叠为搜索按钮的统一工具栏容器
class RemoteResponsiveToolbar extends StatelessWidget {
  final Widget searchField;
  final Widget trailing;
  final FocusNode? searchFocusNode;
  final bool isSearchExpanded;
  final ValueChanged<bool> onToggleSearchExpanded;
  final VoidCallback onClearSearch;
  final String searchTooltip;
  final double collapseBreakpoint;
  final int searchFlex;
  final int trailingFlex;
  final EdgeInsetsGeometry padding;

  const RemoteResponsiveToolbar({
    super.key,
    required this.searchField,
    required this.trailing,
    this.searchFocusNode,
    required this.isSearchExpanded,
    required this.onToggleSearchExpanded,
    required this.onClearSearch,
    required this.searchTooltip,
    this.collapseBreakpoint = 480.0,
    this.searchFlex = 1,
    this.trailingFlex = 1,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= collapseBreakpoint;

        return Container(
          padding: padding,
          child: isWide
              ? Row(
                  children: [
                    Expanded(
                      flex: searchFlex,
                      child: searchField,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: trailingFlex,
                      child: trailing,
                    ),
                  ],
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: isSearchExpanded
                      ? Row(
                          key: const ValueKey('remote_search_expanded'),
                          children: [
                            IconButton(
                              style: kCompactIconButtonStyle,
                              icon: const Icon(Icons.arrow_back_rounded,
                                  size: 18),
                              tooltip: l10n.closeSearch,
                              onPressed: () {
                                searchFocusNode?.unfocus();
                                onToggleSearchExpanded(false);
                                onClearSearch();
                              },
                            ),
                            const SizedBox(width: 4),
                            Expanded(child: searchField),
                          ],
                        )
                      : Row(
                          key: const ValueKey('remote_search_collapsed'),
                          children: [
                            IconButton.filledTonal(
                              style: kCompactIconButtonStyle,
                              icon: const Icon(Icons.search_rounded, size: 18),
                              tooltip: searchTooltip,
                              onPressed: () {
                                onToggleSearchExpanded(true);
                                searchFocusNode?.requestFocus();
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: trailing),
                          ],
                        ),
                ),
        );
      },
    );
  }
}
