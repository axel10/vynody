import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'folder_layout_utils.dart';
import 'hoverable_card.dart';

/// 为单侧可见（原地淡入淡出）条目向子树下发锁定的稳态 [FolderZoomLayoutMetrics]。
class ZoomItemEffectiveMetrics extends InheritedWidget {
  const ZoomItemEffectiveMetrics({
    super.key,
    required this.metrics,
    required super.child,
  });

  final FolderZoomLayoutMetrics metrics;

  static FolderZoomLayoutMetrics? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ZoomItemEffectiveMetrics>()
        ?.metrics;
  }

  @override
  bool updateShouldNotify(ZoomItemEffectiveMetrics oldWidget) =>
      !identical(oldWidget.metrics, metrics);
}

/// Computed geometric layout for an item undergoing animated list-to-grid zoom morphing.
class ZoomItemLayout {
  final double coverLeft;
  final double coverTop;
  final double coverSize;
  final double textLeft;
  final double textTop;
  final double textWidth;
  final double textHeight;
  final double trailingSpace;
  final double listPadH;

  const ZoomItemLayout({
    required this.coverLeft,
    required this.coverTop,
    required this.coverSize,
    required this.textLeft,
    required this.textTop,
    required this.textWidth,
    required this.textHeight,
    required this.trailingSpace,
    required this.listPadH,
  });

  /// Computes the layout positions and dimensions for given constraints and zoom metrics.
  static ZoomItemLayout compute({
    required BoxConstraints constraints,
    required FolderZoomLayoutMetrics metrics,
    required bool isPortrait,
    double? trailingWidth,
    double selectionOffset = 0.0,
  }) {
    final gridMorph = metrics.gridMorph;
    final W = constraints.maxWidth;
    final H = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : metrics.animatedListExtent;

    final listPadH = isPortrait ? 12.0 : 16.0;
    final listCoverSize = getFolderListCoverSize(
      metrics.animatedZoomScale,
    ).clamp(0.0, math.max(0.0, H - 8.0));
    final listCoverLeft = listPadH;
    final listCoverTop = ((H - listCoverSize) / 2.0).clamp(0.0, H);

    final gridCoverSize = math.max(
      0.0,
      math.min(W, H - metrics.animatedGridTextHeight),
    );
    final gridCoverLeft = (W - gridCoverSize) / 2.0;
    const gridCoverTop = 0.0;

    final coverLeft = lerpDouble(listCoverLeft, gridCoverLeft, gridMorph)!;
    final coverTop = lerpDouble(listCoverTop, gridCoverTop, gridMorph)!;
    final coverSize = lerpDouble(listCoverSize, gridCoverSize, gridMorph)!;

    final trailingSpace = lerpDouble(trailingWidth ?? 0.0, 0.0, gridMorph)!;

    final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
    final listCoverGap = 16.0 * coverProgress;

    final listTextLeft =
        listCoverLeft + listCoverSize + listCoverGap + selectionOffset;
    final listTextHeight = math.max(listCoverSize, math.max(0.0, H - 8.0));
    final listTextTop = ((H - listTextHeight) / 2.0).clamp(0.0, H);
    final listTextWidth = math.max(
      0.0,
      W - listTextLeft - listPadH - trailingSpace,
    );

    const gridTextLeft = 0.0;
    final gridTextTop = gridCoverSize + 8.0;
    final gridTextWidth = W;
    final gridTextHeight = math.max(0.0, H - gridTextTop);

    final textLeft = lerpDouble(listTextLeft, gridTextLeft, gridMorph)!;
    final textTop = lerpDouble(listTextTop, gridTextTop, gridMorph)!;
    final textWidth = lerpDouble(listTextWidth, gridTextWidth, gridMorph)!;
    final textHeight = lerpDouble(listTextHeight, gridTextHeight, gridMorph)!;

    return ZoomItemLayout(
      coverLeft: coverLeft,
      coverTop: coverTop,
      coverSize: coverSize,
      textLeft: textLeft,
      textTop: textTop,
      textWidth: textWidth,
      textHeight: textHeight,
      trailingSpace: trailingSpace,
      listPadH: listPadH,
    );
  }
}

/// Typography resolution helper for zoom items across list and grid tiers.
class ZoomItemTypography {
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;

  const ZoomItemTypography({
    required this.titleStyle,
    required this.subtitleStyle,
  });

  /// Resolves the default title and subtitle text styles based on [FolderZoomLayoutMetrics].
  static ZoomItemTypography resolve({
    required BuildContext context,
    required FolderZoomLayoutMetrics metrics,
    Color? titleColor,
    Color? subtitleColor,
    FontWeight? listTitleFontWeight,
    double? listTitleFontSize,
  }) {
    final theme = Theme.of(context);
    final isPortrait = metrics.isPortrait;
    final isGridTarget = metrics.isGridTarget;

    if (!isGridTarget) {
      final title = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
        color: titleColor ?? theme.colorScheme.onSurface,
        fontWeight: listTitleFontWeight ?? FontWeight.w600,
        fontSize: listTitleFontSize ?? metrics.animatedTitleFontSize,
        height: 1.2,
      );
      final subtitle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: metrics.animatedSubtitleFontSize,
        color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
        height: 1.2,
      );
      return ZoomItemTypography(titleStyle: title, subtitleStyle: subtitle);
    } else {
      final title = ((isPortrait
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.titleMedium) ??
              const TextStyle())
          .copyWith(
        fontWeight: FontWeight.w600,
        fontSize: metrics.animatedTitleFontSize,
        color: titleColor ?? theme.colorScheme.onSurface,
        height: 1.25,
      );
      final subtitle =
          (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: metrics.animatedSubtitleFontSize,
        color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
        height: 1.2,
      );
      return ZoomItemTypography(titleStyle: title, subtitleStyle: subtitle);
    }
  }
}

/// Standard 2-line text column widget for a zoom item.
class ZoomItemDefaultTextColumn extends StatelessWidget {
  final String title;
  final String? subtitle;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;
  final double gridMorph;
  final Alignment alignment;
  final CrossAxisAlignment crossAxisAlignment;
  final Widget? titlePrefix;
  final Widget? titleSuffix;

  const ZoomItemDefaultTextColumn({
    super.key,
    required this.title,
    this.subtitle,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.gridMorph,
    this.alignment = Alignment.centerLeft,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.titlePrefix,
    this.titleSuffix,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: OverflowBox(
        minHeight: 0.0,
        maxHeight: double.infinity,
        alignment: alignment,
        child: Column(
          crossAxisAlignment: crossAxisAlignment,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (titlePrefix != null) ...[
                  titlePrefix!,
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                if (titleSuffix != null) ...[
                  const SizedBox(width: 4),
                  titleSuffix!,
                ],
              ],
            ),
            if (subtitle != null) ...[
              SizedBox(height: lerpDouble(4.0, 3.0, gridMorph)!),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subtitleStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Unified scaffold widget for all ZoomItem components.
///
/// Encapsulates:
/// - Smooth layout positioning and size interpolation between List and Grid tiers.
/// - InkWell and touch gesture handling, including unified [onContextMenu] fallback for both
///   desktop secondary-click and mobile long-press.
/// - Automatic [HoverableCard] wrapper in grid mode.
/// - Standard typography, text animations, and overflow protection.
class ZoomItemScaffold extends StatelessWidget {
  final FolderZoomLayoutMetrics metrics;
  final Widget? cover;
  final String? titleText;
  final String? subtitleText;
  final Widget? textColumn;

  /// 可选的高性能文本列构建器。
  ///
  /// 若提供，将在 [ZoomItemLayout.compute] 计算出文本区域具体尺寸后直接调用，
  /// 避免内容组件内部再套一层 [LayoutBuilder]，省去全屏条目在 layout 阶段挂起的开销。
  final Widget Function(BuildContext context, double textWidth, double textHeight)?
      textColumnBuilder;
  final Widget? trailing;
  final double? trailingWidth;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isHighlighted;
  final bool wrapHoverableCard;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(LongPressStartDetails details)? onLongPressStart;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final void Function(Offset position)? onContextMenu;
  final BorderRadius? borderRadius;
  final Color? titleColor;
  final Color? subtitleColor;
  final FontWeight? listTitleFontWeight;
  final double? listTitleFontSize;
  final CrossAxisAlignment? gridCrossAxisAlignment;
  final Alignment? gridAlignment;
  final double selectionOffset;
  final Widget? fallbackLeadingWhenNoCover;
  final Widget? titlePrefix;
  final Widget? titleSuffix;

  const ZoomItemScaffold({
    super.key,
    required this.metrics,
    this.cover,
    this.titleText,
    this.subtitleText,
    this.textColumn,
    this.textColumnBuilder,
    this.trailing,
    this.trailingWidth,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isHighlighted = false,
    this.wrapHoverableCard = true,
    this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onSecondaryTapDown,
    this.onContextMenu,
    this.borderRadius,
    this.titleColor,
    this.subtitleColor,
    this.listTitleFontWeight,
    this.listTitleFontSize,
    this.gridCrossAxisAlignment,
    this.gridAlignment,
    this.selectionOffset = 0.0,
    this.fallbackLeadingWhenNoCover,
    this.titlePrefix,
    this.titleSuffix,
  });

  static int? _findSliverChildIndex(BuildContext context) {
    RenderObject? current = context.findRenderObject();
    while (current != null) {
      final parentData = current.parentData;
      if (parentData is SliverMultiBoxAdaptorParentData) {
        return parentData.index;
      }
      current = current.parent;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final childIndex = _findSliverChildIndex(context);
        final transition = childIndex != null
            ? metrics.resolveItemTransition(childIndex)
            : null;
        final effectiveMetrics = transition?.effectiveMetrics ?? metrics;
        final isFadeScale = transition != null && !transition.isShared;

        final theme = Theme.of(context);
        final isPortrait = effectiveMetrics.isPortrait;
        final gridMorph = effectiveMetrics.gridMorph;
        final isGridTarget = effectiveMetrics.isGridTarget;

        final coverRadiusValue = lerpDouble(8.0, 14.0, gridMorph)!;
        final effectiveRadius =
            borderRadius ?? BorderRadius.circular(coverRadiusValue);

        // Compute text styles if not using a fully custom textColumn
        final typography = ZoomItemTypography.resolve(
          context: context,
          metrics: effectiveMetrics,
          titleColor: titleColor,
          subtitleColor: subtitleColor,
          listTitleFontWeight: listTitleFontWeight,
          listTitleFontSize: listTitleFontSize,
        );

        final defaultGridAlignment = gridAlignment ?? Alignment.topLeft;
        final textAlignAlignment = Alignment.lerp(
          Alignment.centerLeft,
          defaultGridAlignment,
          gridMorph,
        )!;
        final textCrossAlign = gridCrossAxisAlignment != null
            ? (gridMorph > 0.5
                ? gridCrossAxisAlignment!
                : CrossAxisAlignment.start)
            : CrossAxisAlignment.start;

        final effectiveTextColumn = textColumn ??
            (titleText != null
                ? ZoomItemDefaultTextColumn(
                    title: titleText!,
                    subtitle: subtitleText,
                    titleStyle: typography.titleStyle,
                    subtitleStyle: typography.subtitleStyle,
                    gridMorph: gridMorph,
                    alignment: textAlignAlignment,
                    crossAxisAlignment: textCrossAlign,
                    titlePrefix: titlePrefix,
                    titleSuffix: titleSuffix,
                  )
                : const SizedBox.shrink());

        // Resolve unified context menu callback
        final effectiveSecondaryTapDown = onSecondaryTapDown ??
            (onContextMenu != null
                ? (details) => onContextMenu!(details.globalPosition)
                : null);
        final effectiveLongPressStart = onLongPressStart ??
            (onContextMenu != null
                ? (details) => onContextMenu!(details.globalPosition)
                : null);
        final effectiveLongPress = onLongPress ??
            (onContextMenu != null ? () => onContextMenu!(Offset.zero) : null);

        final listBgAlpha = (1.0 - gridMorph).clamp(0.0, 1.0);
        final Color itemBgColor;
        if (isSelectionMode && isSelected && listBgAlpha > 0.01) {
          itemBgColor = theme.colorScheme.primaryContainer
              .withValues(alpha: 0.35 * listBgAlpha);
        } else if (isHighlighted && listBgAlpha > 0.01) {
          itemBgColor =
              theme.colorScheme.primary.withValues(alpha: 0.2 * listBgAlpha);
        } else {
          itemBgColor = Colors.transparent;
        }

        final effectiveSelectionOffset = isFadeScale
            ? ((isSelectionMode && gridMorph < 0.5)
                ? (28.0 *
                    (1.0 -
                        (getFolderListCoverSize(
                                  effectiveMetrics.animatedZoomScale,
                                ) /
                                40.0)
                            .clamp(0.0, 1.0)))
                : 0.0)
            : selectionOffset;

        final layout = ZoomItemLayout.compute(
          constraints: constraints,
          metrics: effectiveMetrics,
          isPortrait: isPortrait,
          trailingWidth: trailingWidth,
          selectionOffset: effectiveSelectionOffset,
        );

        final itemContent = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: effectiveSecondaryTapDown,
          onLongPressStart: effectiveLongPressStart,
          onLongPress: effectiveLongPress,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: itemBgColor,
              borderRadius: effectiveRadius,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: effectiveRadius,
              child: InkWell(
                borderRadius: effectiveRadius,
                enableFeedback: false,
                onTap: onTap,
                hoverColor: gridMorph < 0.5
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                    : Colors.transparent,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (layout.coverSize > 0.5 && cover != null)
                      Positioned(
                        left: layout.coverLeft,
                        top: layout.coverTop,
                        width: layout.coverSize,
                        height: layout.coverSize,
                        child: cover!,
                      )
                    else if (fallbackLeadingWhenNoCover != null &&
                        gridMorph < 0.5)
                      Positioned(
                        left: layout.coverLeft,
                        top: ((constraints.maxHeight.isFinite
                                        ? constraints.maxHeight
                                        : effectiveMetrics.animatedListExtent) -
                                    24.0) /
                                2.0,
                        width: 24.0,
                        height: 24.0,
                        child: fallbackLeadingWhenNoCover!,
                      ),
                    Positioned(
                      left: layout.textLeft,
                      top: layout.textTop,
                      width: layout.textWidth,
                      height: layout.textHeight,
                      child: textColumnBuilder != null
                          ? textColumnBuilder!(
                              context,
                              layout.textWidth,
                              layout.textHeight,
                            )
                          : effectiveTextColumn,
                    ),
                    if (gridMorph < 0.99 && trailing != null)
                      Positioned(
                        right: layout.listPadH,
                        top: 0,
                        bottom: 0,
                        child: Opacity(
                          opacity: (1.0 - gridMorph).clamp(0.0, 1.0),
                          child: Center(child: trailing),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );

        Widget result = wrapHoverableCard
            ? HoverableCard(
                enabled: isGridTarget,
                child: itemContent,
              )
            : itemContent;

        if (isFadeScale) {
          if (!identical(effectiveMetrics, metrics)) {
            result = ZoomItemEffectiveMetrics(
              metrics: effectiveMetrics,
              child: result,
            );
          }
          result = Opacity(
            opacity: transition.opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: transition.scale,
              alignment: Alignment.center,
              child: result,
            ),
          );
        }

        return result;
      },
    );
  }
}
