import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../models/album_summary.dart';
import 'cover_play_button.dart';
import 'folder_layout_utils.dart';
import 'hoverable_card.dart';
import 'remote_media_badge.dart';
import 'song_thumbnail.dart';

/// 专辑条目，随档位在「列表（封面在左）」与「网格（封面在上）」之间连续变形。
///
/// 与 [FolderZoomItem] / [SongZoomItem] 共用同一套几何口径（[FolderZoomLayoutMetrics]）：
/// 封面/文字的位置全部由 `gridMorph` 插值，字号在网格侧按**卡片宽度**分档
/// （[folderGridFontSizes]），不在列表侧也跟着放缩。
///
/// 与 [AlbumGridCard] 的分工：后者是固定尺寸的卡片（3D cover flow、远程库等仍在用），
/// 本控件只服务"档位驱动"的专辑网格。
class AlbumZoomItem extends StatefulWidget {
  const AlbumZoomItem({
    super.key,
    required this.album,
    required this.metrics,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.enableHero = true,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.onPlay,
    this.onToggleSelect,
  });

  final AlbumSummary album;
  final FolderZoomLayoutMetrics metrics;
  final bool isSelected;
  final bool isSelectionMode;
  final bool enableHero;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails details)? onSecondaryTapDown;

  /// 网格档位下封面右下角的悬浮播放按钮。
  final VoidCallback? onPlay;

  /// 多选态下直接切换选中（未提供时回落到 [onTap]）。
  final VoidCallback? onToggleSelect;

  @override
  State<AlbumZoomItem> createState() => _AlbumZoomItemState();
}

class _AlbumZoomItemState extends State<AlbumZoomItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = widget.metrics;
    final album = widget.album;

    final gridMorph = metrics.gridMorph;
    final isGridTarget = metrics.isGridTarget;

    final coverRadiusValue = lerpDouble(8.0, 12.0, gridMorph)!;
    final coverRadius = BorderRadius.circular(coverRadiusValue);

    Widget coverWidget = RemoteMediaBadge.wrapCover(
      child: SongThumbnail.fromAlbum(
        album,
        size: 250,
        width: double.infinity,
        height: double.infinity,
        borderRadius: coverRadius,
      ),
      songs: album.songs,
      title: album.title,
      top: lerpDouble(4.0, 8.0, gridMorph)!,
      right: lerpDouble(4.0, 8.0, gridMorph)!,
    );
    if (widget.enableHero) {
      coverWidget = Hero(
        tag: 'album-cover-${album.id}',
        child: coverWidget,
      );
    }

    final isSelected = widget.isSelected;

    final coverStack = ExcludeSemantics(
      child: ClipRRect(
        borderRadius: coverRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            coverWidget,
            if (widget.isSelectionMode)
              Positioned.fill(
                child: Container(
                  color: isSelected
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                      : Colors.black26,
                ),
              ),
            if (widget.isSelectionMode)
              Align(
                alignment: Alignment.lerp(
                  Alignment.center,
                  Alignment.topLeft,
                  gridMorph,
                )!,
                child: Padding(
                  padding: EdgeInsets.all(lerpDouble(0.0, 8.0, gridMorph)!),
                  child: SizedBox(
                    width: lerpDouble(32.0, 28.0, gridMorph)!,
                    height: lerpDouble(32.0, 28.0, gridMorph)!,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) =>
                          (widget.onToggleSelect ?? widget.onTap)?.call(),
                      fillColor: WidgetStateProperty.all(Colors.white),
                      checkColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            if (!widget.isSelectionMode && widget.onPlay != null)
              Positioned(
                right: lerpDouble(0.0, 8.0, gridMorph)!,
                bottom: lerpDouble(0.0, 8.0, gridMorph)!,
                child: IgnorePointer(
                  ignoring: !(isGridTarget && _isHovered),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: isGridTarget && _isHovered ? 1.0 : 0.0,
                    child: CoverPlayButton(
                      size: 36,
                      iconSize: 22,
                      onTap: widget.onPlay!,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // 字号：列表侧与宽度无关，网格侧按卡片宽度分档。
    final titleColor = widget.isSelectionMode && isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    final listCoverSize = getFolderListCoverSize(metrics.animatedZoomScale);
    final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
    final selectionOffset = (widget.isSelectionMode && gridMorph < 0.5)
        ? (28.0 * (1.0 - coverProgress))
        : 0.0;

    final scaffold = ZoomItemScaffold(
      metrics: metrics,
      cover: coverStack,
      titleText: album.title,
      subtitleText: album.artist,
      titleColor: titleColor,
      listTitleFontWeight: FontWeight.normal,
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      selectionOffset: selectionOffset,
      wrapHoverableCard: false,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTapDown: widget.onSecondaryTapDown,
      fallbackLeadingWhenNoCover: widget.isSelectionMode && gridMorph < 0.5
          ? Checkbox(
              value: isSelected,
              onChanged: (_) =>
                  (widget.onToggleSelect ?? widget.onTap)?.call(),
              fillColor: WidgetStateProperty.all(Colors.white),
              checkColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            )
          : null,
    );

    // 悬停态只在网格档位有意义（列表档位用 InkWell 的 hoverColor）。
    return MouseRegion(
      onEnter: (_) {
        if (isGridTarget && !_isHovered) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (_isHovered) setState(() => _isHovered = false);
      },
      cursor: SystemMouseCursors.click,
      child: isGridTarget ? HoverableCard(child: scaffold) : scaffold,
    );
  }
}
