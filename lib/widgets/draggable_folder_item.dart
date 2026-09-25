import 'dart:io';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';

/// Wraps a folder widget to provide system-level native drag source support.
/// Enables dragging a folder from library/directory pages into standalone queue window or other apps.
class DraggableFolderItem extends StatelessWidget {
  final MusicFolder folder;
  final Widget child;
  final int songsCount;
  final MusicFile? representativeSong;
  final bool enabled;

  const DraggableFolderItem({
    super.key,
    required this.folder,
    required this.child,
    this.songsCount = 0,
    this.representativeSong,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) {
      return child;
    }

    return DragItemWidget(
      dragItemProvider: (request) async {
        debugPrint('[DRAG] DraggableFolderItem.dragItemProvider called for: ${folder.name} (path: ${folder.path})');
        final allSongs = folder.allSongs;
        final songPaths = allSongs.map((s) => s.path).toList();
        final isSystem = folder.path == 'system';
        final isDir = !isSystem && Directory(folder.path).existsSync();

        final item = DragItem(
          localData: <String, dynamic>{
            'type': 'folder',
            'path': folder.path,
            'name': folder.name,
            if (songPaths.isNotEmpty) 'paths': songPaths,
          },
        );

        if (isDir) {
          item.add(Formats.fileUri(Uri.file(folder.path)));
          item.add(Formats.plainText(folder.path));
        } else if (songPaths.isNotEmpty) {
          item.add(Formats.fileUri(Uri.file(songPaths.first)));
          item.add(Formats.plainText(songPaths.join('\n')));
        }
        request.session.dragCompleted.addListener(() {
          final op = request.session.dragCompleted.value;
          debugPrint('[DRAG] DraggableFolderItem drag completed for "${folder.name}". Result operation: $op');
        });
        return item;
      },
      allowedOperations: () => const [DropOperation.copy, DropOperation.link],
      dragBuilder: (context, child) {
        debugPrint('[DRAG] DraggableFolderItem.dragBuilder called for: ${folder.name}');
        return _buildDragPreview(context);
      },
      child: DraggableWidget(
        hitTestBehavior: HitTestBehavior.translucent,
        child: child,
      ),
    );
  }

  Widget _buildDragPreview(BuildContext context) {
    final theme = Theme.of(context);
    final rep = representativeSong;
    final hasThumb = rep?.thumbnailPath != null &&
        rep!.thumbnailPath!.isNotEmpty &&
        File(rep.thumbnailPath!).existsSync();
    final hasArt = rep?.artworkPath != null &&
        rep!.artworkPath!.isNotEmpty &&
        File(rep.artworkPath!).existsSync();
    final coverPath = hasThumb ? rep.thumbnailPath : (hasArt ? rep.artworkPath : null);

    final displayCount = songsCount > 0 ? songsCount : folder.allSongs.length;

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
                      folder.path == 'system'
                          ? Icons.library_music_rounded
                          : Icons.folder_rounded,
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
                    folder.name,
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
                          folder.path == 'system' ? '系统媒体' : folder.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (displayCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$displayCount首',
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
