import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../player/library/playlist_service.dart';
import '../utils/playlist_name.dart';
import 'folder_layout_utils.dart';
import 'playlist_cover.dart';

/// 播放列表条目，随档位在「列表（封面在左）」与「网格（封面在上）」之间连续变形。
class PlaylistZoomItem extends StatelessWidget {
  const PlaylistZoomItem({
    super.key,
    required this.playlist,
    required this.metrics,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.enableHero = true,
    this.trailing,
    this.trailingWidth,
    this.subtitleText,
    this.titlePrefix,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.onPlay,
    this.onToggleSelect,
  });

  final Playlist playlist;
  final FolderZoomLayoutMetrics metrics;
  final bool isSelected;
  final bool isSelectionMode;
  final bool enableHero;
  final Widget? trailing;
  final double? trailingWidth;
  final String? subtitleText;
  final Widget? titlePrefix;
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
    final l10n = AppLocalizations.of(context)!;
    final gridMorph = metrics.gridMorph;

    final gridIconSize = switch (metrics.tier) {
      FolderZoomTier.smallGrid => 32.0,
      FolderZoomTier.mediumGrid => 40.0,
      FolderZoomTier.largeGrid || _ => 48.0,
    };
    final listIconSize = switch (metrics.tier) {
      FolderZoomTier.minimalList => 0.0,
      FolderZoomTier.compactList => 20.0,
      FolderZoomTier.standardList => 28.0,
      FolderZoomTier.largeList => 38.0,
      _ => 28.0,
    };
    final defaultIconSize = lerpDouble(listIconSize, gridIconSize, gridMorph)!;

    final coverWidget = PlaylistCover(
      playlist: playlist,
      size: 250,
      width: double.infinity,
      height: double.infinity,
      iconSize: defaultIconSize,
      enableHero: enableHero,
    );

    final cover = ZoomItemCover(
      metrics: metrics,
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      onToggleSelect: onToggleSelect ?? onTap,
      onPlay: playlist.songs.isNotEmpty ? onPlay : null,
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
      titleText: localizedPlaylistName(context, playlist),
      subtitleText: subtitleText ?? l10n.songCount(playlist.songs.length),
      titlePrefix: titlePrefix,
      trailing: trailing,
      trailingWidth: trailingWidth,
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
