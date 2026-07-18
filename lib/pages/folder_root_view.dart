import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/folder_header_banner.dart';
import '../widgets/folder_grid_card.dart';
import '../widgets/folder_list_tile.dart';
import '../widgets/song_thumbnail.dart';
import '../widgets/song_tile.dart';
import '../widgets/song_grid_card.dart';
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
  late final TextEditingController _searchController;
  bool _isSearching = false;
  String _searchQuery = '';

  List<MusicFile> _matchedSongs = [];
  Timer? _searchDebounce;

  void _performSearch(String query) {
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _matchedSongs = [];
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref.read(scannerServiceProvider).searchSongs(query);
      if (mounted) {
        setState(() {
          _matchedSongs = results;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
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
    _searchDebounce?.cancel();
    _searchController.dispose();
    _localScrollController.removeListener(_onScroll);
    _localScrollController.dispose();
    super.dispose();
  }

  void _handleShowMenu(
    BuildContext menuContext,
    Offset position,
    MusicFile file,
  ) {
    final songsToAdd = <MusicFile>[file];
    showSongContextMenu(
      menuContext,
      position,
      song: file,
      songs: songsToAdd,
      mode: SongContextMenuMode.full,
      onAddToPlaylist: () => showAddSongsToPlaylistDialog(
        menuContext,
        ref.read(playlistServiceProvider),
        songsToAdd,
      ),
      onPlayNext: () => ref
          .read(audioServiceProvider)
          .enqueueNext(songsToAdd),
      onAddToQueue: () => ref
          .read(audioServiceProvider)
          .appendToQueue(songsToAdd),
    );
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
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    final selectionLabel = l10n.selectedFolders(widget.selectedRootPaths.length);
    final rootListBottomPadding = isRootSelectionMode ? 224.0 : 160.0;

    final totalSongsCount = rootFolders.fold<int>(
      0,
      (sum, folder) => sum + scanner.getSongCountForFolder(folder),
    );
    final totalDurationMs = rootFolders.fold<int>(
      0,
      (sum, folder) => sum + scanner.getSongDurationForFolder(folder),
    );

    // We pass stub lists to satisfy LibrarySelectionPanel length checks.
    final selectedRootSongs = List.filled(widget.selectedRootPaths.length, MusicFile(path: '', name: ''));
    final allRootSongs = List.filled(rootFolders.length, MusicFile(path: '', name: ''));

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

      final representativeSong = () {
        for (final folder in rootFolders) {
          final song = scanner.getRepresentativeSongForFolder(folder);
          if (song != null) return song;
        }
        return null;
      }();

      final matchedRootFolders = _searchQuery.isNotEmpty
          ? _findMatchingFolders(rootFolders, _searchQuery)
          : rootFolders;

      final matchedSongs = _searchQuery.isNotEmpty
          ? _matchedSongs
          : <MusicFile>[];

      final noResults = _searchQuery.isNotEmpty && matchedRootFolders.isEmpty && matchedSongs.isEmpty;

      final double foldersBottomPadding = matchedSongs.isEmpty ? 160.0 : 16.0;

      Widget rootFoldersSliver;
      if (noResults) {
        rootFoldersSliver = SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 64.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noMatchingFoldersOrSongs,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else if (isGrid) {
        rootFoldersSliver = SliverLayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.crossAxisExtent;
            final crossAxisCount = switch (width) {
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
            final itemWidth = (width - 32 - (crossAxisCount - 1) * 16) / crossAxisCount;
            final childAspectRatio = itemWidth / (itemWidth + textHeight);

            final showSystemMedia = Platform.isAndroid && _searchQuery.isEmpty;
            final itemCount = matchedRootFolders.length + (showSystemMedia ? 1 : 0);

            return SliverPadding(
              padding: EdgeInsets.only(bottom: foldersBottomPadding, left: 16, right: 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: childAspectRatio,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (showSystemMedia && index == 0) {
                      final systemFolder = scanner.systemMediaFolder ??
                          MusicFolder(
                            path: 'system',
                            name: l10n.systemMediaLibrary,
                          );
                      final songsCount = scanner.getSongCountForFolder(systemFolder);
                      final representativeSong = scanner.getRepresentativeSongForFolder(systemFolder);
                      
                      return AnimatedOpacity(
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 180),
                        child: HoverableCard(
                          child: FolderGridCard(
                            folder: systemFolder,
                            songsCount: songsCount,
                            representativeSong: representativeSong,
                            subtitle: hasPermission ? null : l10n.needPermissionToScan,
                            onTap: () async {
                              if (!hasPermission) {
                                await scanner.checkAndRequestPermissions();
                              }
                              if (context.mounted) {
                                widget.onNavigateTo(
                                  scanner.systemMediaFolder ??
                                      MusicFolder(
                                        path: 'system',
                                        name: l10n.systemMediaLibrary,
                                      ),
                                );
                              }
                            },
                          ),
                        ),
                      );
                    }

                    final folderIndex = showSystemMedia ? index - 1 : index;
                    final folder = matchedRootFolders[folderIndex];
                    final isRootAvailable = scanner.isRootPathAvailable(folder.path);
                    final representativeSong = scanner.getRepresentativeSongForFolder(folder);
                    return AnimatedOpacity(
                      opacity: isRootAvailable ? 1.0 : 0.45,
                      duration: const Duration(milliseconds: 180),
                      child: HoverableCard(
                        child: FolderGridCard(
                          folder: folder,
                          songsCount: scanner.getSongCountForFolder(folder),
                          representativeSong: representativeSong,
                          onTap: isRootAvailable ? () => widget.onNavigateTo(folder) : null,
                          onLongPress: () => widget.onShowFolderBottomSheet(folder, isRoot: true),
                          onSecondaryTapDown: (details) => widget.onShowFolderBottomSheet(folder, isRoot: true),
                        ),
                      ),
                    );
                  },
                  childCount: itemCount,
                ),
              ),
            );
          },
        );
      } else {
        rootFoldersSliver = SliverPadding(
          padding: EdgeInsets.only(bottom: foldersBottomPadding),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final folder = matchedRootFolders[index];
                final isRootAvailable = scanner.isRootPathAvailable(folder.path);
                final representativeSong = scanner.getRepresentativeSongForFolder(folder);
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
                      songsCount: scanner.getSongCountForFolder(folder),
                      representativeSong: representativeSong,
                      onTap: isRootAvailable ? () => widget.onNavigateTo(folder) : null,
                      onLongPress: () => widget.onShowFolderBottomSheet(folder, isRoot: true),
                      onSecondaryTapDown: (details) => widget.onShowFolderBottomSheet(folder, isRoot: true),
                    ),
                  ),
                );
              },
              childCount: matchedRootFolders.length,
            ),
          ),
        );
      }

      Widget songsSliver;
      final isSongGrid = settings.folderViewMode == FolderViewMode.grid;
      if (matchedSongs.isEmpty) {
        songsSliver = const SliverToBoxAdapter(child: SizedBox.shrink());
      } else if (isSongGrid) {
        songsSliver = SliverLayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.crossAxisExtent;
            final crossAxisCount = switch (width) {
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
            final itemWidth = (width - 32 - (crossAxisCount - 1) * 16) / crossAxisCount;
            final childAspectRatio = itemWidth / (itemWidth + textHeight);

            return SliverPadding(
              padding: const EdgeInsets.only(bottom: 160, left: 16, right: 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: childAspectRatio,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, fileIndex) {
                    final file = matchedSongs[fileIndex];
                    final isCurrent = currentMusic?.path == file.path;
                    return HoverableCard(
                      child: SongGridCard(
                        song: file,
                        isCurrent: isCurrent,
                        isPlaying: ref.watch(audioIsPlayingProvider),
                        isSelected: false,
                        isSelectionMode: false,
                        onTap: () async {
                          unawaited(() async {
                            try {
                               await audio.playPlaylist(
                                 matchedSongs,
                                 initialIndex: fileIndex,
                                 source: PlaybackSource(
                                   type: PlaybackSourceType.folder,
                                   id: 'search_results',
                                   name: l10n.search,
                                 ),
                               );
                            } catch (e, st) {
                              debugPrint(
                                'FolderRootView: failed to start matched song playback: $e',
                              );
                              debugPrintStack(stackTrace: st);
                            }
                          }());

                          await widget.onOpenPlayback?.call();
                        },
                        onLongPress: () {},
                        onSecondaryTapDown: (details) {
                          _handleShowMenu(context, details.globalPosition, file);
                        },
                      ),
                    );
                  },
                  childCount: matchedSongs.length,
                ),
              ),
            );
          },
        );
      } else {
        songsSliver = SliverPadding(
          padding: const EdgeInsets.only(top: 8, bottom: 160),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, fileIndex) {
                final file = matchedSongs[fileIndex];
                final isCurrent = currentMusic?.path == file.path;
                return GestureDetector(
                  key: ValueKey(file.path),
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) {
                    _handleShowMenu(context, details.globalPosition, file);
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).orientation == Orientation.portrait ? 8 : 16,
                      vertical: 4,
                    ),
                    child: SongTile(
                      song: file,
                      isCurrent: isCurrent,
                      isSelected: false,
                      isSelectionMode: false,
                      isHighlighted: false,
                      onTap: () async {
                        unawaited(() async {
                          try {
                             await audio.playPlaylist(
                               matchedSongs,
                               initialIndex: fileIndex,
                               source: PlaybackSource(
                                 type: PlaybackSourceType.folder,
                                 id: 'search_results',
                                 name: l10n.search,
                               ),
                             );
                          } catch (e, st) {
                            debugPrint(
                              'FolderRootView: failed to start matched song playback: $e',
                            );
                            debugPrintStack(stackTrace: st);
                          }
                        }());

                        await widget.onOpenPlayback?.call();
                      },
                      onLongPress: () {},
                      onSecondaryTapDown: (details) {
                        _handleShowMenu(context, details.globalPosition, file);
                      },
                      onMorePressed: (buttonContext) {
                        final renderObject = buttonContext.findRenderObject();
                        final renderBox = renderObject is RenderBox ? renderObject : null;
                        if (renderBox == null) return;
                        final Offset offset = renderBox.localToGlobal(Offset.zero);
                        _handleShowMenu(buttonContext, offset, file);
                      },
                    ),
                  ),
                );
              },
              childCount: matchedSongs.length,
            ),
          ),
        );
      }

      rootList = CustomScrollView(
        key: const ValueKey('root_folders_scroll_view'),
        controller: _localScrollController,
        cacheExtent: 1000.0,
        slivers: [
          SliverToBoxAdapter(
            child: FolderHeaderBanner(
              title: l10n.scanDirectory,
              subtitle: '',
              songsCount: totalSongsCount,
              totalDuration: Duration(milliseconds: totalDurationMs),
              coverWidget: representativeSong != null
                  ? SongThumbnail(
                      path: representativeSong.path,
                      id: representativeSong.id,
                      size: 100,
                      width: 100,
                      height: 100,
                      borderRadius: BorderRadius.zero,
                    )
                  : Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            HSLColor.fromAHSL(1.0, ('root'.hashCode.abs() % 360).toDouble(), 0.65, 0.45).toColor(),
                            HSLColor.fromAHSL(1.0, (('root'.hashCode.abs() % 360 + 40) % 360).toDouble(), 0.75, 0.35).toColor(),
                          ],
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.library_music_rounded, size: 40, color: Colors.white70),
                      ),
                    ),
              actionButtons: [
                FilledButton.icon(
                  onPressed: widget.onPickFolder,
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: Text(l10n.addRootDirectory),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                MediaQuery.of(context).size.width > 480
                    ? FilledButton.tonalIcon(
                        onPressed: totalSongsCount == 0
                            ? null
                            : () async {
                                final songs = await scanner.getAllRootSongs();
                                if (songs.isNotEmpty) {
                                  await audio.playPlaylist(
                                    songs,
                                    source: PlaybackSource(
                                      type: PlaybackSourceType.folder,
                                      id: 'root',
                                      name: l10n.scanDirectory,
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: Text(l10n.playAll),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : Tooltip(
                        message: l10n.playAll,
                        child: FilledButton.tonal(
                          onPressed: totalSongsCount == 0
                              ? null
                              : () async {
                                  final songs = await scanner.getAllRootSongs();
                                  if (songs.isNotEmpty) {
                                    await audio.playPlaylist(
                                      songs,
                                      source: PlaybackSource(
                                        type: PlaybackSourceType.folder,
                                        id: 'root',
                                        name: l10n.scanDirectory,
                                      ),
                                    );
                                  }
                                },
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, size: 16),
                        ),
                      ),
                const SizedBox(width: 8),
                MediaQuery.of(context).size.width > 480
                    ? FilledButton.tonalIcon(
                        onPressed: totalSongsCount == 0
                            ? null
                            : () async {
                                final songs = await scanner.getAllRootSongs();
                                if (songs.isNotEmpty) {
                                  await audio.playPlaylist(
                                    List.of(songs)..shuffle(),
                                    source: PlaybackSource(
                                      type: PlaybackSourceType.folder,
                                      id: 'root',
                                      name: l10n.scanDirectory,
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.shuffle_rounded, size: 16),
                        label: Text(l10n.shuffle),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : Tooltip(
                        message: l10n.shuffle,
                        child: FilledButton.tonal(
                          onPressed: totalSongsCount == 0
                              ? null
                              : () async {
                                  final songs = await scanner.getAllRootSongs();
                                  if (songs.isNotEmpty) {
                                    await audio.playPlaylist(
                                      List.of(songs)..shuffle(),
                                      source: PlaybackSource(
                                        type: PlaybackSourceType.folder,
                                        id: 'root',
                                        name: l10n.scanDirectory,
                                      ),
                                    );
                                  }
                                },
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Icon(Icons.shuffle_rounded, size: 16),
                        ),
                      ),
              ],
              actionButtonsScrollable: true,
              isSearching: _isSearching,
              searchController: _searchController,
              searchQuery: _searchQuery,
              searchHintText: '${l10n.search}...',
              onSearchQueryChanged: (val) {
                setState(() {
                  _searchQuery = val.trim();
                });
                _performSearch(val.trim());
              },
              onToggleSearch: (val) {
                setState(() {
                  _isSearching = val;
                  if (!val) {
                    _searchQuery = '';
                    _matchedSongs = [];
                  }
                });
              },
            ),
          ),
          if (Platform.isAndroid && _searchQuery.isEmpty && !isGrid)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).orientation == Orientation.portrait ? 8 : 16,
                  vertical: 4,
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  hoverColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                  leading: const Icon(
                    Icons.library_music,
                    color: Colors.purple,
                  ),
                  title: Text(AppLocalizations.of(context)!.systemMediaLibrary),
                  subtitle: hasPermission
                      ? null
                      : Text(
                          AppLocalizations.of(context)!.needPermissionToScan,
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                              name: AppLocalizations.of(context)!.systemMediaLibrary,
                            ),
                      );
                    }
                  },
                ),
              ),
            ),
          rootFoldersSliver,
          songsSliver,
        ],
      );
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
                        hideSongProperties: true,
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

  MusicFile? _findRepresentativeSongForRoots(List<MusicFolder> folders) {
    for (final folder in folders) {
      final song = findRepresentativeSong(folder);
      if (song != null) {
        return song;
      }
    }
    return null;
  }



  List<MusicFolder> _findMatchingFolders(List<MusicFolder> roots, String query) {
    final results = <MusicFolder>[];
    final lowercaseQuery = query.toLowerCase();

    void search(MusicFolder folder) {
      if (folder.name.toLowerCase().contains(lowercaseQuery)) {
        results.add(folder);
      }
      for (final sub in folder.subFolders) {
        search(sub);
      }
    }

    for (final root in roots) {
      search(root);
    }
    return results;
  }

  List<MusicFile> _findMatchingSongs(List<MusicFolder> roots, String query) {
    final results = <MusicFile>[];
    final lowercaseQuery = query.toLowerCase();

    void search(MusicFolder folder) {
      for (final file in folder.files) {
        final matchesName = file.name.toLowerCase().contains(lowercaseQuery);
        final matchesTitle = file.title?.toLowerCase().contains(lowercaseQuery) ?? false;
        final matchesArtist = file.artist?.toLowerCase().contains(lowercaseQuery) ?? false;
        final matchesAlbum = file.album?.toLowerCase().contains(lowercaseQuery) ?? false;
        if (matchesName || matchesTitle || matchesArtist || matchesAlbum) {
          results.add(file);
        }
      }
      for (final sub in folder.subFolders) {
        search(sub);
      }
    }

    for (final root in roots) {
      search(root);
    }
    return results;
  }

}
