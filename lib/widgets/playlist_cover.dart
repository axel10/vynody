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
  });

  final Playlist playlist;
  final double size;
  final double? width;
  final double? height;
  final double borderRadius;
  final bool enableHero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isFavorite = playlist.id == PlaylistService.favoritePlaylistId;
    final hasSongs = playlist.songs.isNotEmpty;

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
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.redAccent,
                  size: 14,
                ),
              ),
            ),
          ],
        );
      } else {
        content = Container(
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
              size: (size * 0.4).clamp(18.0, 72.0),
            ),
          ),
        );
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
        content = Container(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Center(
            child: DefaultCoverArt(
              type: CoverArtType.folder,
              customIcon: Icons.queue_music_rounded,
              iconSize: (size * 0.4).clamp(18.0, 72.0),
            ),
          ),
        );
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
