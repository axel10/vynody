import 'dart:io';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/widgets/draggable_preview_card.dart';

/// Wraps an album card widget to provide system-level native drag source support.
/// Enables dragging an album from library/album pages into standalone queue window or other apps.
class DraggableAlbumItem extends StatelessWidget {
  final AlbumSummary album;
  final Widget child;
  final bool enabled;

  const DraggableAlbumItem({
    super.key,
    required this.album,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || !DesktopDraggableWrapper.isPlatformSupported) {
      return child;
    }

    final rep = album.representativeSong;
    final hasThumb = rep.thumbnailPath != null &&
        rep.thumbnailPath!.isNotEmpty &&
        File(rep.thumbnailPath!).existsSync();
    final hasArt = rep.artworkPath != null &&
        rep.artworkPath!.isNotEmpty &&
        File(rep.artworkPath!).existsSync();
    final coverPath = hasThumb ? rep.thumbnailPath : (hasArt ? rep.artworkPath : null);

    return DesktopDraggableWrapper(
      enabled: enabled,
      dragItemProvider: (request) async {
        debugPrint('[DRAG] DraggableAlbumItem.dragItemProvider called for: ${album.title} (${album.songs.length} songs)');
        final songPaths = album.songs.map((s) => s.path).toList();
        final item = DragItem(
          localData: <String, dynamic>{
            'type': 'album',
            'id': album.id,
            'title': album.title,
            'artist': album.artist,
            'paths': songPaths,
          },
        );
        if (songPaths.isNotEmpty) {
          item.add(Formats.fileUri(Uri.file(songPaths.first)));
          item.add(Formats.plainText(songPaths.join('\n')));
        }
        request.session.dragCompleted.addListener(() {
          final op = request.session.dragCompleted.value;
          debugPrint('[DRAG] DraggableAlbumItem drag completed for "${album.title}". Result operation: $op');
        });
        return item;
      },
      dragBuilder: (context, child) {
        debugPrint('[DRAG] DraggableAlbumItem.dragBuilder called for: ${album.title}');
        final l10n = AppLocalizations.of(context)!;
        return AppDraggablePreviewCard(
          title: album.title,
          subtitle: album.artist,
          imagePath: coverPath,
          defaultIcon: Icons.album_rounded,
          badgeText: l10n.songsCountFormat(album.trackCount),
          count: album.trackCount,
        );
      },
      child: child,
    );
  }
}
