import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/widgets/library_selection_scope.dart';

/// Wraps a song widget to provide system-level native drag source support.
/// Enables dragging a song from library, albums, directories into standalone queue window or other apps.
/// Supports dragging single songs or multiple songs when in multi-select mode.
class DraggableSongItem extends ConsumerWidget {
  final MusicFile song;
  final Widget child;
  final bool enabled;
  final bool? isSelected;
  final bool? isSelectionMode;
  final Iterable<String>? selectedPaths;

  const DraggableSongItem({
    super.key,
    required this.song,
    required this.child,
    this.enabled = true,
    this.isSelected,
    this.isSelectionMode,
    this.selectedPaths,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled || (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) {
      return child;
    }

    final selectionState = ref.watch(librarySelectionStateProvider);
    final globalSelectionActive = selectionState.isActive &&
        selectionState.scope != LibrarySelectionScope.none &&
        selectionState.selectedKeys.isNotEmpty;

    final bool selectionActive = (isSelectionMode ?? false) ||
        (selectedPaths != null && selectedPaths!.isNotEmpty) ||
        globalSelectionActive;

    final bool thisSongSelected = isSelected ??
        (selectedPaths != null && selectedPaths!.contains(song.path)) ??
        (globalSelectionActive && selectionState.selectedKeys.contains(song.path));

    final List<String> dragPaths;
    if (selectionActive && thisSongSelected) {
      if (selectedPaths != null && selectedPaths!.isNotEmpty) {
        dragPaths = selectedPaths!.toList();
      } else if (globalSelectionActive) {
        final stringKeys =
            selectionState.selectedKeys.whereType<String>().toList();
        if (stringKeys.isNotEmpty && stringKeys.contains(song.path)) {
          dragPaths = stringKeys;
        } else {
          dragPaths = [song.path];
        }
      } else {
        dragPaths = [song.path];
      }
    } else {
      dragPaths = [song.path];
    }
    final int dragCount = dragPaths.length;
    final bool isBatch = dragCount > 1;

    return DragItemWidget(
      dragItemProvider: (request) async {
        debugPrint(
            '[DRAG] DraggableSongItem.dragItemProvider called for: ${song.displayName} (path: ${song.path}), total: $dragCount');
        final item = DragItem(
          localData: <String, dynamic>{
            'path': song.path,
            'paths': dragPaths,
            'name': song.name,
            'title': song.title,
            'artist': song.artist,
            'count': dragCount,
          },
        );

        if (!isBatch) {
          final isRemote = RemoteMediaResolver.isRemoteUri(song.path) ||
              song.path.startsWith('http://') ||
              song.path.startsWith('https://');
          if (!isRemote && File(song.path).existsSync()) {
            item.add(Formats.fileUri(Uri.file(song.path)));
          } else if (isRemote) {
            final uri = Uri.tryParse(song.path);
            if (uri != null) {
              item.add(Formats.uri(NamedUri(uri)));
            }
          }
        } else {
          final first = dragPaths.first;
          final isFirstRemote = RemoteMediaResolver.isRemoteUri(first) ||
              first.startsWith('http://') ||
              first.startsWith('https://');
          if (!isFirstRemote && File(first).existsSync()) {
            item.add(Formats.fileUri(Uri.file(first)));
          }
        }

        item.add(Formats.plainText(dragPaths.join('\n')));

        request.session.dragCompleted.addListener(() {
          final op = request.session.dragCompleted.value;
          debugPrint(
              '[DRAG] DraggableSongItem drag completed for "${song.displayName}" ($dragCount items). Result operation: $op');
        });
        return item;
      },
      allowedOperations: () => const [DropOperation.copy, DropOperation.link],
      dragBuilder: (context, child) {
        debugPrint(
            '[DRAG] DraggableSongItem.dragBuilder called for: ${song.displayName} (batch: $isBatch, count: $dragCount)');
        return _buildDragPreview(context, song, isBatch: isBatch, count: dragCount);
      },
      child: DraggableWidget(
        hitTestBehavior: HitTestBehavior.translucent,
        child: child,
      ),
    );
  }

  Widget _buildDragPreview(
    BuildContext context,
    MusicFile song, {
    bool isBatch = false,
    int count = 1,
  }) {
    final theme = Theme.of(context);
    final hasThumb = song.thumbnailPath != null &&
        song.thumbnailPath!.isNotEmpty &&
        File(song.thumbnailPath!).existsSync();
    final hasArt = song.artworkPath != null &&
        song.artworkPath!.isNotEmpty &&
        File(song.artworkPath!).existsSync();
    final coverPath =
        hasThumb ? song.thumbnailPath : (hasArt ? song.artworkPath : null);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 250,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 38,
                  height: 38,
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
                          size: 22,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                ),
                if (isBatch && count > 1)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimary,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
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
                    isBatch ? '已选择 $count 首歌曲' : (song.artist ?? '未知歌手'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isBatch
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight:
                          isBatch ? FontWeight.w500 : FontWeight.normal,
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
