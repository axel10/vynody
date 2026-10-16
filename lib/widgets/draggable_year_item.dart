import 'dart:io';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/year_summary.dart';
import 'package:vynody/widgets/draggable_preview_card.dart';

/// Wraps a year item widget to provide system-level native drag source support.
/// Enables dragging a release year (and its songs) from the local library into
/// the standalone queue window or other apps.
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
    if (!enabled || !DesktopDraggableWrapper.isPlatformSupported) {
      return child;
    }

    final l10n = AppLocalizations.of(context)!;
    final label = year.labelWith(l10n.unknownYear);

    final isBatch = isSelectionMode &&
        isSelected &&
        selectedYears != null &&
        selectedYears!.length > 1;

    final hasThumb = year.representativeThumbnailPath != null &&
        year.representativeThumbnailPath!.isNotEmpty &&
        File(year.representativeThumbnailPath!).existsSync();
    final hasArt = year.representativeArtworkPath != null &&
        year.representativeArtworkPath!.isNotEmpty &&
        File(year.representativeArtworkPath!).existsSync();
    final coverPath = hasThumb
        ? year.representativeThumbnailPath
        : (hasArt ? year.representativeArtworkPath : null);

    return DesktopDraggableWrapper(
      enabled: enabled,
      dragItemProvider: (request) async {
        debugPrint(
            '[DRAG] DraggableYearItem.dragItemProvider called for: $label (${year.songs.length} songs, isBatch: $isBatch)');
        final List<String> songPaths;
        if (isBatch) {
          final set = <String>{};
          for (final y in selectedYears!) {
            for (final s in y.songs) {
              set.add(s.path);
            }
          }
          songPaths = set.toList();
        } else {
          songPaths = year.songs.map((s) => s.path).toList();
        }

        final item = DragItem(
          localData: <String, dynamic>{
            'type': 'year',
            'id': year.queryKey,
            'name': label,
            'paths': songPaths,
            'count': songPaths.length,
          },
        );
        if (songPaths.isNotEmpty) {
          final first = songPaths.first;
          if (File(first).existsSync()) {
            item.add(Formats.fileUri(Uri.file(first)));
          }
          item.add(Formats.plainText(songPaths.join('\n')));
        }
        request.session.dragCompleted.addListener(() {
          final op = request.session.dragCompleted.value;
          debugPrint(
              '[DRAG] DraggableYearItem drag completed for "$label". Result operation: $op');
        });
        return item;
      },
      dragBuilder: (context, child) {
        debugPrint('[DRAG] DraggableYearItem.dragBuilder called for: $label');
        final l10n = AppLocalizations.of(context)!;
        if (isBatch) {
          final totalSongs = selectedYears!.fold<int>(
              0, (sum, y) => sum + y.songs.length);
          return AppDraggablePreviewCard(
            title: label,
            subtitle: l10n.selectedYearsWithTotalSongs(
              selectedYears!.length,
              totalSongs,
            ),
            imagePath: coverPath,
            defaultIcon: Icons.calendar_month_rounded,
            badgeText: '${selectedYears!.length}',
            count: selectedYears!.length,
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
