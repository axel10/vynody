import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/utils/playlist_name.dart';
import 'package:vynody/widgets/drag/drag_cover.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';
import 'package:vynody/widgets/drag/drag_preview_card.dart';
import 'package:vynody/widgets/drag/drag_source.dart';

/// Wraps a local playlist item widget to provide system-level native drag source support.
///
/// Enables dragging a playlist into the queue drawer, the standalone queue
/// window, or custom playlists. Dragging a playlist that is part of a
/// multi-selection carries every song from all selected playlists.
class DraggablePlaylistItem extends StatelessWidget {
  final Playlist playlist;
  final Widget child;
  final bool enabled;
  final bool isSelectionMode;
  final bool isSelected;
  final List<Playlist>? selectedPlaylists;

  const DraggablePlaylistItem({
    super.key,
    required this.playlist,
    required this.child,
    this.enabled = true,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedPlaylists,
  });

  @override
  Widget build(BuildContext context) {
    final selection = selectedPlaylists;
    final batchSelection =
        (isSelectionMode &&
            isSelected &&
            selection != null &&
            selection.length > 1)
        ? selection
        : null;

    return DragSource(
      enabled: enabled,
      buildPayload: () {
        final batch = batchSelection;
        if (batch != null) {
          return SongPathsPayload.flattened(batch.map((p) => p.songs));
        }
        return SongPathsPayload(
          paths: [for (final song in playlist.songs) song.path],
        );
      },
      buildPreview: (context) {
        final l10n = AppLocalizations.of(context)!;
        final playlistName = localizedPlaylistName(context, playlist);
        final count = playlist.songs.length;
        final isFavorite = playlist.id == PlaylistService.favoritePlaylistId;

        final batch = batchSelection;
        if (batch != null) {
          return AppDraggablePreviewCard(
            title: playlistName,
            subtitle: l10n.selectedPlaylistsCount(batch.length),
            defaultIcon: isFavorite
                ? Icons.favorite_rounded
                : Icons.queue_music_rounded,
            badgeText: '${batch.length}',
            count: batch.length,
            isBatch: true,
          );
        }

        final representative =
            playlist.songs.firstWhereOrNull(
              (s) =>
                  (s.thumbnailPath != null && s.thumbnailPath!.isNotEmpty) ||
                  (s.artworkPath != null && s.artworkPath!.isNotEmpty),
            ) ??
            playlist.songs.firstOrNull;

        final coverPath = representative != null
            ? resolveDragCoverPath(
                thumbnailPath: representative.thumbnailPath,
                artworkPath: representative.artworkPath,
              )
            : null;

        return AppDraggablePreviewCard(
          title: playlistName,
          subtitle: count > 0 ? l10n.songsCountFormat(count) : null,
          imagePath: coverPath,
          defaultIcon: isFavorite
              ? Icons.favorite_rounded
              : Icons.queue_music_rounded,
          badgeText: count > 0 ? l10n.songsCountFormat(count) : null,
          count: count > 0 ? count : 1,
        );
      },
      child: child,
    );
  }
}
