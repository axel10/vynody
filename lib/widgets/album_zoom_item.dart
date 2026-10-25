import 'package:flutter/material.dart';

import '../models/album_summary.dart';
import 'folder_layout_utils.dart';
import 'remote_media_badge.dart';
import 'song_thumbnail.dart';

/// 专辑条目，随档位在「列表（封面在左）」与「网格（封面在上）」之间连续变形。
class AlbumZoomItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gridMorph = metrics.gridMorph;

    Widget thumbnail = SongThumbnail.fromAlbum(
      album,
      size: 250,
      width: double.infinity,
      height: double.infinity,
    );
    if (enableHero) {
      thumbnail = Hero(
        tag: 'album-cover-${album.id}',
        child: thumbnail,
      );
    }

    final coverWidget = RemoteMediaBadge.wrapCover(
      songs: album.songs,
      title: album.title,
      top: 4.0,
      right: 4.0,
      child: thumbnail,
    );

    final cover = ZoomItemCover(
      metrics: metrics,
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      onToggleSelect: onToggleSelect ?? onTap,
      onPlay: onPlay,
      child: coverWidget,
    );

    final titleColor = isSelectionMode && isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    final listCoverSize = getFolderListCoverSize(metrics.animatedZoomScale);
    final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
    final selectionOffset = (isSelectionMode && gridMorph < 0.5)
        ? (28.0 * (1.0 - coverProgress))
        : 0.0;

    return ZoomItemScaffold(
      metrics: metrics,
      cover: cover,
      titleText: album.title,
      subtitleText: album.artist,
      titleColor: titleColor,
      listTitleFontWeight: FontWeight.normal,
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      selectionOffset: selectionOffset,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTapDown: onSecondaryTapDown,
      fallbackLeadingWhenNoCover: isSelectionMode && gridMorph < 0.5
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => (onToggleSelect ?? onTap)?.call(),
              fillColor: WidgetStateProperty.all(Colors.white),
              checkColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            )
          : null,
    );
  }
}
