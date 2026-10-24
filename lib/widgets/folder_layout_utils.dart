import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../utils/layout_constants.dart';
import 'folder_nav_bar_scaffold.dart';

export '../utils/layout_constants.dart';

/// Discrete fixed tier values for `folderZoomScale`:
/// List view (4 tiers): 0.0, 1/6, 2/6, 3/6
/// Grid view (3 tiers): 4/6, 5/6, 1.0
const double kFolderZoomTierMinimalList = 0.0;
const double kFolderZoomTierCompactList = 1.0 / 6.0;
const double kFolderZoomTierStandardList = 2.0 / 6.0;
const double kFolderZoomTierLargeList = 3.0 / 6.0;
const double kFolderZoomTierSmallGrid = 4.0 / 6.0;
const double kFolderZoomTierMediumGrid = 5.0 / 6.0;
const double kFolderZoomTierLargeGrid = 1.0;

const List<double> kFolderZoomTierValues = [
  kFolderZoomTierMinimalList,
  kFolderZoomTierCompactList,
  kFolderZoomTierStandardList,
  kFolderZoomTierLargeList,
  kFolderZoomTierSmallGrid,
  kFolderZoomTierMediumGrid,
  kFolderZoomTierLargeGrid,
];

/// Snaps an arbitrary zoom scale to the closest discrete tier value.
double snapFolderZoomScale(double value) {
  double closest = kFolderZoomTierValues.first;
  double minDiff = (value - closest).abs();
  for (final v in kFolderZoomTierValues) {
    final diff = (value - v).abs();
    if (diff < minDiff) {
      minDiff = diff;
      closest = v;
    }
  }
  return closest;
}

/// Steps the zoom scale up or down by [delta] tiers.
double stepFolderZoomScale(double current, int delta) {
  final currentSnapped = snapFolderZoomScale(current);
  final index = kFolderZoomTierValues.indexOf(currentSnapped);
  if (index == -1) return currentSnapped;
  final newIndex = (index + delta).clamp(0, kFolderZoomTierValues.length - 1);
  return kFolderZoomTierValues[newIndex];
}

/// Discrete layout & typography tiers derived from `folderZoomScale`.
enum FolderZoomTier {
  /// Tier 0: Single-column minimal list without cover/thumbnail (pure text).
  minimalList,

  /// Tier 1: Single-column compact list with smaller cover; song info on the right.
  compactList,

  /// Tier 2: Single-column standard list with medium cover; 3-line column.
  standardList,

  /// Tier 3: Single-column spacious list with large cover; 3-line column.
  largeList,

  /// Tier 4: Multi-column compact grid with higher column density.
  smallGrid,

  /// Tier 5: Multi-column standard grid.
  mediumGrid,

  /// Tier 6: Multi-column spacious grid with lower column density and larger cards.
  largeGrid,
}

extension FolderZoomTierX on FolderZoomTier {
  /// Whether this tier represents a grid view.
  bool get isGrid => switch (this) {
        FolderZoomTier.minimalList ||
        FolderZoomTier.compactList ||
        FolderZoomTier.standardList ||
        FolderZoomTier.largeList =>
          false,
        FolderZoomTier.smallGrid ||
        FolderZoomTier.mediumGrid ||
        FolderZoomTier.largeGrid =>
          true,
      };

  /// Discrete cover size in list view (0.0 for minimal list with thumbnail hidden).
  double get listCoverSize => switch (this) {
        FolderZoomTier.minimalList => 0.0,
        FolderZoomTier.compactList => 40.0,
        FolderZoomTier.standardList => 64.0,
        FolderZoomTier.largeList => 88.0,
        _ => 0.0,
      };

  /// Discrete single-row tile extent (height) in list view.
  double get listTileExtent => switch (this) {
        FolderZoomTier.minimalList => 48.0,
        FolderZoomTier.compactList => 56.0,
        FolderZoomTier.standardList => 80.0,
        FolderZoomTier.largeList => 104.0,
        _ => 56.0,
      };

  /// Normalized zoom scale for this discrete tier.
  double get zoomScale => kFolderZoomTierValues[index];
}

FolderZoomTier getFolderZoomTier(double zoomScale) {
  final snapped = snapFolderZoomScale(zoomScale);
  int bestIdx = 0;
  double minDiff = double.infinity;
  for (int i = 0; i < kFolderZoomTierValues.length; i++) {
    final diff = (snapped - kFolderZoomTierValues[i]).abs();
    if (diff < minDiff) {
      minDiff = diff;
      bestIdx = i;
    }
  }
  return FolderZoomTier.values[bestIdx];
}

/// Boundary threshold between list tiers and grid tiers.
const double kFolderZoomGridThreshold =
    (kFolderZoomTierLargeList + kFolderZoomTierSmallGrid) / 2.0;

bool isFolderZoomGrid(double zoomScale) => zoomScale >= kFolderZoomGridThreshold;

/// Both Minimal List and Compact List use the 2-line right-aligned info layout.
bool isFolderZoomCompactList(double zoomScale) =>
    zoomScale < (kFolderZoomTierCompactList + kFolderZoomTierStandardList) / 2.0;

/// Piecewise linear interpolation across list tiers for a layout property.
double _interpolateListTierProperty(
  double zoomScale,
  double Function(FolderZoomTier tier) propertyGetter,
) {
  const listTiers = [
    FolderZoomTier.minimalList,
    FolderZoomTier.compactList,
    FolderZoomTier.standardList,
    FolderZoomTier.largeList,
  ];

  if (zoomScale <= listTiers.first.zoomScale) {
    return propertyGetter(listTiers.first);
  }
  if (zoomScale >= listTiers.last.zoomScale) {
    return propertyGetter(listTiers.last);
  }

  for (int i = 0; i < listTiers.length - 1; i++) {
    final t0 = listTiers[i];
    final t1 = listTiers[i + 1];
    if (zoomScale >= t0.zoomScale && zoomScale <= t1.zoomScale) {
      final span = t1.zoomScale - t0.zoomScale;
      final fraction = span <= 0.0 ? 0.0 : (zoomScale - t0.zoomScale) / span;
      return lerpDouble(propertyGetter(t0), propertyGetter(t1), fraction)!;
    }
  }
  return propertyGetter(listTiers.last);
}

/// Thumbnail size in list view (`zoomScale < kFolderZoomGridThreshold`),
/// ranging smoothly from `0px` (minimal list, hidden) to `88px` (large list).
double getFolderListCoverSize(double zoomScale) {
  return _interpolateListTierProperty(zoomScale, (t) => t.listCoverSize);
}

/// Total height of a single row tile in list view,
/// ranging from `48px` (minimal list) to `104px` (large list).
double getFolderListTileExtent(double zoomScale) {
  return _interpolateListTierProperty(zoomScale, (t) => t.listTileExtent);
}

/// Returns the discrete text block height below the cover in grid view.
///
/// Text size changes by tier (`smallGrid`, `mediumGrid`, `largeGrid`) rather
/// than scaling continuously with `zoomScale`.
double calculateFolderZoomGridTextHeight(
  BuildContext context, {
  required double zoomScale,
}) {
  final isPortrait =
      MediaQuery.of(context).orientation == Orientation.portrait;
  final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
  final clampedScale = textScale.clamp(1.0, 1.3);
  final tier = getFolderZoomTier(zoomScale);
  final double baseHeight = switch (tier) {
    FolderZoomTier.smallGrid => isPortrait ? 58.0 : 62.0,
    FolderZoomTier.mediumGrid => isPortrait ? 64.0 : 68.0,
    FolderZoomTier.largeGrid || _ => isPortrait ? 70.0 : 74.0,
  };
  return baseHeight * clampedScale;
}

/// 网格条目的字号三元组：（标题、副标题、第三行信息）。
typedef FolderGridFontSizes = ({double title, double subtitle, double info});

/// 网格条目字号——按**卡片宽度**分档，而不是屏幕宽度。
///
/// 卡片宽度由列数与窗口宽度共同决定：横屏 8 列时卡片只有约 `142pt`，手机竖屏 4 列
/// 只有约 `84pt`，而窗口宽度可能远大于 `780`。以前用
/// `MediaQuery.size.width >= 780` 判「宽屏」，这些窄卡片也在吃宽屏字号，标题频繁
/// 被省略号截断；反过来竖屏 2 列的大卡片（约 `183pt`）却拿到小字号。
///
/// 档位表就是唯一来源，[FolderZoomItem] 与 [SongZoomItem] 都从这里取，别再各自
/// 按屏幕宽度写一份。
FolderGridFontSizes folderGridFontSizes(double cardWidth) {
  if (cardWidth >= 240.0) {
    return (title: 15.0, subtitle: 12.5, info: 11.0);
  }
  if (cardWidth >= 200.0) {
    return (title: 14.5, subtitle: 12.0, info: 10.5);
  }
  if (cardWidth >= 150.0) {
    return (title: 13.5, subtitle: 11.5, info: 10.0);
  }
  if (cardWidth >= 110.0) {
    return (title: 12.5, subtitle: 10.5, info: 9.5);
  }
  return (title: 11.5, subtitle: 9.5, info: 9.0);
}

/// 目录页列表视图的行间距（相邻两行 `Row` 之间）。
const double kFolderListRowSpacing = 8.0;

/// 标题横幅高度的兜底值：测不到实测高度时使用（首帧、或横幅已滚出缓存区）。
const double kFolderHeaderBannerFallbackHeight = 190.0;

/// 内容区上方「无权限访问」提示块的估算高度（`folder.path == 'system'` 且未授权时）。
const double kFolderPermissionWarningHeight = 200.0;

/// 「定位当前播放」要加在行偏移上的内容区上方高度：顶栏 + 标题横幅（+ 权限提示）。
///
/// 横幅高度不是常量——它随系统文字缩放、搜索框展开而变，所以优先用 [bannerKey]
/// 实测（key 挂在横幅上）；横幅已经滚出缓存区、element 被卸载时回落到
/// [kFolderHeaderBannerFallbackHeight]。
///
/// 竖屏时顶栏高度已包含在横幅的 `topHeader` 里，因此不再单独叠加。
double folderContentTopOffset({
  required BuildContext context,
  required bool isPortrait,
  GlobalKey? bannerKey,
  bool hasPermissionWarning = false,
}) {
  final bannerHeight = _measuredBannerHeight(bannerKey);
  final barHeight =
      isPortrait ? 0.0 : FolderNavBarScaffold.getBarHeight(context);
  return barHeight +
      bannerHeight +
      (hasPermissionWarning ? kFolderPermissionWarningHeight : 0.0);
}

double _measuredBannerHeight(GlobalKey? key) {
  final renderObject = key?.currentContext?.findRenderObject();
  if (renderObject is RenderBox &&
      renderObject.hasSize &&
      renderObject.size.height > 0) {
    return renderObject.size.height;
  }
  return kFolderHeaderBannerFallbackHeight;
}

/// 目录页内容的左右内边距。
///
/// 列表档位收窄（竖屏 `4`、横屏 `8`），网格档位统一 [kGridHorizontalPadding]；
/// 切换档位时按 `gridMorph` 插值。目录类 sliver 与 [FolderZoomPolicy] 共用此函数，
/// 不要在别处再写一遍 `lerpDouble(4/8 -> 16)`。
double folderContentHorizontalPadding({
  required bool isPortrait,
  required double gridMorph,
}) {
  return lerpDouble(
    isPortrait ? 4.0 : 8.0,
    kGridHorizontalPadding,
    gridMorph.clamp(0.0, 1.0),
  )!;
}

/// 目录页缩放的布局规格：列数、卡片几何、滚动偏移估算。
///
/// **宽度语义已统一**：对外只接受「页面交给 sliver 的外层宽度」
/// （即 `crossAxisExtent`，尚未扣除 [folderContentHorizontalPadding]）。
/// 左右内边距由 [resolve] 内部扣除，调用方不要再自己 `- 32`。
class FolderZoomPolicy {
  /// 网格卡片宽度（内容宽度下均分）。
  final double cardWidth;

  /// 网格卡片总高（封面 + 文字区）。
  final double cardHeight;

  /// 列表视图的单行步距（行高 + [kFolderListRowSpacing]）。
  final double listRowStride;

  /// 网格列数。
  final int crossAxisCount;

  /// 目标档位是否落在网格侧（`zoomScale >= 0.5`）。
  final bool isGrid;

  const FolderZoomPolicy._({
    required this.cardWidth,
    required this.cardHeight,
    required this.listRowStride,
    required this.crossAxisCount,
    required this.isGrid,
  });

  /// 标准网格 delegate（如排序态 `SliverGridDelegateWithFixedCrossAxisCount`）的宽高比。
  double get childAspectRatio =>
      (cardWidth > 0 && cardHeight > 0) ? cardWidth / cardHeight : 1.0;

  /// 由上下文、外层宽度与缩放档位解析出完整布局规格。
  factory FolderZoomPolicy.resolve({
    required BuildContext context,
    required double outerWidth,
    required double zoomScale,
    bool? isPortrait,
  }) {
    final snappedZoom = snapFolderZoomScale(zoomScale);
    final portrait = isPortrait ??
        (MediaQuery.maybeOrientationOf(context) == Orientation.portrait);
    final tier = getFolderZoomTier(snappedZoom);
    final isGrid = isFolderZoomGrid(snappedZoom);

    final crossAxisCount = calculateCrossAxisCount(
      width: outerWidth,
      tier: tier,
      isPortrait: portrait,
    );
    final horizontalPadding = folderContentHorizontalPadding(
      isPortrait: portrait,
      gridMorph: isGrid ? 1.0 : 0.0,
    );
    final contentWidth = math.max(
      1.0,
      outerWidth - horizontalPadding * 2,
    );
    final cardWidth = gridCardWidth(
      contentWidth: contentWidth,
      crossAxisCount: crossAxisCount,
    );
    final cardHeight = cardWidth +
        calculateFolderZoomGridTextHeight(context, zoomScale: snappedZoom);

    return FolderZoomPolicy._(
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      listRowStride:
          getFolderListTileExtent(snappedZoom) + kFolderListRowSpacing,
      crossAxisCount: crossAxisCount,
      isGrid: isGrid,
    );
  }

  /// 内容宽度下按 [crossAxisCount] 均分得到的卡片宽度。
  ///
  /// 与 [SliverAnimatedZoomGridDelegate] 的几何计算共用，避免两处各推一份公式。
  static double gridCardWidth({
    required double contentWidth,
    required int crossAxisCount,
    double crossAxisSpacing = kGridCrossAxisSpacing,
  }) {
    if (crossAxisCount <= 0) return 0.0;
    final usable = contentWidth - (crossAxisCount - 1) * crossAxisSpacing;
    return math.max(1.0, usable / crossAxisCount);
  }

  /// Calculates responsive cross axis count based on [width], [tier], and [isPortrait].
  ///
  /// In landscape orientation:
  /// - largeGrid (`1.0`) is fixed at 6 columns.
  /// - mediumGrid (`0.8`) is 7 columns (+1).
  /// - smallGrid (`0.6`) is 8 columns (+1).
  ///
  /// In portrait orientation, each smaller tier also adds one column:
  /// - Mobile portrait (< 600px): largeGrid 2, mediumGrid 3, smallGrid 4.
  /// - Tablet portrait (>= 600px): largeGrid 3, mediumGrid 4, smallGrid 5.
  static int calculateCrossAxisCount({
    required double width,
    required FolderZoomTier tier,
    required bool isPortrait,
  }) {
    if (!isPortrait) {
      const baseLarge = 6;
      return switch (tier) {
        FolderZoomTier.smallGrid => baseLarge + 2, // 8
        FolderZoomTier.mediumGrid => baseLarge + 1, // 7
        FolderZoomTier.largeGrid || _ => baseLarge, // 6
      };
    }

    final baseLarge = switch (width) {
      >= 900 => 4,
      >= 600 => 3,
      _ => 2,
    };
    return switch (tier) {
      FolderZoomTier.smallGrid => baseLarge + 2,
      FolderZoomTier.mediumGrid => baseLarge + 1,
      FolderZoomTier.largeGrid || _ => baseLarge,
    };
  }

  /// Calculates scroll offset for an item at [songIndex] preceded by [folderCount] subfolders.
  double calculateScrollOffset({
    required int folderCount,
    required int songIndex,
  }) {
    double offset = 0.0;
    if (isGrid) {
      final folderRows = (folderCount / crossAxisCount).ceil();
      offset += folderRows * (cardHeight + kGridMainAxisSpacing);
      final songRows = (songIndex / crossAxisCount).floor();
      offset += songRows * (cardHeight + kGridMainAxisSpacing);
    } else {
      offset += folderCount * listRowStride;
      offset += songIndex * listRowStride;
    }
    return offset;
  }

  /// Centers the item offset within the viewport, clamped to maxScrollExtent.
  double centerInViewport({
    required double itemOffset,
    required double viewportDimension,
    required double maxScrollExtent,
  }) {
    final itemExtent = isGrid ? cardHeight : listRowStride;
    final target = itemOffset - (viewportDimension / 2) + (itemExtent / 2);
    return target.clamp(0.0, maxScrollExtent);
  }
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

  /// 目标网格卡片宽度（**不参与动画**）。
  ///
  /// 只用于「按卡片宽度做离散决策」——目前是 [folderGridFontSizes]。若跟着
  /// `gridMorph` 连续插值，文字每帧都要重新排版，且字号会在动画中途乱跳。
  final double targetCardWidth;

  const FolderZoomLayoutMetrics({
    required this.targetZoomScale,
    required this.animatedZoomScale,
    required this.gridMorph,
    required this.compactMorph,
    required this.animatedGridCols,
    required this.animatedGridTextHeight,
    required this.animatedListExtent,
    required this.targetCardWidth,
  });

  bool get isGridTarget => isFolderZoomGrid(targetZoomScale);
  FolderZoomTier get tier => getFolderZoomTier(targetZoomScale);

  /// Target discrete column count in Grid View (e.g. 6, 7, 8).
  int get targetGridCols => animatedGridCols.round();

  /// 排序态网格（固定 delegate、不参与 morph）所需的宽高比。
  ///
  /// 复算用的卡片宽度直接取 [targetCardWidth]（与 morph 网格同一来源），
  /// 不再自己拿 `outerWidth - 2 * padding` 推一遍。
  double get targetChildAspectRatio {
    final cardHeight = targetCardWidth + animatedGridTextHeight;
    return (cardHeight > 0 && targetCardWidth > 0)
        ? targetCardWidth / cardHeight
        : 1.0;
  }
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

typedef _ZoomTargets = ({
  double gridMorph,
  double compactMorph,
  double gridCols,
  double gridTextHeight,
  double listExtent,
  double cardWidth,
});

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

  /// 见 [FolderZoomLayoutMetrics.targetCardWidth]：不进动画，只跟着目标值跳。
  double _targetCardWidth = 0.0;

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

  /// 当前 `zoomScale` / 宽度对应的目标布局值（动画的终点，也是首帧的起点）。
  _ZoomTargets _targets() {
    final zoomScale = widget.zoomScale;
    final isPortrait =
        MediaQuery.maybeOrientationOf(context) == Orientation.portrait;
    final gridCols = FolderZoomPolicy.calculateCrossAxisCount(
      width: widget.width,
      tier: getFolderZoomTier(zoomScale),
      isPortrait: isPortrait,
    );
    return (
      gridMorph: isFolderZoomGrid(zoomScale) ? 1.0 : 0.0,
      compactMorph: isFolderZoomCompactList(zoomScale) ? 1.0 : 0.0,
      gridCols: gridCols.toDouble(),
      gridTextHeight: calculateFolderZoomGridTextHeight(
        context,
        zoomScale: zoomScale,
      ),
      listExtent: getFolderListTileExtent(zoomScale),
      cardWidth: FolderZoomPolicy.gridCardWidth(
        contentWidth: math.max(
          1.0,
          widget.width - kGridHorizontalPadding * 2,
        ),
        crossAxisCount: gridCols,
      ),
    );
  }

  void _applyTargets(_ZoomTargets targets, {required bool animate}) {
    _targetCardWidth = targets.cardWidth;

    if (animate) {
      _fromZoomScale = _eval(_fromZoomScale, _toZoomScale);
      _fromGridMorph = _eval(_fromGridMorph, _toGridMorph);
      _fromCompactMorph = _eval(_fromCompactMorph, _toCompactMorph);
      _fromGridCols = _eval(_fromGridCols, _toGridCols);
      _fromGridTextHeight = _eval(_fromGridTextHeight, _toGridTextHeight);
      _fromListExtent = _eval(_fromListExtent, _toListExtent);
    } else {
      _fromZoomScale = _toZoomScale = widget.zoomScale;
      _fromGridMorph = _toGridMorph = targets.gridMorph;
      _fromCompactMorph = _toCompactMorph = targets.compactMorph;
      _fromGridCols = _toGridCols = targets.gridCols;
      _fromGridTextHeight = _toGridTextHeight = targets.gridTextHeight;
      _fromListExtent = _toListExtent = targets.listExtent;
      return;
    }

    _toZoomScale = widget.zoomScale;
    _toGridMorph = targets.gridMorph;
    _toCompactMorph = targets.compactMorph;
    _toGridCols = targets.gridCols;
    _toGridTextHeight = targets.gridTextHeight;
    _toListExtent = targets.listExtent;

    _controller.forward(from: 0.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final targets = _targets();
    if (!_initialized) {
      _applyTargets(targets, animate: false);
      _initialized = true;
    }
  }

  @override
  void didUpdateWidget(FolderZoomSliverBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targets = _targets();

    if ((oldWidget.zoomScale - widget.zoomScale).abs() > 1e-4) {
      _applyTargets(targets, animate: true);
    } else if ((oldWidget.width - widget.width).abs() > 0.5) {
      // Window resize: update column count immediately without lag.
      _fromGridCols = _toGridCols = targets.gridCols;
      _fromGridTextHeight = _toGridTextHeight = targets.gridTextHeight;
      _targetCardWidth = targets.cardWidth;
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
      targetCardWidth: _targetCardWidth,
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
    this.listMainAxisSpacing = kFolderListRowSpacing,
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
    final cardWidth = FolderZoomPolicy.gridCardWidth(
      contentWidth: usableWidth,
      crossAxisCount: cols,
      crossAxisSpacing: gridCrossAxisSpacing,
    );
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

  /// 每行（含行间距）的纵向步距，供 `getMin/MaxChildIndexForScrollOffset` 与
  /// `computeMaxScrollOffset` 共用，避免三处各推一遍。
  double _mainStrideForCols(int cols) {
    final cardWidth = FolderZoomPolicy.gridCardWidth(
      contentWidth: usableWidth,
      crossAxisCount: cols,
      crossAxisSpacing: gridCrossAxisSpacing,
    );
    return cardWidth + gridTextHeight + gridMainAxisSpacing;
  }

  int _minIndexForCols(int cols, double scrollOffset) {
    if (scrollOffset <= 0.0) return 0;
    final mainStride = _mainStrideForCols(cols);
    if (mainStride <= 0.0) return 0;
    return math.max(0, cols * (scrollOffset ~/ mainStride));
  }

  int _maxIndexForCols(int cols, double targetEndScrollOffset) {
    if (targetEndScrollOffset <= 0.0) return 0;
    final mainStride = _mainStrideForCols(cols);
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
    final mainStride = _mainStrideForCols(cols);
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
