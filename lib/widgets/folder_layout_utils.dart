import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../utils/layout_constants.dart';
import 'folder_nav_bar_scaffold.dart';
import 'folder_zoom_pinch.dart';

export '../utils/layout_constants.dart';
export 'zoom_item_scaffold.dart';
export 'zoom_item_cover.dart';
export 'folder_zoom_pinch.dart';

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
  return folderZoomGridTextHeightFor(
    tier: getFolderZoomTier(zoomScale),
    isPortrait: MediaQuery.of(context).orientation == Orientation.portrait,
    textScale: folderZoomTextScaleOf(context),
  );
}

/// [calculateFolderZoomGridTextHeight] 的纯函数版本：不碰 `MediaQuery`。
///
/// 每帧都要算目标布局时（捏合跟手、字号插值）必须用这个版本，
/// 否则一次 `_calculateTargets` 里要摸两次 `MediaQuery`。
double folderZoomGridTextHeightFor({
  required FolderZoomTier tier,
  required bool isPortrait,
  required double textScale,
}) {
  final clampedScale = textScale.clamp(1.0, 1.3);
  final double baseHeight = switch (tier) {
    FolderZoomTier.smallGrid => isPortrait ? 58.0 : 62.0,
    FolderZoomTier.mediumGrid => isPortrait ? 64.0 : 68.0,
    FolderZoomTier.largeGrid || _ => isPortrait ? 70.0 : 74.0,
  };
  return baseHeight * clampedScale;
}

/// 系统文字缩放系数（以 `10pt` 为基准），统一走这一个入口。
double folderZoomTextScaleOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) / 10;

/// 插值字号的对齐步长。
///
/// `fontSize` 每变一点，`RenderParagraph` 就要重造一次 `Paragraph`（shaping +
/// 排版）。捏合跟手时每个可见条目每帧三套字号都在变，网格 6~8 列就是每帧上
/// 百次重排版。对齐到 `0.5` 后，一次档位过渡里每个字号只会真正变 2~4 次，
/// 视觉上看不出差别（半像素的字号），排版次数降一个数量级。
const double kFolderZoomFontSizeQuantum = 0.5;

/// 把插值出来的字号对齐到 [kFolderZoomFontSizeQuantum]。
double quantizeFolderZoomFontSize(double fontSize) =>
    (fontSize / kFolderZoomFontSizeQuantum).roundToDouble() *
    kFolderZoomFontSizeQuantum;

/// 网格条目的字号三元组：（标题、副标题、第三行信息）。
typedef FolderGridFontSizes = ({double title, double subtitle, double info});

/// 根据档位、卡片宽度及屏幕方向，解析出该档位的基准字号三元组（标题、副标题、第三行信息）。
FolderGridFontSizes resolveFolderZoomFontSizes({
  required FolderZoomTier tier,
  required double cardWidth,
  required bool isPortrait,
}) {
  final gridFonts = folderGridFontSizes(cardWidth);
  return switch (tier) {
    FolderZoomTier.minimalList => isPortrait
        ? (title: 13.5, subtitle: 11.5, info: 11.0)
        : (title: 14.0, subtitle: 12.0, info: 12.0),
    FolderZoomTier.compactList => isPortrait
        ? (title: 14.0, subtitle: 12.0, info: 11.0)
        : (title: 14.5, subtitle: 12.5, info: 12.0),
    FolderZoomTier.standardList => isPortrait
        ? (title: 14.0, subtitle: 12.0, info: 11.0)
        : (title: 15.5, subtitle: 13.0, info: 13.0),
    FolderZoomTier.largeList => isPortrait
        ? (title: 15.5, subtitle: 13.0, info: 11.5)
        : (title: 16.5, subtitle: 13.5, info: 13.5),
    FolderZoomTier.smallGrid ||
    FolderZoomTier.mediumGrid ||
    FolderZoomTier.largeGrid =>
      gridFonts,
  };
}

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
/// 列表模式下条目之间无额外间距，完全交由条目内部上下 padding 保持留白。
const double kFolderListRowSpacing = 0.0;

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

  /// 平滑插值的标题字号。
  final double animatedTitleFontSize;

  /// 平滑插值的副标题字号。
  final double animatedSubtitleFontSize;

  /// 平滑插值的第三行（详细信息）字号。
  final double animatedInfoFontSize;

  /// 当前是否竖屏。
  ///
  /// 条目层以前各自 `MediaQuery.of(context).orientation`，一个画面里几十个条目
  /// 每帧各摸一次；方向本来就在 [FolderZoomSliverBuilder] 算目标布局时拿到了，
  /// 统一从这里下发。默认值只服务测试里手工构造 metrics 的场景。
  final bool isPortrait;

  /// 条目内容该渲染网格那套还是列表那套。
  ///
  /// 以前这一侧是靠 `gridMorph >= 0.5` 在 [gridMorph] 的 0.5 处单点翻转的，
  /// 手势在中点附近来回磨时会反复翻转。这里由 [FolderZoomSliverBuilder] 按
  /// 滞回统一算好下发，保证整屏条目在同一帧一起交接。
  ///
  /// 为空时降级为「[gridMorph] >= 0.5」，供测试直接构造 metrics 的场景使用。
  final bool? contentIsGrid;

  /// 内容交接时的整体不透明度（`1.0` = 完全清晰）。
  ///
  /// 网格与列表两套布局的字数/行数不同，交接瞬间会有一次结构突变；在交接点
  /// 两侧各留一小段压暗把这次突变盖掉。只有 `gridMorph` 落在交接点附近时
  /// 才小于 1，此时条目会多一层 `Opacity`，其余时间不产生额外合成。
  final double contentReveal;

  const FolderZoomLayoutMetrics({
    required this.targetZoomScale,
    required this.animatedZoomScale,
    required this.gridMorph,
    required this.compactMorph,
    required this.animatedGridCols,
    required this.animatedGridTextHeight,
    required this.animatedListExtent,
    required this.targetCardWidth,
    this.animatedTitleFontSize = 14.0,
    this.animatedSubtitleFontSize = 12.0,
    this.animatedInfoFontSize = 11.0,
    this.isPortrait = false,
    this.contentIsGrid,
    this.contentReveal = 1.0,
  });

  bool get isGridTarget => isFolderZoomGrid(targetZoomScale);

  /// 条目内容实际使用的布局侧，见 [contentIsGrid]。
  bool get renderAsGrid => contentIsGrid ?? (gridMorph >= 0.5);

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

/// 网格 ↔ 列表内容交接的滞回上界：`gridMorph` 越过这里才切到网格那套。
const double kFolderZoomContentHandoffUpper = 0.55;

/// 交接滞回下界：低于这里才切回列表那套。
const double kFolderZoomContentHandoffLower = 0.45;

/// 交接点两侧这么宽的区间里内容压暗到
/// [kFolderZoomContentHandoffMinOpacity]。
///
/// 越宽压暗持续越久；0.12 对应 `gridMorph` 的 0.38~0.62，是「交接前后
/// 约 5% 行程」的观感，能盖住结构突变又不至于让整段过渡发虚。
const double kFolderZoomContentHandoffFadeHalfWindow = 0.12;

/// 交接瞬间的内容不透明度下限（不压到全透明，避免中间态看起来像丢失）。
const double kFolderZoomContentHandoffMinOpacity = 0.55;

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
  double titleFontSize,
  double subtitleFontSize,
  double infoFontSize,
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

  late double _fromTitleFontSize;
  late double _toTitleFontSize;

  late double _fromSubtitleFontSize;
  late double _toSubtitleFontSize;

  late double _fromInfoFontSize;
  late double _toInfoFontSize;

  /// 见 [FolderZoomLayoutMetrics.targetCardWidth]：不进动画，只跟着目标值跳。
  double _targetCardWidth = 0.0;

  bool _initialized = false;

  /// 条目内容当前渲染的是哪一侧：`1` 网格、`-1` 列表、`0` 未定。
  ///
  /// 滞回要靠它跨帧记忆——只看当前 `gridMorph` 的话，手势磨在交接点附近时
  /// 内容会逐帧翻转，每次翻转都是一整套文字重新排版。
  int _contentSide = 0;

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

  /// 按滞回决定条目内容渲染哪一侧，并给出交接处的压暗程度。
  ///
  /// 网格与列表两套布局的字数、行数都不同，同时构建再交叉淡化意味着每个可见
  /// 条目每帧要排两份文字、做两次 `saveLayer`。屏外条目本来就由 sliver 懒构建
  /// 挡掉了，真正白花的是视口和 cacheExtent 里那批——这里改成任何时刻只渲染
  /// 当前侧一份，把「另一份」的排版和合成全省下来。
  ///
  /// 代价是内容在交接点会突变，所以交接点两侧各留一段压暗（[contentReveal]）。
  ({bool isGrid, double reveal}) _resolveContentHandoff(double morph) {
    final int side;
    if (morph >= kFolderZoomContentHandoffUpper) {
      side = 1;
    } else if (morph <= kFolderZoomContentHandoffLower) {
      side = -1;
    } else {
      // 滞回区里保持上一帧的侧别；首帧（_contentSide == 0）退回单点判定。
      side = _contentSide != 0 ? _contentSide : (morph >= 0.5 ? 1 : -1);
    }
    _contentSide = side;

    final double distance = (morph - 0.5).abs();
    final double reveal = distance >= kFolderZoomContentHandoffFadeHalfWindow
        ? 1.0
        : kFolderZoomContentHandoffMinOpacity +
              (1.0 - kFolderZoomContentHandoffMinOpacity) *
                  (distance / kFolderZoomContentHandoffFadeHalfWindow);
    return (isGrid: side > 0, reveal: reveal);
  }

  /// 计算某个 `zoomScale` 对应的目标布局值。
  ///
  /// [isPortrait] / [textScale] 可由调用方带入：`build` 里本来就要取一次
  /// `MediaQuery`，再让这个函数自己摸一遍等于每帧多做两次查找。
  _ZoomTargets _calculateTargets(
    double zoomScale, {
    bool? isPortrait,
    double? textScale,
  }) {
    final portrait = isPortrait ??
        (MediaQuery.maybeOrientationOf(context) == Orientation.portrait);
    final scaled = textScale ?? folderZoomTextScaleOf(context);
    final tier = getFolderZoomTier(zoomScale);
    final gridCols = FolderZoomPolicy.calculateCrossAxisCount(
      width: widget.width,
      tier: tier,
      isPortrait: portrait,
    );
    final cardWidth = FolderZoomPolicy.gridCardWidth(
      contentWidth: math.max(
        1.0,
        widget.width - kGridHorizontalPadding * 2,
      ),
      crossAxisCount: gridCols,
    );
    final fontSizes = resolveFolderZoomFontSizes(
      tier: tier,
      cardWidth: cardWidth,
      isPortrait: portrait,
    );
    return (
      gridMorph: isFolderZoomGrid(zoomScale) ? 1.0 : 0.0,
      compactMorph: isFolderZoomCompactList(zoomScale) ? 1.0 : 0.0,
      gridCols: gridCols.toDouble(),
      gridTextHeight: folderZoomGridTextHeightFor(
        tier: tier,
        isPortrait: portrait,
        textScale: scaled,
      ),
      listExtent: getFolderListTileExtent(zoomScale),
      cardWidth: cardWidth,
      titleFontSize: fontSizes.title,
      subtitleFontSize: fontSizes.subtitle,
      infoFontSize: fontSizes.info,
    );
  }

  // ── 捏合期间的目标值缓存 ────────────────────────────────────────────
  //
  // 捏合时 `from` / `to` 两个档位在整个手势里是固定的，没必要每帧重算；
  // `build` 每帧都会来取，缓存下来把每帧 2~3 次 `_calculateTargets` 降到 0。
  final Map<double, _ZoomTargets> _pinchTargetsCache = <double, _ZoomTargets>{};
  double _pinchCacheWidth = -1;
  bool _pinchCacheIsPortrait = false;
  double _pinchCacheTextScale = -1;

  _ZoomTargets _cachedTargets(
    double zoomScale, {
    required bool isPortrait,
    required double textScale,
  }) {
    if (_pinchCacheWidth != widget.width ||
        _pinchCacheIsPortrait != isPortrait ||
        _pinchCacheTextScale != textScale) {
      _pinchTargetsCache.clear();
      _pinchCacheWidth = widget.width;
      _pinchCacheIsPortrait = isPortrait;
      _pinchCacheTextScale = textScale;
    }
    return _pinchTargetsCache.putIfAbsent(
      zoomScale,
      () => _calculateTargets(
        zoomScale,
        isPortrait: isPortrait,
        textScale: textScale,
      ),
    );
  }

  /// 当前 `zoomScale` / 宽度对应的目标布局值（动画的终点，也是首帧的起点）。
  _ZoomTargets _targets() => _calculateTargets(widget.zoomScale);

  void _applyTargets(_ZoomTargets targets, {required bool animate}) {
    _targetCardWidth = targets.cardWidth;

    if (animate) {
      _fromZoomScale = _eval(_fromZoomScale, _toZoomScale);
      _fromGridMorph = _eval(_fromGridMorph, _toGridMorph);
      _fromCompactMorph = _eval(_fromCompactMorph, _toCompactMorph);
      _fromGridCols = _eval(_fromGridCols, _toGridCols);
      _fromGridTextHeight = _eval(_fromGridTextHeight, _toGridTextHeight);
      _fromListExtent = _eval(_fromListExtent, _toListExtent);
      _fromTitleFontSize = _eval(_fromTitleFontSize, _toTitleFontSize);
      _fromSubtitleFontSize = _eval(_fromSubtitleFontSize, _toSubtitleFontSize);
      _fromInfoFontSize = _eval(_fromInfoFontSize, _toInfoFontSize);
    } else {
      _fromZoomScale = _toZoomScale = widget.zoomScale;
      _fromGridMorph = _toGridMorph = targets.gridMorph;
      _fromCompactMorph = _toCompactMorph = targets.compactMorph;
      _fromGridCols = _toGridCols = targets.gridCols;
      _fromGridTextHeight = _toGridTextHeight = targets.gridTextHeight;
      _fromListExtent = _toListExtent = targets.listExtent;
      _fromTitleFontSize = _toTitleFontSize = targets.titleFontSize;
      _fromSubtitleFontSize = _toSubtitleFontSize = targets.subtitleFontSize;
      _fromInfoFontSize = _toInfoFontSize = targets.infoFontSize;
      return;
    }

    _toZoomScale = widget.zoomScale;
    _toGridMorph = targets.gridMorph;
    _toCompactMorph = targets.compactMorph;
    _toGridCols = targets.gridCols;
    _toGridTextHeight = targets.gridTextHeight;
    _toListExtent = targets.listExtent;
    _toTitleFontSize = targets.titleFontSize;
    _toSubtitleFontSize = targets.subtitleFontSize;
    _toInfoFontSize = targets.infoFontSize;

    _controller.forward(from: 0.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只有首帧需要在这里取初值。
    //
    // 本 State 依赖 `FolderZoomPinchScope`，捏合期间每帧都会 notify，
    // `didChangeDependencies` 也就每帧被调一次——不提前返回的话，这里会白白
    // 算一遍 `_targets()`（结果直接丢掉），叠加 build 里的两次就是每帧三次。
    if (_initialized) return;
    _applyTargets(_targets(), animate: false);
    _initialized = true;
  }

  @override
  void didUpdateWidget(FolderZoomSliverBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool scaleChanged =
        (oldWidget.zoomScale - widget.zoomScale).abs() > 1e-4;
    final bool widthChanged = (oldWidget.width - widget.width).abs() > 0.5;
    // 父级因为别的原因重建（播放状态、筛选、选中态…）时不必重算目标布局。
    if (!scaleChanged && !widthChanged) return;

    final targets = _targets();
    final pinch = FolderZoomPinchScope.maybeOf(context);

    if (scaleChanged) {
      if (pinch != null &&
          pinch.committedScale != null &&
          (pinch.committedScale! - widget.zoomScale).abs() < 1e-4) {
        // 本次变化由 pinch 手势吸附完成触发，直接同步目标状态，避免二次重复动画。
        _applyTargets(targets, animate: false);
      } else {
        _applyTargets(targets, animate: true);
      }
    } else if (widthChanged) {
      // Window resize: update column count immediately without lag.
      _fromGridCols = _toGridCols = targets.gridCols;
      _fromGridTextHeight = _toGridTextHeight = targets.gridTextHeight;
      _fromTitleFontSize = _toTitleFontSize = targets.titleFontSize;
      _fromSubtitleFontSize = _toSubtitleFontSize = targets.subtitleFontSize;
      _fromInfoFontSize = _toInfoFontSize = targets.infoFontSize;
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
    // 一个 build 里只取一次 MediaQuery，下面两条分支共用。
    final isPortrait =
        MediaQuery.maybeOrientationOf(context) == Orientation.portrait;
    final textScale = folderZoomTextScaleOf(context);

    final pinch = FolderZoomPinchScope.maybeOf(context);
    if (pinch != null && pinch.isActive) {
      final fromScale = pinch.baseZoomScale;
      final toScale = pinch.targetZoomScale;
      // 两个档位的目标布局在整个手势里是固定的：缓存住，别每帧重算。
      final targetsFrom = _cachedTargets(
        fromScale,
        isPortrait: isPortrait,
        textScale: textScale,
      );
      final targetsTo = _cachedTargets(
        toScale,
        isPortrait: isPortrait,
        textScale: textScale,
      );
      final t = pinch.progress;
      final activeTarget = t > 0.5 ? toScale : fromScale;
      final double gridMorph =
          (lerpDouble(targetsFrom.gridMorph, targetsTo.gridMorph, t) ??
                  targetsFrom.gridMorph)
              .clamp(0.0, 1.0);
      final handoff = _resolveContentHandoff(gridMorph);

      final metrics = FolderZoomLayoutMetrics(
        targetZoomScale: activeTarget,
        animatedZoomScale:
            lerpDouble(fromScale, toScale, t) ?? fromScale,
        gridMorph: gridMorph,
        compactMorph:
            (lerpDouble(targetsFrom.compactMorph, targetsTo.compactMorph, t) ??
                    targetsFrom.compactMorph)
                .clamp(0.0, 1.0),
        animatedGridCols:
            lerpDouble(targetsFrom.gridCols, targetsTo.gridCols, t) ??
            targetsFrom.gridCols,
        animatedGridTextHeight:
            lerpDouble(
              targetsFrom.gridTextHeight,
              targetsTo.gridTextHeight,
              t,
            ) ??
            targetsFrom.gridTextHeight,
        animatedListExtent:
            lerpDouble(targetsFrom.listExtent, targetsTo.listExtent, t) ??
            targetsFrom.listExtent,
        targetCardWidth: t > 0.5 ? targetsTo.cardWidth : targetsFrom.cardWidth,
        animatedTitleFontSize: quantizeFolderZoomFontSize(
          lerpDouble(targetsFrom.titleFontSize, targetsTo.titleFontSize, t) ??
              targetsFrom.titleFontSize,
        ),
        animatedSubtitleFontSize: quantizeFolderZoomFontSize(
          lerpDouble(
                targetsFrom.subtitleFontSize,
                targetsTo.subtitleFontSize,
                t,
              ) ??
              targetsFrom.subtitleFontSize,
        ),
        animatedInfoFontSize: quantizeFolderZoomFontSize(
          lerpDouble(targetsFrom.infoFontSize, targetsTo.infoFontSize, t) ??
              targetsFrom.infoFontSize,
        ),
        isPortrait: isPortrait,
        contentIsGrid: handoff.isGrid,
        contentReveal: handoff.reveal,
      );
      return widget.builder(context, metrics);
    }

    final double gridMorph = _eval(
      _fromGridMorph,
      _toGridMorph,
    ).clamp(0.0, 1.0);
    final handoff = _resolveContentHandoff(gridMorph);

    final metrics = FolderZoomLayoutMetrics(
      targetZoomScale: widget.zoomScale,
      animatedZoomScale: _eval(_fromZoomScale, _toZoomScale),
      gridMorph: gridMorph,
      compactMorph: _eval(_fromCompactMorph, _toCompactMorph).clamp(0.0, 1.0),
      animatedGridCols: _eval(_fromGridCols, _toGridCols),
      animatedGridTextHeight: _eval(_fromGridTextHeight, _toGridTextHeight),
      animatedListExtent: _eval(_fromListExtent, _toListExtent),
      targetCardWidth: _targetCardWidth,
      animatedTitleFontSize: quantizeFolderZoomFontSize(
        _eval(_fromTitleFontSize, _toTitleFontSize),
      ),
      animatedSubtitleFontSize: quantizeFolderZoomFontSize(
        _eval(_fromSubtitleFontSize, _toSubtitleFontSize),
      ),
      animatedInfoFontSize: quantizeFolderZoomFontSize(
        _eval(_fromInfoFontSize, _toInfoFontSize),
      ),
      isPortrait: isPortrait,
      contentIsGrid: handoff.isGrid,
      contentReveal: handoff.reveal,
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
