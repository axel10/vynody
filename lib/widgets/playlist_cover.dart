import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../player/library/playlist_service.dart';
import 'default_cover_art.dart';
import 'song_thumbnail.dart';

/// 统一的本地播放列表封面组件
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({
    super.key,
    required this.playlist,
    this.size = 250,
    this.width,
    this.height,
    this.borderRadius = 8.0,
    this.enableHero = false,
    this.iconSize,
  });

  final Playlist playlist;
  final double size;
  final double? width;
  final double? height;
  final double borderRadius;
  final bool enableHero;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isFavorite = playlist.id == PlaylistService.favoritePlaylistId;
    final hasSongs = playlist.songs.isNotEmpty;

    Widget buildEmptyFavorite(double resolvedSide) {
      final effectiveIconSize = iconSize ?? (resolvedSide * 0.4).clamp(16.0, 72.0);
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    Colors.red.shade900.withValues(alpha: 0.6),
                    Colors.pink.shade900.withValues(alpha: 0.4),
                  ]
                : [
                    Colors.red.shade100,
                    Colors.pink.shade50,
                  ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.favorite_rounded,
            color: isDark ? Colors.red.shade300 : Colors.red.shade400,
            size: effectiveIconSize,
          ),
        ),
      );
    }

    Widget buildEmptyPlaylist(double resolvedSide) {
      final effectiveIconSize = iconSize ?? (resolvedSide * 0.4).clamp(16.0, 72.0);
      return Container(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Center(
          child: DefaultCoverArt(
            type: CoverArtType.folder,
            customIcon: Icons.queue_music_rounded,
            iconSize: effectiveIconSize,
          ),
        ),
      );
    }

    Widget resolveEmptyContent(Widget Function(double side) builder) {
      if (iconSize != null) {
        return builder(size);
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final side = (constraints.maxWidth.isFinite && constraints.maxHeight.isFinite)
              ? math.min(constraints.maxWidth, constraints.maxHeight)
              : (constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : (constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : size));
          return builder(side);
        },
      );
    }

    Widget content;

    if (isFavorite) {
      if (hasSongs) {
        content = Stack(
          fit: StackFit.expand,
          children: [
            SongThumbnail.fromSong(
              playlist.songs.first,
              size: size,
              width: double.infinity,
              height: double.infinity,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Colors.redAccent.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Positioned(
              top: (width != null && width! < 60) ? 4 : 8,
              right: (width != null && width! < 60) ? 4 : 8,
              child: Container(
                padding: EdgeInsets.all((width != null && width! < 60) ? 2.5 : 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.favorite_rounded,
                  color: Colors.redAccent,
                  size: (width != null && width! < 60) ? 10 : 14,
                ),
              ),
            ),
          ],
        );
      } else {
        content = resolveEmptyContent(buildEmptyFavorite);
      }
    } else {
      if (hasSongs) {
        content = SongThumbnail.fromSong(
          playlist.songs.first,
          size: size,
          width: double.infinity,
          height: double.infinity,
        );
      } else {
        content = resolveEmptyContent(buildEmptyPlaylist);
      }
    }

    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width ?? size,
        height: height ?? size,
        child: content,
      ),
    );

    if (enableHero) {
      return Hero(
        tag: 'playlist-cover-${playlist.id}',
        child: clipped,
      );
    }

    return clipped;
  }
}
