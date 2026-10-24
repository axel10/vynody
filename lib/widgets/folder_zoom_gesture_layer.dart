import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart'
    show LibraryZoomScope;
import 'folder_layout_utils.dart';

/// 两次滚轮事件之间静默多久，就算「新的一次滚动」。
///
/// 「滚一格」在 macOS 上往往不是一个事件：平滑滚动会把它拆成一串间隔
/// `8~16ms` 的事件，松手后的惯性还会再补一长串。所以滚轮按「滚动簇」处理——
/// 时间戳间隔小于这个值的连续同向事件算同一簇，**一簇只换一档**。
///
/// 这个值要同时满足两件事：
/// - 大于设备拆分单个物理格时的间隔（`~16ms`），否则一格会换两档；
/// - 小于人手连续滚两格的最小间隔（`~40ms` 以上），否则两格并成一档。
const Duration kFolderZoomWheelGestureGap = Duration(milliseconds: 50);

/// 捏合比例超过这个倍数（或它的倒数）才算「有明确的放大/缩小意图」。
///
/// 一次捏合手势最多只换一档，所以这里只决定「多小的张合才触发」，
/// 不再决定跨几档——`1.08` 约等于双指间距变化 8%。
const double kFolderZoomPinchStepRatio = 1.08;

/// 给「按档位缩放条目」的滚动区挂上第二套调节入口：
///
/// - 键鼠：`Ctrl` + 滚轮（macOS 上 `⌘` + 滚轮同样有效），向上滚放大、向下滚缩小，
///   一次滚动只走一档；
/// - 触控板：双指捏合；
/// - 触屏：双指捏合。
///
/// 两者都只是把 [scope] 对应的档位值沿 [kFolderZoomTierValues] 逐档步进，
/// 实际布局仍由 `FolderZoomSliverBuilder` 负责动画，所以和右上角的档位弹窗
/// 完全共用一套状态。
///
/// [scope] 决定写哪一份记忆：目录页是 [LibraryZoomScope.folder]（默认），
/// 专辑页是 `album`，专辑详情的曲目是 `track`。
class FolderZoomGestureLayer extends ConsumerStatefulWidget {
  const FolderZoomGestureLayer({
    super.key,
    required this.child,
    this.scope = LibraryZoomScope.folder,
  });

  final Widget child;
  final LibraryZoomScope scope;

  @override
  ConsumerState<FolderZoomGestureLayer> createState() =>
      _FolderZoomGestureLayerState();
}

class _FolderZoomGestureLayerState extends ConsumerState<FolderZoomGestureLayer> {
  /// 当前滚动簇的方向（`1` 放大、`-1` 缩小，`0` 表示还没有簇）与上一笔事件时间戳。
  ///
  /// 旧实现是「按像素累计 + 150ms 冷却」，两个坑叠在一起：
  /// 1. 累计到 40px 才换档，而 macOS 上一格鼠标滚轮的 `scrollDelta` 常小于 40，
  ///    于是要滚好几格才响一次，手感就是「有时没反应」；
  /// 2. 冷却期内的事件照样累加，冷却一过就把攒下来的量一次结算掉，
  ///    于是「再滚一下就跳两档」。
  ///
  /// 现在改成按簇计：每簇的第一笔事件立刻换一档，同簇后续事件（含惯性）全部吞掉。
  Duration? _lastWheelStamp;
  int _wheelBurstDirection = 0;
  bool _wheelBurstStepped = false;

  /// 本次捏合是否已经换过档。
  ///
  /// 一次捏合（手指按下到抬起）只换一档：档位是离散的六档，连续跟手会把
  /// 一档一档连成「一捏到底」，很难停在中意的档位上。
  bool _pinchStepLatched = false;

  bool get _isZoomModifierPressed {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed) return true;
    // macOS 上 ⌘ + 滚轮是更顺手的习惯，一并认。
    return defaultTargetPlatform == TargetPlatform.macOS &&
        keyboard.isMetaPressed;
  }

  void _stepTier(int steps, {bool haptic = false}) {
    if (steps == 0) return;
    final settings = ref.read(settingsServiceProvider);
    final current = settings.zoomScaleFor(widget.scope);
    final stepped = stepFolderZoomScale(current, steps);
    final next = widget.scope == LibraryZoomScope.queue
        ? stepped.clamp(
            kFolderZoomTierMinimalList,
            kFolderZoomTierLargeList,
          )
        : stepped;
    if ((next - current).abs() < 1e-6) return;
    settings.setZoomScale(widget.scope, next);
    if (haptic) {
      HapticFeedback.selectionClick();
    }
  }

  // ── 键鼠 / 触控板滚轮 ────────────────────────────────────────────────

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_isZoomModifierPressed) return;

    final delta = event.scrollDelta;
    final double amount = delta.dy != 0 ? delta.dy : delta.dx;
    if (amount == 0) return;

    // 必须抢占 pointerSignalResolver：Scrollable 内部的 Listener 在 hit-test
    // 路径上比这一层更深，正常情况下它会先注册并赢下事件，列表就会跟着滚。
    // 这里的 Listener 盖在滚动区上方（见 build），路径顺序更靠前，先注册先赢。
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent signal,
    ) {
      if (signal is PointerScrollEvent) {
        signal.respond(allowPlatformDefault: false);
      }
      _handleWheel(amount, event.timeStamp);
    });
  }

  /// 一笔滚轮事件 → 最多推进一档。
  ///
  /// 用 [PointerScrollEvent.timeStamp]（引擎给的单调平台时间）而不是
  /// `DateTime.now()`：它不会因为一帧内批量派发而失真，也便于测试直接构造时间轴。
  void _handleWheel(double amount, Duration timeStamp) {
    // 向上滚（dy 为负）放大、向下滚缩小，和浏览器 Ctrl+滚轮一致。
    final int direction = amount.isNegative ? 1 : -1;

    final lastStamp = _lastWheelStamp;
    _lastWheelStamp = timeStamp;

    final bool continuesBurst = lastStamp != null &&
        timeStamp >= lastStamp &&
        timeStamp - lastStamp < kFolderZoomWheelGestureGap &&
        direction == _wheelBurstDirection;

    if (!continuesBurst) {
      // 静默够久或换了方向：算新的一次滚动，重新获得一档额度。
      _wheelBurstDirection = direction;
      _wheelBurstStepped = false;
    }
    // 同一簇里只认第一笔：触控板惯性、系统把一个物理格拆成多笔，都走这里被吞掉。
    if (_wheelBurstStepped) return;

    _wheelBurstStepped = true;
    _stepTier(direction);
  }

  // ── 触控板捏合（PointerPanZoom） ───────────────────────────────────

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    // 触控板双指滚动同样走 panZoom，只有真正捏合（scale 偏离 1）才处理。
    if ((event.scale - 1.0).abs() < 1e-3) return;
    _applyPinchScale(event.scale, haptic: false);
  }

  // ── 触屏捏合 ──────────────────────────────────────────────────────
  //
  // 触屏这条路径同时挂了两套检测：
  // 1. 覆盖层 Listener 里的原始指针表——不参与手势竞技场，所以哪怕
  //    Scrollable 的拖拽识别器抢走了第一根手指，这里照样能算出双指间距；
  // 2. [_FolderPinchGestureRecognizer]——它的职责其实是「别让列表跟着滚」，
  //    顺带也能触发换档。
  // 两边都走 [_applyPinchScale]，靠 [_pinchStepLatched] 去重，一次捏合只换一档。

  /// 当前按在屏幕上的触点（仅触屏），以及双指标定间距。
  final Map<int, Offset> _touchPointers = <int, Offset>{};
  double? _pinchBaseSpan;

  bool _isTouch(PointerEvent event) => event.kind == PointerDeviceKind.touch;

  void _handleTouchDown(PointerDownEvent event) {
    if (!_isTouch(event)) return;
    _touchPointers[event.pointer] = event.position;
    if (_touchPointers.length >= 2) {
      // 双指（或更多）齐了：以这一刻的间距为基准，本手势只换一档。
      _pinchBaseSpan = _currentSpan();
      _resetPinch();
    }
  }

  void _handleTouchMove(PointerMoveEvent event) {
    if (!_isTouch(event) || !_touchPointers.containsKey(event.pointer)) return;
    _touchPointers[event.pointer] = event.position;

    final base = _pinchBaseSpan;
    if (base == null || base <= 0) return;
    final span = _currentSpan();
    if (span <= 0) return;
    _applyPinchScale(span / base, haptic: true);
  }

  void _handleTouchUp(PointerEvent event) {
    if (!_isTouch(event)) return;
    if (_touchPointers.remove(event.pointer) == null) return;
    if (_touchPointers.length < 2) {
      // 手指少于两根：本次捏合结束，下一次捏合可以再换一档。
      _pinchBaseSpan = null;
      _resetPinch();
    }
  }

  /// 当前触点中最远的两个之间的距离；不足两个返回 `0`。
  double _currentSpan() {
    if (_touchPointers.length < 2) return 0;
    double maxSpan = 0;
    final points = _touchPointers.values.toList(growable: false);
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final distance = (points[i] - points[j]).distance;
        if (distance > maxSpan) maxSpan = distance;
      }
    }
    return maxSpan;
  }

  void _handlePinchUpdate(ScaleUpdateDetails details) {
    _applyPinchScale(details.scale, haptic: true);
  }

  void _resetPinch() => _pinchStepLatched = false;

  void _applyPinchScale(double scale, {required bool haptic}) {
    if (_pinchStepLatched || scale <= 0 || scale.isNaN) return;

    final int steps;
    if (scale >= kFolderZoomPinchStepRatio) {
      steps = 1;
    } else if (scale <= 1 / kFolderZoomPinchStepRatio) {
      steps = -1;
    } else {
      return;
    }

    _pinchStepLatched = true;
    _stepTier(steps, haptic: haptic);
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _FolderPinchGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_FolderPinchGestureRecognizer>(
              () => _FolderPinchGestureRecognizer(debugOwner: this),
              (_FolderPinchGestureRecognizer instance) {
                instance.onUpdate = _handlePinchUpdate;
              },
            ),
      },
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handleTouchDown,
              onPointerMove: _handleTouchMove,
              onPointerUp: _handleTouchUp,
              onPointerCancel: _handleTouchUp,
              onPointerSignal: _handlePointerSignal,
              onPointerPanZoomStart: (_) => _resetPinch(),
              onPointerPanZoomUpdate: _handlePanZoomUpdate,
              onPointerPanZoomEnd: (_) => _resetPinch(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 只认双指触屏捏合的 [ScaleGestureRecognizer]。
///
/// 触控板的 panZoom 一律不受理，否则它会和 Scrollable 的双指滚动抢手势，
/// 把「双指上下滚动」变成「缩放空转」。
class _FolderPinchGestureRecognizer extends ScaleGestureRecognizer {
  _FolderPinchGestureRecognizer({super.debugOwner});

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    return event.kind == PointerDeviceKind.touch && super.isPointerAllowed(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    // 第二根手指一落下就接管手势。
    //
    // 痛点：不接管的话，第一根手指的细微位移（甚至只是按压时的滚形）就会让
    // Scrollable 的拖拽识别器先一步赢下竞技场，我们被踢出那个 pointer，
    // 之后永远凑不齐两根手指——触屏上表现为「双指捏合时灵时不灵」。
    // 接管后双指平移不再滚动列表，但触屏滚动本来就靠单指，代价可以接受。
    if (event is PointerDownEvent && pointerCount >= 2) {
      resolve(GestureDisposition.accepted);
    }
  }
}
