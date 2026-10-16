import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/widgets/drag/drag_cover.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';
import 'package:vynody/widgets/drag/drag_preview_card.dart';
import 'package:vynody/widgets/drag/drag_source.dart';

/// Wraps an album card widget to provide system-level native drag source support.
///
/// Enables dragging an album from library/album pages into the standalone queue
/// window or other apps.
class DraggableAlbumItem extends StatelessWidget {
  final AlbumSummary album;
  final Widget child;
  final bool enabled;

  const DraggableAlbumItem({
    super.key,
    required this.album,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return DragSource(
      enabled: enabled,
      buildPayload: () => SongPathsPayload(
        paths: [for (final song in album.songs) song.path],
      ),
      buildPreview: (context) {
        final l10n = AppLocalizations.of(context)!;
        final representative = album.representativeSong;
        return AppDraggablePreviewCard(
          title: album.title,
          subtitle: album.artist,
          imagePath: resolveDragCoverPath(
            thumbnailPath: representative.thumbnailPath,
            artworkPath: representative.artworkPath,
          ),
          defaultIcon: Icons.album_rounded,
          badgeText: l10n.songsCountFormat(album.trackCount),
          count: album.trackCount,
        );
      },
      child: child,
    );
  }
}
