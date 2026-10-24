import 'dart:async';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'folder_grid_card.dart';
import 'song_grid_card.dart';
import 'folder_layout_utils.dart';

/// Renders an empty search results placeholder sliver.
class FolderEmptySearchResultsSliver extends StatelessWidget {
  final String message;
  final bool isSearching;

  const FolderEmptySearchResultsSliver({
    super.key,
    required this.message,
    this.isSearching = false,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isSearching)
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                Icon(
                  Icons.search_off_rounded,
                  size: 64,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.5),
                ),
              const SizedBox(height: 16),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a section header divider sliver for songs count.
class FolderSectionHeaderSliver extends StatelessWidget {
  final String title;

  const FolderSectionHeaderSliver({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7),
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders subfolders in unified zoom-driven grid/list view.
class FolderSubfoldersSliver extends StatelessWidget {
  final List<MusicFolder> folders;
  final FolderViewMode? viewMode;
  final double? zoomScale;
  final ScannerService scanner;
  final bool isSelectionMode;
  final bool isSortMode;
  final Set<String> selectedFolderPaths;
  final bool isRoot;
  final bool showSystemMedia;
  final bool hasPermission;
  final String? systemMediaTitle;
  final String? systemMediaSubtitle;
  final void Function(MusicFolder) onNavigateTo;
  final void Function(MusicFolder folder, int index)? onFolderTap;
  final void Function(MusicFolder folder, int index)? onFolderLongPress;
  final void Function(String path)? onToggleFolderSelection;
  final VoidCallback? onToggleSelectionMode;
  final void Function(MusicFolder, {required bool isRoot})?
      onShowFolderBottomSheet;
  final void Function(MusicFolder, Offset position, {required bool isRoot})?
      onShowFolderContextMenu;
  final double? bottomPadding;
  final double? crossAxisExtent;

  const FolderSubfoldersSliver({
    super.key,
    required this.folders,
    this.viewMode,
    this.zoomScale,
    required this.scanner,
    this.isSelectionMode = false,
    this.isSortMode = false,
    this.selectedFolderPaths = const {},
    this.isRoot = false,
    this.showSystemMedia = false,
    this.hasPermission = true,
    this.systemMediaTitle,
    this.systemMediaSubtitle,
    required this.onNavigateTo,
    this.onFolderTap,
    this.onFolderLongPress,
    this.onToggleFolderSelection,
    this.onToggleSelectionMode,
    this.onShowFolderBottomSheet,
    this.onShowFolderContextMenu,
    this.bottomPadding,
    this.crossAxisExtent,
  });

  double get _effectiveZoomScale {
    if (zoomScale != null) return zoomScale!.clamp(0.0, 1.0);
    return switch (viewMode) {
      FolderViewMode.list => 0.35,
      FolderViewMode.hybrid || FolderViewMode.grid || null => 0.65,
    };
  }

  @override
  Widget build(BuildContext context) {
    final totalItemCount = folders.length + (showSystemMedia ? 1 : 0);
    if (totalItemCount == 0) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final width = crossAxisExtent ?? MediaQuery.sizeOf(context).width;
    final paddingBottom = bottomPadding ?? (isRoot ? 160.0 : 0.0);
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final effectiveZoom = _effectiveZoomScale;

    return FolderZoomSliverBuilder(
      zoomScale: effectiveZoom,
      width: width,
      builder: (context, metrics) {
        final isGrid = metrics.isGridTarget;

        // Reorderable mode for root folders
        if (isRoot && isSortMode && !isSelectionMode) {
          if (isGrid) {
            final crossAxisCount =
                getFolderZoomGridCrossAxisCount(width, effectiveZoom);
            final childAspectRatio = calculateFolderGridChildAspectRatio(
              context,
              width,
              crossAxisCount,
              zoomScale: effectiveZoom,
            );

            final List<MusicFolder> allFoldersWithSystem = [];
            final systemFolder = scanner.systemMediaFolder ??
                MusicFolder(
                  path: 'system',
                  name: systemMediaTitle ?? '',
                );
            if (showSystemMedia) {
              allFoldersWithSystem.add(systemFolder);
            }
            allFoldersWithSystem.addAll(folders);

            return SliverPadding(
              padding: EdgeInsets.only(
                top: 8,
                bottom: paddingBottom,
                left: kGridHorizontalPadding,
                right: kGridHorizontalPadding,
              ),
              sliver: SliverToBoxAdapter(
                child: ReorderableBuilder(
                  lockedIndices: showSystemMedia ? const [0] : const [],
                  nonDraggableIndices: showSystemMedia ? const [0] : const [],
                  onReorder: (ReorderedListFunction reorderedListFunction) {
                    final reordered =
                        reorderedListFunction(allFoldersWithSystem)
                            as List<MusicFolder>;
                    final realFolders = showSystemMedia
                        ? reordered.where((f) => f.path != 'system').toList()
                        : reordered;
                    final newPaths = realFolders.map((f) => f.path).toList();
                    unawaited(scanner.reorderRootPaths(newPaths));
                  },
                  builder: (children) {
                    return GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: kGridCrossAxisSpacing,
                        mainAxisSpacing: kGridMainAxisSpacing,
                        childAspectRatio: childAspectRatio,
                      ),
                      children: children,
                    );
                  },
                  children: allFoldersWithSystem.map((folder) {
                    if (folder.path == 'system') {
                      final songsCount =
                          scanner.getSongCountForFolder(systemFolder);
                      final representativeSong =
                          scanner.getRepresentativeSongForFolder(systemFolder);

                      return AnimatedOpacity(
                        key: const ValueKey('folder_system'),
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 180),
                        child: FolderZoomItem(
                          folder: systemFolder,
                          metrics: metrics,
                          songsCount: songsCount,
                          representativeSong: representativeSong,
                          subtitle: hasPermission ? null : systemMediaSubtitle,
                          isSortMode: true,
                          onTap: null,
                        ),
                      );
                    }

                    final isAvailable =
                        scanner.isRootPathAvailable(folder.path);
                    final representativeSong =
                        scanner.getRepresentativeSongForFolder(folder);
                    final songsCount = scanner.getSongCountForFolder(folder);

                    return AnimatedOpacity(
                      key: ValueKey('folder_${folder.path}'),
                      opacity: isAvailable ? 1.0 : 0.45,
                      duration: const Duration(milliseconds: 180),
                      child: FolderZoomItem(
                        folder: folder,
                        metrics: metrics,
                        songsCount: songsCount,
                        representativeSong: representativeSong,
                        isSelected: false,
                        isSelectionMode: false,
                        isSortMode: true,
                        onTap: null,
                        onSecondaryTapDown: (details) {
                          onShowFolderContextMenu?.call(
                            folder,
                            details.globalPosition,
                            isRoot: isRoot,
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          } else {
            return SliverPadding(
              padding: EdgeInsets.only(
                top: isRoot ? 0 : 8,
                bottom: paddingBottom,
                left: isPortrait ? 4 : 8,
                right: isPortrait ? 4 : 8,
              ),
              sliver: SliverReorderableList(
                itemCount: totalItemCount,
                onReorder: (oldIndex, newIndex) {
                  if (showSystemMedia && (oldIndex == 0 || newIndex == 0)) {
                    return;
                  }
                  final realOld = showSystemMedia ? oldIndex - 1 : oldIndex;
                  var realNew = showSystemMedia ? newIndex - 1 : newIndex;
                  if (realNew > realOld) realNew--;
                  unawaited(scanner.moveRootPath(realOld, realNew));
                },
                itemBuilder: (context, index) {
                  if (showSystemMedia && index == 0) {
                    final systemFolder = scanner.systemMediaFolder ??
                        MusicFolder(
                          path: 'system',
                          name: systemMediaTitle ?? '',
                        );
                    final songsCount =
                        scanner.getSongCountForFolder(systemFolder);
                    final representativeSong =
                        scanner.getRepresentativeSongForFolder(systemFolder);

                    return ReorderableDelayedDragStartListener(
                      key: const ValueKey('folder_system'),
                      index: index,
                      enabled: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SizedBox(
                          height: metrics.animatedListExtent,
                          child: FolderZoomItem(
                            folder: systemFolder,
                            metrics: metrics,
                            songsCount: songsCount,
                            representativeSong: representativeSong,
                            subtitle:
                                hasPermission ? null : systemMediaSubtitle,
                            onTap: null,
                          ),
                        ),
                      ),
                    );
                  }

                  final folderIndex = showSystemMedia ? index - 1 : index;
                  final folder = folders[folderIndex];
                  final isAvailable = scanner.isRootPathAvailable(folder.path);
                  final representativeSong =
                      scanner.getRepresentativeSongForFolder(folder);
                  final songsCount = scanner.getSongCountForFolder(folder);

                  return ReorderableDelayedDragStartListener(
                    key: ValueKey('sort_folder_${folder.path}'),
                    index: index,
                    child: AnimatedOpacity(
                      opacity: isAvailable ? 1.0 : 0.45,
                      duration: const Duration(milliseconds: 180),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SizedBox(
                          height: metrics.animatedListExtent,
                          child: FolderZoomItem(
                            folder: folder,
                            metrics: metrics,
                            songsCount: songsCount,
                            representativeSong: representativeSong,
                            isSelected: false,
                            isSelectionMode: false,
                            isSortMode: true,
                            onTap: null,
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                            onSecondaryTapDown: (details) {
                              onShowFolderContextMenu?.call(
                                folder,
                                details.globalPosition,
                                isRoot: isRoot,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          }
        }

        // Unified SliverGrid for both List Mode (`gridMorph = 0.0`) and Grid Mode (`gridMorph = 1.0`)
        final hPad = lerpDouble(
          isPortrait ? 4.0 : 8.0,
          kGridHorizontalPadding,
          metrics.gridMorph,
        )!;
        final topPad = lerpDouble(
          isRoot ? 0.0 : 8.0,
          8.0,
          metrics.gridMorph,
        )!;

        return SliverPadding(
          padding: EdgeInsets.only(
            top: topPad,
            bottom: paddingBottom,
            left: hPad,
            right: hPad,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (showSystemMedia && index == 0) {
                  final systemFolder = scanner.systemMediaFolder ??
                      MusicFolder(
                        path: 'system',
                        name: systemMediaTitle ?? '',
                      );
                  final songsCount =
                      scanner.getSongCountForFolder(systemFolder);
                  final representativeSong =
                      scanner.getRepresentativeSongForFolder(systemFolder);

                  return AnimatedOpacity(
                    key: const ValueKey('folder_system'),
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: FolderZoomItem(
                      folder: systemFolder,
                      metrics: metrics,
                      songsCount: songsCount,
                      representativeSong: representativeSong,
                      subtitle: hasPermission ? null : systemMediaSubtitle,
                      onTap: isSelectionMode
                          ? null
                          : () async {
                              if (!hasPermission) {
                                await scanner.checkAndRequestPermissions();
                              }
                              if (context.mounted) {
                                onNavigateTo(systemFolder);
                              }
                            },
                    ),
                  );
                }

                final folderIndex = showSystemMedia ? index - 1 : index;
                final folder = folders[folderIndex];
                final isAvailable =
                    isRoot ? scanner.isRootPathAvailable(folder.path) : true;
                final isSelected = selectedFolderPaths.contains(folder.path);
                final representativeSong =
                    scanner.getRepresentativeSongForFolder(folder);
                final songsCount = isRoot
                    ? scanner.getSongCountForFolder(folder)
                    : folder.allSongs.length;

                return AnimatedOpacity(
                  key: ValueKey('folder_${folder.path}'),
                  opacity: isAvailable ? 1.0 : 0.45,
                  duration: const Duration(milliseconds: 180),
                  child: FolderZoomItem(
                    folder: folder,
                    metrics: metrics,
                    songsCount: songsCount,
                    representativeSong: representativeSong,
                    isSelected: isSelected,
                    isSelectionMode: isSelectionMode,
                    isSortMode: isSortMode,
                    onTap: onFolderTap != null
                        ? (isAvailable || isSelectionMode
                            ? () => onFolderTap?.call(folder, folderIndex)
                            : null)
                        : (isSelectionMode
                            ? () => onToggleFolderSelection?.call(folder.path)
                            : (isAvailable
                                ? () => onNavigateTo(folder)
                                : null)),
                    onLongPress: onFolderLongPress != null
                        ? () => onFolderLongPress?.call(folder, folderIndex)
                        : () {
                            if (!isSelectionMode && !isSortMode) {
                              onToggleSelectionMode?.call();
                              onToggleFolderSelection?.call(folder.path);
                            } else if (isSelectionMode) {
                              onToggleFolderSelection?.call(folder.path);
                            }
                          },
                    onSecondaryTapDown: (details) {
                      onShowFolderContextMenu?.call(
                        folder,
                        details.globalPosition,
                        isRoot: isRoot,
                      );
                    },
                  ),
                );
              },
              childCount: totalItemCount,
            ),
          ),
        );
      },
    );
  }
}

/// Renders songs in unified zoom-driven grid/list view.
class FolderSongsSliver extends StatelessWidget {
  final List<MusicFile> songs;
  final FolderViewMode? viewMode;
  final double? zoomScale;
  final String? currentSongPath;
  final bool isPlaying;
  final bool isSelectionMode;
  final Set<String> selectedSongPaths;
  final String? highlightedSongPath;
  final void Function(MusicFile song, int index) onSongTap;
  final void Function(MusicFile song)? onSongLongPress;
  final void Function(MusicFile song, TapDownDetails details)
      onSongSecondaryTapDown;
  final void Function(MusicFile song, BuildContext context)? onSongMorePressed;
  final double topPadding;
  final double bottomPadding;
  final double? crossAxisExtent;

  const FolderSongsSliver({
    super.key,
    required this.songs,
    this.viewMode,
    this.zoomScale,
    this.currentSongPath,
    this.isPlaying = false,
    this.isSelectionMode = false,
    this.selectedSongPaths = const {},
    this.highlightedSongPath,
    required this.onSongTap,
    this.onSongLongPress,
    required this.onSongSecondaryTapDown,
    this.onSongMorePressed,
    this.topPadding = 8.0,
    this.bottomPadding = 160.0,
    this.crossAxisExtent,
  });

  double get _effectiveZoomScale {
    if (zoomScale != null) return zoomScale!.clamp(0.0, 1.0);
    return switch (viewMode) {
      FolderViewMode.grid => 0.65,
      FolderViewMode.list || FolderViewMode.hybrid || null => 0.35,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final width = crossAxisExtent ?? MediaQuery.sizeOf(context).width;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final effectiveZoom = _effectiveZoomScale;

    return FolderZoomSliverBuilder(
      zoomScale: effectiveZoom,
      width: width,
      builder: (context, metrics) {
        final hPad = lerpDouble(
          isPortrait ? 4.0 : 8.0,
          kGridHorizontalPadding,
          metrics.gridMorph,
        )!;

        return SliverPadding(
          padding: EdgeInsets.only(
            top: topPadding,
            bottom: bottomPadding,
            left: hPad,
            right: hPad,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
            delegate: SliverChildBuilderDelegate(
              (context, fileIndex) {
                final file = songs[fileIndex];
                final isCurrent = currentSongPath == file.path;
                final isSelected = selectedSongPaths.contains(file.path);

                return SongZoomItem(
                  key: ValueKey(file.path),
                  song: file,
                  metrics: metrics,
                  isCurrent: isCurrent,
                  isPlaying: isPlaying,
                  isSelected: isSelected,
                  isSelectionMode: isSelectionMode,
                  selectedPaths: selectedSongPaths,
                  isHighlighted: highlightedSongPath == file.path,
                  onTap: () => onSongTap(file, fileIndex),
                  onLongPress: () => onSongLongPress?.call(file),
                  onSecondaryTapDown: (details) {
                    onSongSecondaryTapDown(file, details);
                  },
                  onMorePressed: onSongMorePressed != null
                      ? (buttonContext) =>
                          onSongMorePressed!(file, buttonContext)
                      : null,
                );
              },
              childCount: songs.length,
            ),
          ),
        );
      },
    );
  }
}
