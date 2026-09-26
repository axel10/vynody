import 'dart:io';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/widgets/draggable_preview_card.dart';

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
    if (!enabled || !DesktopDraggableWrapper.isPlatformSupported) {
      return child;
    }

    final rep = representativeSong;
    final hasThumb = rep?.thumbnailPath != null &&
        rep!.thumbnailPath!.isNotEmpty &&
        File(rep.thumbnailPath!).existsSync();
    final hasArt = rep?.artworkPath != null &&
        rep!.artworkPath!.isNotEmpty &&
        File(rep.artworkPath!).existsSync();
    final coverPath = hasThumb ? rep.thumbnailPath : (hasArt ? rep.artworkPath : null);
    final displayCount = songsCount > 0 ? songsCount : folder.allSongs.length;

    return DesktopDraggableWrapper(
      enabled: enabled,
      dragItemProvider: (request) async {
        debugPrint('[DRAG] DraggableFolderItem.dragItemProvider called for: ${folder.name} (path: ${folder.path})');
        final allSongs = folder.allSongs;
        final songPaths = allSongs.map((s) => s.path).toList();
        final isSystem = folder.path == 'system';
        final isRemote = RemoteMediaResolver.isRemoteUri(folder.path);
        final isDir = !isSystem && !isRemote && Directory(folder.path).existsSync();

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
          final first = songPaths.first;
          if (!RemoteMediaResolver.isRemoteUri(first) && File(first).existsSync()) {
            item.add(Formats.fileUri(Uri.file(first)));
          }
          item.add(Formats.plainText(songPaths.join('\n')));
        } else {
          item.add(Formats.plainText(folder.path));
          final uri = Uri.tryParse(folder.path);
          if (uri != null) {
            item.add(Formats.uri(NamedUri(uri)));
          }
        }
        request.session.dragCompleted.addListener(() {
          final op = request.session.dragCompleted.value;
          debugPrint('[DRAG] DraggableFolderItem drag completed for "${folder.name}". Result operation: $op');
        });
        return item;
      },
      dragBuilder: (context, child) {
        debugPrint('[DRAG] DraggableFolderItem.dragBuilder called for: ${folder.name}');
        final l10n = AppLocalizations.of(context)!;
        return AppDraggablePreviewCard(
          title: folder.name,
          subtitle: folder.path == 'system' ? l10n.systemMediaLibrary : folder.path,
          imagePath: coverPath,
          defaultIcon: folder.path == 'system'
              ? Icons.library_music_rounded
              : Icons.folder_rounded,
          badgeText: displayCount > 0 ? l10n.songsCountFormat(displayCount) : null,
          count: displayCount,
        );
      },
      child: child,
    );
  }
}
