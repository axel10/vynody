import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'folder_layout_utils.dart';
import 'folder_zoom_item.dart';
import 'song_zoom_item.dart';

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
  final double zoomScale;
  final ScannerService scanner;
  final bool isSelectionMode;
  final Set<String> selectedFolderPaths;

  /// 多选整理态专用的重排状态机（由页面持有，缩放手势层也用同一个冻结闸）。
  /// 勾选集合直接复用 [selectedFolderPaths]，不再另起一套状态。
  final ZoomReorderController? reorderController;

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

  /// 本段身份，必须与 `SliverAnimatedZoomGridDelegate.section` 一致。
  final Object? section;

  const FolderSubfoldersSliver({
    super.key,
    required this.folders,
    required this.zoomScale,
    required this.scanner,
    this.isSelectionMode = false,
    this.selectedFolderPaths = const {},
    this.reorderController,
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
    this.section,
  });

  double get _effectiveZoomScale => snapFolderZoomScale(zoomScale);

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

    return FolderZoomSectionHost(
      zoomScale: effectiveZoom,
      width: width,
      builder: (context, metrics) {
        final isGrid = metrics.isGridTarget;

        // 多选整理态：条目右上角出现排序手柄，列表档与网格档共用同一个
        // 可重排网格。槽位几何与 SliverAnimatedZoomGridDelegate 同源
        // （ZoomReorderGeometry 取权重最大的目标层），两档表现一致。
        if (isRoot && isSelectionMode) {
          final hPad = isGrid
              ? kGridHorizontalPadding
              : folderContentHorizontalPadding(
                  isPortrait: isPortrait,
                  gridMorph: 0.0,
                );
          // ZoomReorderGeometry.from 把传入宽度直接当 contentWidth，
          // 必须扣掉外层 SliverPadding，否则卡片宽 32px、插入位判定错位；
          // 这样也正好与 delegate 的 usableWidth 对齐（originOffsetX 为 0）。
          final contentWidth = width - hPad * 2;

          final systemFolder = scanner.systemMediaFolder ??
              MusicFolder(path: 'system', name: systemMediaTitle ?? '');
          final items = <MusicFolder>[
            if (showSystemMedia) systemFolder,
            ...folders,
          ];
          final lockedIndices =
              showSystemMedia ? const <int>{0} : const <int>{};
          final selectedIndices = <int>{
            for (var i = 0; i < items.length; i++)
              if (!lockedIndices.contains(i) &&
                  selectedFolderPaths.contains(items[i].path))
                i,
          };

          return SliverPadding(
            padding: EdgeInsets.only(
              top: isGrid ? 8.0 : (isRoot ? 0.0 : 8.0),
              bottom: paddingBottom,
              left: hPad,
              right: hPad,
            ),
            sliver: ZoomReorderableSliverGrid(
              metrics: metrics,
              width: contentWidth,
              itemCount: items.length,
              itemKeyBuilder: (index) => ValueKey<String>(items[index].path),
              section: section,
              controller: reorderController,
              selectedIndices: selectedIndices,
              lockedIndices: lockedIndices,
              minInsertIndex: showSystemMedia ? 1 : 0,
              showHandles: true,
              handleChild: buildFolderReorderHandle(context),
              previewBuilder: (context, _, count) =>
                  buildFolderReorderPreview(context, count),
              onReorder: (draggedIndices, insertIndex) {
                final reordered = ZoomReorderController.applyReorder(
                  items,
                  draggedIndices,
                  insertIndex,
                );
                final newPaths = reordered
                    .where((f) => f.path != 'system')
                    .map((f) => f.path)
                    .toList();
                unawaited(scanner.reorderRootPaths(newPaths));
              },
              itemBuilder: (context, index) {
                final folder = items[index];
                if (folder.path == 'system') {
                  return FolderZoomItem(
                    folder: systemFolder,
                    metrics: metrics,
                    index: index,
                    section: section,
                    songsCount: scanner.getSongCountForFolder(systemFolder),
                    representativeSong:
                        scanner.getRepresentativeSongForFolder(systemFolder),
                    subtitle: hasPermission ? null : systemMediaSubtitle,
                    isSortMode: true,
                    onTap: null,
                  );
                }
                final isSelected = selectedFolderPaths.contains(folder.path);
                final isAvailable = scanner.isRootPathAvailable(folder.path);
                return AnimatedOpacity(
                  opacity: isAvailable ? 1.0 : 0.45,
                  duration: const Duration(milliseconds: 180),
                  child: FolderZoomItem(
                    folder: folder,
                    metrics: metrics,
                    index: index,
                    section: section,
                    songsCount: scanner.getSongCountForFolder(folder),
                    representativeSong:
                        scanner.getRepresentativeSongForFolder(folder),
                    isSelected: isSelected,
                    // 复用现成的多选视觉：网格态 checkbox 在左上角，
                    // 与右上角的 ZoomReorderHandle 不冲突。
                    isSelectionMode: true,
                    isSortMode: true,
                    onTap: () {
                      final folderIndex =
                          showSystemMedia ? index - 1 : index;
                      if (onFolderTap != null) {
                        onFolderTap!(folder, folderIndex);
                      } else {
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
            ),
          );
        }

        // Unified SliverGrid for both List Mode (`gridMorph = 0.0`) and Grid Mode (`gridMorph = 1.0`)
        final hPad = folderContentHorizontalPadding(
          isPortrait: isPortrait,
          gridMorph: metrics.gridMorph,
        );
        // 段首内边距**必须与档位无关**：它落在缩放网格的 `SliverPadding` 上，
        // 属于「两段之间不参与缩放的内容」。包里的滚动补偿
        // （`FolderZoomViewportTracker.gapBefore`）把它当成常量，只在单层稳态量一次，
        // 过渡期按「常量 + 上游各段高度」外推下游段的位置。一旦这里随 `gridMorph`
        // 变化（曾经是根目录 `lerp(0, 8)`、云端 `lerp(0, 8)`），列表→网格收尾那一帧
        // 切回真实布局就要一次性补上差额：实测段头 +8、云端列表 +16（两段各加 8），
        // 看起来就是「动画完了整体往下一沉」。回归见
        // `zoomable_sliver_grid/test/zoom_section_gap_test.dart`。
        const double topPad = 8.0;

        return SliverPadding(
          padding: EdgeInsets.only(
            top: topPad,
            bottom: paddingBottom,
            left: hPad,
            right: hPad,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverAnimatedZoomGridDelegate(
              metrics: metrics,
              section: section,
            ),
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
                      index: index,
                      section: section,
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
                    : folder.songCount;

                return AnimatedOpacity(
                  key: ValueKey('folder_${folder.path}'),
                  opacity: isAvailable ? 1.0 : 0.45,
                  duration: const Duration(milliseconds: 180),
                  child: FolderZoomItem(
                    folder: folder,
                    metrics: metrics,
                    index: index,
                    section: section,
                    songsCount: songsCount,
                    representativeSong: representativeSong,
                    isSelected: isSelected,
                    isSelectionMode: isSelectionMode,
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
                            if (!isSelectionMode) {
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
  final double zoomScale;
  final String? currentSongPath;
  final bool isPlaying;
  final bool isSelectionMode;
  final Set<String> selectedSongPaths;
  final String? highlightedSongPath;
  final void Function(MusicFile song, int index) onSongTap;
  final void Function(MusicFile song)? onSongLongPress;
  final void Function(MusicFile song, TapDownDetails details)
      onSongSecondaryTapDown;
  final double topPadding;
  final double bottomPadding;
  final double? crossAxisExtent;

  /// 本段身份，必须与 `SliverAnimatedZoomGridDelegate.section` 一致。
  final Object? section;

  const FolderSongsSliver({
    super.key,
    required this.songs,
    required this.zoomScale,
    this.currentSongPath,
    this.isPlaying = false,
    this.isSelectionMode = false,
    this.selectedSongPaths = const {},
    this.highlightedSongPath,
    required this.onSongTap,
    this.onSongLongPress,
    required this.onSongSecondaryTapDown,
    this.topPadding = 8.0,
    this.bottomPadding = 160.0,
    this.crossAxisExtent,
    this.section,
  });

  double get _effectiveZoomScale => snapFolderZoomScale(zoomScale);

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final width = crossAxisExtent ?? MediaQuery.sizeOf(context).width;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final effectiveZoom = _effectiveZoomScale;

    return FolderZoomSectionHost(
      zoomScale: effectiveZoom,
      width: width,
      builder: (context, metrics) {
        final hPad = folderContentHorizontalPadding(
          isPortrait: isPortrait,
          gridMorph: metrics.gridMorph,
        );

        return SliverPadding(
          padding: EdgeInsets.only(
            top: topPadding,
            bottom: bottomPadding,
            left: hPad,
            right: hPad,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverAnimatedZoomGridDelegate(
              metrics: metrics,
              section: section,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, fileIndex) {
                final file = songs[fileIndex];
                final isCurrent = currentSongPath == file.path;
                final isSelected = selectedSongPaths.contains(file.path);

                return SongZoomItem(
                  key: ValueKey(file.path),
                  song: file,
                  metrics: metrics,
                  index: fileIndex,
                  section: section,
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

/// 多选整理态下条目右上角的排序手柄图标。
Widget buildFolderReorderHandle(BuildContext context) {
  return Icon(
    Icons.drag_handle_rounded,
    size: 18,
    color: Theme.of(context).colorScheme.primary,
  );
}

/// 排序模式下「多条已选根目录合成合集」的拖拽浮层。
///
/// 浮层尺寸由 `ZoomReorderGeometry.rectForSlot(0)` 决定，这里只负责内容；
/// 用 [Center] 作根，在 tight 约束下会铺满整个浮层槽位。
Widget buildFolderReorderPreview(BuildContext context, int count) {
  final theme = Theme.of(context);
  return Material(
    elevation: 8,
    borderRadius: BorderRadius.circular(14),
    color: theme.colorScheme.surfaceContainerHighest,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.folder_rounded,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    ),
  );
}
