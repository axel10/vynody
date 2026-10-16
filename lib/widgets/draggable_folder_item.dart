import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/widgets/drag/drag_cover.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';
import 'package:vynody/widgets/drag/drag_preview_card.dart';
import 'package:vynody/widgets/drag/drag_source.dart';

/// Wraps a folder widget to provide system-level native drag source support.
///
/// Enables dragging a folder from library/directory pages into the standalone
/// queue window or other apps. Local folders are published as the directory
/// itself, so destinations outside the app receive the folder rather than its
/// individual tracks.
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
    return DragSource(
      enabled: enabled,
      buildPayload: () => FolderDragPayload(
        folderPath: folder.path,
        songPaths: [for (final song in folder.allSongs) song.path],
      ),
      buildPreview: (context) {
        final l10n = AppLocalizations.of(context)!;
        final representative = representativeSong;
        final isSystemFolder = folder.path == 'system';
        // Resolved lazily: [songsCount] is already known by the caller, so the
        // folder only has to be walked when it was not supplied.
        final displayCount =
            songsCount > 0 ? songsCount : folder.allSongs.length;

        return AppDraggablePreviewCard(
          title: folder.name,
          subtitle: isSystemFolder ? l10n.systemMediaLibrary : folder.path,
          imagePath: resolveDragCoverPath(
            thumbnailPath: representative?.thumbnailPath,
            artworkPath: representative?.artworkPath,
          ),
          defaultIcon:
              isSystemFolder ? Icons.library_music_rounded : Icons.folder_rounded,
          badgeText: displayCount > 0 ? l10n.songsCountFormat(displayCount) : null,
          count: displayCount,
        );
      },
      child: child,
    );
  }
}
