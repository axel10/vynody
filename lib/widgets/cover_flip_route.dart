import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'playback/playback_cover_flight.dart';

/// 封面 FLIP 转场的起点快照。
///
/// 由列表/网格等源页面在推入详情页前捕获，记录源封面在全局窗口坐标系下的矩形、
/// 视觉圆角、窗口尺寸、源纹理分桶尺寸，以及控制源封面显隐的回调。
class CoverFlipOrigin {
  const CoverFlipOrigin({
    required this.tag,
    required this.rect,
    required this.borderRadius,
    required this.windowSize,
    this.sourceBucketSize,
    this.onSetSourceHidden,
  });

  /// 关联同一封面的唯一标识（如 `'album:${album.id}'`）。
  final Object tag;

  /// 源封面在全局窗口坐标系下的视觉矩形。
  final Rect rect;

  /// 源封面的视觉圆角半径（dp）。
  final double borderRadius;

  /// 捕获快照时的窗口逻辑尺寸，用于检测转场或停留期间的窗口缩放/旋转。
  final Size windowSize;

  /// 源封面所使用的缩略图解码分桶尺寸（dp），供目标页首帧直接命中同桶缓存。
  final double? sourceBucketSize;

  /// 飞行期间通知源封面隐藏/恢复的回调。
  final ValueChanged<bool>? onSetSourceHidden;

  /// 控制源封面在飞行期间的显隐状态。
  void setSourceHidden(bool hidden) {
    onSetSourceHidden?.call(hidden);
  }
}

class _CoverFlipSourceEntry {
  _CoverFlipSourceEntry({
    required this.tag,
    required this.contextGetter,
    required this.borderRadiusGetter,
    required this.sourceBucketSizeGetter,
    required this.enabledGetter,
    required this.setHidden,
    required this.lastInteractionSeqGetter,
  });

  Object tag;
  final BuildContext? Function() contextGetter;
  final double Function() borderRadiusGetter;
  final double? Function() sourceBucketSizeGetter;
  final bool Function() enabledGetter;
  final ValueChanged<bool> setHidden;
  final int Function() lastInteractionSeqGetter;
}

/// 维护活跃页面中已挂载封面源锚点的轻量级注册表。
class CoverFlipRegistry {
  CoverFlipRegistry._();

  static final Map<Object, List<_CoverFlipSourceEntry>> _entriesByTag =
      <Object, List<_CoverFlipSourceEntry>>{};

  static int _interactionCounter = 0;

  static int nextInteractionSeq() => ++_interactionCounter;

  static void _register(_CoverFlipSourceEntry entry) {
    final list = _entriesByTag.putIfAbsent(
      entry.tag,
      () => <_CoverFlipSourceEntry>[],
    );
    list.add(entry);
  }

  static void _unregister(_CoverFlipSourceEntry entry) {
    final list = _entriesByTag[entry.tag];
    if (list == null) return;
    list.remove(entry);
    if (list.isEmpty) {
      _entriesByTag.remove(entry.tag);
    }
  }

  static void _updateTag(_CoverFlipSourceEntry entry, Object newTag) {
    if (entry.tag == newTag) return;
    _unregister(entry);
    entry.tag = newTag;
    _register(entry);
  }

  /// 为指定 [tag] 捕获当前处于激活路由且屏幕可见的最佳源封面快照。
  static CoverFlipOrigin? captureOrigin(
    BuildContext callerContext, {
    required Object tag,
  }) {
    final entries = _entriesByTag[tag];
    if (entries == null || entries.isEmpty) return null;

    final ModalRoute<dynamic>? callerRoute = callerContext.mounted
        ? ModalRoute.of(callerContext)
        : null;

    _CoverFlipSourceEntry? bestEntry;
    Rect? bestRect;
    Size? bestWindowSize;
    int bestSeq = -1;

    for (int i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (!entry.enabledGetter()) continue;

      final ctx = entry.contextGetter();
      if (ctx == null || !ctx.mounted) continue;

      final entryRoute = ModalRoute.of(ctx);
      if (callerRoute != null &&
          entryRoute != null &&
          !identical(callerRoute, entryRoute)) {
        continue;
      }
      if (entryRoute != null && !entryRoute.isCurrent) {
        continue;
      }

      final renderObject = ctx.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        continue;
      }

      final localSize = renderObject.size;
      if (localSize.width <= 1.0 || localSize.height <= 1.0) continue;
      if (hasOffstageAncestor(renderObject)) continue;

      final windowSize = MediaQuery.maybeSizeOf(ctx);
      if (windowSize == null ||
          windowSize.width <= 0.0 ||
          windowSize.height <= 0.0) {
        continue;
      }

      final topLeft = renderObject.localToGlobal(Offset.zero);
      final bottomRight = renderObject.localToGlobal(
        Offset(localSize.width, localSize.height),
      );
      if (!topLeft.dx.isFinite ||
          !topLeft.dy.isFinite ||
          !bottomRight.dx.isFinite ||
          !bottomRight.dy.isFinite) {
        continue;
      }

      final rect = Rect.fromPoints(topLeft, bottomRight);
      if (rect.width <= 1.0 || rect.height <= 1.0) continue;
      if (rect.bottom <= 0.0 ||
          rect.top >= windowSize.height ||
          rect.right <= 0.0 ||
          rect.left >= windowSize.width) {
        continue;
      }

      final seq = entry.lastInteractionSeqGetter();
      if (bestEntry == null || seq > bestSeq) {
        bestEntry = entry;
        bestRect = rect;
        bestWindowSize = windowSize;
        bestSeq = seq;
      }
    }

    if (bestEntry == null || bestRect == null || bestWindowSize == null) {
      return null;
    }

    final matchedEntry = bestEntry;
    return CoverFlipOrigin(
      tag: tag,
      rect: bestRect,
      borderRadius: matchedEntry.borderRadiusGetter(),
      windowSize: bestWindowSize,
      sourceBucketSize: matchedEntry.sourceBucketSizeGetter(),
      onSetSourceHidden: matchedEntry.setHidden,
    );
  }

  /// 检测渲染节点是否位于隐藏的 `Offstage` 或非激活 `IndexedStack` 分支内。
  static bool hasOffstageAncestor(RenderObject renderObject) {
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
}

/// 标记列表/网格中的封面作为 FLIP 转场起点，并在飞行期间无缝隐藏自身。
class CoverFlipSource extends StatefulWidget {
  const CoverFlipSource({
    super.key,
    required this.tag,
    required this.child,
    this.borderRadius = 12.0,
    this.borderRadiusGetter,
    this.sourceBucketSize,
    this.enabled = true,
  });

  final Object tag;
  final Widget child;
  final double borderRadius;
  final double Function()? borderRadiusGetter;
  final double? sourceBucketSize;
  final bool enabled;

  @override
  State<CoverFlipSource> createState() => _CoverFlipSourceState();
}

class _CoverFlipSourceState extends State<CoverFlipSource> {
  final ValueNotifier<bool> _isHiddenNotifier = ValueNotifier<bool>(false);
  int _lastInteractionSeq = 0;
  late final _CoverFlipSourceEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = _CoverFlipSourceEntry(
      tag: widget.tag,
      contextGetter: () => mounted ? context : null,
      borderRadiusGetter: () =>
          widget.borderRadiusGetter?.call() ?? widget.borderRadius,
      sourceBucketSizeGetter: () => widget.sourceBucketSize,
      enabledGetter: () => widget.enabled,
      setHidden: _setHidden,
      lastInteractionSeqGetter: () => _lastInteractionSeq,
    );
    CoverFlipRegistry._register(_entry);
  }

  @override
  void didUpdateWidget(CoverFlipSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag != widget.tag) {
      CoverFlipRegistry._updateTag(_entry, widget.tag);
      if (_isHiddenNotifier.value) {
        _isHiddenNotifier.value = false;
      }
    }
    if (!widget.enabled && _isHiddenNotifier.value) {
      _isHiddenNotifier.value = false;
    }
  }

  void _setHidden(bool hidden) {
    if (!mounted) return;
    if (_isHiddenNotifier.value != hidden) {
      _isHiddenNotifier.value = hidden;
    }
  }

  @override
  void dispose() {
    CoverFlipRegistry._unregister(_entry);
    _isHiddenNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _lastInteractionSeq = CoverFlipRegistry.nextInteractionSeq();
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: _isHiddenNotifier,
        child: widget.child,
        builder: (context, hidden, child) {
          // 包装层必须常驻：隐藏/恢复若切换根 widget 类型（`child` ↔ `Opacity`），
          // Flutter 会按 runtimeType 失配把整棵子树重建 —— `SongThumbnail` 的
          // State 被销毁，封面重走「解析 → 待解析空白 → 淡入」，表现为点进详情、
          // 返回列表时那张封面闪一下（远程封面 / 会话内刚生成尚未落库的缩略图
          // 尤其明显，它们的图片来源只存在 State 里）。恒定 `Opacity` 后 hide/show
          // 只改 alpha；alpha=255 时 `RenderOpacity` 直接绘制子节点，不建图层。
          return Opacity(
            opacity: hidden ? 0.0 : 1.0,
            child: child,
          );
        },
      ),
    );
  }
}

/// 配合详情页内部 FLIP 动画使用的页面路由。
///
/// 不对整页施加平移或整体淡入，使目标封面能够从第一帧起由 [CoverFlipOrigin]
/// 的位置直接飞入目标槽位；当路由被销毁时确保恢复源封面的可见性。
class CoverFlipPageRoute<T> extends PageRouteBuilder<T> {
  CoverFlipPageRoute({
    super.settings,
    required this.origin,
    required WidgetBuilder builder,
    super.transitionDuration = const Duration(milliseconds: 360),
    super.reverseTransitionDuration = const Duration(milliseconds: 300),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        );

  final CoverFlipOrigin origin;

  @override
  void dispose() {
    origin.setSourceHidden(false);
    super.dispose();
  }
}

/// FLIP 封面飞行的几何计算辅助方法（委托给 [PlaybackCoverFlightGeometry]）。
class CoverFlipMath {
  CoverFlipMath._();

  static ({
    Matrix4 transform,
    double localBorderRadius,
    double scale,
    Rect currentRect,
  }) computeTransform({
    required Rect startRect,
    required double startBorderRadius,
    required Rect endRect,
    required double endBorderRadius,
    required double progress,
  }) {
    return PlaybackCoverFlightGeometry.computeCoverFlightTransform(
      startRect: startRect,
      startBorderRadius: startBorderRadius,
      endRect: endRect,
      endBorderRadius: endBorderRadius,
      progress: progress,
    );
  }
}
