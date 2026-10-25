import 'package:flutter/material.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/widgets/song_thumbnail.dart';
import 'package:vynody/widgets/remote_media_badge.dart';

/// A reusable album cover artwork widget.
///
/// Encapsulates [SongThumbnail.fromAlbum], default rounded corners,
/// and optional [Hero] animation tagging.
class AlbumCover extends StatelessWidget {
  const AlbumCover({
    super.key,
    required this.album,
    this.size = 120.0,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.enableHero = false,
    this.heroTag,
    this.showRemoteBadge = true,
  });

  /// Whether to display a remote badge if all songs are from a remote media library.
  final bool showRemoteBadge;

  /// The album data.
  final AlbumSummary album;

  /// Square dimensions if [width] and [height] are omitted.
  final double size;

  /// Custom width override.
  final double? width;

  /// Custom height override.
  final double? height;

  /// Corner radius of the album cover.
  final BorderRadius? borderRadius;

  /// Whether to wrap this cover in a [Hero] widget for page transitions.
  final bool enableHero;

  /// Custom hero tag. Defaults to `'album-cover-${album.id}'` when [enableHero] is true.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    // Hero 动画已全局禁用，直接使用原始封面组件
    Widget cover = SongThumbnail.fromAlbum(
      album,
      size: size,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );

    final double effectiveSize = width ?? height ?? size;
    return RemoteMediaBadge.wrapCover(
      child: cover,
      songs: album.songs,
      title: album.title,
      top: effectiveSize < 70 ? 4.0 : 6.0,
      right: effectiveSize < 70 ? 4.0 : 6.0,
      iconSize: effectiveSize < 70 ? 11.0 : 13.0,
      padding: effectiveSize < 70 ? 3.0 : 4.0,
      showRemoteBadge: showRemoteBadge,
    );
  }
}
