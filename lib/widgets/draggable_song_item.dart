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
        final item = DragItem(
          localData: song,
        );
        // Add native file uri so system drop targets and other windows recognize it as a file
        item.add(Formats.fileUri(Uri.file(song.path)));
        item.add(Formats.plainText(song.path));
        return item;
      },
      allowedOperations: () => const [DropOperation.copy, DropOperation.link],
      child: DraggableWidget(
        child: child,
      ),
    );
  }
}
