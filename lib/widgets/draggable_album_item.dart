import 'dart:io';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/models/album_summary.dart';

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
    if (!enabled || (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) {
      return child;
    }

    return DragItemWidget(
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
      allowedOperations: () => const [DropOperation.copy, DropOperation.link],
      dragBuilder: (context, child) {
        debugPrint('[DRAG] DraggableAlbumItem.dragBuilder called for: ${album.title}');
        return _buildDragPreview(context, album);
      },
      child: DraggableWidget(
        hitTestBehavior: HitTestBehavior.translucent,
        child: child,
      ),
    );
  }

  Widget _buildDragPreview(BuildContext context, AlbumSummary album) {
    final theme = Theme.of(context);
    final rep = album.representativeSong;
    final hasThumb = rep.thumbnailPath != null &&
        rep.thumbnailPath!.isNotEmpty &&
        File(rep.thumbnailPath!).existsSync();
    final hasArt = rep.artworkPath != null &&
        rep.artworkPath!.isNotEmpty &&
        File(rep.artworkPath!).existsSync();
    final coverPath = hasThumb ? rep.thumbnailPath : (hasArt ? rep.artworkPath : null);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 250,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                image: coverPath != null
                    ? DecorationImage(
                        image: FileImage(File(coverPath)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: coverPath == null
                  ? Icon(
                      Icons.album_rounded,
                      size: 24,
                      color: theme.colorScheme.primary,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          album.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${album.trackCount}首',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
