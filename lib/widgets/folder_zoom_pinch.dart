import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'folder_layout_utils.dart';

/// 捏合手势控制器：管理「手指捏合条目实时跟随缩放」与「未达阈值回弹 / 超过阈值换档」的交互状态。
class FolderZoomPinchController extends ChangeNotifier {
  FolderZoomPinchController({required TickerProvider vsync}) : _vsync = vsync;

  final TickerProvider _vsync;
  AnimationController? _animController;

  bool _isActive = false;

  /// 当前是否正处于双指捏合手势交互中（手指按住移动或松手正在吸附/回弹）。
  bool get isActive => _isActive;

  bool _isEnding = false;

  /// 当前是否正在执行松手吸附或回弹动画。
  bool get isEnding => _isEnding;

  double _baseZoomScale = 0.0;

  /// 手势开始时的基准档位（离散 snapped 值）。
  double get baseZoomScale => _baseZoomScale;

  double _targetZoomScale = 0.0;

  /// 当前手势方向意图的目标档位（放大为下一档，缩小为上一档）。
  double get targetZoomScale => _targetZoomScale;

  double _progress = 0.0;

  /// 档位过渡进度：`0.0` 对应基准档位，`1.0` 对应目标档位。
  double get progress => _progress;

  double _currentScale = 1.0;

  /// 当前捏合比例（以手势开始时的间距为 `1.0`）。
  double get currentScale => _currentScale;

  bool _isCommitted = false;

  /// 当前是否已超过换档阈值（松手是否会确认换档）。
  bool get isCommitted => _isCommitted;

  /// 最近一次通过 pinch 手势确认的目标档位。
  ///
  /// 用于通知 [FolderZoomSliverBuilder] 无需在 `didUpdateWidget` 时二次触发
  /// 260ms 的冗余过渡动画。
  double? _committedScale;
  double? get committedScale => _committedScale;

  void clearCommittedScale() => _committedScale = null;

  /// 允许的缩放档位上下限。
  double minScale = kFolderZoomTierMinimalList;
  double maxScale = kFolderZoomTierLargeGrid;

  /// 换档的进度激活阈值（移动两个触摸点距离约四分之一，即 25% 即可确认换档意图并震动）。
  static const double kCommitThreshold = 0.25;

  /// 换档的进度撤销阈值（只有反向缩回到四分之一的一半（12.5%）以下，才取消换档意图）。
  static const double kCancelThreshold = 0.125;

  /// 开始捏合手势。
  void startPinch(
    double currentScale, {
    double? min,
    double? max,
  }) {
    _animController?.stop();
    _animController?.dispose();
    _animController = null;

    _isActive = true;
    _isEnding = false;
    _committedScale = null;
    _baseZoomScale = snapFolderZoomScale(currentScale);
    _targetZoomScale = _baseZoomScale;
    _progress = 0.0;
    _currentScale = 1.0;
    _isCommitted = false;
    if (min != null) minScale = min;
    if (max != null) maxScale = max;
    notifyListeners();
  }

  /// 捏合移动更新（对齐 Poweramp 物理缩放模型）：
  /// - 缩小：两根手指完全捏在一起（间距趋向 0，scale = 0）时，一档正好缩放完成（progress = 1.0）；
  /// - 放大：双指距离移动到原本两倍（scale = 2.0）时，放大一档的动画正好完成（progress = 1.0）。
  void updatePinch({
    required double scale,
    VoidCallback? onThresholdCrossed,
  }) {
    if (!_isActive || _isEnding) return;
    if (scale <= 0 || scale.isNaN) return;
    _currentScale = scale;

    final double candidateTarget;
    final double rawProgress;
    if (scale >= 1.0) {
      // 放大方向：目标是下一档
      // 双指距离移动到原本两倍（scale = 2.0）时正好达到 1.0
      candidateTarget = stepFolderZoomScale(_baseZoomScale, 1).clamp(
        minScale,
        maxScale,
      );
      rawProgress = scale - 1.0;
    } else {
      // 缩小方向：目标是上一档
      // 两根手指完全捏在一起（scale -> 0）时正好达到 1.0
      candidateTarget = stepFolderZoomScale(_baseZoomScale, -1).clamp(
        minScale,
        maxScale,
      );
      rawProgress = 1.0 - scale;
    }

    final bool hasTarget = (candidateTarget - _baseZoomScale).abs() > 1e-4;
    // 有目标档位时跟手线性推进；已经在最值档位时施加橡皮筋阻尼。
    final double nextProgress = hasTarget
        ? rawProgress.clamp(0.0, 1.0)
        : (rawProgress * 0.15).clamp(0.0, 0.2);

    // 目标与进度都没变 => 这一帧没有任何视觉变化，不 notify。
    //
    // 触控板的双指平移、以及同一比例被两路指针源重复上报，都会走到这里；
    // 白 notify 一次就是整屏可见条目重建一遍，代价远大于这里的两次比较。
    if ((nextProgress - _progress).abs() < 1e-6 &&
        (candidateTarget - _targetZoomScale).abs() < 1e-6) {
      return;
    }

    _targetZoomScale = candidateTarget;
    _progress = nextProgress;

    if (!hasTarget) {
      if (_isCommitted) {
        _isCommitted = false;
        onThresholdCrossed?.call();
      }
    } else {
      if (!_isCommitted) {
        if (_progress >= kCommitThreshold - 1e-4) {
          _isCommitted = true;
          onThresholdCrossed?.call();
        }
      } else {
        if (_progress < kCancelThreshold - 1e-4) {
          _isCommitted = false;
          onThresholdCrossed?.call();
        }
      }
    }

    notifyListeners();
  }

  /// 捏合手势结束：松手结算。
  ///
  /// 若未超过阈值，平滑动画弹回 `0.0`，保留原档位；
  /// 若超过阈值，平滑动画吸附至 `1.0`，完成后调用 [onCommit] 持久化新档位。
  void endPinch({required void Function(double newScale) onCommit}) {
    if (!_isActive || _isEnding) return;

    // 从头到尾没有跟手位移，也没有确认换档（触控板轻扫、双指平移、误触）：
    // 不必跑 200ms 的吸附动画，直接收尾。
    //
    // 否则每一次双指滚动都会多挂 200ms 的捏合态，期间整个可见列表仍在重建。
    if (!_isCommitted && _progress.abs() < 1e-3) {
      _isActive = false;
      _progress = 0.0;
      notifyListeners();
      return;
    }

    _isEnding = true;

    final startProgress = _progress;
    final bool shouldCommit = _isCommitted;
    final double endProgress = shouldCommit ? 1.0 : 0.0;
    final targetScale = _targetZoomScale;

    _animController?.dispose();
    final controller = AnimationController(
      vsync: _vsync,
      duration: const Duration(milliseconds: 200),
    );
    _animController = controller;

    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );

    controller.addListener(() {
      _progress =
          lerpDouble(startProgress, endProgress, animation.value) ??
          endProgress;
      notifyListeners();
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (shouldCommit) {
          _committedScale = targetScale;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _committedScale = null;
            });
          });
        }
        _isActive = false;
        _isEnding = false;
        _progress = 0.0;
        _animController?.dispose();
        _animController = null;
        if (shouldCommit) {
          onCommit(targetScale);
        }
        notifyListeners();
      }
    });

    controller.forward(from: 0.0);
  }

  /// 取消捏合手势，立即复原。
  void cancelPinch() {
    if (!_isActive) return;
    _animController?.stop();
    _animController?.dispose();
    _animController = null;
    _isActive = false;
    _progress = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _animController?.dispose();
    super.dispose();
  }
}

/// 将 [FolderZoomPinchController] 注入 Widget 树，供 [FolderZoomSliverBuilder] 获取。
class FolderZoomPinchScope extends InheritedNotifier<FolderZoomPinchController> {
  const FolderZoomPinchScope({
    super.key,
    required FolderZoomPinchController super.notifier,
    required super.child,
  });

  static FolderZoomPinchController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FolderZoomPinchScope>()
        ?.notifier;
  }
}
