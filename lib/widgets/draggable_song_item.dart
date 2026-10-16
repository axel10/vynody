import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/widgets/drag/drag_cover.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';
import 'package:vynody/widgets/drag/drag_preview_card.dart';
import 'package:vynody/widgets/drag/drag_source.dart';
import 'package:vynody/widgets/library_selection_scope.dart';

/// Wraps a song widget to provide system-level native drag source support.
///
/// Enables dragging a song from library, albums, directories into the
/// standalone queue window or other apps. Dragging a song that is part of a
/// multi-selection carries the whole selection.
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
    // Selection can arrive from three places: the explicit [isSelected] /
    // [isSelectionMode] props, an explicit [selectedPaths] list, or the global
    // selection provider. They are folded exactly once, here, and the resulting
    // list drives both the preview count and the published payload — so the two
    // can no longer disagree.
    //
    // The whole selection state is watched rather than individual fields
    // because `LibrarySelectionState` has value equality; that keeps the
    // rebuild correct without several derived subscriptions having to stay in
    // sync with each other.
    final selection = ref.watch(librarySelectionStateProvider);
    final globalPaths = selection.isActive &&
            selection.scope != LibrarySelectionScope.none &&
            selection.selectedKeys.isNotEmpty
        ? selection.selectedKeys.whereType<String>().toList()
        : const <String>[];
    final isGlobalSelectionActive = globalPaths.isNotEmpty;

    final selectionActive = (isSelectionMode ?? false) ||
        (selectedPaths != null && selectedPaths!.isNotEmpty) ||
        isGlobalSelectionActive;
    final thisSongSelected = isSelected ??
        selectedPaths?.contains(song.path) ??
        globalPaths.contains(song.path);

    final List<String> dragPaths;
    if (selectionActive && thisSongSelected) {
      if (selectedPaths != null && selectedPaths!.isNotEmpty) {
        dragPaths = selectedPaths!.toList();
      } else if (isGlobalSelectionActive && globalPaths.contains(song.path)) {
        dragPaths = globalPaths;
      } else {
        dragPaths = [song.path];
      }
    } else {
      dragPaths = [song.path];
    }

    final isBatch = dragPaths.length > 1;

    return DragSource(
      enabled: enabled,
      buildPayload: () => SongPathsPayload(paths: dragPaths),
      buildPreview: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AppDraggablePreviewCard(
          title: song.displayName,
          subtitle: isBatch
              ? l10n.selectedSongs(dragPaths.length)
              : (song.artist?.isNotEmpty == true
                  ? song.artist!
                  : l10n.unknownArtist),
          imagePath: resolveDragCoverPath(
            thumbnailPath: song.thumbnailPath,
            artworkPath: song.artworkPath,
          ),
          defaultIcon: Icons.music_note_rounded,
          isBatch: isBatch,
          count: dragPaths.length,
        );
      },
      child: child,
    );
  }
}
