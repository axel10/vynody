import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 迷你播放器封面的屏幕坐标与圆角快照。
@immutable
class PlaybackCoverOriginSnapshot {
  const PlaybackCoverOriginSnapshot({
    required this.rect,
    required this.borderRadius,
    required this.windowSize,
    required this.capturedAtMicros,
  });

  /// 迷你封面在全局窗口坐标系下的矩形区域。
  final Rect rect;

  /// 迷你封面的视觉圆角半径（dp）。
  final double borderRadius;

  /// 捕获快照时的窗口逻辑尺寸，用于检测转场期间的窗口缩放或旋转。
  final Size windowSize;

  /// 捕获时间戳（微秒），避免点击回调与抽屉打开回调在同一次交互中重复覆盖快照。
  final int capturedAtMicros;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackCoverOriginSnapshot &&
        other.rect == rect &&
        other.borderRadius == borderRadius &&
        other.windowSize == windowSize;
  }

  @override
  int get hashCode => Object.hash(rect, borderRadius, windowSize);
}

/// 封面原位反向变换（FLIP）与播放页分层过渡的纯几何计算工具。
class PlaybackCoverFlightGeometry {
  PlaybackCoverFlightGeometry._();

  /// 计算进度 [progress]（0 = 迷你播放器位置，1 = 播放页最终槽位）时，
  /// 施加在最终槽位（[endRect]，原点对齐左上角）上的 `Matrix4` 与反向补偿圆角。
  /// [sheetOffsetY] 为外层播放页抽屉当前的纵向滑入偏移（`(1 - progress) * screenHeight`），
  /// 用于抵消整页上滑位移，使封面严格沿屏幕全局 `Rect.lerp(startRect, endRect, progress)` 飞行。
  static ({
    Matrix4 transform,
    double localBorderRadius,
    double scale,
    Rect currentRect,
  }) computeCoverFlightTransform({
    required Rect startRect,
    required double startBorderRadius,
    required Rect endRect,
    required double endBorderRadius,
    required double progress,
    double sheetOffsetY = 0.0,
  }) {
    final double p = progress.clamp(0.0, 1.0);
    if (p >= 1.0 || endRect.width <= 0.0 || endRect.height <= 0.0) {
      return (
        transform: Matrix4.identity(),
        localBorderRadius: endBorderRadius,
        scale: 1.0,
        currentRect: endRect,
      );
    }

    final Rect currentRect = Rect.lerp(startRect, endRect, p) ?? endRect;
    final double scaleX = currentRect.width / endRect.width;
    final double scaleY = currentRect.height / endRect.height;
    final double avgScale = (scaleX + scaleY) * 0.5;
    final double dx = currentRect.left - endRect.left;
    final double dy = currentRect.top - (endRect.top + sheetOffsetY);

    final double visualRadius =
        lerpDouble(startBorderRadius, endBorderRadius, p) ?? endBorderRadius;
    final double localBorderRadius =
        avgScale > 0.0001 ? (visualRadius / avgScale) : endBorderRadius;

    final Matrix4 transform = Matrix4.identity()
      ..translateByDouble(dx, dy, 0.0, 1.0)
      ..scaleByDouble(scaleX, scaleY, 1.0, 1.0);

    return (
      transform: transform,
      localBorderRadius: localBorderRadius,
      scale: avgScale,
      currentRect: currentRect,
    );
  }

  /// 针对非 1:1 比例封面，平滑过渡 `MiniArtwork` 的 `BoxFit.cover` 与
  /// `CoverCarousel` 的 `BoxFit.contain`（标准 1:1 封面恒返回 1.0）。
  static double computeBoxFitCoverToContainScale({
    int? artworkWidth,
    int? artworkHeight,
    required double progress,
  }) {
    if (artworkWidth == null ||
        artworkHeight == null ||
        artworkWidth <= 0 ||
        artworkHeight <= 0) {
      return 1.0;
    }
    final double p = progress.clamp(0.0, 1.0);
    if (p >= 1.0) return 1.0;
    final double aspect = artworkWidth / artworkHeight;
    if ((aspect - 1.0).abs() < 0.01) return 1.0;
    final double coverScale = math.max(aspect, 1.0 / aspect);
    return lerpDouble(coverScale, 1.0, p) ?? 1.0;
  }

  /// 播放页全屏背景层的不透明度曲线。
  static double computeBackdropOpacity(double progress) {
    final double p = progress.clamp(0.0, 1.0);
    if (p <= 0.0) return 0.0;
    if (p >= 1.0) return 1.0;
    return Curves.easeOutCubic.transform(p);
  }

  /// 播放页非封面控件（标题、控制栏、歌词面板、顶部收起按钮、底部导航）的不透明度。
  static double computeChromeOpacity(double progress) {
    final double p = progress.clamp(0.0, 1.0);
    if (p >= 1.0) return 1.0;
    return ((p - 0.18) / 0.82).clamp(0.0, 1.0);
  }

  /// 播放页非封面控件在展开/收起过程中的微幅纵向跟随位移（dp）。
  static double computeChromeSlideDy(
    double progress, {
    double maxSlide = 36.0,
  }) {
    final double p = progress.clamp(0.0, 1.0);
    if (p >= 1.0) return 0.0;
    return (1.0 - p) * maxSlide;
  }
}

class _MiniArtworkAnchorEntry {
  _MiniArtworkAnchorEntry({
    required this.contextGetter,
    required this.borderRadiusGetter,
  });

  final BuildContext? Function() contextGetter;
  final double Function() borderRadiusGetter;
}

/// 协调迷你播放器封面锚点快照、展开进度广播与下拉跟手交互的控制器。
class PlaybackCoverFlightController {
  final List<_MiniArtworkAnchorEntry> _anchors = <_MiniArtworkAnchorEntry>[];

  /// 播放页展开进度（0.0 = 完全收起，1.0 = 完全展开）。
  /// 默认置为 1.0，使脱离 `MainLayout` 独立挂载的 `PlaybackPage` / `PlaybackHeroCard`
  /// （如独立测试或截图预览）默认处于完整展开态；`MainLayout.initState` 会在首帧前同步覆写实际进度。
  final ValueNotifier<double> progressNotifier = ValueNotifier<double>(1.0);

  /// 当前转场绑定的迷你封面起点/落点快照（无可见迷你封面时为 null）。
  final ValueNotifier<PlaybackCoverOriginSnapshot?> originNotifier =
      ValueNotifier<PlaybackCoverOriginSnapshot?>(null);

  /// 是否隐藏底层迷你播放器中的源封面（仅在起止边界翻转，避免每帧触发迷你栏重建）。
  final ValueNotifier<bool> hideSourceArtworkNotifier =
      ValueNotifier<bool>(false);

  /// 播放页是否已完全展开且由 `MainLayout` 托管（用于让被完全遮挡的底层毛玻璃 Dock
  /// 在自身 `AnimatedPositioned` 内部暂停合成绘制，同时保留布局尺寸与 `StackParentData`）。
  final ValueNotifier<bool> isFullyOpenNotifier = ValueNotifier<bool>(false);

  /// 底层迷你播放器是否因播放页抽屉激活而需要屏蔽指针事件。
  final ValueNotifier<bool> isUnderlyingMiniBlockedNotifier =
      ValueNotifier<bool>(false);

  bool _isAttachedToMainLayout = false;
  bool _isSmallWindow = false;
  double _screenHeight = 0.0;

  /// 外层播放页抽屉在当前进度下的自底向上滑入纵向偏移（dp）。
  double get currentSheetOffsetY {
    if (_isSmallWindow || _screenHeight <= 0.0) return 0.0;
    final double p = progressNotifier.value.clamp(0.0, 1.0);
    if (p >= 0.9999) return 0.0;
    return ((1.0 - p) * _screenHeight).clamp(0.0, _screenHeight);
  }

  /// 由 `MainLayout` 挂载的手势驱动回调。
  VoidCallback? _onInteractiveDragStart;
  void Function(double deltaDy, double screenHeight)? _onInteractiveDragUpdate;
  void Function(double velocityY)? _onInteractiveDragEnd;
  VoidCallback? _onInteractiveDragCancel;

  bool _refreshScheduled = false;

  VoidCallback registerMiniArtworkAnchor({
    required BuildContext? Function() contextGetter,
    required double Function() borderRadiusGetter,
  }) {
    final entry = _MiniArtworkAnchorEntry(
      contextGetter: contextGetter,
      borderRadiusGetter: borderRadiusGetter,
    );
    _anchors.add(entry);
    return () {
      _anchors.remove(entry);
    };
  }

  void bindInteractiveDragCallbacks({
    required VoidCallback onDragStart,
    required void Function(double deltaDy, double screenHeight) onDragUpdate,
    required void Function(double velocityY) onDragEnd,
    required VoidCallback onDragCancel,
  }) {
    _isAttachedToMainLayout = true;
    _onInteractiveDragStart = onDragStart;
    _onInteractiveDragUpdate = onDragUpdate;
    _onInteractiveDragEnd = onDragEnd;
    _onInteractiveDragCancel = onDragCancel;
  }

  void unbindInteractiveDragCallbacks() {
    _isAttachedToMainLayout = false;
    _onInteractiveDragStart = null;
    _onInteractiveDragUpdate = null;
    _onInteractiveDragEnd = null;
    _onInteractiveDragCancel = null;
  }

  void startInteractiveDrag() => _onInteractiveDragStart?.call();

  void updateInteractiveDrag(double deltaDy, double screenHeight) =>
      _onInteractiveDragUpdate?.call(deltaDy, screenHeight);

  void endInteractiveDrag(double velocityY) =>
      _onInteractiveDragEnd?.call(velocityY);

  void cancelInteractiveDrag() => _onInteractiveDragCancel?.call();

  /// 更新播放页展开进度（由 `MainLayout` 的动画控制器监听统一驱动）。
  void updateProgress(
    double progress, {
    required bool isSmallWindow,
    double? screenHeight,
    bool isDrawerOpen = false,
  }) {
    _isSmallWindow = isSmallWindow;
    if (screenHeight != null && screenHeight > 0.0) {
      _screenHeight = screenHeight;
    }
    final double effective = isSmallWindow ? 1.0 : progress.clamp(0.0, 1.0);
    if ((progressNotifier.value - effective).abs() > 0.00001) {
      progressNotifier.value = effective;
    }
    final bool fullyOpen =
        _isAttachedToMainLayout && !isSmallWindow && effective >= 0.9999;
    if (isFullyOpenNotifier.value != fullyOpen) {
      isFullyOpenNotifier.value = fullyOpen;
    }
    final bool blocked =
        _isAttachedToMainLayout && (isSmallWindow || effective > 0.0001);
    if (isUnderlyingMiniBlockedNotifier.value != blocked) {
      isUnderlyingMiniBlockedNotifier.value = blocked;
    }
    if (effective <= 0.0001 && !isSmallWindow && !isDrawerOpen) {
      if (originNotifier.value != null) {
        originNotifier.value = null;
      }
    }
    _syncHideSourceState();
  }

  void _syncHideSourceState() {
    final bool shouldHide =
        progressNotifier.value > 0.0001 && originNotifier.value != null;
    if (hideSourceArtworkNotifier.value != shouldHide) {
      hideSourceArtworkNotifier.value = shouldHide;
    }
  }

  /// 在点击迷你播放器区域时优先从所属子树捕获起点快照。
  void captureOriginFromContext(BuildContext? tapSourceContext) {
    final snapshot = _measureBestAnchor(preferredAncestor: tapSourceContext);
    originNotifier.value = snapshot;
    _syncHideSourceState();
  }

  /// 在打开播放页前捕获起点快照；若刚刚（150ms 内）已由点击事件捕获过，则直接复用。
  void captureOriginIfNeeded() {
    final existing = originNotifier.value;
    final now = DateTime.now().microsecondsSinceEpoch;
    if (existing != null && (now - existing.capturedAtMicros) < 150 * 1000) {
      return;
    }
    originNotifier.value = _measureBestAnchor();
    _syncHideSourceState();
  }

  /// 在开始收起或下拉手势前，从底层保持布局的活跃锚点刷新最新落点矩形（兼容播放页内旋转屏幕或缩放窗口）。
  void refreshOriginFromLiveAnchor() {
    originNotifier.value = _measureBestAnchor();
    _syncHideSourceState();
  }

  /// 若飞行中途发生窗口尺寸变化（如桌面端拖拽窗口或横竖屏翻转），在帧末平滑同步最新锚点坐标。
  void scheduleRefreshForWindowSizeChange(Size currentWindowSize) {
    final existing = originNotifier.value;
    if (existing == null || existing.windowSize == currentWindowSize) return;
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (progressNotifier.value <= 0.0001) return;
      originNotifier.value = _measureBestAnchor();
      _syncHideSourceState();
    });
  }

  void clearOrigin() {
    if (originNotifier.value != null) {
      originNotifier.value = null;
      _syncHideSourceState();
    }
  }

  PlaybackCoverOriginSnapshot? _measureBestAnchor({
    BuildContext? preferredAncestor,
  }) {
    if (_anchors.isEmpty) return null;

    RenderObject? preferredRootRenderObject;
    if (preferredAncestor != null && preferredAncestor.mounted) {
      preferredRootRenderObject = preferredAncestor.findRenderObject();
    }

    PlaybackCoverOriginSnapshot? fallbackCandidate;

    // 逆序遍历：后挂载的顶层页面（如二级页 MiniPlayerWrapper）优先于底层宿主。
    for (int i = _anchors.length - 1; i >= 0; i--) {
      final entry = _anchors[i];
      final ctx = entry.contextGetter();
      if (ctx == null || !ctx.mounted) continue;

      final modalRoute = ModalRoute.of(ctx);
      if (modalRoute != null && !modalRoute.isCurrent) {
        continue;
      }

      final renderObject = ctx.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        continue;
      }

      final size = renderObject.size;
      if (size.width <= 1.0 || size.height <= 1.0) continue;

      // 过滤掉处于 IndexedStack 非激活页或 Offstage 隐藏子树中的锚点。
      if (_hasOffstageAncestor(renderObject)) continue;

      final windowSize = MediaQuery.maybeSizeOf(ctx);
      if (windowSize == null ||
          windowSize.width <= 0.0 ||
          windowSize.height <= 0.0) {
        continue;
      }

      final topLeft = renderObject.localToGlobal(Offset.zero);
      if (!topLeft.dx.isFinite || !topLeft.dy.isFinite) continue;

      final rect = topLeft & size;
      // 过滤掉因多选模式、键盘弹出等原因移出屏幕边界的迷你播放器。
      if (rect.bottom <= 0.0 ||
          rect.top >= windowSize.height ||
          rect.right <= 0.0 ||
          rect.left >= windowSize.width) {
        continue;
      }

      final snapshot = PlaybackCoverOriginSnapshot(
        rect: rect,
        borderRadius: entry.borderRadiusGetter(),
        windowSize: windowSize,
        capturedAtMicros: DateTime.now().microsecondsSinceEpoch,
      );

      if (preferredRootRenderObject != null &&
          _isDescendantOf(renderObject, preferredRootRenderObject)) {
        return snapshot;
      }

      fallbackCandidate ??= snapshot;
    }

    return fallbackCandidate;
  }

  static bool _hasOffstageAncestor(RenderObject renderObject) {
    RenderObject child = renderObject;
    RenderObject? parent = child.parent;
    while (parent != null) {
      if (parent is RenderOffstage && parent.offstage) {
        return true;
      }
      if (parent is RenderIndexedStack) {
        final int? activeIndex = parent.index;
        if (activeIndex == null) return true;
        RenderBox? current = parent.firstChild;
        int idx = 0;
        bool isActiveChild = false;
        while (current != null) {
          if (identical(current, child)) {
            isActiveChild = (idx == activeIndex);
            break;
          }
          final parentData = current.parentData;
          current = parentData is ContainerBoxParentData<RenderBox>
              ? parentData.nextSibling
              : null;
          idx++;
        }
        if (!isActiveChild) return true;
      }
      child = parent;
      parent = child.parent;
    }
    return false;
  }

  static bool _isDescendantOf(RenderObject child, RenderObject ancestor) {
    RenderObject? node = child;
    while (node != null) {
      if (identical(node, ancestor)) return true;
      node = node.parent;
    }
    return false;
  }

  void dispose() {
    _anchors.clear();
    unbindInteractiveDragCallbacks();
    progressNotifier.dispose();
    originNotifier.dispose();
    hideSourceArtworkNotifier.dispose();
    isFullyOpenNotifier.dispose();
    isUnderlyingMiniBlockedNotifier.dispose();
  }
}

final playbackCoverFlightControllerProvider =
    Provider<PlaybackCoverFlightController>((ref) {
  final controller = PlaybackCoverFlightController();
  ref.onDispose(controller.dispose);
  return controller;
});
