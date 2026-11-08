import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';
import '../l10n/app_localizations.dart';
import '../widgets/song_thumbnail.dart';
import 'default_cover_art.dart';
import 'draggable_folder_item.dart';
import 'folder_layout_utils.dart';

/// Unified folder item widget that smoothly morphs between List View and Grid View
/// based on [FolderZoomLayoutMetrics].
class FolderZoomItem extends StatelessWidget {
  const FolderZoomItem({
    super.key,
    required this.folder,
    required this.metrics,
    this.songsCount = 0,
    this.representativeSong,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isSortMode = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.trailing,
    this.subtitle,
    this.customTitle,
    this.enableHero = true,
    this.isIndexed = false,
    this.index,
    this.section,
  });

  final MusicFolder folder;
  final FolderZoomLayoutMetrics metrics;
  final int? index;

  /// 本条目所属的网格段，必须与 `SliverAnimatedZoomGridDelegate.section` 一致。
  ///
  /// 一页里只有一个网格时留空即可；一页挂多个网格（目录 + 歌曲）时，冻结的
  /// 「单侧可见条目」表按段分开，索引才对得上。
  final Object? section;
  final int songsCount;
  final MusicFile? representativeSong;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isSortMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final Widget? trailing;
  final String? subtitle;
  final String? customTitle;
  final bool enableHero;
  final bool isIndexed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final gridMorph = metrics.gridMorph;

    final isSystem = folder.path == 'system';
    final gridIconSize = switch (metrics.tier) {
      FolderZoomTier.smallGrid => 32.0,
      FolderZoomTier.mediumGrid => 40.0,
      FolderZoomTier.largeGrid || _ => 48.0,
    };
    final listIconSize = switch (metrics.tier) {
      FolderZoomTier.minimalList => 0.0,
      FolderZoomTier.compactList => 22.0,
      FolderZoomTier.standardList => 28.0,
      FolderZoomTier.largeList => 38.0,
      _ => 28.0,
    };
    final defaultIconSize = lerpDouble(listIconSize, gridIconSize, gridMorph)!;
    final defaultCoverWidget = DefaultCoverArt.folder(
      isSystem: isSystem,
      iconSize: defaultIconSize,
    );

    Widget coverWidget;
    if (representativeSong != null) {
      coverWidget = SongThumbnail.fromSong(
        representativeSong!,
        size: zoomItemThumbnailSizeFor(metrics),
        width: double.infinity,
        height: double.infinity,
        borderRadius: BorderRadius.zero,
        fallbackWidget: defaultCoverWidget,
      );
    } else {
      coverWidget = defaultCoverWidget;
    }

    Widget? indexBadge;
    if (isIndexed) {
      indexBadge = Positioned(
        top: lerpDouble(3.0, 8.0, gridMorph)!,
        right: lerpDouble(3.0, 8.0, gridMorph)!,
        child: Tooltip(
          message: l10n.remoteFolderAlreadyIndexed,
          child: Container(
            padding: EdgeInsets.all(lerpDouble(3.0, 4.5, gridMorph)!),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
                width: 0.8,
              ),
            ),
            child: Icon(
              Icons.library_add_check_rounded,
              size: lerpDouble(11.0, 13.0, gridMorph)!,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }

    final cover = ZoomItemCover(
      metrics: metrics,
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      onToggleSelect: onTap,
      badge: indexBadge,
      child: coverWidget,
    );

    final heroCover = cover;

    final listCoverSize = getFolderListCoverSize(metrics.animatedZoomScale);
    final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
    final selectionOffset = (isSelectionMode && gridMorph < 0.5)
        ? (28.0 * (1.0 - coverProgress))
        : 0.0;

    final titleColor = isSelectionMode && isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    final Widget? fallbackLeading = isSelectionMode && gridMorph < 0.5
        ? Checkbox(
            value: isSelected,
            onChanged: (_) => onTap?.call(),
            fillColor: WidgetStateProperty.all(Colors.white),
            checkColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          )
        : null;

    final scaffold = ZoomItemScaffold(
      metrics: metrics,
      index: index,
      section: section,
      cover: heroCover,
      titleText: customTitle ?? folder.name,
      subtitleText: subtitle ?? l10n.songsCountFormat(songsCount),
      titleColor: titleColor,
      listTitleFontWeight: FontWeight.normal,
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      selectionOffset: selectionOffset,
      trailing: trailing,
      trailingWidth: trailing != null ? 44.0 : 0.0,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTapDown: onSecondaryTapDown,
      fallbackLeadingWhenNoCover: fallbackLeading,
    );

    final String folderA11yLabel =
        '${customTitle ?? folder.name}, ${subtitle ?? l10n.songsCountFormat(songsCount)}';

    return Semantics(
      container: true,
      button: true,
      label: folderA11yLabel,
      selected: isSelectionMode ? isSelected : null,
      child: ExcludeSemantics(
        child: DraggableFolderItem(
          folder: folder,
          songsCount: songsCount,
          representativeSong: representativeSong,
          enabled: !isSelectionMode && !isSortMode,
          child: scaffold,
        ),
      ),
    );
  }
}
