import 'dart:io';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/genre_summary.dart';
import 'package:vynody/widgets/draggable_preview_card.dart';

/// Wraps a genre item widget to provide system-level native drag source support.
/// Enables dragging a genre from local library into standalone queue window or other apps.
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
    if (!enabled || !DesktopDraggableWrapper.isPlatformSupported) {
      return child;
    }

    final isBatch = isSelectionMode &&
        isSelected &&
        selectedGenres != null &&
        selectedGenres!.length > 1;

    final hasThumb = genre.representativeThumbnailPath != null &&
        genre.representativeThumbnailPath!.isNotEmpty &&
        File(genre.representativeThumbnailPath!).existsSync();
    final hasArt = genre.representativeArtworkPath != null &&
        genre.representativeArtworkPath!.isNotEmpty &&
        File(genre.representativeArtworkPath!).existsSync();
    final coverPath = hasThumb
        ? genre.representativeThumbnailPath
        : (hasArt ? genre.representativeArtworkPath : null);

    return DesktopDraggableWrapper(
      enabled: enabled,
      dragItemProvider: (request) async {
        debugPrint(
            '[DRAG] DraggableGenreItem.dragItemProvider called for: ${genre.name} (${genre.songs.length} songs, isBatch: $isBatch)');
        final List<String> songPaths;
        if (isBatch) {
          final set = <String>{};
          for (final g in selectedGenres!) {
            for (final s in g.songs) {
              set.add(s.path);
            }
          }
          songPaths = set.toList();
        } else {
          songPaths = genre.songs.map((s) => s.path).toList();
        }

        final item = DragItem(
          localData: <String, dynamic>{
            'type': 'genre',
            'id': genre.queryKey,
            'name': genre.name,
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
              '[DRAG] DraggableGenreItem drag completed for "${genre.name}". Result operation: $op');
        });
        return item;
      },
      dragBuilder: (context, child) {
        debugPrint(
            '[DRAG] DraggableGenreItem.dragBuilder called for: ${genre.name}');
        final l10n = AppLocalizations.of(context)!;
        if (isBatch) {
          final totalSongs = selectedGenres!.fold<int>(
              0, (sum, g) => sum + g.songs.length);
          return AppDraggablePreviewCard(
            title: genre.name,
            subtitle: l10n.selectedGenresWithTotalSongs(
              selectedGenres!.length,
              totalSongs,
            ),
            imagePath: coverPath,
            defaultIcon: Icons.style_rounded,
            badgeText: '${selectedGenres!.length}',
            count: selectedGenres!.length,
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
