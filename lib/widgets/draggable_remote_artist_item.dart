import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';
import 'package:vynody/widgets/drag/drag_preview_card.dart';
import 'package:vynody/widgets/drag/drag_source.dart';

/// Wraps a remote artist item widget (Navidrome / Jellyfin) to provide
/// system-level native drag source support.
///
/// Enables dragging a remote artist into the queue drawer, the standalone queue
/// window, or custom playlists. Dragging a remote artist that is part of a
/// multi-selection carries every selected artist.
class DraggableRemoteArtistItem extends StatelessWidget {
  final RemoteServer server;
  final Map<String, dynamic> artist;
  final Widget child;
  final bool enabled;
  final bool isSelectionMode;
  final bool isSelected;
  final Set<String>? selectedArtistIds;

  const DraggableRemoteArtistItem({
    super.key,
    required this.server,
    required this.artist,
    required this.child,
    this.enabled = true,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedArtistIds,
  });

  @override
  Widget build(BuildContext context) {
    // Non-null only while this artist is the anchor of a multi-selection, which
    // is also the only case where the drag carries more than one artist.
    final selection = selectedArtistIds;
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
        final artistId = artist['id'] as String? ?? '';
        return RemoteCollectionPayload([
          for (final id in batch ?? <String>{artistId})
            RemoteCollectionRef(
              serverType: server.type,
              serverId: server.id,
              kind: RemoteCollectionKind.artist,
              id: id,
            ),
        ]);
      },
      buildPreview: (context) {
        final l10n = AppLocalizations.of(context)!;
        final isJellyfin = server.type == RemoteServerType.jellyfin;
        final artistName = artist['name'] as String? ?? '未知艺术家';
        final albumCount = artist['albumCount'] as int? ?? 0;

        final batch = batchSelection;
        if (batch != null) {
          return AppDraggablePreviewCard(
            title: artistName,
            subtitle: l10n.selectedArtistsCount(batch.length),
            defaultIcon: Icons.mic_rounded,
            badgeText: '${batch.length}',
            count: batch.length,
            isBatch: true,
          );
        }

        final serverLabel =
            isJellyfin ? l10n.jellyfinArtist : l10n.navidromeArtist;
        return AppDraggablePreviewCard(
          title: artistName,
          subtitle: albumCount > 0 ? l10n.albumCount(albumCount) : serverLabel,
          defaultIcon: Icons.mic_rounded,
          badgeText: albumCount > 0 ? l10n.albumCount(albumCount) : null,
          count: 1,
        );
      },
      child: child,
    );
  }
}
