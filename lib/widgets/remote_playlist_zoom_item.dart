import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../player/remote/remote_server_models.dart';
import 'folder_layout_utils.dart';
import 'remote_artwork_widget.dart';

/// 远程媒体库的歌单条目，与本地 [PlaylistZoomItem] 共用同一副骨架。
///
/// 不能直接复用 [PlaylistZoomItem] 的原因是封面来源不同：本地走
/// `SongThumbnail`（磁盘文件），远程走 `RemoteArtworkWidget`
/// （`subsonic-cover://` / `jellyfin-cover://` 封面 id）。但几何变形、
/// 选中浮层、列表↔网格连续 morph 全部交给 `ZoomItemScaffold` /
/// `ZoomItemCover`，所以两个页面看到的卡片和本地歌单页是同一套。
class RemotePlaylistZoomItem extends StatelessWidget {
  const RemotePlaylistZoomItem({
    super.key,
    required this.server,
    required this.password,
    required this.title,
    required this.songCount,
    required this.metrics,
    this.coverArtId,
    this.index,
    this.section,
    this.subtitleText,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isPinned = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.onPlay,
    this.onToggleSelect,
  });

  final RemoteServer server;
  final String password;
  final String title;
  final int songCount;
  final FolderZoomLayoutMetrics metrics;

  /// 服务端歌单封面 id，缺省时用图标兜底。
  final String? coverArtId;

  final int? index;
  final Object? section;

  /// 副标题覆盖（默认「N 首歌曲」）。
  final String? subtitleText;

  final bool isSelected;
  final bool isSelectionMode;

  /// 固定条目（星标歌曲这一虚拟歌单）：无封面时用红心图标，不与普通歌单混淆。
  final bool isPinned;

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

    // 网格态卡片宽度随档位变化，解码尺寸跟着走，避免大卡片用 44dp 的纹理糊掉。
    final double decodeSize =
        math.max(200.0, zoomItemThumbnailSizeFor(metrics));
    final hasCover = coverArtId != null && coverArtId!.isNotEmpty;

    final fallbackIcon =
        isPinned ? Icons.favorite_rounded : Icons.playlist_play_rounded;

    final Widget coverWidget;
    if (hasCover) {
      coverWidget = RemoteArtworkWidget(
        server: server,
        password: password,
        coverArtId: coverArtId,
        size: decodeSize,
        width: double.infinity,
        height: double.infinity,
        fallbackIcon: fallbackIcon,
      );
    } else {
      coverWidget = Container(
        color: isPinned
            ? Colors.redAccent.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Center(
          child: Icon(
            fallbackIcon,
            size: defaultIconSize,
            color: isPinned ? Colors.redAccent : theme.colorScheme.primary,
          ),
        ),
      );
    }

    final cover = ZoomItemCover(
      metrics: metrics,
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      onToggleSelect: onToggleSelect ?? onTap,
      onPlay: songCount > 0 ? onPlay : null,
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
      index: index,
      section: section,
      cover: cover,
      titleText: title,
      subtitleText: subtitleText ?? l10n.songCount(songCount),
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
