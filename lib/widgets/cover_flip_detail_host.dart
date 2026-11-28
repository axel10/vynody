import 'package:flutter/material.dart';

import 'cover_flip_route.dart';
import 'playback/playback_cover_flight.dart';

/// 封面槽位：由 [CoverFlipDetailHost] 创建，交给内容区放进页头封面位置。
///
/// 槽位与飞行层共用同一个 [contentKey]，落位时封面元素被整体搬过去，
/// 不会重新解码图片；[hidden] 为 true 表示封面此刻正由飞行层承载，槽位留空。
class CoverFlipSlot {
  const CoverFlipSlot({
    required this.slotKey,
    required this.contentKey,
    required this.hidden,
  });

  /// 槽位占位框的 key，宿主靠它测量目标矩形。
  final GlobalKey slotKey;

  /// 封面本体共用的 GlobalKey。
  final GlobalKey contentKey;

  /// 是否让槽位留空（飞行进行中）。
  final bool hidden;

  /// 把封面本体装进槽位。
  Widget wrap(Widget cover, {required double size}) {
    return SizedBox(
      key: slotKey,
      width: size,
      height: size,
      child: hidden ? null : KeyedSubtree(key: contentKey, child: cover),
    );
  }
}

/// 页头内容构建器：把 [slot] 放进页头封面位置即可。
typedef CoverFlipContentBuilder = Widget Function(
  BuildContext context,
  CoverFlipSlot slot,
);

/// 飞行封面构建器：按边长与阴影强度绘制封面本体。
///
/// 槽位与飞行层是同一份实现，[shadowAlphaScale] 在起飞时为 0、落位时为 1，
/// 这样阴影只在靠近目标位置时浮现，不会在源页面位置凭空多出一圈投影。
typedef CoverFlipCoverBuilder = Widget Function(
  double size,
  double shadowAlphaScale,
);

/// 通用「封面组件复用（FLIP）」详情页宿主。
///
/// 与 [CoverFlipPageRoute] 搭配使用：源页面用 [CoverFlipSource] 标记封面，
/// 推入详情页时由 [CoverFlipRegistry] 捕获快照，详情页再把快照交给本组件。
///
/// 本组件负责：
/// - 首帧后测量页头封面槽位，把封面从源位置原位飞入槽位；
/// - 目标页背景与其余内容按曲线淡入，避免整页平移；
/// - 返回时反向飞回；槽位已滚出屏幕则退化为整页淡出；
/// - 飞行结束把封面元素搬进槽位（同一 GlobalKey），无重绘闪烁。
class CoverFlipDetailHost extends StatefulWidget {
  const CoverFlipDetailHost({
    super.key,
    required this.origin,
    required this.coverBuilder,
    required this.contentBuilder,
    this.targetBorderRadiusResolver,
  });

  /// 源封面快照。
  final CoverFlipOrigin origin;

  /// 飞行封面构建器。
  final CoverFlipCoverBuilder coverBuilder;

  /// 页面内容构建器。
  final CoverFlipContentBuilder contentBuilder;

  /// 目标封面圆角推理；默认 12.0（方形封面）。圆形头像传 `rect.width / 2`。
  final double Function(Rect targetRect)? targetBorderRadiusResolver;

  @override
  State<CoverFlipDetailHost> createState() => _CoverFlipDetailHostState();
}

class _CoverFlipDetailHostState extends State<CoverFlipDetailHost> {
  final GlobalKey _layerKey = GlobalKey(debugLabel: 'cover_flip_detail_layer');
  final GlobalKey _slotKey = GlobalKey(debugLabel: 'cover_flip_detail_slot');
  final GlobalKey _contentKey =
      GlobalKey(debugLabel: 'cover_flip_detail_content');

  Rect? _targetRect;
  Offset _overlayOrigin = Offset.zero;
  bool _isFlipActive = true;
  bool _useFallbackFadePop = false;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureAndStartFlight();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null && modalRoute.animation != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
      _routeAnimation = modalRoute.animation;
      _routeAnimation?.addStatusListener(_onRouteAnimationStatus);
    }
  }

  @override
  void dispose() {
    widget.origin.setSourceHidden(false);
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    super.dispose();
  }

  void _measureAndStartFlight() {
    if (_routeAnimation?.status == AnimationStatus.completed) {
      widget.origin.setSourceHidden(false);
      if (_isFlipActive) {
        setState(() => _isFlipActive = false);
      }
      return;
    }
    final measured = _measureTarget();
    if (measured == null) {
      widget.origin.setSourceHidden(false);
      if (_isFlipActive) {
        setState(() => _isFlipActive = false);
      }
      return;
    }
    widget.origin.setSourceHidden(true);
    setState(() {
      _targetRect = measured.rect;
      _overlayOrigin = measured.overlayOrigin;
    });
  }

  ({Rect rect, Offset overlayOrigin})? _measureTarget() {
    final ctx = _slotKey.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final size = renderObject.size;
    if (size.width <= 1.0 || size.height <= 1.0) return null;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottomRight = renderObject.localToGlobal(
      Offset(size.width, size.height),
    );
    if (!topLeft.dx.isFinite ||
        !topLeft.dy.isFinite ||
        !bottomRight.dx.isFinite ||
        !bottomRight.dy.isFinite) {
      return null;
    }

    Offset overlayOrigin = Offset.zero;
    final layerCtx = _layerKey.currentContext;
    if (layerCtx != null && layerCtx.mounted) {
      final layerBox = layerCtx.findRenderObject();
      if (layerBox is RenderBox && layerBox.attached && layerBox.hasSize) {
        final originPoint = layerBox.localToGlobal(Offset.zero);
        if (originPoint.dx.isFinite && originPoint.dy.isFinite) {
          overlayOrigin = originPoint;
        }
      }
    }

    return (
      rect: Rect.fromPoints(topLeft, bottomRight),
      overlayOrigin: overlayOrigin,
    );
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (!mounted) return;
    switch (status) {
      case AnimationStatus.reverse:
        final mediaSize = MediaQuery.sizeOf(context);
        final bool sameWindow = mediaSize == widget.origin.windowSize;
        final measured = sameWindow ? _measureTarget() : null;
        final bool isVisible = measured != null &&
            measured.rect.bottom > 0.0 &&
            measured.rect.top < mediaSize.height;
        if (isVisible) {
          widget.origin.setSourceHidden(true);
          setState(() {
            _targetRect = measured.rect;
            _overlayOrigin = measured.overlayOrigin;
            _isFlipActive = true;
            _useFallbackFadePop = false;
          });
        } else {
          widget.origin.setSourceHidden(false);
          setState(() {
            _isFlipActive = false;
            _useFallbackFadePop = true;
          });
        }
      case AnimationStatus.completed:
        if (_isFlipActive) {
          setState(() {
            _isFlipActive = false;
            _useFallbackFadePop = false;
          });
        }
      case AnimationStatus.dismissed:
        widget.origin.setSourceHidden(false);
      case AnimationStatus.forward:
        break;
    }
  }

  Widget _buildFlyingCover(double size, double shadowAlphaScale) {
    return KeyedSubtree(
      key: _contentKey,
      child: widget.coverBuilder(size, shadowAlphaScale),
    );
  }

  Widget _buildFlightLayer(Animation<double> routeAnim) {
    final Rect localStart = widget.origin.rect.shift(-_overlayOrigin);
    final Rect? targetRect = _targetRect;
    final double curved = Curves.fastOutSlowIn.transform(routeAnim.value);

    if (targetRect == null) {
      return Stack(
        children: [
          Positioned(
            left: localStart.left,
            top: localStart.top,
            width: localStart.width,
            height: localStart.height,
            child: _buildFlyingCover(localStart.width, 0.0),
          ),
        ],
      );
    }

    final Rect localEnd = targetRect.shift(-_overlayOrigin);
    final double targetRadius =
        widget.targetBorderRadiusResolver?.call(targetRect) ?? 12.0;
    final flight = CoverFlipMath.computeTransform(
      startRect: localStart,
      startBorderRadius: widget.origin.borderRadius,
      endRect: localEnd,
      endBorderRadius: targetRadius,
      progress: curved,
    );
    final double shadowAlphaScale = ((curved - 0.15) / 0.85).clamp(0.0, 1.0);

    return Stack(
      children: [
        Positioned(
          left: localEnd.left,
          top: localEnd.top,
          width: localEnd.width,
          height: localEnd.height,
          child: Transform(
            alignment: Alignment.topLeft,
            transform: flight.transform,
            child: _buildFlyingCover(localEnd.width, shadowAlphaScale),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeAnim = _routeAnimation;
    final bool isAnimatingFlip = routeAnim != null && _isFlipActive;
    final bool isAnimatingFallback = routeAnim != null && _useFallbackFadePop;
    final bool isTransitioning = isAnimatingFlip || isAnimatingFallback;

    final Widget content = widget.contentBuilder(
      context,
      CoverFlipSlot(
        slotKey: _slotKey,
        contentKey: _contentKey,
        hidden: isAnimatingFlip,
      ),
    );

    if (routeAnim == null) return content;

    final theme = Theme.of(context);
    return Stack(
      key: _layerKey,
      fit: StackFit.expand,
      children: [
        if (isTransitioning)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: routeAnim,
              builder: (context, _) {
                final double p =
                    Curves.fastOutSlowIn.transform(routeAnim.value);
                final double bgAlpha = isAnimatingFallback
                    ? p
                    : PlaybackCoverFlightGeometry.computeBackdropOpacity(p);
                return ColoredBox(
                  color: theme.colorScheme.surface.withValues(alpha: bgAlpha),
                );
              },
            ),
          ),
        AnimatedBuilder(
          animation: routeAnim,
          child: RepaintBoundary(child: content),
          builder: (context, child) {
            if (!isTransitioning) return child!;
            final double p = Curves.fastOutSlowIn.transform(routeAnim.value);
            if (isAnimatingFallback) {
              return Opacity(opacity: p, child: child);
            }
            final double chromeOpacity =
                PlaybackCoverFlightGeometry.computeChromeOpacity(p);
            if (chromeOpacity >= 0.9999) return child!;
            return Opacity(opacity: chromeOpacity, child: child);
          },
        ),
        if (isAnimatingFlip)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: routeAnim,
                builder: (context, _) => _buildFlightLayer(routeAnim),
              ),
            ),
          ),
      ],
    );
  }
}
