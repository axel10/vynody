import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/folder_grid_card.dart';
import '../widgets/folder_list_tile.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/utils/folder_helpers.dart';

class FolderRootView extends ConsumerStatefulWidget {
  const FolderRootView({
    super.key,
    required this.onOpenPlayback,
    required this.isSelectionMode,
    required this.selectedRootPaths,
    required this.onPickFolder,
    required this.onToggleRootSelection,
    required this.onToggleRootSelectionMode,
    required this.onDeleteSelectedRootFolders,
    required this.onNavigateTo,
    required this.onLocateCurrentSong,
    required this.onShowFolderBottomSheet,
  });

  final Future<void> Function()? onOpenPlayback;
  final bool isSelectionMode;
  final Set<String> selectedRootPaths;
  final VoidCallback onPickFolder;
  final void Function(String) onToggleRootSelection;
  final VoidCallback onToggleRootSelectionMode;
  final Future<void> Function() onDeleteSelectedRootFolders;
  final void Function(MusicFolder) onNavigateTo;
  final VoidCallback onLocateCurrentSong;
  final void Function(MusicFolder, {required bool isRoot}) onShowFolderBottomSheet;

  @override
  ConsumerState<FolderRootView> createState() => _FolderRootViewState();
}

class _FolderRootViewState extends ConsumerState<FolderRootView> {
  late final ScrollController _localScrollController;

  @override
  void initState() {
    super.initState();
    final targetOffset = ref.read(scannerServiceProvider).getFolderScrollOffset('root');
    _localScrollController = ScrollController(initialScrollOffset: targetOffset);
    _localScrollController.addListener(_onScroll);
  }

  void _onScroll() {
    ref.read(scannerServiceProvider).setFolderScrollOffset(
      'root',
      _localScrollController.offset,
    );
  }

  @override
  void dispose() {
    _localScrollController.removeListener(_onScroll);
    _localScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerServiceProvider);
    final settings = ref.watch(settingsServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final isRootSelectionMode =
        ref.watch(librarySelectionScopeProvider) ==
        LibrarySelectionScope.folderRoot;
    final rootFolders = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.rootFolders),
    );
    final hasPermission = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.hasPermission),
    );
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    final selectionLabel = l10n.selectedFolders(widget.selectedRootPaths.length);
    final rootListBottomPadding = isRootSelectionMode ? 224.0 : 160.0;

    final selectedRootSongs = <MusicFile>[];
    final seenSelected = <String>{};
    for (final folder in rootFolders) {
      if (widget.selectedRootPaths.contains(folder.path)) {
        for (final song in folder.allSongs) {
          if (seenSelected.add(song.path)) {
            selectedRootSongs.add(song);
          }
        }
      }
    }
    final allRootSongs = <MusicFile>[];
    final seenAll = <String>{};
    for (final folder in rootFolders) {
      for (final song in folder.allSongs) {
        if (seenAll.add(song.path)) {
          allRootSongs.add(song);
        }
      }
    }

    Widget rootList;
    if (isRootSelectionMode) {
      rootList = ReorderableListView.builder(
        key: const ValueKey('root_folders_list'),
        buildDefaultDragHandles: false,
        scrollController: _localScrollController,
        cacheExtent: 1000.0,
        padding: EdgeInsets.only(bottom: rootListBottomPadding),
        itemCount: rootFolders.length,
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) newIndex--;
          unawaited(scanner.moveRootPath(oldIndex, newIndex));
        },
        itemBuilder: (context, index) {
          final folder = rootFolders[index];
          final isSelected = widget.selectedRootPaths.contains(folder.path);
          final isRootAvailable = scanner.isRootPathAvailable(folder.path);
          return GestureDetector(
            key: ValueKey(folder.path),
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) {
              widget.onShowFolderBottomSheet(folder, isRoot: true);
            },
            onLongPress: () {
              widget.onToggleRootSelection(folder.path);
            },
            child: AnimatedOpacity(
              opacity: isRootAvailable ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 180),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal:
                      MediaQuery.of(context).orientation ==
                          Orientation.portrait
                      ? 8
                      : 16,
                  vertical: 4,
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  hoverColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.06),
                  enabled: isRootAvailable || isRootSelectionMode,
                  selected: isSelected,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.45),
                  leading: Checkbox(
                    value: isSelected,
                    onChanged: (_) =>
                        widget.onToggleRootSelection(folder.path),
                  ),
                  title: Text(folder.name),
                  subtitle: Text(
                    ScannerPathUtils.cleanDisplayPath(folder.path),
                  ),
                  onTap: () => widget.onToggleRootSelection(folder.path),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } else {
      final isGrid = settings.folderViewMode == FolderViewMode.hybrid ||
          settings.folderViewMode == FolderViewMode.grid;
      if (isGrid) {
        rootList = LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = switch (constraints.maxWidth) {
              >= 1350 => 6,
              >= 1100 => 5,
              >= 850 => 4,
              >= 650 => 3,
              _ => 2,
            };

            final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
            final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
            final clampedScale = textScale.clamp(1.0, 1.3);
            final double textHeight = (isPortrait ? 72.0 : 84.0) * clampedScale;
            final itemWidth = (constraints.maxWidth - 32 - (crossAxisCount - 1) * 16) / crossAxisCount;
            final childAspectRatio = itemWidth / (itemWidth + textHeight);

            return GridView.builder(
              key: const ValueKey('root_folders_grid'),
              controller: _localScrollController,
              cacheExtent: 1000.0,
              padding: EdgeInsets.only(bottom: rootListBottomPadding, left: 16, right: 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: childAspectRatio,
              ),
              itemCount: rootFolders.length,
              itemBuilder: (context, index) {
                final folder = rootFolders[index];
                final isRootAvailable = scanner.isRootPathAvailable(folder.path);
                final representativeSong = findRepresentativeSong(folder);
                return AnimatedOpacity(
                  opacity: isRootAvailable ? 1.0 : 0.45,
                  duration: const Duration(milliseconds: 180),
                  child: HoverableCard(
                    child: FolderGridCard(
                      folder: folder,
                      songsCount: folder.allSongs.length,
                      representativeSong: representativeSong,
                      onTap: isRootAvailable ? () => widget.onNavigateTo(folder) : null,
                      onLongPress: () => widget.onShowFolderBottomSheet(folder, isRoot: true),
                      onSecondaryTapDown: (details) => widget.onShowFolderBottomSheet(folder, isRoot: true),
                    ),
                  ),
                );
              },
            );
          },
        );
      } else {
        rootList = ListView.builder(
          key: const ValueKey('root_folders_list_normal'),
          controller: _localScrollController,
          cacheExtent: 1000.0,
          padding: EdgeInsets.only(bottom: rootListBottomPadding),
          itemCount: rootFolders.length,
          itemBuilder: (context, index) {
            final folder = rootFolders[index];
            final isRootAvailable = scanner.isRootPathAvailable(folder.path);
            final representativeSong = findRepresentativeSong(folder);
            return AnimatedOpacity(
              opacity: isRootAvailable ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 180),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).orientation == Orientation.portrait ? 8 : 16,
                  vertical: 4,
                ),
                child: FolderListTile(
                  folder: folder,
                  songsCount: folder.allSongs.length,
                  representativeSong: representativeSong,
                  onTap: isRootAvailable ? () => widget.onNavigateTo(folder) : null,
                  onLongPress: () => widget.onShowFolderBottomSheet(folder, isRoot: true),
                  onSecondaryTapDown: (details) => widget.onShowFolderBottomSheet(folder, isRoot: true),
                ),
              ),
            );
          },
        );
      }
    }

    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: folderPageMaxWidth),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.scanDirectory,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isPortrait)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded),
                          onSelected: (value) {
                            if (value == 'locate') {
                              widget.onLocateCurrentSong();
                            } else if (value == 'sort') {
                              widget.onToggleRootSelectionMode();
                            } else if (value == 'view_mode') {
                              settings.folderViewMode = switch (settings.folderViewMode) {
                                FolderViewMode.list => FolderViewMode.hybrid,
                                FolderViewMode.hybrid => FolderViewMode.grid,
                                FolderViewMode.grid => FolderViewMode.list,
                              };
                            }
                          },
                          itemBuilder: (context) => [
                            if (currentMusic != null)
                              PopupMenuItem(
                                value: 'locate',
                                child: Row(
                                  children: [
                                    const Icon(Icons.my_location_rounded, size: 20),
                                    const SizedBox(width: 12),
                                    Text(l10n.locateCurrentSong),
                                  ],
                                ),
                              ),
                            PopupMenuItem(
                              value: 'sort',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.sort,
                                    size: 20,
                                    color: isRootSelectionMode ? Theme.of(context).colorScheme.primary : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(l10n.sort),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'view_mode',
                              child: Row(
                                children: [
                                  Icon(
                                    switch (settings.folderViewMode) {
                                      FolderViewMode.list => Icons.grid_view_rounded,
                                      FolderViewMode.hybrid => Icons.view_module_rounded,
                                      FolderViewMode.grid => Icons.view_list_rounded,
                                    },
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    switch (settings.folderViewMode) {
                                      FolderViewMode.list => l10n.hybridView,
                                      FolderViewMode.hybrid => l10n.gridView,
                                      FolderViewMode.grid => l10n.listView,
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        if (currentMusic != null)
                          IconButton(
                            icon: const Icon(Icons.my_location_rounded),
                            onPressed: widget.onLocateCurrentSong,
                            tooltip: l10n.locateCurrentSong,
                          ),
                        IconButton(
                          icon: Icon(
                            switch (settings.folderViewMode) {
                              FolderViewMode.list => Icons.grid_view_rounded,
                              FolderViewMode.hybrid => Icons.view_module_rounded,
                              FolderViewMode.grid => Icons.view_list_rounded,
                            },
                          ),
                          onPressed: () {
                            settings.folderViewMode = switch (settings.folderViewMode) {
                              FolderViewMode.list => FolderViewMode.hybrid,
                              FolderViewMode.hybrid => FolderViewMode.grid,
                              FolderViewMode.grid => FolderViewMode.list,
                            };
                          },
                          tooltip: switch (settings.folderViewMode) {
                            FolderViewMode.list => l10n.hybridView,
                            FolderViewMode.hybrid => l10n.gridView,
                            FolderViewMode.grid => l10n.listView,
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.sort,
                            color: isRootSelectionMode
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          onPressed: widget.onToggleRootSelectionMode,
                          tooltip: l10n.sort,
                        ),
                      ],
                    ],
                  ),
                ),
                if (Platform.isAndroid)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          MediaQuery.of(context).orientation ==
                              Orientation.portrait
                          ? 8
                          : 16,
                      vertical: 4,
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      hoverColor: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.06),
                      leading: const Icon(
                        Icons.library_music,
                        color: Colors.purple,
                      ),
                      title: Text(
                        AppLocalizations.of(context)!.systemMediaLibrary,
                      ),
                      subtitle: hasPermission
                          ? null
                          : Text(
                              AppLocalizations.of(context)!.needPermissionToScan,
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                      onTap: () async {
                        if (!hasPermission) {
                          await scanner.checkAndRequestPermissions();
                        }
                        if (context.mounted) {
                          widget.onNavigateTo(
                            scanner.systemMediaFolder ??
                                MusicFolder(
                                  path: 'system',
                                  name: AppLocalizations.of(
                                    context,
                                  )!.systemMediaLibrary,
                                ),
                          );
                        }
                      },
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        MediaQuery.of(context).orientation == Orientation.portrait
                        ? 8
                        : 16,
                    vertical: 4,
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    hoverColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.06),
                    leading: const Icon(
                      Icons.add_circle_outline,
                      color: Colors.blue,
                    ),
                    title: Text(AppLocalizations.of(context)!.addRootDirectory),
                    onTap: widget.onPickFolder,
                  ),
                ),
                Expanded(
                  child: rootList,
                ),
              ],
            ),
          ),
        ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                reverseDuration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offsetAnimation = Tween<Offset>(
                    begin: const Offset(0, 1.0),
                    end: Offset.zero,
                  ).animate(animation);
                  return SlideTransition(position: offsetAnimation, child: child);
                },
                child: isRootSelectionMode
                    ? LibrarySelectionPanel(
                        key: const ValueKey('root-selection-panel'),
                        selectedSongs: selectedRootSongs,
                        allSongs: allRootSongs,
                        title: selectionLabel,
                        onToggleSelectAll: () {
                          final isAllSelected =
                              widget.selectedRootPaths.length == rootFolders.length;
                          if (isAllSelected) {
                            for (final f in rootFolders) {
                              widget.onToggleRootSelection(f.path);
                            }
                          } else {
                            for (final f in rootFolders) {
                              if (!widget.selectedRootPaths.contains(f.path)) {
                                widget.onToggleRootSelection(f.path);
                              }
                            }
                          }
                        },
                        onCancel: widget.onToggleRootSelectionMode,
                        onDelete: widget.selectedRootPaths.isEmpty
                            ? null
                            : widget.onDeleteSelectedRootFolders,
                        deleteLabel: l10n.delete,
                        onOpenLocation: widget.selectedRootPaths.length == 1
                            ? () => openFolderLocation(widget.selectedRootPaths.first)
                            : null,
                        openLocationLabel: l10n.openFolderLocation,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('root-selection-panel-hidden'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
