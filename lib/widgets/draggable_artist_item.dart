import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/widgets/drag/drag_cover.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';
import 'package:vynody/widgets/drag/drag_preview_card.dart';
import 'package:vynody/widgets/drag/drag_source.dart';

/// Wraps an artist item widget to provide system-level native drag source support.
///
/// Enables dragging an artist from the local library into the standalone queue
/// window or other apps. Dragging an artist that is part of a multi-selection
/// carries the songs of every selected artist.
class DraggableArtistItem extends StatelessWidget {
  final ArtistSummary artist;
  final Widget child;
  final bool enabled;
  final bool isSelectionMode;
  final bool isSelected;
  final List<ArtistSummary>? selectedArtists;

  const DraggableArtistItem({
    super.key,
    required this.artist,
    required this.child,
    this.enabled = true,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedArtists,
  });

  @override
  Widget build(BuildContext context) {
    // Non-null only while this artist is the anchor of a multi-selection, which
    // is also the only case where the drag carries more than one artist.
    final selection = selectedArtists;
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
        if (batch != null) {
          return SongPathsPayload.flattened(batch.map((item) => item.songs));
        }
        return SongPathsPayload(
          paths: [for (final song in artist.songs) song.path],
        );
      },
      buildPreview: (context) {
        final l10n = AppLocalizations.of(context)!;
        final representative = artist.representativeSong;
        final coverPath = resolveDragCoverPath(
          cachedImagePath: artist.cachedImagePath,
          thumbnailPath: representative.thumbnailPath,
          artworkPath: representative.artworkPath,
        );

        final batch = batchSelection;
        if (batch != null) {
          final totalSongs = batch.fold<int>(
            0,
            (sum, item) => sum + item.songs.length,
          );
          return AppDraggablePreviewCard(
            title: artist.name,
            subtitle:
                l10n.selectedArtistsWithTotalSongs(batch.length, totalSongs),
            imagePath: coverPath,
            defaultIcon: Icons.mic_rounded,
            badgeText: '${batch.length}',
            count: batch.length,
            isBatch: true,
          );
        }

        return AppDraggablePreviewCard(
          title: artist.name,
          subtitle: l10n.songsCountFormat(artist.songCount),
          imagePath: coverPath,
          defaultIcon: Icons.mic_rounded,
          badgeText: l10n.songsCountFormat(artist.songCount),
          count: artist.songCount,
        );
      },
      child: child,
    );
  }
}
