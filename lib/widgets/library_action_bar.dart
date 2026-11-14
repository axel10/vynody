import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'library_search_field.dart';
import 'library_toolbar_buttons.dart';

/// 顶部工具栏「宽 / 窄」判据的**唯一入口**。
///
/// 此前本地分类页按 `isLandscape || maxWidth >= 780`、远程专辑/艺术家/歌单按 600、
/// 歌曲按 740、页面级按 750，另有一个 480 的折叠阈值 —— 同一个窗口宽度
/// 下两边会在不同时刻切换横竖布局。所有分类页头与远程媒体库工具栏一律走这里，
/// 不要再往调用点写死阈值。
bool libraryToolbarIsWide({
  required bool isLandscape,
  required double maxWidth,
}) {
  return isLandscape || maxWidth >= 780;
}

/// 常态与「点搜索后整行变搜索框」两态共用的行高。
///
/// 搜索框约 40、按钮盒 40，原生 [IconButton] 若不限高会按 48 排版；不锁死高度
/// 的话，一点搜索按钮整行就向下长几像素，下方列表跟着被顶一下。与文件夹页
/// `_kPortraitActionRowHeight` 同一口径。
const double kLibraryActionBarHeight = 44.0;

/// 横屏常驻搜索框宽度。
const double kLibraryActionBarSearchWidth = 240.0;

/// 顶部工具栏的一个次要动作。
///
/// 横屏一律平铺成 [LibraryToolbarMetrics] 规格的 40×40 图标按钮；竖屏除
/// [keepInNarrow] 的项外全部收进右侧「更多」菜单。
///
/// [wideButton] 用于自带状态或需要自身 context 的控件（如 [LibraryZoomButton]）；
/// [menuEntries] 用于排序这类带子选项的动作 —— 横屏是弹出按钮，竖屏把子项展开
/// 成「更多」里的一组条目，避免菜单里再套一层菜单。
class LibraryToolbarAction {
  const LibraryToolbarAction({
    required this.icon,
    required this.label,
    this.onPressed,
    this.color,
    this.showBadge = false,
    this.keepInNarrow = false,
    this.hideInWide = false,
    this.hideInNarrow = false,
    this.wideButton,
    this.menuEntries,
  });

  /// 菜单项图标；同时作为未指定 [wideButton] 时横屏按钮的图标。
  final IconData icon;

  /// 悬浮提示，同时也是默认菜单项文案。
  final String label;

  /// 默认按钮 / 默认菜单项共用的回调。
  /// 同时给了 [wideButton] 与 [menuEntries] 时可以省略。
  final VoidCallback? onPressed;

  final Color? color;

  /// 是否在图标右上角挂一个小红点（来源筛选已生效）。
  final bool showBadge;

  /// 竖屏不收进「更多」，仍渲染成按钮放在「更多」左边。
  /// 目前只有远程媒体库的「只看收藏」红心需要。
  final bool keepInNarrow;

  /// 横屏不显示（但竖屏仍进「更多」）。
  /// 主从分栏页的排序被收进左栏顶部，页头这行不能再重复放一份。
  final bool hideInWide;

  /// 竖屏不显示（既不外露也不进「更多」），仅在横屏展示。
  /// 例如远程媒体库横屏顶部的手动刷新按钮（竖屏已有下拉刷新）。
  final bool hideInNarrow;

  final Widget? wideButton;

  /// 自定义竖屏菜单条目。参数是本组件所在的 [BuildContext]，供弹窗类动作
  /// 定位锚点；为空时按 [icon] / [label] / [onPressed] 生成一条默认项。
  final List<PopupMenuEntry<void>> Function(BuildContext context)? menuEntries;
}

/// 生成一条与默认菜单项同款的 [PopupMenuEntry]。
///
/// 供 [LibraryToolbarAction.menuEntries] 复用：排序子项、视图档位等需要自定义
/// 回调的动作不必各自再写一遍 Row / 图标 / 文案排版。
PopupMenuEntry<void> libraryToolbarMenuEntry({
  required BuildContext context,
  required IconData icon,
  required String label,
  required VoidCallback? onTap,
  Color? color,
  bool selected = false,
  bool showBadge = false,
}) {
  final theme = Theme.of(context);
  final effectiveColor = selected
      ? theme.colorScheme.primary
      : (color ?? theme.colorScheme.onSurfaceVariant);
  return PopupMenuItem<void>(
    height: 40,
    onTap: onTap,
    child: Row(
      children: [
        Icon(icon, size: 20, color: effectiveColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: selected ? theme.colorScheme.primary : null,
              fontWeight: selected ? FontWeight.w600 : null,
            ),
          ),
        ),
        if (showBadge)
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        if (selected)
          Icon(Icons.check_rounded, size: 16, color: theme.colorScheme.primary),
      ],
    ),
  );
}

/// 生成一条默认的「更多」菜单项（没有自定义 [LibraryToolbarAction.menuEntries] 时使用）。
PopupMenuEntry<void> _libraryToolbarDefaultMenuEntry(
  BuildContext context,
  LibraryToolbarAction action,
) {
  return libraryToolbarMenuEntry(
    context: context,
    icon: action.icon,
    label: action.label,
    onTap: action.onPressed,
    color: action.color,
    showBadge: action.showBadge,
  );
}

/// 竖屏「更多」按钮及其菜单的**唯一实现**。
///
/// 页头动作行（[LibraryActionBar]）与滚动后浮出的顶栏胶囊
/// （`LibraryTopNavCapsule`）共用本函数 —— 两处菜单的构造方式、条目排版、
/// 徽标与选中态必须完全一致，否则同一个动作会有两种长相。
///
/// [actions] 传取值函数而不是列表：菜单在展开那一刻才求值，始终拿到调用方
/// 最新一次 build 生成的闭包（「播放全部」捕获的是当前可见列表）。
Widget libraryToolbarMoreButton({
  required List<LibraryToolbarAction> Function() actions,
  String? tooltip,
  double buttonSize = LibraryToolbarMetrics.buttonSize,
  double iconSize = LibraryToolbarMetrics.iconSize,
  Color? color,
}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final l10n = AppLocalizations.of(context);
      return PopupMenuButton<void>(
        tooltip: tooltip ?? l10n?.more,
        padding: EdgeInsets.zero,
        splashRadius: 20,
        itemBuilder: (menuContext) {
          final available = actions();
          if (available.isEmpty) {
            return const <PopupMenuEntry<void>>[];
          }
          return <PopupMenuEntry<void>>[
            for (final action in available)
              ...(action.menuEntries?.call(context) ??
                  <PopupMenuEntry<void>>[
                    _libraryToolbarDefaultMenuEntry(context, action),
                  ]),
          ];
        },
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Icon(
            Icons.more_vert_rounded,
            size: iconSize,
            color: color ?? theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    },
  );
}

/// 本地媒体库与远程媒体库共用的顶部动作行。
///
/// - 横屏：搜索框最左 → 播放全部 / 随机播放 → 其余全部按钮平铺（不折叠）；
///   条目数量等尾部信息右对齐。
/// - 竖屏：左侧只有播放全部 / 随机播放 / 搜索按钮；其余操作全部进右侧「更多」
///   菜单，只有 [LibraryToolbarAction.keepInNarrow] 的动作留在「更多」左边。
///   点搜索后这一整行平滑切换成搜索框 + 关闭按钮。
///
/// 搜索框统一用 [LibrarySearchField]、按钮统一用 [libraryToolbarIconButton]，
/// 不再由各页面各自决定尺寸与圆角。
class LibraryActionBar extends StatefulWidget {
  const LibraryActionBar({
    super.key,
    required this.isWide,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchCleared,
    this.searchHintText,
    this.searchFocusNode,
    this.showSearch = true,
    this.onPlayAll,
    this.onShufflePlay,
    this.actions = const <LibraryToolbarAction>[],
    this.countLabel,
    this.leading,
    this.onResolvedActions,
  });

  final bool isWide;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final String? searchHintText;
  final FocusNode? searchFocusNode;

  /// 横屏主从分栏时置 false：搜索框收进左栏顶部，本行不再重复放一个。
  final bool showSearch;

  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;

  /// 次要动作；横屏平铺，竖屏折叠。
  final List<LibraryToolbarAction> actions;

  /// 条目数量等尾部信息，仅横屏显示（竖屏一行放不下，也不该挤占操作区）。
  final String? countLabel;

  /// 横屏时并进本行最左侧的内容（本地分类页的大标题）。
  ///
  /// 传了它，横屏就回到「标题在左、搜索框与按钮组在右」的单行页头；
  /// 不传则搜索框独自占据行首。竖屏忽略本参数 —— 标题由调用方放在本行上方。
  final Widget? leading;

  /// 本行实际渲染的全部动作（含播放全部 / 随机 / 搜索），按竖屏「更多」菜单
  /// 需要的顺序给出。
  ///
  /// 页头把它登记给 [LibraryHeaderActionsController]，供滚动后浮出的顶栏胶囊
  /// 复用同一份清单。本行保持原有的分流规则：播放组与搜索常驻、`keepInNarrow`
  /// 贴「更多」左侧、其余进菜单；胶囊则把整份清单都收进菜单。
  final ValueChanged<List<LibraryToolbarAction>>? onResolvedActions;

  @override
  State<LibraryActionBar> createState() => _LibraryActionBarState();
}

class _LibraryActionBarState extends State<LibraryActionBar> {
  late bool _isSearching;
  late final FocusNode _fallbackFocusNode = FocusNode();

  FocusNode get _focusNode => widget.searchFocusNode ?? _fallbackFocusNode;

  @override
  void initState() {
    super.initState();
    _isSearching = widget.searchQuery.isNotEmpty;
  }

  @override
  void didUpdateWidget(LibraryActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（例如跨设备同步、搜索页回填）把搜索词写进来时，要跟着进入展开态，
    // 否则窄屏会出现「有搜索结果但输入框没展开」。
    if (widget.searchQuery.isNotEmpty && !_isSearching) {
      _isSearching = true;
    }
  }

  @override
  void dispose() {
    _fallbackFocusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    // 从滚动后浮出的胶囊「更多」里触发时，页头（连同这一行的搜索按钮）已经
    // 滚出视口上方，直接展开只会得到一个看不见的输入框。先滚回顶部。
    // 横屏页头在 Column 里、不在 Scrollable 内，maybeOf 返回 null，此处自然跳过。
    final ScrollPosition? position = Scrollable.maybeOf(context)?.position;
    if (position != null && position.hasPixels && position.pixels > 0) {
      position.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    setState(() => _isSearching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _closeSearch() {
    widget.searchController.clear();
    widget.onSearchCleared();
    setState(() => _isSearching = false);
  }

  Widget _buildActionButton(LibraryToolbarAction action) {
    final override = action.wideButton;
    if (override != null) return override;
    return libraryToolbarIconButton(
      icon: action.icon,
      tooltip: action.label,
      onPressed: action.onPressed,
      color: action.color,
      wrapIcon: action.showBadge ? (icon) => Badge(smallSize: 8, child: icon) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final searchField = LibrarySearchField(
      controller: widget.searchController,
      focusNode: _focusNode,
      hintText: widget.searchHintText ?? l10n.search,
      query: widget.searchQuery,
      onChanged: widget.onSearchChanged,
      onClear: widget.onSearchCleared,
    );

    final playButtons = <Widget>[
      if (widget.onPlayAll != null)
        libraryToolbarIconButton(
          icon: Icons.play_arrow_rounded,
          tooltip: l10n.playAll,
          onPressed: widget.onPlayAll,
        ),
      if (widget.onShufflePlay != null)
        libraryToolbarIconButton(
          icon: Icons.shuffle_rounded,
          tooltip: l10n.shufflePlay,
          onPressed: widget.onShufflePlay,
        ),
    ];

    // 竖屏「更多」菜单与胶囊共用的完整清单。播放组与搜索在本行是独立按钮、
    // 不在 widget.actions 里，必须在这里补进清单，否则滚动后它们会从菜单里消失。
    //
    // 回调只做「登记」，不得在内部 setState —— 这里正处于本行的 build 阶段。
    widget.onResolvedActions?.call(<LibraryToolbarAction>[
      if (widget.onPlayAll != null)
        LibraryToolbarAction(
          icon: Icons.play_arrow_rounded,
          label: l10n.playAll,
          onPressed: widget.onPlayAll,
        ),
      if (widget.onShufflePlay != null)
        LibraryToolbarAction(
          icon: Icons.shuffle_rounded,
          label: l10n.shufflePlay,
          onPressed: widget.onShufflePlay,
        ),
      if (widget.showSearch)
        LibraryToolbarAction(
          icon: Icons.search_rounded,
          label: l10n.search,
          onPressed: _openSearch,
        ),
      ...widget.actions.where((a) => !a.hideInNarrow),
    ]);

    if (widget.isWide) {
      final countText = widget.countLabel != null && widget.countLabel!.isNotEmpty
          ? Text(
              widget.countLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            )
          : null;

      return ConstrainedBox(
        // 只兜底不锁死：横屏这一行可能并进大标题（比 44 高），锁死会把它裁掉。
        constraints: const BoxConstraints(minHeight: kLibraryActionBarHeight),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 桌面迷你窗横屏时可用宽度可能不到 400，搜索框按宽度收缩，
            // 免得「240 搜索框 + 全部动作按钮」把 Row 撑出 overflow。
            final searchWidth = (constraints.maxWidth * 0.28)
                .clamp(120.0, kLibraryActionBarSearchWidth)
                .toDouble();
            return Row(
              children: [
                if (widget.leading != null) ...[
                  // 不能用 Flexible：它自带 flex 1，会和下面的 Spacer 均分留白，
                  // 结果按钮组停在中间而不是贴右（且 Flex 不会回收 loose 子项的
                  // 剩余空间）。这里按可用宽度直接收口，剩余全给 Spacer。
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.45,
                    ),
                    child: widget.leading!,
                  ),
                  const SizedBox(width: 16),
                  // 标题留在最左，搜索框与按钮组整体贴右。
                  // 尾部还有统计信息时不能再插 Spacer：它和下面顶住统计的
                  // Expanded 各占一份 flex，空白被均分，两边都贴不到边。
                  if (countText == null) const Spacer(),
                ],
                if (widget.showSearch) ...[
                  SizedBox(width: searchWidth, child: searchField),
                  const SizedBox(width: 8),
                ],
                ...playButtons,
                for (final action in widget.actions)
                  if (!action.hideInWide) _buildActionButton(action),
                if (countText != null) ...[
                  const SizedBox(width: 12),
                  // 必须用 Expanded 顶住剩余空间再靠右摆放：写成
                  // `Spacer + Flexible(child)` 时两者各分一半留白，文字停在行中
                  // 偏右、右侧空出一截（800 宽下实测差 76）。
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      // heightFactor 必须给：不锁的话 Align 会在无界高度（sliver）
                      // 里试图撑满，直接触发 layout 断言。
                      heightFactor: 1,
                      child: countText,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      );
    }

    final narrowActions = widget.actions
        .where((a) => !a.hideInNarrow && a.keepInNarrow)
        .toList(growable: false);
    final overflowActions = widget.actions
        .where((a) => !a.hideInNarrow && !a.keepInNarrow)
        .toList(growable: false);

    return SizedBox(
      height: kLibraryActionBarHeight,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: _isSearching && widget.showSearch
            ? Row(
                key: const ValueKey('library_action_bar_search'),
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 4),
                  libraryToolbarIconButton(
                    icon: Icons.close_rounded,
                    tooltip: l10n.cancel,
                    onPressed: _closeSearch,
                  ),
                ],
              )
            : Row(
                key: const ValueKey('library_action_bar_actions'),
                children: [
                  ...playButtons,
                  if (widget.showSearch)
                    libraryToolbarIconButton(
                      icon: Icons.search_rounded,
                      tooltip: l10n.search,
                      onPressed: _openSearch,
                    ),
                  const Spacer(),
                  for (final action in narrowActions) _buildActionButton(action),
                  if (overflowActions.isNotEmpty)
                    libraryToolbarMoreButton(
                      actions: () => overflowActions,
                    ),
                ],
              ),
      ),
    );
  }
}
