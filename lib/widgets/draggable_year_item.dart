import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/year_summary.dart';
import 'package:vynody/widgets/drag/drag_cover.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';
import 'package:vynody/widgets/drag/drag_preview_card.dart';
import 'package:vynody/widgets/drag/drag_source.dart';

/// Wraps a year item widget to provide system-level native drag source support.
///
/// Enables dragging a release year (and its songs) from the local library into
/// the standalone queue window or other apps. Dragging a year that is part of a
/// multi-selection carries the songs of every selected year.
class DraggableYearItem extends StatelessWidget {
  final YearSummary year;
  final Widget child;
  final bool enabled;
  final bool isSelectionMode;
  final bool isSelected;
  final List<YearSummary>? selectedYears;

  const DraggableYearItem({
    super.key,
    required this.year,
    required this.child,
    this.enabled = true,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedYears,
  });

  @override
  Widget build(BuildContext context) {
    // Non-null only while this year is the anchor of a multi-selection, which is
    // also the only case where the drag carries more than one year.
    final selection = selectedYears;
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
          paths: [for (final song in year.songs) song.path],
        );
      },
      buildPreview: (context) {
        final l10n = AppLocalizations.of(context)!;
        final label = year.labelWith(l10n.unknownYear);
        final coverPath = resolveDragCoverPath(
          thumbnailPath: year.representativeThumbnailPath,
          artworkPath: year.representativeArtworkPath,
        );

        final batch = batchSelection;
        if (batch != null) {
          final totalSongs = batch.fold<int>(
            0,
            (sum, item) => sum + item.songs.length,
          );
          return AppDraggablePreviewCard(
            title: label,
            subtitle: l10n.selectedYearsWithTotalSongs(batch.length, totalSongs),
            imagePath: coverPath,
            defaultIcon: Icons.calendar_month_rounded,
            badgeText: '${batch.length}',
            count: batch.length,
            isBatch: true,
          );
        }

        return AppDraggablePreviewCard(
          title: label,
          subtitle: l10n.songsCountFormat(year.songCount),
          imagePath: coverPath,
          defaultIcon: Icons.calendar_month_rounded,
          badgeText: l10n.songsCountFormat(year.songCount),
          count: year.songCount,
        );
      },
      child: child,
    );
  }
}
