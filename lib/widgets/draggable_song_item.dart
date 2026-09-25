import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/widgets/draggable_preview_card.dart';
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
    if (!enabled || !DesktopDraggableWrapper.isPlatformSupported) {
      return child;
    }

    final isGlobalSelectionActive = ref.watch(
      librarySelectionStateProvider.select(
        (s) => s.isActive && s.scope != LibrarySelectionScope.none && s.selectedKeys.isNotEmpty,
      ),
    );
    final isGlobalSongSelected = isGlobalSelectionActive
        ? ref.watch(
            librarySelectionStateProvider.select(
              (s) => s.selectedKeys.contains(song.path),
            ),
          )
        : false;

    final bool selectionActive = (isSelectionMode ?? false) ||
        (selectedPaths != null && selectedPaths!.isNotEmpty) ||
        isGlobalSelectionActive;

    final bool thisSongSelected = isSelected ??
        selectedPaths?.contains(song.path) ??
        isGlobalSongSelected;

    final int dragCount;
    if (selectionActive && thisSongSelected) {
      if (selectedPaths != null && selectedPaths!.isNotEmpty) {
        dragCount = selectedPaths!.length;
      } else if (isGlobalSelectionActive) {
        dragCount = ref.watch(
          librarySelectionStateProvider.select((s) => s.selectedKeys.length),
        );
      } else {
        dragCount = 1;
      }
    } else {
      dragCount = 1;
    }
    final bool isBatch = dragCount > 1;

    final hasThumb = song.thumbnailPath != null &&
        song.thumbnailPath!.isNotEmpty &&
        File(song.thumbnailPath!).existsSync();
    final hasArt = song.artworkPath != null &&
        song.artworkPath!.isNotEmpty &&
        File(song.artworkPath!).existsSync();
    final coverPath =
        hasThumb ? song.thumbnailPath : (hasArt ? song.artworkPath : null);

    return DesktopDraggableWrapper(
      enabled: enabled,
      dragItemProvider: (request) async {
        final List<String> dragPaths;
        if (selectionActive && thisSongSelected) {
          if (selectedPaths != null && selectedPaths!.isNotEmpty) {
            dragPaths = selectedPaths!.toList();
          } else {
            final globalState = ref.read(librarySelectionStateProvider);
            final stringKeys =
                globalState.selectedKeys.whereType<String>().toList();
            if (stringKeys.isNotEmpty && stringKeys.contains(song.path)) {
              dragPaths = stringKeys;
            } else {
              dragPaths = [song.path];
            }
          }
        } else {
          dragPaths = [song.path];
        }
        final actualCount = dragPaths.length;
        final actualIsBatch = actualCount > 1;

        debugPrint(
            '[DRAG] DraggableSongItem.dragItemProvider called for: ${song.displayName} (path: ${song.path}), total: $actualCount');
        final item = DragItem(
          localData: <String, dynamic>{
            'path': song.path,
            'paths': dragPaths,
            'name': song.name,
            'title': song.title,
            'artist': song.artist,
            'count': actualCount,
          },
        );

        if (!actualIsBatch) {
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
      dragBuilder: (context, child) {
        debugPrint(
            '[DRAG] DraggableSongItem.dragBuilder called for: ${song.displayName} (batch: $isBatch, count: $dragCount)');
        return AppDraggablePreviewCard(
          title: song.displayName,
          subtitle: isBatch ? '已选择 $dragCount 首歌曲' : (song.artist ?? '未知歌手'),
          imagePath: coverPath,
          defaultIcon: Icons.music_note_rounded,
          isBatch: isBatch,
          count: dragCount,
        );
      },
      child: child,
    );
  }
}
