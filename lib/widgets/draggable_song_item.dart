import 'dart:io';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/models/music_file.dart';

/// Wraps a song widget to provide system-level native drag source support.
/// Enables dragging a song from library, albums, directories into standalone queue window or other apps.
class DraggableSongItem extends StatelessWidget {
  final MusicFile song;
  final Widget child;
  final bool enabled;

  const DraggableSongItem({
    super.key,
    required this.song,
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
        debugPrint('[DRAG] DraggableSongItem.dragItemProvider called for: ${song.displayName} (path: ${song.path})');
        final item = DragItem(
          localData: <String, String?>{
            'path': song.path,
            'name': song.name,
            'title': song.title,
            'artist': song.artist,
          },
        );
        // Add native file uri so system drop targets and other windows recognize it as a file
        item.add(Formats.fileUri(Uri.file(song.path)));
        item.add(Formats.plainText(song.path));
        request.session.dragCompleted.addListener(() {
          final op = request.session.dragCompleted.value;
          debugPrint('[DRAG] DraggableSongItem drag completed for "${song.displayName}". Result operation: $op');
        });
        return item;
      },
      allowedOperations: () => const [DropOperation.copy, DropOperation.link],
      dragBuilder: (context, child) {
        debugPrint('[DRAG] DraggableSongItem.dragBuilder called for: ${song.displayName}');
        return _buildDragPreview(context, song);
      },
      child: DraggableWidget(
        hitTestBehavior: HitTestBehavior.translucent,
        child: child,
      ),
    );
  }

  Widget _buildDragPreview(BuildContext context, MusicFile song) {
    final theme = Theme.of(context);
    final hasThumb = song.thumbnailPath != null &&
        song.thumbnailPath!.isNotEmpty &&
        File(song.thumbnailPath!).existsSync();
    final hasArt = song.artworkPath != null &&
        song.artworkPath!.isNotEmpty &&
        File(song.artworkPath!).existsSync();
    final coverPath = hasThumb ? song.thumbnailPath : (hasArt ? song.artworkPath : null);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 240,
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
              width: 36,
              height: 36,
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
                      Icons.music_note_rounded,
                      size: 20,
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
                    song.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist ?? '未知歌手',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
