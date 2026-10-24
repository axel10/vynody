import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'folder_layout_utils.dart';
import 'hoverable_card.dart';

/// 媒体库条目通用形变容器。
///
/// 封装了随档位（[FolderZoomLayoutMetrics]）在「列表（左侧封面/头像）」与
/// 「网格（上方居中封面/头像）」之间连续插值的完整几何计算与动效，统一处理：
/// - 列表/网格形态切换时的绝对坐标插值；
/// - 列表多选时选中项背景色高亮；
/// - 极小列表态（封面完全缩小至 0）下的 fallback 复选框位置；
/// - 网格态下的卡片悬停反馈（[HoverableCard]）与列表态下的水波纹。
class LibraryZoomCardLayout extends StatefulWidget {
  const LibraryZoomCardLayout({
    super.key,
    required this.metrics,
    required this.cover,
    required this.text,
    this.fallbackCheckbox,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.borderRadius = 8.0,
    this.enableHoverCard = true,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
  });

  final FolderZoomLayoutMetrics metrics;
  final Widget cover;
  final Widget text;
  final Widget? fallbackCheckbox;
  final bool isSelected;
  final bool isSelectionMode;
  final double borderRadius;
  final bool enableHoverCard;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails details)? onSecondaryTapDown;

  @override
  State<LibraryZoomCardLayout> createState() => _LibraryZoomCardLayoutState();
}

class _LibraryZoomCardLayoutState extends State<LibraryZoomCardLayout> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final metrics = widget.metrics;
    final gridMorph = metrics.gridMorph;
    final isGridTarget = metrics.isGridTarget;

    final listBgAlpha = (1.0 - gridMorph).clamp(0.0, 1.0);

    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: widget.onSecondaryTapDown,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.isSelectionMode && widget.isSelected && listBgAlpha > 0.01
              ? theme.colorScheme.primaryContainer
                  .withValues(alpha: 0.35 * listBgAlpha)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            enableFeedback: false,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            hoverColor: gridMorph < 0.5
                ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                : Colors.transparent,
            child: LayoutBuilder(
              builder: (context, constraints) {
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

                final coverLeft =
                    lerpDouble(listCoverLeft, gridCoverLeft, gridMorph)!;
                final coverTop =
                    lerpDouble(listCoverTop, gridCoverTop, gridMorph)!;
                final coverSize =
                    lerpDouble(listCoverSize, gridCoverSize, gridMorph)!;

                final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
                final listCoverGap = 16.0 * coverProgress;
                final selectionOffset =
                    (widget.isSelectionMode && gridMorph < 0.5)
                        ? (28.0 * (1.0 - coverProgress))
                        : 0.0;

                final listTextLeft = listCoverLeft +
                    listCoverSize +
                    listCoverGap +
                    selectionOffset;
                final listTextHeight =
                    math.max(listCoverSize, math.max(0.0, H - 8.0));
                final listTextTop = ((H - listTextHeight) / 2.0).clamp(0.0, H);
                final listTextWidth =
                    math.max(0.0, W - listTextLeft - listPadH);

                const gridTextLeft = 0.0;
                final gridTextTop = gridCoverSize + 4.0;
                final gridTextWidth = W;
                final gridTextHeight = math.max(0.0, H - gridTextTop);

                final textLeft =
                    lerpDouble(listTextLeft, gridTextLeft, gridMorph)!;
                final textTop =
                    lerpDouble(listTextTop, gridTextTop, gridMorph)!;
                final textWidth =
                    lerpDouble(listTextWidth, gridTextWidth, gridMorph)!;
                final textHeight =
                    lerpDouble(listTextHeight, gridTextHeight, gridMorph)!;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (coverSize > 0.5)
                      Positioned(
                        left: coverLeft,
                        top: coverTop,
                        width: coverSize,
                        height: coverSize,
                        child: widget.cover,
                      )
                    else if (widget.isSelectionMode &&
                        gridMorph < 0.5 &&
                        widget.fallbackCheckbox != null)
                      Positioned(
                        left: listCoverLeft,
                        top: ((H - 24.0) / 2.0).clamp(0.0, H),
                        width: 24.0,
                        height: 24.0,
                        child: widget.fallbackCheckbox!,
                      ),
                    Positioned(
                      left: textLeft,
                      top: textTop,
                      width: textWidth,
                      height: textHeight,
                      child: widget.text,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    if (!widget.enableHoverCard) {
      return content;
    }

    return MouseRegion(
      onEnter: (_) {
        if (isGridTarget && !_isHovered) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (_isHovered) setState(() => _isHovered = false);
      },
      cursor: SystemMouseCursors.click,
      child: isGridTarget ? HoverableCard(child: content) : content,
    );
  }
}
