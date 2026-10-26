import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
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

/// 左侧 Master 列表为滚动条预留的右侧空白（逻辑像素）。
///
/// 滚动条是悬浮绘制在内容之上的（桌面端默认厚度 8），条目的选中态背景若铺满
/// 整个栏宽，右缘就会压在滚动条底下，故右侧额外留出这段间距。
const double _masterScrollbarReserve = 12.0;

/// 响应式主从分栏/两级页面通用脚手架
///
/// 特性：
/// 1. 横屏/宽屏：左侧 Master 列表 + 右侧 Detail 详情（两栏分栏），左栏带分割线，右栏无选中时显示占位组件；
/// 2. 竖屏/窄屏：一级页面仅显示 Master 列表，点击条目通过 Navigator.push 进入二级详情页；
/// 3. 横竖屏旋转自适应：竖屏下 Push 了二级详情页时若旋转到横屏，自动 pop 详情页回到两栏布局，状态零闪烁与零错位；
///    反向旋转（横屏 → 竖屏）不自动跳转，始终停留在主列表，是否进入详情页完全由用户点击决定；
/// 4. 选中项智能保持：横屏下确保选中项有效，支持外部受控、通过 selectedKeyProvider 自动响应与自动选中第一项；
/// 5. 多选面板自适应：自动处理横屏与竖屏下底部多选浮层的动画与避让高度。
class MasterDetailScaffold<T> extends ConsumerStatefulWidget {
  const MasterDetailScaffold({
    super.key,
    required this.items,
    required this.itemKey,
    this.selectedKey,
    this.onSelectedKeyChanged,
    this.selectedKeyProvider,
    this.onKeySelected,
    required this.routeName,
    required this.masterItemBuilder,
    required this.detailBuilder,
    required this.detailPageBuilder,
    this.masterToolbarBuilder,
    this.masterPaneHeaderBuilder,
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
    this.portraitScrollWrapper,
    this.portraitSliverBuilder,
  });

  /// 列表数据源
  final List<T> items;

  /// 获取每个条目的唯一标识 Key
  final String Function(T item) itemKey;

  /// 当前选中的条目 Key（外部受控模式）
  final String? selectedKey;

  /// 选中 Key 发生变化时的回调
  final ValueChanged<String>? onSelectedKeyChanged;

  /// 选中的 key 的 Provider 监听源（用于跨路由/跨页面自动响应选中项变更）
  final ProviderListenable<String?>? selectedKeyProvider;

  /// 当在列表手动切换选中 key 时，若传入了此回调，自动回写 Provider
  final void Function(WidgetRef ref, String key)? onKeySelected;

  /// 竖屏下 push 详情页的路由名称（用于横屏时自动 pop 回退，如 'artist_detail' / 'genre_detail'）
  final String routeName;

  /// 工具栏构建器（isWide 为 true 表示横屏顶部工具栏，false 表示竖屏顶部工具栏）
  final Widget Function(BuildContext context, bool isWide)? masterToolbarBuilder;

  /// 横屏时贴在左栏内部的栏头（通常是「搜索左侧列表」的输入框）。
  ///
  /// 横屏页头横跨两栏，把列表搜索放在页头里会让人分不清它过滤的是哪一栏，
  /// 右侧详情再有自己的搜索时两个放大镜还会挨在一起；
  /// 收进左栏后「左搜条目、右搜内容」的关系一眼可见。
  /// 竖屏不使用（竖屏没有分栏，搜索留在页头即可）。
  final Widget Function(BuildContext context)? masterPaneHeaderBuilder;

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

  /// 竖屏滚动区外层包裹器（例如接入手势变焦层）。
  final Widget Function(BuildContext context, Widget child)? portraitScrollWrapper;

  /// 竖屏 Slivers 构建器（若提供，将替代默认的单列列表 SliverPadding）。
  final List<Widget> Function(
    BuildContext context,
    List<T> items,
    BoxConstraints constraints,
    double bottomOffset,
  )? portraitSliverBuilder;

  @override
  ConsumerState<MasterDetailScaffold<T>> createState() =>
      _MasterDetailScaffoldState<T>();
}

class _MasterDetailScaffoldState<T>
    extends ConsumerState<MasterDetailScaffold<T>> {
  bool _isDetailPushed = false;
  late ScrollController _internalScrollController;
  String? _internalSelectedKey;

  ScrollController get _effectiveScrollController =>
      widget.masterScrollController ?? _internalScrollController;

  String? get _effectiveSelectedKey =>
      widget.selectedKey ?? _internalSelectedKey;

  @override
  void initState() {
    super.initState();
    _internalScrollController = ScrollController();
    final initKey = widget.selectedKey ??
        (widget.selectedKeyProvider != null
            ? ref.read(widget.selectedKeyProvider!)
            : null);
    if (initKey != null) {
      _internalSelectedKey = initKey;
      _scrollToSelectedKey(initKey, widget.items);
    }
  }

  @override
  void didUpdateWidget(covariant MasterDetailScaffold<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedKey != null &&
        widget.selectedKey != oldWidget.selectedKey) {
      _internalSelectedKey = widget.selectedKey;
      _scrollToSelectedKey(widget.selectedKey, widget.items);
    } else if (oldWidget.items.isEmpty && widget.items.isNotEmpty) {
      final key = _effectiveSelectedKey;
      if (key != null) {
        _scrollToSelectedKey(key, widget.items);
      }
    }
  }

  void _scrollToSelectedKey(String? key, List<T> items) {
    if (key == null || items.isEmpty) return;
    final index = items.indexWhere((item) => widget.itemKey(item) == key);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_effectiveScrollController.hasClients) return;
      const double estimatedItemExtent = 64.0;
      final targetOffset = (index * estimatedItemExtent).clamp(
        0.0,
        _effectiveScrollController.position.maxScrollExtent,
      );
      final currentOffset = _effectiveScrollController.offset;
      final viewportHeight =
          _effectiveScrollController.position.viewportDimension;
      if (targetOffset < currentOffset ||
          targetOffset > currentOffset + viewportHeight - estimatedItemExtent) {
        _effectiveScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _internalScrollController.dispose();
    super.dispose();
  }

  T? _findItemByKey(String key, List<T> items) {
    for (final item in items) {
      if (widget.itemKey(item) == key) return item;
    }
    return null;
  }

  void _selectKey(
    String key, {
    required bool isUserAction,
    required bool isLandscape,
  }) {
    if (_internalSelectedKey != key) {
      setState(() {
        _internalSelectedKey = key;
      });
    }
    if (widget.onKeySelected != null) {
      widget.onKeySelected!(ref, key);
    }
    widget.onSelectedKeyChanged?.call(key);
    _scrollToSelectedKey(key, widget.items);

    if (!isLandscape && !isUserAction && !_isDetailPushed) {
      final targetItem = _findItemByKey(key, widget.items);
      if (targetItem != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              !_isDetailPushed &&
              MediaQuery.orientationOf(context) == Orientation.portrait) {
            _openDetailOnPortrait(targetItem);
          }
        });
      }
    }
  }

  T? _resolveSelectedItem(List<T> items) {
    if (items.isEmpty) return null;
    final selectedKey = _effectiveSelectedKey;
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
    final selectedKey = _effectiveSelectedKey;
    if (selectedKey != null &&
        items.any((item) => widget.itemKey(item) == selectedKey)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || items.isEmpty) return;
      final fallbackKey = widget.itemKey(items.first);
      if (_effectiveSelectedKey == fallbackKey) return;
      setState(() {
        _internalSelectedKey = fallbackKey;
      });
      if (widget.onKeySelected != null) {
        widget.onKeySelected!(ref, fallbackKey);
      }
      widget.onSelectedKeyChanged?.call(fallbackKey);
    });
  }

  void _openDetailOnPortrait(T item) {
    final key = widget.itemKey(item);
    setState(() {
      _internalSelectedKey = key;
    });
    if (widget.onKeySelected != null) {
      widget.onKeySelected!(ref, key);
    }
    widget.onSelectedKeyChanged?.call(key);
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
    final key = widget.itemKey(item);
    if (isLandscape) {
      _selectKey(key, isUserAction: true, isLandscape: true);
    } else {
      _openDetailOnPortrait(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedKeyProvider != null) {
      ref.listen<String?>(widget.selectedKeyProvider!, (previous, next) {
        if (next != null && next != _effectiveSelectedKey) {
          final isLandscape =
              MediaQuery.orientationOf(context) == Orientation.landscape;
          _selectKey(next, isUserAction: false, isLandscape: isLandscape);
        }
      });
    }

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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.masterPaneHeaderBuilder != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12 + _masterScrollbarReserve,
                                    6,
                                  ),
                                  child: widget.masterPaneHeaderBuilder!(context),
                                ),
                              Expanded(
                                child: items.isEmpty
                                    ? (widget.emptyMasterBuilder != null
                                        ? widget.emptyMasterBuilder!(context)
                                        : const SizedBox.shrink())
                                    : Scrollbar(
                                        controller: _effectiveScrollController,
                                        // 静止时不常驻显示滚动条，仅在滚动/拖动时淡入，
                                        // 滚动结束后自动淡出（与左侧 Rail 的滚动条行为保持一致）。
                                        thumbVisibility: false,
                                        child: ListView.builder(
                                          controller: _effectiveScrollController,
                                          padding: EdgeInsets.fromLTRB(
                                            8,
                                            8,
                                            8 + _masterScrollbarReserve,
                                            bottomPadding,
                                          ),
                                          itemCount: items.length,
                                          itemBuilder: (context, index) {
                                            final item = items[index];
                                            final isSelected =
                                                widget.itemKey(item) ==
                                                    _effectiveSelectedKey;
                                            void handleTap() => _handleMasterTap(
                                                item, index, true);

                                            final itemWidget =
                                                widget.masterItemBuilder(
                                              context,
                                              item,
                                              index,
                                              isSelected,
                                              true,
                                              handleTap,
                                            );

                                            return Padding(
                                              key: ValueKey(
                                                  widget.itemKey(item)),
                                              padding:
                                                  const EdgeInsets.only(bottom: 2),
                                              child: widget.wrapWithInkWell
                                                  ? InkWell(
                                                      onTap: handleTap,
                                                      onLongPress: widget
                                                                  .onItemLongPress !=
                                                              null
                                                          ? () => widget
                                                              .onItemLongPress!(
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
                            ],
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
                else if (widget.portraitSliverBuilder != null)
                  ...widget.portraitSliverBuilder!(
                    context,
                    items,
                    constraints,
                    bottomOffset,
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
                              widget.itemKey(item) == _effectiveSelectedKey;
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

          if (widget.portraitScrollWrapper != null) {
            mainContent = widget.portraitScrollWrapper!(context, mainContent);
          }
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
