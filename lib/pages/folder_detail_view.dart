import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_sorting.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import '../widgets/song_tile.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/song_thumbnail.dart';
import '../widgets/folder_grid_card.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/folder_helpers.dart';

class FolderDetailView extends ConsumerStatefulWidget {
  const FolderDetailView({
    super.key,
    required this.folder,
    required this.onOpenPlayback,
    required this.isSelectionMode,
    required this.selectedSongPaths,
    required this.selectedFolderPaths,
    required this.onNavigateTo,
    required this.onGoBack,
    required this.onToggleSelectionMode,
    required this.onToggleFolderSelection,
    required this.onToggleSelection,
    required this.onSelectAllVisible,
    required this.onClearAllSelection,
    required this.onLocateCurrentSong,
    required this.onShowFolderBottomSheet,
    required this.highlightedSongPath,
  });

  final MusicFolder folder;
  final Future<void> Function()? onOpenPlayback;
  final bool isSelectionMode;
  final Set<String> selectedSongPaths;
  final Set<String> selectedFolderPaths;
  final void Function(MusicFolder) onNavigateTo;
  final VoidCallback onGoBack;
  final VoidCallback onToggleSelectionMode;
  final void Function(String) onToggleFolderSelection;
  final void Function(String) onToggleSelection;
  final VoidCallback onSelectAllVisible;
  final VoidCallback onClearAllSelection;
  final VoidCallback onLocateCurrentSong;
  final void Function(MusicFolder, {required bool isRoot}) onShowFolderBottomSheet;
  final String? highlightedSongPath;

  @override
  ConsumerState<FolderDetailView> createState() => _FolderDetailViewState();
}

class _FolderDetailViewState extends ConsumerState<FolderDetailView> {
  late final ScrollController _localScrollController;
  late final TextEditingController _searchController;
  bool _isSearching = false;
  String _searchQuery = '';
  String? _lastHighlightedPath;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    final targetOffset = ref.read(scannerServiceProvider).getFolderScrollOffset(widget.folder.path);
    _localScrollController = ScrollController(initialScrollOffset: targetOffset);
    _localScrollController.addListener(_onScroll);

    if (widget.highlightedSongPath != null) {
      _lastHighlightedPath = widget.highlightedSongPath;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlightedSong());
    }
  }

  @override
  void didUpdateWidget(FolderDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedSongPath != null && widget.highlightedSongPath != _lastHighlightedPath) {
      _lastHighlightedPath = widget.highlightedSongPath;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlightedSong());
    }
  }

  void _onScroll() {
    ref.read(scannerServiceProvider).setFolderScrollOffset(
      widget.folder.path,
      _localScrollController.offset,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _localScrollController.removeListener(_onScroll);
    _localScrollController.dispose();
    super.dispose();
  }

  List<MusicFolder> _findMatchingFolders(MusicFolder root, String query) {
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

    for (final sub in root.subFolders) {
      search(sub);
    }
    return results;
  }

  List<MusicFile> _findMatchingSongs(MusicFolder root, String query) {
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

    search(root);
    return results;
  }

  void _scrollToHighlightedSong() {
    if (!mounted) return;
    final songPath = widget.highlightedSongPath;
    if (songPath == null) return;

    final fileIndex = widget.folder.files.indexWhere((file) => p.equals(file.path, songPath));
    if (fileIndex == -1) return;

    final hasPermission = ref.read(scannerServiceProvider).hasPermission;
    final showPermissionWarning = widget.folder.path == 'system' && !hasPermission;

    double fileOffset = 48.0;
    fileOffset += 190.0;

    if (showPermissionWarning) {
      fileOffset += 200.0;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = ((screenWidth - 16) / 196).floor().clamp(2, 6);
    final double cardWidth = (screenWidth - 32 - (crossAxisCount - 1) * 16) / crossAxisCount;
    final double cardHeight = cardWidth / 0.72;

    final totalGridItems = widget.folder.subFolders.length;
    final int rows = (totalGridItems / crossAxisCount).ceil();
    fileOffset += rows * (cardHeight + 16);
    fileOffset += fileIndex * 80.0;

    if (_localScrollController.hasClients) {
      final double viewportHeight = _localScrollController.position.viewportDimension;
      double targetOffset = fileOffset - (viewportHeight / 2) + 40.0;
      final maxScroll = _localScrollController.position.maxScrollExtent;
      targetOffset = targetOffset.clamp(0.0, maxScroll);

      _localScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  List<MusicFile> _getSelectedSongs() {
    final songs = <MusicFile>[];
    songs.addAll(
      widget.folder.allSongs.where(
        (file) => widget.selectedSongPaths.contains(file.path),
      ),
    );
    for (final sub in widget.folder.subFolders) {
      if (widget.selectedFolderPaths.contains(sub.path)) {
        songs.addAll(sub.allSongs);
      }
    }
    final seen = <String>{};
    return songs.where((song) => seen.add(song.path)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final hasPermission = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.hasPermission),
    );
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    final matchedFolders = _searchQuery.isNotEmpty
        ? _findMatchingFolders(widget.folder, _searchQuery)
        : widget.folder.subFolders;
    final matchedSongs = _searchQuery.isNotEmpty
        ? _findMatchingSongs(widget.folder, _searchQuery)
        : widget.folder.files;

    final showSelectionPanel =
        widget.isSelectionMode &&
        isUserRootSelectionContext(
          scanner,
          widget.folder,
          scanner.navigationHistory,
        );
    final selectionPanelHeight = showSelectionPanel ? 220.0 : 0.0;

    final representativeSong = findRepresentativeSong(widget.folder);

    Widget scrollBody;

    Widget subfoldersSliver;
    final gridItemsCount = matchedFolders.length;
    subfoldersSliver = gridItemsCount > 0
        ? SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final folder = matchedFolders[index];
                  final isSelected = widget.selectedFolderPaths.contains(folder.path);
                  final folderRepSong = findRepresentativeSong(folder);
                  return HoverableCard(
                    child: FolderGridCard(
                      folder: folder,
                      songsCount: folder.allSongs.length,
                      representativeSong: folderRepSong,
                      isSelected: isSelected,
                      isSelectionMode: widget.isSelectionMode,
                      onTap: widget.isSelectionMode
                          ? () => widget.onToggleFolderSelection(folder.path)
                          : () => widget.onNavigateTo(folder),
                      onLongPress: () {
                        if (!widget.isSelectionMode) {
                          widget.onToggleSelectionMode();
                          widget.onToggleFolderSelection(folder.path);
                        } else {
                          widget.onToggleFolderSelection(folder.path);
                        }
                      },
                      onSecondaryTapDown: (details) {
                        if (!widget.isSelectionMode) {
                          widget.onShowFolderBottomSheet(folder, isRoot: false);
                        }
                      },
                    ),
                  );
                },
                childCount: gridItemsCount,
              ),
            ),
          )
        : const SliverToBoxAdapter(child: SizedBox.shrink());

    Widget songsSliver;
    final noResults = _searchQuery.isNotEmpty && matchedFolders.isEmpty && matchedSongs.isEmpty;
    if (noResults) {
      songsSliver = SliverToBoxAdapter(
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
                  Localizations.localeOf(context).languageCode == 'zh' ? '未找到匹配的文件夹或歌曲' : 'No matching folders or songs found',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      songsSliver = SliverPadding(
        padding: const EdgeInsets.only(top: 8),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, fileIndex) {
              final file = matchedSongs[fileIndex];
              final isCurrent = currentMusic?.path == file.path;
              final isSelected = widget.selectedSongPaths.contains(file.path);
              final songsToAdd =
                  (widget.selectedSongPaths.isNotEmpty ||
                      widget.selectedFolderPaths.isNotEmpty)
                  ? _getSelectedSongs()
                  : <MusicFile>[file];

              void handleShowMenu(
                BuildContext menuContext,
                Offset position,
              ) {
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

              return GestureDetector(
                key: ValueKey(file.path),
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) {
                  handleShowMenu(context, details.globalPosition);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        MediaQuery.of(context).orientation ==
                            Orientation.portrait
                        ? 8
                        : 16,
                    vertical: 4,
                  ),
                  child: SongTile(
                    song: file,
                    isCurrent: isCurrent,
                    isSelected: isSelected,
                    isSelectionMode: widget.isSelectionMode,
                    isHighlighted: widget.highlightedSongPath == file.path,
                    onTap: widget.isSelectionMode
                        ? () => widget.onToggleSelection(file.path)
                        : () async {
                            unawaited(() async {
                              try {
                                await audio.playPlaylist(
                                  matchedSongs,
                                  initialIndex: fileIndex,
                                );
                              } catch (e, st) {
                                debugPrint(
                                  'FoldersPage: failed to start folder playback for ${file.path}: $e',
                                );
                                debugPrintStack(stackTrace: st);
                              }
                            }());

                            if (mounted) {
                              widget.onClearAllSelection();
                              await widget.onOpenPlayback?.call();
                            }
                          },
                    onLongPress: () {
                      if (!widget.isSelectionMode) {
                        widget.onToggleSelectionMode();
                        widget.onToggleSelection(file.path);
                      }
                    },
                    onSecondaryTapDown: (details) {
                      handleShowMenu(context, details.globalPosition);
                    },
                    onMorePressed: (buttonContext) {
                      final renderObject = buttonContext.findRenderObject();
                      final renderBox = renderObject is RenderBox ? renderObject : null;
                      if (renderBox == null) return;
                      final Offset offset = renderBox.localToGlobal(Offset.zero);
                      handleShowMenu(buttonContext, offset);
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

    scrollBody = CustomScrollView(
      key: ValueKey(widget.folder.path),
      controller: _localScrollController,
      scrollCacheExtent: const ScrollCacheExtent.pixels(1000.0),
      slivers: [
        SliverToBoxAdapter(
          child: _buildBreadcrumbs(widget.folder, scanner),
        ),
        SliverToBoxAdapter(
          child: _buildFolderHeaderBanner(
            context: context,
            folder: widget.folder,
            representativeSong: representativeSong,
            songsCount: widget.folder.allSongs.length,
            displayPath: ScannerPathUtils.cleanDisplayPath(widget.folder.path),
            onPlayAll: () => audio.playPlaylist(widget.folder.allSongs),
            onShuffle: () => audio.playPlaylist(List.of(widget.folder.allSongs)..shuffle()),
          ),
        ),
        if (widget.folder.path == 'system' && !hasPermission)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.noMediaLibraryPermission),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => scanner.checkAndRequestPermissions(),
                      child: Text(l10n.grantPermission),
                    ),
                  ],
                ),
              ),
            ),
          ),
        subfoldersSliver,
        songsSliver,
        SliverPadding(
          padding: EdgeInsets.only(bottom: 160 + selectionPanelHeight),
        ),
      ],
    );

    final selectedSongs = showSelectionPanel ? _getSelectedSongs() : <MusicFile>[];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        widget.onGoBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (widget.isSelectionMode && !showSelectionPanel)
                    Container(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(l10n.selectedSongs(_getSelectedSongs().length)),
                          const Spacer(),
                          TextButton(
                            onPressed: widget.onToggleSelectionMode,
                            child: Text(l10n.cancel),
                          ),
                        ],
                      ),
                    ),
                  Expanded(child: scrollBody),
                ],
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
                  child: showSelectionPanel
                      ? LibrarySelectionPanel(
                          key: const ValueKey('folder-selection-panel'),
                          selectedSongs: selectedSongs,
                          allSongs: widget.folder.allSongs,
                          onToggleSelectAll: () {
                            final isAllSelected =
                                selectedSongs.length == widget.folder.allSongs.length &&
                                widget.folder.allSongs.isNotEmpty;
                            if (isAllSelected) {
                              widget.onClearAllSelection();
                            } else {
                              widget.onSelectAllVisible();
                            }
                          },
                          onCancel: widget.onClearAllSelection,
                          onOpenLocation: (widget.selectedFolderPaths.length == 1 &&
                                  widget.selectedSongPaths.isEmpty)
                              ? () => openFolderLocation(widget.selectedFolderPaths.first)
                              : null,
                          openLocationLabel: (widget.selectedFolderPaths.length == 1 &&
                                  widget.selectedSongPaths.isEmpty)
                              ? l10n.openFolderLocation
                              : null,
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('folder-selection-panel-hidden'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs(MusicFolder current, ScannerService scanner) {
    final theme = Theme.of(context);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final settings = ref.watch(settingsServiceProvider);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    List<Widget> breadcrumbItems = [];

    breadcrumbItems.add(
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onGoBack,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Icon(
              Icons.arrow_back_rounded,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );

    breadcrumbItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );

    breadcrumbItems.add(
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            scanner.setNavigationState(null, []);
            widget.onClearAllSelection();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Icon(
              Icons.home_rounded,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );

    for (int i = 0; i < scanner.navigationHistory.length; i++) {
      final folder = scanner.navigationHistory[i];
      breadcrumbItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      );
      breadcrumbItems.add(
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              scanner.setNavigationState(
                folder,
                scanner.navigationHistory.take(i).toList(),
              );
              widget.onClearAllSelection();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Text(
                folder.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
      );
    }

    breadcrumbItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
    breadcrumbItems.add(
      Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        child: Text(
          current.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: breadcrumbItems),
            ),
          ),
          const SizedBox(width: 8),
          if (currentMusic != null) ...[
            IconButton(
              icon: const Icon(Icons.my_location_rounded),
              onPressed: widget.onLocateCurrentSong,
              tooltip: AppLocalizations.of(context)!.locateCurrentSong,
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: Icon(
              settings.folderViewMode == FolderViewMode.grid
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
            ),
            onPressed: () {
              settings.folderViewMode = settings.folderViewMode == FolderViewMode.grid
                  ? FolderViewMode.list
                  : FolderViewMode.grid;
            },
            tooltip: settings.folderViewMode == FolderViewMode.grid
                ? (isZh ? '列表视图' : 'List View')
                : (isZh ? '网格视图' : 'Grid View'),
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => _showSortDialog(context, scanner),
            tooltip: AppLocalizations.of(context)!.sort,
          ),
        ],
      ),
    );
  }

  void _showSortDialog(BuildContext context, ScannerService scanner) {
    final currentFolder = widget.folder;
    final currentFolderPath = currentFolder.path;
    final globalSettings = scanner.getGlobalSortSettings();
    final currentFolderSettings = scanner.getSortSettingsForFolder(currentFolderPath);
    final initialScope = scanner.hasSortOverrideForFolder(currentFolderPath)
        ? SortScope.currentFolder
        : SortScope.global;
    var selectedScope = initialScope;
    var selectedCriteria = initialScope == SortScope.currentFolder
        ? currentFolderSettings.criteria
        : globalSettings.criteria;
    var selectedOrder = initialScope == SortScope.currentFolder
        ? currentFolderSettings.order
        : globalSettings.order;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void syncSelectionForScope(SortScope scope) {
              final settings =
                  scope == SortScope.currentFolder
                  ? scanner.getSortSettingsForFolder(currentFolderPath)
                  : scanner.getGlobalSortSettings();
              selectedCriteria = settings.criteria;
              selectedOrder = settings.order;
            }

            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.sortBy),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.sortScope,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  RadioGroup<SortScope>(
                    onChanged: (v) {
                      if (v == null || v == selectedScope) return;
                      setState(() {
                        selectedScope = v;
                        syncSelectionForScope(v);
                      });
                    },
                    groupValue: selectedScope,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(
                            AppLocalizations.of(context)!.currentFolderScope,
                          ),
                          leading: const Radio(
                            value: SortScope.currentFolder,
                          ),
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(context)!.globalScope,
                          ),
                          leading: const Radio(value: SortScope.global),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.sortBy,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  RadioGroup<SortCriteria>(
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        selectedCriteria = v;
                      });
                      scanner.setSortCriteria(
                        v,
                        scope: selectedScope,
                        folderPath: currentFolder.path,
                      );
                    },
                    groupValue: selectedCriteria,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(AppLocalizations.of(context)!.title),
                          leading: const Radio(value: SortCriteria.title),
                        ),
                        ListTile(
                          title: Text(AppLocalizations.of(context)!.fileName),
                          leading: const Radio(value: SortCriteria.filename),
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(context)!.trackNumber,
                          ),
                          leading: const Radio(value: SortCriteria.trackNumber),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.sortOrder,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  RadioGroup<SortOrder>(
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        selectedOrder = v;
                      });
                      scanner.setSortOrder(
                        v,
                        scope: selectedScope,
                        folderPath: currentFolder.path,
                      );
                    },
                    groupValue: selectedOrder,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(AppLocalizations.of(context)!.ascending),
                          leading: const Radio(value: SortOrder.ascending),
                        ),
                        ListTile(
                          title: Text(AppLocalizations.of(context)!.descending),
                          leading: const Radio(value: SortOrder.descending),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.confirm),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFolderHeaderBanner({
    required BuildContext context,
    required MusicFolder folder,
    required MusicFile? representativeSong,
    required int songsCount,
    required String displayPath,
    required VoidCallback onPlayAll,
    required VoidCallback onShuffle,
  }) {
    final theme = Theme.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final int hash = folder.path.hashCode;
    final double hue = (hash.abs() % 360).toDouble();
    final Color startColor = HSLColor.fromAHSL(1.0, hue, 0.65, 0.45).toColor();
    final Color endColor = HSLColor.fromAHSL(1.0, (hue + 40) % 360, 0.75, 0.35).toColor();

    Widget coverWidget;
    if (representativeSong != null) {
      coverWidget = SongThumbnail(
        path: representativeSong.path,
        id: representativeSong.id,
        size: 100,
        width: 100,
        height: 100,
      );
    } else {
      coverWidget = Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [startColor, endColor],
          ),
        ),
        child: const Center(
          child: Icon(Icons.folder_rounded, size: 40, color: Colors.white70),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.5),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Hero(
                tag: 'folder-cover-${folder.path}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: coverWidget,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayPath,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isZh ? '$songsCount 首歌曲' : '$songsCount songs',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isSearching
                ? Row(
                    key: const ValueKey('search-active-row'),
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: theme.textTheme.bodyMedium,
                          decoration: InputDecoration(
                            hintText: isZh ? '在当前目录及子目录下搜索...' : 'Search in folder and subfolders...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 20),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            isDense: true,
                          ),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val.trim();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _isSearching = false;
                            _searchQuery = '';
                          });
                        },
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('actions-normal-row'),
                    children: [
                      FilledButton.icon(
                        onPressed: onPlayAll,
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: Text(isZh ? '播放全部' : 'Play All'),
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
                      FilledButton.tonalIcon(
                        onPressed: onShuffle,
                        icon: const Icon(Icons.shuffle_rounded, size: 16),
                        label: Text(isZh ? '随机播放' : 'Shuffle'),
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
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isSearching = true;
                          });
                        },
                        icon: const Icon(Icons.search_rounded, size: 16),
                        tooltip: isZh ? '搜索' : 'Search',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
