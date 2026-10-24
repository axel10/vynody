import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../utils/layout_constants.dart';

export '../utils/layout_constants.dart';

/// Minimum and maximum values for `folderZoomScale`.
const double kFolderZoomMin = 0.0;
const double kFolderZoomCompactListThreshold = 0.25;
const double kFolderZoomGridThreshold = 0.50;
const double kFolderZoomLargeGridThreshold = 0.75;
const double kFolderZoomMax = 1.0;

/// Discrete layout & typography tiers derived from `folderZoomScale`.
enum FolderZoomTier {
  /// `< 0.25`: Single-column list with smaller cover; song info moves to the right.
  compactList,

  /// `0.25 .. < 0.50`: Single-column list with larger cover; song info stays below subtitle.
  standardList,

  /// `0.50 .. < 0.75`: Multi-column grid with smaller covers and small typography.
  smallGrid,

  /// `>= 0.75`: Multi-column grid with larger covers and large typography.
  largeGrid,
}

FolderZoomTier getFolderZoomTier(double zoomScale) {
  if (zoomScale < kFolderZoomCompactListThreshold) {
    return FolderZoomTier.compactList;
  }
  if (zoomScale < kFolderZoomGridThreshold) {
    return FolderZoomTier.standardList;
  }
  if (zoomScale < kFolderZoomLargeGridThreshold) {
    return FolderZoomTier.smallGrid;
  }
  return FolderZoomTier.largeGrid;
}

bool isFolderZoomGrid(double zoomScale) =>
    zoomScale >= kFolderZoomGridThreshold;

bool isFolderZoomCompactList(double zoomScale) =>
    zoomScale < kFolderZoomCompactListThreshold;

bool isFolderZoomLargeGrid(double zoomScale) =>
    zoomScale >= kFolderZoomLargeGridThreshold;

/// Continuous thumbnail size in list view (`zoomScale < 0.5`), ranging from `40px` to `64px`.
double getFolderListCoverSize(double zoomScale) {
  final t = (zoomScale / kFolderZoomGridThreshold).clamp(0.0, 1.0);
  return lerpDouble(40.0, 64.0, t)!;
}

/// Total height of a single row tile in list view (`coverSize + 16px` vertical padding).
double getFolderListTileExtent(double zoomScale) {
  return getFolderListCoverSize(zoomScale) + 16.0;
}

/// Returns the discrete text block height below the cover in grid view.
///
/// Text size changes by tier (`smallGrid` vs `largeGrid`) rather than scaling
/// continuously with `zoomScale`.
double calculateFolderZoomGridTextHeight(
  BuildContext context, {
  required double zoomScale,
}) {
  final isPortrait =
      MediaQuery.of(context).orientation == Orientation.portrait;
  final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
  final clampedScale = textScale.clamp(1.0, 1.3);
  final isLarge = isFolderZoomLargeGrid(zoomScale);
  final double baseHeight = isLarge
      ? (isPortrait ? 60.0 : 64.0)
      : (isPortrait ? 50.0 : 54.0);
  return baseHeight * clampedScale;
}

/// Returns responsive cross axis count based on layout width and `zoomScale` (`>= 0.5`).
int getFolderZoomGridCrossAxisCount(double width, double zoomScale) {
  final gridProgress = ((zoomScale - kFolderZoomGridThreshold) /
          (kFolderZoomMax - kFolderZoomGridThreshold))
      .clamp(0.0, 1.0);

  final (int maxCols, int minCols) = switch (width) {
    >= 1280 => (7, 3),
    >= 960 => (6, 2),
    >= 680 => (5, 2),
    _ => (4, 2),
  };

  final continuous = lerpDouble(maxCols.toDouble(), minCols.toDouble(), gridProgress)!;
  return continuous.round().clamp(minCols, maxCols);
}

/// Returns responsive cross axis count based on layout width for folder and song grids.
int getFolderGridCrossAxisCount(double width, [double zoomScale = 0.65]) {
  return getFolderZoomGridCrossAxisCount(width, zoomScale);
}

/// Calculates grid item aspect ratio considering system font scaling and orientation.
double calculateFolderGridChildAspectRatio(
  BuildContext context,
  double width,
  int crossAxisCount, {
  double? textHeight,
  double zoomScale = 0.65,
}) {
  if (width <= 0) return 1.0;
  final double resolvedTextHeight = textHeight ??
      calculateFolderZoomGridTextHeight(context, zoomScale: zoomScale);
  final itemWidth = calculateGridItemWidth(
    width: width,
    crossAxisCount: crossAxisCount,
  );
  if (itemWidth <= 0 || (itemWidth + resolvedTextHeight) <= 0) return 1.0;
  final ratio = itemWidth / (itemWidth + resolvedTextHeight);
  return ratio > 0 ? ratio : 1.0;
}

/// Snapshot of animated layout metrics passed to unified folder/song slivers and items.
class FolderZoomLayoutMetrics {
  final double targetZoomScale;
  final double animatedZoomScale;

  /// `0.0` = pure 1-column List View, `1.0` = pure N-column Grid View.
  final double gridMorph;

  /// `0.0` = standard 3-line list item (song info below subtitle),
  /// `1.0` = compact 2-line list item (song info on the right side).
  final double compactMorph;

  /// Animated column count in Grid View (e.g. `4.0` -> `3.0`).
  final double animatedGridCols;

  /// Animated text block height below the cover in Grid View.
  final double animatedGridTextHeight;

  /// Animated row height in List View.
  final double animatedListExtent;

  const FolderZoomLayoutMetrics({
    required this.targetZoomScale,
    required this.animatedZoomScale,
    required this.gridMorph,
    required this.compactMorph,
    required this.animatedGridCols,
    required this.animatedGridTextHeight,
    required this.animatedListExtent,
  });

  bool get isGridTarget => isFolderZoomGrid(targetZoomScale);
  bool get isLargeGridTarget => isFolderZoomLargeGrid(targetZoomScale);
  bool get isCompactListTarget => isFolderZoomCompactList(targetZoomScale);
  FolderZoomTier get tier => getFolderZoomTier(targetZoomScale);
}

/// Animates [FolderZoomLayoutMetrics] smoothly whenever `zoomScale` changes,
/// and returns the sliver built by [builder].
class FolderZoomSliverBuilder extends StatefulWidget {
  const FolderZoomSliverBuilder({
    super.key,
    required this.zoomScale,
    required this.width,
    required this.builder,
  });

  final double zoomScale;
  final double width;
  final Widget Function(BuildContext context, FolderZoomLayoutMetrics metrics)
      builder;

  @override
  State<FolderZoomSliverBuilder> createState() =>
      _FolderZoomSliverBuilderState();
}

class _FolderZoomSliverBuilderState extends State<FolderZoomSliverBuilder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late CurvedAnimation _curved;

  late double _fromZoomScale;
  late double _toZoomScale;

  late double _fromGridMorph;
  late double _toGridMorph;

  late double _fromCompactMorph;
  late double _toCompactMorph;

  late double _fromGridCols;
  late double _toGridCols;

  late double _fromGridTextHeight;
  late double _toGridTextHeight;

  late double _fromListExtent;
  late double _toListExtent;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(_onTick);
    _curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  void _onTick() {
    if (mounted) {
      setState(() {});
    }
  }

  double _eval(double from, double to) =>
      lerpDouble(from, to, _curved.value) ?? to;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final targetTextHeight = calculateFolderZoomGridTextHeight(
      context,
      zoomScale: widget.zoomScale,
    );
    final targetCols =
        getFolderZoomGridCrossAxisCount(widget.width, widget.zoomScale)
            .toDouble();
    final targetListExtent = getFolderListTileExtent(widget.zoomScale);
    final targetGridMorph = isFolderZoomGrid(widget.zoomScale) ? 1.0 : 0.0;
    final targetCompactMorph =
        isFolderZoomCompactList(widget.zoomScale) ? 1.0 : 0.0;

    if (!_initialized) {
      _fromZoomScale = _toZoomScale = widget.zoomScale;
      _fromGridMorph = _toGridMorph = targetGridMorph;
      _fromCompactMorph = _toCompactMorph = targetCompactMorph;
      _fromGridCols = _toGridCols = targetCols;
      _fromGridTextHeight = _toGridTextHeight = targetTextHeight;
      _fromListExtent = _toListExtent = targetListExtent;
      _initialized = true;
    }
  }

  @override
  void didUpdateWidget(FolderZoomSliverBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targetTextHeight = calculateFolderZoomGridTextHeight(
      context,
      zoomScale: widget.zoomScale,
    );
    final targetCols =
        getFolderZoomGridCrossAxisCount(widget.width, widget.zoomScale)
            .toDouble();
    final targetListExtent = getFolderListTileExtent(widget.zoomScale);
    final targetGridMorph = isFolderZoomGrid(widget.zoomScale) ? 1.0 : 0.0;
    final targetCompactMorph =
        isFolderZoomCompactList(widget.zoomScale) ? 1.0 : 0.0;

    if ((oldWidget.zoomScale - widget.zoomScale).abs() > 1e-4) {
      _fromZoomScale = _eval(_fromZoomScale, _toZoomScale);
      _fromGridMorph = _eval(_fromGridMorph, _toGridMorph);
      _fromCompactMorph = _eval(_fromCompactMorph, _toCompactMorph);
      _fromGridCols = _eval(_fromGridCols, _toGridCols);
      _fromGridTextHeight = _eval(_fromGridTextHeight, _toGridTextHeight);
      _fromListExtent = _eval(_fromListExtent, _toListExtent);

      _toZoomScale = widget.zoomScale;
      _toGridMorph = targetGridMorph;
      _toCompactMorph = targetCompactMorph;
      _toGridCols = targetCols;
      _toGridTextHeight = targetTextHeight;
      _toListExtent = targetListExtent;

      _controller.forward(from: 0.0);
    } else if ((oldWidget.width - widget.width).abs() > 0.5) {
      // Window resize: update column count immediately without lag.
      _fromGridCols = _toGridCols = targetCols;
      _fromGridTextHeight = _toGridTextHeight = targetTextHeight;
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = FolderZoomLayoutMetrics(
      targetZoomScale: widget.zoomScale,
      animatedZoomScale: _eval(_fromZoomScale, _toZoomScale),
      gridMorph: _eval(_fromGridMorph, _toGridMorph).clamp(0.0, 1.0),
      compactMorph: _eval(_fromCompactMorph, _toCompactMorph).clamp(0.0, 1.0),
      animatedGridCols: _eval(_fromGridCols, _toGridCols),
      animatedGridTextHeight: _eval(_fromGridTextHeight, _toGridTextHeight),
      animatedListExtent: _eval(_fromListExtent, _toListExtent),
    );
    return widget.builder(context, metrics);
  }
}

/// Unified [SliverGridDelegate] that smoothly interpolates item geometry between
/// 1-column List View (`gridMorph = 0.0`) and N-column Grid View (`gridMorph = 1.0`),
/// as well as across column count changes (`animatedGridCols`) and list row height
/// changes (`listTileExtent`).
class SliverAnimatedZoomGridDelegate extends SliverGridDelegate {
  const SliverAnimatedZoomGridDelegate({
    required this.metrics,
    this.listMainAxisSpacing = 8.0,
    this.gridCrossAxisSpacing = kGridCrossAxisSpacing,
    this.gridMainAxisSpacing = kGridMainAxisSpacing,
  });

  final FolderZoomLayoutMetrics metrics;
  final double listMainAxisSpacing;
  final double gridCrossAxisSpacing;
  final double gridMainAxisSpacing;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final usableWidth = math.max(1.0, constraints.crossAxisExtent);
    return _SliverAnimatedZoomGridLayout(
      usableWidth: usableWidth,
      gridMorph: metrics.gridMorph,
      animatedGridCols: metrics.animatedGridCols,
      gridTextHeight: metrics.animatedGridTextHeight,
      listTileExtent: metrics.animatedListExtent,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
  }

  @override
  bool shouldRelayout(SliverAnimatedZoomGridDelegate oldDelegate) {
    return oldDelegate.metrics.gridMorph != metrics.gridMorph ||
        oldDelegate.metrics.animatedGridCols != metrics.animatedGridCols ||
        oldDelegate.metrics.animatedGridTextHeight !=
            metrics.animatedGridTextHeight ||
        oldDelegate.metrics.animatedListExtent != metrics.animatedListExtent ||
        oldDelegate.listMainAxisSpacing != listMainAxisSpacing ||
        oldDelegate.gridCrossAxisSpacing != gridCrossAxisSpacing ||
        oldDelegate.gridMainAxisSpacing != gridMainAxisSpacing;
  }
}

class _SliverAnimatedZoomGridLayout extends SliverGridLayout {
  const _SliverAnimatedZoomGridLayout({
    required this.usableWidth,
    required this.gridMorph,
    required this.animatedGridCols,
    required this.gridTextHeight,
    required this.listTileExtent,
    required this.listMainAxisSpacing,
    required this.gridCrossAxisSpacing,
    required this.gridMainAxisSpacing,
  });

  final double usableWidth;
  final double gridMorph;
  final double animatedGridCols;
  final double gridTextHeight;
  final double listTileExtent;
  final double listMainAxisSpacing;
  final double gridCrossAxisSpacing;
  final double gridMainAxisSpacing;

  int get _cFloor => animatedGridCols.floor().clamp(1, 12);
  int get _cCeil => animatedGridCols.ceil().clamp(1, 12);
  double get _colFrac => (animatedGridCols - _cFloor).clamp(0.0, 1.0);

  SliverGridGeometry _listGeometry(int index) {
    final stride = listTileExtent + listMainAxisSpacing;
    return SliverGridGeometry(
      scrollOffset: index * stride,
      crossAxisOffset: 0.0,
      mainAxisExtent: listTileExtent,
      crossAxisExtent: usableWidth,
    );
  }

  SliverGridGeometry _gridGeometryForCols(int cols, int index) {
    final row = index ~/ cols;
    final col = index % cols;
    final totalSpacing = (cols - 1) * gridCrossAxisSpacing;
    final cardWidth = math.max(1.0, (usableWidth - totalSpacing) / cols);
    final cardHeight = cardWidth + gridTextHeight;
    final mainStride = cardHeight + gridMainAxisSpacing;
    final crossStride = cardWidth + gridCrossAxisSpacing;

    return SliverGridGeometry(
      scrollOffset: row * mainStride,
      crossAxisOffset: col * crossStride,
      mainAxisExtent: cardHeight,
      crossAxisExtent: cardWidth,
    );
  }

  static SliverGridGeometry _lerpGeometry(
    SliverGridGeometry a,
    SliverGridGeometry b,
    double t,
  ) {
    if (t <= 0.0) return a;
    if (t >= 1.0) return b;
    return SliverGridGeometry(
      scrollOffset: lerpDouble(a.scrollOffset, b.scrollOffset, t)!,
      crossAxisOffset: lerpDouble(a.crossAxisOffset, b.crossAxisOffset, t)!,
      mainAxisExtent: lerpDouble(a.mainAxisExtent, b.mainAxisExtent, t)!,
      crossAxisExtent: lerpDouble(a.crossAxisExtent, b.crossAxisExtent, t)!,
    );
  }

  SliverGridGeometry _gridGeometry(int index) {
    final cFloor = _cFloor;
    final cCeil = _cCeil;
    final geomFloor = _gridGeometryForCols(cFloor, index);
    if (cFloor == cCeil || _colFrac <= 0.0) {
      return geomFloor;
    }
    final geomCeil = _gridGeometryForCols(cCeil, index);
    return _lerpGeometry(geomFloor, geomCeil, _colFrac);
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    if (gridMorph <= 0.0) {
      return _listGeometry(index);
    }
    if (gridMorph >= 1.0) {
      return _gridGeometry(index);
    }
    return _lerpGeometry(_listGeometry(index), _gridGeometry(index), gridMorph);
  }

  int _minIndexForList(double scrollOffset) {
    final stride = listTileExtent + listMainAxisSpacing;
    if (stride <= 0.0 || scrollOffset <= 0.0) return 0;
    return math.max(0, scrollOffset ~/ stride);
  }

  int _maxIndexForList(double targetEndScrollOffset) {
    final stride = listTileExtent + listMainAxisSpacing;
    if (stride <= 0.0 || targetEndScrollOffset <= 0.0) return 0;
    return math.max(0, (targetEndScrollOffset / stride).ceil() - 1);
  }

  int _minIndexForCols(int cols, double scrollOffset) {
    if (scrollOffset <= 0.0) return 0;
    final totalSpacing = (cols - 1) * gridCrossAxisSpacing;
    final cardWidth = math.max(1.0, (usableWidth - totalSpacing) / cols);
    final mainStride = cardWidth + gridTextHeight + gridMainAxisSpacing;
    if (mainStride <= 0.0) return 0;
    return math.max(0, cols * (scrollOffset ~/ mainStride));
  }

  int _maxIndexForCols(int cols, double targetEndScrollOffset) {
    if (targetEndScrollOffset <= 0.0) return 0;
    final totalSpacing = (cols - 1) * gridCrossAxisSpacing;
    final cardWidth = math.max(1.0, (usableWidth - totalSpacing) / cols);
    final mainStride = cardWidth + gridTextHeight + gridMainAxisSpacing;
    if (mainStride <= 0.0) return 0;
    final rows = (targetEndScrollOffset / mainStride).ceil();
    return math.max(0, cols * rows - 1);
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    if (scrollOffset <= 0.0) return 0;
    if (gridMorph <= 0.0) {
      return _minIndexForList(scrollOffset);
    }
    final minGrid = math.min(
      _minIndexForCols(_cFloor, scrollOffset),
      _minIndexForCols(_cCeil, scrollOffset),
    );
    if (gridMorph >= 1.0) {
      return minGrid;
    }
    return math.min(_minIndexForList(scrollOffset), minGrid);
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    if (gridMorph <= 0.0) {
      return _maxIndexForList(scrollOffset);
    }
    final maxGrid = math.max(
      _maxIndexForCols(_cFloor, scrollOffset),
      _maxIndexForCols(_cCeil, scrollOffset),
    );
    if (gridMorph >= 1.0) {
      return maxGrid;
    }
    return math.max(_maxIndexForList(scrollOffset), maxGrid);
  }

  double _maxScrollOffsetForList(int childCount) {
    if (childCount <= 0) return 0.0;
    final stride = listTileExtent + listMainAxisSpacing;
    return childCount * stride - listMainAxisSpacing;
  }

  double _maxScrollOffsetForCols(int cols, int childCount) {
    if (childCount <= 0) return 0.0;
    final rows = (childCount + cols - 1) ~/ cols;
    final totalSpacing = (cols - 1) * gridCrossAxisSpacing;
    final cardWidth = math.max(1.0, (usableWidth - totalSpacing) / cols);
    final cardHeight = cardWidth + gridTextHeight;
    final mainStride = cardHeight + gridMainAxisSpacing;
    return rows * mainStride - gridMainAxisSpacing;
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    if (childCount <= 0) return 0.0;
    if (gridMorph <= 0.0) {
      return _maxScrollOffsetForList(childCount);
    }
    final gridOffsetFloor = _maxScrollOffsetForCols(_cFloor, childCount);
    final gridOffsetCeil = _maxScrollOffsetForCols(_cCeil, childCount);
    final gridOffset =
        lerpDouble(gridOffsetFloor, gridOffsetCeil, _colFrac) ?? gridOffsetFloor;
    if (gridMorph >= 1.0) {
      return gridOffset;
    }
    return lerpDouble(
      _maxScrollOffsetForList(childCount),
      gridOffset,
      gridMorph,
    )!;
  }
}
