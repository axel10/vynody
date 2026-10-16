import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/genre_summary.dart';
import 'package:vynody/widgets/drag/drag_cover.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';
import 'package:vynody/widgets/drag/drag_preview_card.dart';
import 'package:vynody/widgets/drag/drag_source.dart';

/// Wraps a genre item widget to provide system-level native drag source support.
///
/// Enables dragging a genre from the local library into the standalone queue
/// window or other apps. Dragging a genre that is part of a multi-selection
/// carries the songs of every selected genre.
class DraggableGenreItem extends StatelessWidget {
  final GenreSummary genre;
  final Widget child;
  final bool enabled;
  final bool isSelectionMode;
  final bool isSelected;
  final List<GenreSummary>? selectedGenres;

  const DraggableGenreItem({
    super.key,
    required this.genre,
    required this.child,
    this.enabled = true,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedGenres,
  });

  @override
  Widget build(BuildContext context) {
    // Non-null only while this genre is the anchor of a multi-selection, which
    // is also the only case where the drag carries more than one genre.
    final selection = selectedGenres;
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
          paths: [for (final song in genre.songs) song.path],
        );
      },
      buildPreview: (context) {
        final l10n = AppLocalizations.of(context)!;
        final coverPath = resolveDragCoverPath(
          thumbnailPath: genre.representativeThumbnailPath,
          artworkPath: genre.representativeArtworkPath,
        );

        final batch = batchSelection;
        if (batch != null) {
          final totalSongs = batch.fold<int>(
            0,
            (sum, item) => sum + item.songs.length,
          );
          return AppDraggablePreviewCard(
            title: genre.name,
            subtitle:
                l10n.selectedGenresWithTotalSongs(batch.length, totalSongs),
            imagePath: coverPath,
            defaultIcon: Icons.style_rounded,
            badgeText: '${batch.length}',
            count: batch.length,
            isBatch: true,
          );
        }

        return AppDraggablePreviewCard(
          title: genre.name,
          subtitle: l10n.songsCountFormat(genre.songCount),
          imagePath: coverPath,
          defaultIcon: Icons.style_rounded,
          badgeText: l10n.songsCountFormat(genre.songCount),
          count: genre.songCount,
        );
      },
      child: child,
    );
  }
}
