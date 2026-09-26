import 'dart:io';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/widgets/draggable_preview_card.dart';

/// Wraps an artist item widget to provide system-level native drag source support.
/// Enables dragging an artist from local library into standalone queue window or other apps.
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
    if (!enabled || !DesktopDraggableWrapper.isPlatformSupported) {
      return child;
    }

    final isBatch = isSelectionMode &&
        isSelected &&
        selectedArtists != null &&
        selectedArtists!.length > 1;
    final rep = artist.representativeSong;
    final cachedImageValid = artist.cachedImagePath != null &&
        artist.cachedImagePath!.isNotEmpty &&
        File(artist.cachedImagePath!).existsSync();
    final hasThumb = rep.thumbnailPath != null &&
        rep.thumbnailPath!.isNotEmpty &&
        File(rep.thumbnailPath!).existsSync();
    final hasArt = rep.artworkPath != null &&
        rep.artworkPath!.isNotEmpty &&
        File(rep.artworkPath!).existsSync();
    final coverPath = cachedImageValid
        ? artist.cachedImagePath
        : (hasThumb ? rep.thumbnailPath : (hasArt ? rep.artworkPath : null));

    return DesktopDraggableWrapper(
      enabled: enabled,
      dragItemProvider: (request) async {
        debugPrint(
            '[DRAG] DraggableArtistItem.dragItemProvider called for: ${artist.name} (${artist.songs.length} songs, isBatch: $isBatch)');
        final List<String> songPaths;
        if (isBatch) {
          final set = <String>{};
          for (final a in selectedArtists!) {
            for (final s in a.songs) {
              set.add(s.path);
            }
          }
          songPaths = set.toList();
        } else {
          songPaths = artist.songs.map((s) => s.path).toList();
        }

        final item = DragItem(
          localData: <String, dynamic>{
            'type': 'artist',
            'id': artist.queryKey,
            'name': artist.name,
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
              '[DRAG] DraggableArtistItem drag completed for "${artist.name}". Result operation: $op');
        });
        return item;
      },
      dragBuilder: (context, child) {
        debugPrint(
            '[DRAG] DraggableArtistItem.dragBuilder called for: ${artist.name}');
        final l10n = AppLocalizations.of(context)!;
        if (isBatch) {
          final totalSongs = selectedArtists!.fold<int>(
              0, (sum, a) => sum + a.songs.length);
          return AppDraggablePreviewCard(
            title: artist.name,
            subtitle: l10n.selectedArtistsWithTotalSongs(selectedArtists!.length, totalSongs),
            imagePath: coverPath,
            defaultIcon: Icons.person_rounded,
            badgeText: '${selectedArtists!.length}',
            count: selectedArtists!.length,
            isBatch: true,
          );
        }
        return AppDraggablePreviewCard(
          title: artist.name,
          subtitle: l10n.songsCountFormat(artist.songCount),
          imagePath: coverPath,
          defaultIcon: Icons.person_rounded,
          badgeText: l10n.songsCountFormat(artist.songCount),
          count: artist.songCount,
        );
      },
      child: child,
    );
  }
}
