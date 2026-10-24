import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/selection_utils.dart';
import '../library_selection_scope.dart';

/// 进程级开关注册表，用来让原生文件拖拽给框选让路。
///
/// [DragSource] 会把 [suppressNativeDrag] 接到 `isLocationDraggable` 上：
/// 返回 `false` 时 `super_drag_and_drop` 的拖拽手势不会进入 arena，因此
/// 按住 Alt 从曲目行起手拖动会落到框选而不是「把歌拖到 Finder」。
///
/// 只有存在活跃的 [MarqueeSelectionRegion] 时才生效，未接入框选的列表
/// 行为完全不变。
class MarqueeSelectionRuntime {
  const MarqueeSelectionRuntime._();

  static int _activeRegions = 0;

  static void attachRegion() => _activeRegions++;

  static void detachRegion() {
    if (_activeRegions > 0) _activeRegions--;
  }

  static bool get isAvailable => _activeRegions > 0;

  /// 按住 Alt 强制框选。Alt 在指针按下当刻读取，与手势竞技场没有时序竞争。
  static bool get suppressNativeDrag =>
      isAvailable && ModifierKeyUtils.isAltPressed;
}

/// 框选区域：包裹一个可滚动列表，支持鼠标左键拖出矩形框批量选中。
///
/// 起手规则（与文件管理器一致）：
/// * 在列表项之间的空白处按下拖动 → 框选；
/// * 在列表项上按住 Alt 拖动 → 强制框选（压掉原生文件拖拽）；
/// * 在列表项上直接拖动 → 保持原生的拖拽文件行为，不受影响。
///
/// 选中结果直接写入 [librarySelectionStateProvider]，因此调用方无需再维护
/// 额外的选中状态：多选态、底部操作面板、条目高亮都会自动跟随。
class MarqueeSelectionRegion extends ConsumerStatefulWidget {
  const MarqueeSelectionRegion({
    super.key,
    required this.child,
    required this.scope,
    this.enabled = true,
    this.scrollController,
    this.autoScroll = true,
  });

  final Widget child;

  /// 框选结果写入的选择作用域，须与列表所在的 [SelectionStateMixin.selectionScope] 一致。
  final LibrarySelectionScope scope;

  final bool enabled;

  /// 用于拖到视口边缘时自动滚动。为空时不做自动滚动。
  final ScrollController? scrollController;

  final bool autoScroll;

  @override
  ConsumerState<MarqueeSelectionRegion> createState() =>
      _MarqueeSelectionRegionState();
}

/// 拖动多少逻辑像素后才认定这是一次框选（低于阈值按普通点击处理）。
const double _kMarqueeDragThreshold = 4.0;

/// 距离视口上下边缘多少像素开始自动滚动。
const double _kAutoScrollEdge = 56.0;

class _MarqueeSelectionRegionState extends ConsumerState<MarqueeSelectionRegion>
    with SingleTickerProviderStateMixin {
  final _MarqueeItemRegistry _registry = _MarqueeItemRegistry();

  /// 框选矩形（本组件坐标系）。用 [ValueNotifier] 驱动重绘，避免拖动过程中
  /// 每帧 setState 重建整棵列表。
  final ValueNotifier<Rect?> _marqueeRect = ValueNotifier<Rect?>(null);

  late final Ticker _ticker;

  Offset? _origin;
  Offset _current = Offset.zero;
  bool _dragging = false;

  /// 本次拖动是否框到过任何条目。没框到过就不提交空集合，避免误清空已有选择。
  bool _hasEverHit = false;

  /// Ctrl/Cmd 追加选择时的基础集合，拖动开始时快照。
  Set<Object> _baseSelection = const <Object>{};

  /// 上一次已提交给 provider 的集合，用于抑制无意义的重复提交。
  Set<Object> _committed = const <Object>{};

  @override
  void initState() {
    super.initState();
    // 必须在此处就创建：放到 `late` 延迟初始化，组件若从未拖动过，第一次
    // 触碰会发生在 dispose，那时 element 已 deactivate，createTicker 会抛错。
    _ticker = createTicker(_handleTick);
    if (widget.enabled) MarqueeSelectionRuntime.attachRegion();
  }

  @override
  void didUpdateWidget(covariant MarqueeSelectionRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        MarqueeSelectionRuntime.attachRegion();
      } else {
        MarqueeSelectionRuntime.detachRegion();
        _abortDrag();
      }
    }
  }

  @override
  void dispose() {
    if (widget.enabled) MarqueeSelectionRuntime.detachRegion();
    _ticker.dispose();
    _marqueeRect.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 指针处理
  // ---------------------------------------------------------------------------

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event.buttons != kPrimaryMouseButton) return;

    final forceMarquee = ModifierKeyUtils.isAltPressed;
    // 曲目行上直接拖动交给原生文件拖拽，不抢。
    if (!forceMarquee && _isPointerOverItem(event.position)) return;

    final selection = ref.read(librarySelectionStateProvider);
    final currentKeys = selection.scope == widget.scope
        ? <Object>{...selection.selectedKeys}
        : const <Object>{};

    _baseSelection = ModifierKeyUtils.isDiscreteSelectPressed
        ? currentKeys
        : const <Object>{};
    _committed = currentKeys;
    _origin = event.localPosition;
    _current = event.localPosition;
    _dragging = false;
    _hasEverHit = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_origin == null) return;
    _current = event.localPosition;

    if (!_dragging) {
      if ((_current - _origin!).distance < _kMarqueeDragThreshold) return;
      _dragging = true;
      if (widget.autoScroll && widget.scrollController != null) {
        _ticker.start();
      }
    }
    _updateMarquee();
  }

  void _handlePointerUp(PointerUpEvent event) => _abortDrag();

  void _handlePointerCancel(PointerCancelEvent event) => _abortDrag();

  void _abortDrag() {
    _origin = null;
    _dragging = false;
    _hasEverHit = false;
    _marqueeRect.value = null;
    _baseSelection = const <String>{};
    if (_ticker.isActive) _ticker.stop();
  }

  // ---------------------------------------------------------------------------
  // 命中计算与提交
  // ---------------------------------------------------------------------------

  void _updateMarquee() {
    final origin = _origin;
    if (origin == null) return;

    final rect = Rect.fromPoints(origin, _current);
    _marqueeRect.value = rect;

    final hits = _collectHits(rect);
    if (hits.isEmpty && !_hasEverHit) return;
    if (hits.isNotEmpty) _hasEverHit = true;

    if (setEquals(hits, _committed)) return;
    _committed = hits;
    ref
        .read(librarySelectionStateProvider.notifier)
        .setSelection(hits, scope: widget.scope);
  }

  Set<Object> _collectHits(Rect localRect) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return _baseSelection.toSet();

    // 指针可以被拖到组件外，把矩形裁回可见区域，避免误选视口外的条目。
    final regionRect = box.localToGlobal(Offset.zero) & box.size;
    final globalRect = Rect.fromPoints(
      box.localToGlobal(localRect.topLeft),
      box.localToGlobal(localRect.bottomRight),
    ).intersect(regionRect);
    // 允许零宽 / 零高：垂直或水平拖动是常见操作，此时框线退化成一条线，
    // 仍应按「线上覆盖到的行」命中。
    if (globalRect.left > globalRect.right ||
        globalRect.top > globalRect.bottom) {
      return _baseSelection.toSet();
    }

    final hits = <Object>{..._baseSelection};
    for (final entry in _registry.entries) {
      final itemBox = entry.value.context.findRenderObject();
      if (itemBox is! RenderBox || !itemBox.attached || !itemBox.hasSize) {
        continue;
      }
      final itemRect = itemBox.localToGlobal(Offset.zero) & itemBox.size;
      if (itemRect.overlaps(globalRect)) {
        hits.add(entry.key);
      }
    }
    return hits;
  }

  /// 指针下方是不是某个可框选条目（含条目自身的空白内边距）。
  bool _isPointerOverItem(Offset globalPosition) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      if (entry.target is _RenderMarqueeItemMarker) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // 边缘自动滚动
  // ---------------------------------------------------------------------------

  void _handleTick(Duration _) {
    if (!_dragging) return;
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) return;

    final size = context.size;
    if (size == null || size.height <= 0) return;

    final position = controller.position;
    final dy = _current.dy;
    double delta = 0;
    if (dy < _kAutoScrollEdge) {
      delta = -_autoScrollSpeed(_kAutoScrollEdge - dy);
    } else if (dy > size.height - _kAutoScrollEdge) {
      delta = _autoScrollSpeed(dy - (size.height - _kAutoScrollEdge));
    }
    if (delta == 0) return;

    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;

    position.jumpTo(target);
    // 内容位移后条目矩形变了，重新框一次。
    _updateMarquee();
  }

  double _autoScrollSpeed(double overshoot) {
    final ratio = (overshoot / _kAutoScrollEdge).clamp(0.0, 1.0);
    return 2.0 + ratio * 12.0;
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _MarqueeScope(
      registry: _registry,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MarqueePainter(
                    rect: _marqueeRect,
                    fillColor: scheme.primary.withValues(alpha: 0.10),
                    borderColor: scheme.primary.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 条目注册
// -----------------------------------------------------------------------------

/// 标记一个列表条目参与框选。
///
/// 没有上层 [MarqueeSelectionRegion] 时自动退化为纯透传，接入是安全的：
/// 可以先在各列表条目上包好，再逐个页面开启框选区域。
class MarqueeSelectableItem extends StatefulWidget {
  const MarqueeSelectableItem({
    super.key,
    required this.selectionKey,
    required this.child,
  });

  /// 与 [LibrarySelectionState.selectedKeys] 一致的键。
  ///
  /// 曲目列表里是歌曲路径（String），播放列表里是下标（int）—— 各页面
  /// 的 `SelectionStateMixin` 用的是哪种键，这里就必须用哪种。
  final Object selectionKey;

  final Widget child;

  @override
  State<MarqueeSelectableItem> createState() => _MarqueeSelectableItemState();
}

class _MarqueeSelectableItemState extends State<MarqueeSelectableItem> {
  _MarqueeItemRegistry? _registry;
  Object? _registeredKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = _MarqueeScope.maybeOf(context);
    if (!identical(registry, _registry)) {
      _detach();
      _registry = registry;
      _attach();
    }
  }

  @override
  void didUpdateWidget(covariant MarqueeSelectableItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionKey != widget.selectionKey) {
      _detach();
      _attach();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attach() =>
      _registeredKey = _registry?.register(widget.selectionKey, this);

  void _detach() {
    final key = _registeredKey;
    if (key != null) {
      _registry?.unregister(key, this);
      _registeredKey = null;
    }
  }

  @override
  Widget build(BuildContext context) => _MarqueeItemMarker(child: widget.child);
}

class _MarqueeItemRegistry {
  final Map<Object, _MarqueeSelectableItemState> _items =
      <Object, _MarqueeSelectableItemState>{};

  Object register(Object key, _MarqueeSelectableItemState state) {
    _items[key] = state;
    return key;
  }

  void unregister(Object key, _MarqueeSelectableItemState state) {
    if (identical(_items[key], state)) _items.remove(key);
  }

  Iterable<MapEntry<Object, _MarqueeSelectableItemState>> get entries =>
      _items.entries;
}

class _MarqueeScope extends InheritedWidget {
  const _MarqueeScope({required this.registry, required super.child});

  final _MarqueeItemRegistry registry;

  static _MarqueeItemRegistry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MarqueeScope>()?.registry;

  @override
  bool updateShouldNotify(_MarqueeScope oldWidget) =>
      !identical(registry, oldWidget.registry);
}

/// 让整块条目区域（含条目自身的透明内边距）都算作「按在条目上」。
class _MarqueeItemMarker extends SingleChildRenderObjectWidget {
  const _MarqueeItemMarker({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMarqueeItemMarker();
}

class _RenderMarqueeItemMarker extends RenderProxyBox {
  @override
  bool hitTestSelf(Offset position) => true;
}

// -----------------------------------------------------------------------------
// 矩形绘制
// -----------------------------------------------------------------------------

class _MarqueePainter extends CustomPainter {
  _MarqueePainter({
    required this.rect,
    required this.fillColor,
    required this.borderColor,
  }) : super(repaint: rect);

  final ValueListenable<Rect?> rect;
  final Color fillColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final value = rect.value;
    if (value == null) return;

    // 垂直/水平拖动时框会退化成一条线，补到 1px 才看得见。
    final visible = Rect.fromLTRB(
      value.left,
      value.top,
      math.max(value.right, value.left + 1),
      math.max(value.bottom, value.top + 1),
    );

    final rounded = RRect.fromRectAndRadius(visible, const Radius.circular(2));
    canvas.drawRRect(rounded, Paint()..color = fillColor);
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );
  }

  @override
  bool shouldRepaint(covariant _MarqueePainter oldDelegate) =>
      !identical(oldDelegate.rect, rect) ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.borderColor != borderColor;
}
