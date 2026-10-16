import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';
import 'package:vynody/widgets/drag/drag_preview_card.dart';
import 'package:vynody/widgets/drag/drag_source.dart';

/// Wraps a remote album item widget (Navidrome / Jellyfin) to provide
/// system-level native drag source support.
///
/// Enables dragging a remote album into the queue drawer, the standalone queue
/// window, or custom playlists. Dragging a remote album that is part of a
/// multi-selection carries every selected album.
///
/// No artwork is shown in the preview: remote covers would have to be fetched
/// over the network, and the preview is snapshotted the moment the drag starts.
class DraggableRemoteAlbumItem extends StatelessWidget {
  final RemoteServer server;
  final String albumId;
  final String title;
  final String artist;
  final int? songCount;
  final Widget child;
  final bool enabled;
  final bool isSelectionMode;
  final bool isSelected;
  final Set<String>? selectedAlbumIds;

  const DraggableRemoteAlbumItem({
    super.key,
    required this.server,
    required this.albumId,
    required this.title,
    required this.artist,
    this.songCount,
    required this.child,
    this.enabled = true,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedAlbumIds,
  });

  @override
  Widget build(BuildContext context) {
    // Non-null only while this album is the anchor of a multi-selection, which
    // is also the only case where the drag carries more than one album.
    final selection = selectedAlbumIds;
    final batchSelection = (isSelectionMode &&
            isSelected &&
            selection != null &&
            selection.length > 1)
        ? selection
        : null;

    return DragSource(
      enabled: enabled,
      buildPayload: () {
        final batch = batchSelection;
        return RemoteCollectionPayload([
          for (final id in batch ?? <String>{albumId})
            RemoteCollectionRef(
              serverType: server.type,
              serverId: server.id,
              kind: RemoteCollectionKind.album,
              id: id,
            ),
        ]);
      },
      buildPreview: (context) {
        final l10n = AppLocalizations.of(context)!;
        final isJellyfin = server.type == RemoteServerType.jellyfin;

        final batch = batchSelection;
        if (batch != null) {
          return AppDraggablePreviewCard(
            title: title,
            subtitle: l10n.selectedAlbumsCount(batch.length),
            defaultIcon: Icons.album_rounded,
            badgeText: '${batch.length}',
            count: batch.length,
            isBatch: true,
          );
        }

        return AppDraggablePreviewCard(
          title: title,
          subtitle: artist.isNotEmpty
              ? artist
              : (isJellyfin ? l10n.jellyfinAlbum : l10n.navidromeAlbum),
          defaultIcon: Icons.album_rounded,
          badgeText: songCount != null && songCount! > 0
              ? l10n.songsCountFormat(songCount!)
              : null,
          count: songCount ?? 1,
        );
      },
      child: child,
    );
  }
}
