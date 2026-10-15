import 'package:flutter/material.dart';
import 'library_selection_scope.dart';
import 'playback_ui_tuning.dart';

typedef MasterItemWidgetBuilder<T> = Widget Function(
  BuildContext context,
  T item,
  int index,
  bool isSelected,
  bool isWide,
  VoidCallback onTap,
);

/// 响应式主从分栏/两级页面通用脚手架
///
/// 特性：
/// 1. 横屏/宽屏：左侧 Master 列表 + 右侧 Detail 详情（两栏分栏），左栏带分割线，右栏无选中时显示占位组件；
/// 2. 竖屏/窄屏：一级页面仅显示 Master 列表，点击条目通过 Navigator.push 进入二级详情页；
/// 3. 横竖屏旋转自适应：在竖屏下 Push 了二级详情页时，若旋转到横屏，自动 pop 详情页回到两栏布局，保证界面状态零闪烁与零错位；
/// 4. 选中项智能保持：横屏下确保选中项有效，支持外部受控与自动选中第一项；
/// 5. 多选面板自适应：自动处理横屏与竖屏下底部多选浮层的动画与避让高度。
class MasterDetailScaffold<T> extends StatefulWidget {
  const MasterDetailScaffold({
    super.key,
    required this.items,
    required this.itemKey,
    required this.selectedKey,
    required this.onSelectedKeyChanged,
    required this.routeName,
    required this.masterItemBuilder,
    required this.detailBuilder,
    required this.detailPageBuilder,
    this.masterToolbarBuilder,
    this.emptyMasterBuilder,
    this.emptyDetailBuilder,
    this.masterScrollController,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
    this.masterWidth,
    this.isSelectionMode = false,
    this.selectionPanel,
    this.onItemTapOverride,
    this.onItemLongPress,
    this.hasPlayingMusic = false,
    this.wrapWithInkWell = false,
  });

  /// 列表数据源
  final List<T> items;

  /// 获取每个条目的唯一标识 Key
  final String Function(T item) itemKey;

  /// 当前选中的条目 Key
  final String? selectedKey;

  /// 选中 Key 发生变化时的回调
  final ValueChanged<String> onSelectedKeyChanged;

  /// 竖屏下 push 详情页的路由名称（用于横屏时自动 pop 回退，如 'artist_detail' / 'genre_detail'）
  final String routeName;

  /// 工具栏构建器（isWide 为 true 表示横屏顶部工具栏，false 表示竖屏顶部工具栏）
  final Widget Function(BuildContext context, bool isWide)? masterToolbarBuilder;

  /// 主列表单项构建器（传入当前的 onTap 回调：横屏时为选中并触发联动，竖屏时为 push 二级详情页）
  final MasterItemWidgetBuilder<T> masterItemBuilder;

  /// 横屏右侧详情 Pane 构建器（若 selectedItem 为 null 则自动使用 emptyDetailBuilder）
  final Widget Function(BuildContext context, T selectedItem) detailBuilder;

  /// 竖屏点击条目后打开的二级详情页构建器
  final Widget Function(BuildContext context, T item) detailPageBuilder;

  /// 主列表为空时的占位视图
  final Widget Function(BuildContext context)? emptyMasterBuilder;

  /// 横屏右侧详情为空时的占位视图
  final Widget Function(BuildContext context)? emptyDetailBuilder;

  /// 主列表滚动控制器
  final ScrollController? masterScrollController;

  /// 内容区顶部内边距（避让状态栏/透明标题栏）
  final double contentTopPadding;

  /// 内容区左侧内边距（横屏避让左侧 Rail 栏）
  final double contentLeftPadding;

  /// 横屏左侧 Master 列表宽度（若为 null 则自动根据屏幕宽度自适应 260~300）
  final double? masterWidth;

  /// 是否处于多选模式
  final bool isSelectionMode;

  /// 底部多选面板（若有）
  final Widget? selectionPanel;

  /// 点击列表项的自定义拦截处理（若返回 true 则不执行默认的选中/跳转逻辑）
  final bool Function(T item, int index)? onItemTapOverride;

  /// 长按列表项的回调
  final void Function(T item, int index)? onItemLongPress;

  /// 当前是否有歌曲正在播放（用于计算竖屏下 MiniPlayer 底部避让）
  final bool hasPlayingMusic;

  /// 是否由脚手架自动为列表项包裹 InkWell（如果条目自身已有 InkWell 或拖拽/右键等手势，设为 false）
  final bool wrapWithInkWell;

  @override
  State<MasterDetailScaffold<T>> createState() => _MasterDetailScaffoldState<T>();
}

class _MasterDetailScaffoldState<T> extends State<MasterDetailScaffold<T>> {
  bool _isDetailPushed = false;
  late ScrollController _internalScrollController;

  ScrollController get _effectiveScrollController =>
      widget.masterScrollController ?? _internalScrollController;

  @override
  void initState() {
    super.initState();
    _internalScrollController = ScrollController();
  }

  @override
  void dispose() {
    _internalScrollController.dispose();
    super.dispose();
  }

  T? _resolveSelectedItem(List<T> items) {
    if (items.isEmpty) return null;
    final selectedKey = widget.selectedKey;
    if (selectedKey != null) {
      for (final item in items) {
        if (widget.itemKey(item) == selectedKey) {
          return item;
        }
      }
    }
    return items.first;
  }

  void _syncSelectedItem(List<T> items) {
    if (items.isEmpty) return;
    final selectedKey = widget.selectedKey;
    if (selectedKey != null &&
        items.any((item) => widget.itemKey(item) == selectedKey)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || items.isEmpty) return;
      final fallbackKey = widget.itemKey(items.first);
      if (widget.selectedKey == fallbackKey) return;
      widget.onSelectedKeyChanged(fallbackKey);
    });
  }

  void _openDetailOnPortrait(T item) {
    final key = widget.itemKey(item);
    widget.onSelectedKeyChanged(key);
    _isDetailPushed = true;

    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: widget.routeName),
            builder: (ctx) => widget.detailPageBuilder(ctx, item),
          ),
        )
        .then((_) {
          if (mounted) {
            _isDetailPushed = false;
          }
        });
  }

  void _handleMasterTap(T item, int index, bool isLandscape) {
    if (widget.onItemTapOverride != null &&
        widget.onItemTapOverride!(item, index)) {
      return;
    }
    if (isLandscape) {
      widget.onSelectedKeyChanged(widget.itemKey(item));
    } else {
      _openDetailOnPortrait(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.items;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;

        // 若横竖屏旋转为横屏，且竖屏下曾 push 了详情页，自动退回当前两栏页
        if (isLandscape && _isDetailPushed) {
          _isDetailPushed = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).popUntil(
                (route) => route.settings.name != widget.routeName,
              );
            }
          });
        }

        final selectedItem = _resolveSelectedItem(items);
        final showBottomPanel = widget.isSelectionMode || widget.selectionPanel != null;

        Widget mainContent;

        if (isLandscape) {
          _syncSelectedItem(items);
          final leftPaneWidth = widget.masterWidth ??
              (constraints.maxWidth >= 1100 ? 300.0 : 260.0);
          final bottomPadding = showBottomPanel ? 180.0 : 12.0;

          mainContent = Padding(
            padding: EdgeInsets.only(
              top: widget.contentTopPadding,
              left: widget.contentLeftPadding,
            ),
            child: Column(
              children: [
                if (widget.masterToolbarBuilder != null)
                  widget.masterToolbarBuilder!(context, true),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 左侧 Master 列表
                      SizedBox(
                        width: leftPaneWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                          ),
                          child: items.isEmpty
                              ? (widget.emptyMasterBuilder != null
                                  ? widget.emptyMasterBuilder!(context)
                                  : const SizedBox.shrink())
                              : Scrollbar(
                                  controller: _effectiveScrollController,
                                  thumbVisibility: true,
                                  child: ListView.builder(
                                    controller: _effectiveScrollController,
                                    padding: EdgeInsets.fromLTRB(
                                      8,
                                      8,
                                      8,
                                      bottomPadding,
                                    ),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      final isSelected =
                                          widget.itemKey(item) ==
                                          widget.selectedKey;
                                      void handleTap() => _handleMasterTap(
                                          item, index, true);

                                      final itemWidget = widget.masterItemBuilder(
                                        context,
                                        item,
                                        index,
                                        isSelected,
                                        true,
                                        handleTap,
                                      );

                                      return Padding(
                                        key: ValueKey(widget.itemKey(item)),
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: widget.wrapWithInkWell
                                            ? InkWell(
                                                onTap: handleTap,
                                                onLongPress: widget
                                                            .onItemLongPress !=
                                                        null
                                                    ? () => widget.onItemLongPress!(
                                                        item, index)
                                                    : null,
                                                child: itemWidget,
                                              )
                                            : itemWidget,
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
                      // 右侧 Detail 详情
                      Expanded(
                        child: selectedItem != null
                            ? widget.detailBuilder(context, selectedItem)
                            : (widget.emptyDetailBuilder != null
                                ? widget.emptyDetailBuilder!(context)
                                : const SizedBox.shrink()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          // 竖屏：单栏列表
          final bottomOffset = MiniPlayerUiTuning.getListBottomPadding(
            context,
            hasPlayingMusic: widget.hasPlayingMusic,
            isSelectionMode: widget.isSelectionMode,
          );

          mainContent = Padding(
            padding: EdgeInsets.only(left: widget.contentLeftPadding),
            child: CustomScrollView(
              controller: _effectiveScrollController,
              slivers: [
                if (widget.contentTopPadding > 0)
                  SliverToBoxAdapter(
                    child: SizedBox(height: widget.contentTopPadding),
                  ),
                if (widget.masterToolbarBuilder != null)
                  SliverToBoxAdapter(
                    child: widget.masterToolbarBuilder!(context, false),
                  ),
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: widget.emptyMasterBuilder != null
                        ? widget.emptyMasterBuilder!(context)
                        : const SizedBox.shrink(),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, bottomOffset),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index.isOdd) {
                            return const SizedBox(height: 8);
                          }
                          final itemIndex = index ~/ 2;
                          final item = items[itemIndex];
                          final isSelected =
                              widget.itemKey(item) == widget.selectedKey;
                          void handleTap() => _handleMasterTap(
                              item, itemIndex, false);

                          final itemWidget = widget.masterItemBuilder(
                            context,
                            item,
                            itemIndex,
                            isSelected,
                            false,
                            handleTap,
                          );

                          return widget.wrapWithInkWell
                              ? InkWell(
                                  onTap: handleTap,
                                  onLongPress: widget.onItemLongPress != null
                                      ? () => widget.onItemLongPress!(
                                          item, itemIndex)
                                      : null,
                                  child: itemWidget,
                                )
                              : itemWidget;
                        },
                        childCount: items.length * 2 - 1,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        return Stack(
          children: [
            Positioned.fill(child: mainContent),
            if (widget.selectionPanel != null)
              AnimatedSelectionPanel(
                isVisible: widget.isSelectionMode,
                child: widget.selectionPanel!,
              ),
          ],
        );
      },
    );
  }
}
