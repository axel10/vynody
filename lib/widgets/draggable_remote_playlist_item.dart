import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';
import 'package:vynody/widgets/drag/drag_preview_card.dart';
import 'package:vynody/widgets/drag/drag_source.dart';

/// Wraps a remote playlist item widget (Navidrome / Jellyfin) to provide
/// system-level native drag source support.
///
/// Enables dragging a remote playlist into the queue drawer, the standalone
/// queue window, or custom playlists. Dragging a remote playlist that is part of
/// a multi-selection carries every selected playlist.
class DraggableRemotePlaylistItem extends StatelessWidget {
  final RemoteServer server;
  final Map<String, dynamic> playlist;
  final Widget child;
  final bool enabled;
  final bool isSelectionMode;
  final bool isSelected;
  final Set<String>? selectedPlaylistIds;
  final int? songCount;

  const DraggableRemotePlaylistItem({
    super.key,
    required this.server,
    required this.playlist,
    required this.child,
    this.enabled = true,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedPlaylistIds,
    this.songCount,
  });

  @override
  Widget build(BuildContext context) {
    // Non-null only while this playlist is the anchor of a multi-selection,
    // which is also the only case where the drag carries more than one playlist.
    final selection = selectedPlaylistIds;
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
        final playlistId = playlist['id'] as String? ?? '';
        return RemoteCollectionPayload([
          for (final id in batch ?? <String>{playlistId})
            RemoteCollectionRef(
              serverType: server.type,
              serverId: server.id,
              kind: RemoteCollectionKind.playlist,
              id: id,
            ),
        ]);
      },
      buildPreview: (context) {
        final l10n = AppLocalizations.of(context)!;
        final isJellyfin = server.type == RemoteServerType.jellyfin;
        final playlistName = playlist['name'] as String? ?? '未知歌单';
        final count = songCount ?? playlist['songCount'] as int? ?? 0;

        final batch = batchSelection;
        if (batch != null) {
          return AppDraggablePreviewCard(
            title: playlistName,
            subtitle: l10n.selectedPlaylistsCount(batch.length),
            defaultIcon: Icons.queue_music_rounded,
            badgeText: '${batch.length}',
            count: batch.length,
            isBatch: true,
          );
        }

        final serverLabel =
            isJellyfin ? l10n.jellyfinPlaylist : l10n.navidromePlaylist;
        return AppDraggablePreviewCard(
          title: playlistName,
          subtitle: count > 0 ? l10n.songsCountFormat(count) : serverLabel,
          defaultIcon: Icons.queue_music_rounded,
          badgeText: count > 0 ? l10n.songsCountFormat(count) : null,
          count: count > 0 ? count : 1,
        );
      },
      child: child,
    );
  }
}
