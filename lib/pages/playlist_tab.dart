import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/library/playlist_service.dart';
import '../dialogs/playlist_manager_dialog.dart';
import '../widgets/song_tile.dart';
import 'package:vynody/utils/file_selector_helper.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/utils/deleted_song_snack.dart';
import 'package:vynody/utils/playlist_name.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import 'package:vynody/utils/layout_constants.dart';
import '../utils/app_snack_bar.dart';

class PlaylistTab extends ConsumerStatefulWidget {
  final double contentTopPadding;
  final double contentLeftPadding;

  const PlaylistTab({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  @override
  ConsumerState<PlaylistTab> createState() => _PlaylistTabState();
}

class _PlaylistTabState extends ConsumerState<PlaylistTab>
    with SelectionStateMixin<PlaylistTab, int> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.playlist;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }


  void _showAddToPlaylistDialog(
    BuildContext context,
    List<MusicFile> selectedSongs,
  ) {
    final playlistService = ref.read(playlistServiceProvider);
    showAddSongsToPlaylistDialog(
      context,
      playlistService,
      selectedSongs,
      onPlaylistCreatedOrUpdated: () {
        cancelSelection();
      },
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.createPlaylist),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.playlistName,
              hintText: AppLocalizations.of(context)!.enterPlaylistName,
              errorText: errorText,
            ),
            onChanged: (val) {
              if (errorText != null) {
                setState(() {
                  errorText = null;
                });
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final playlistService = ref.read(playlistServiceProvider);
                  if (playlistService.playlistExists(name)) {
                    setState(() {
                      errorText = AppLocalizations.of(
                        context,
                      )!.playlistNameExists;
                    });
                    return;
                  }
                  await playlistService.createPlaylist(name);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }
              },
              child: Text(AppLocalizations.of(context)!.createPlaylist),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _importM3uPlaylist(BuildContext context) async {
    try {
      final filePaths = await FileSelectorHelper.pickFiles(
        extensions: ['m3u', 'm3u8'],
        label: 'M3U Playlist',
      );
      if (filePaths == null || filePaths.isEmpty || !context.mounted) return;

      final playlistService = ref.read(playlistServiceProvider);
      final scannerRoots = ref.read(scannerServiceProvider).rootPaths;
      final l10n = AppLocalizations.of(context)!;
      final imported = await playlistService.importPlaylistsFromM3u(
        filePaths,
        rootPaths: scannerRoots,
      );

      if (!context.mounted) return;
      if (imported.isNotEmpty) {
        final last = imported.last;
        AppSnackBar.show(
          context,
          ref,
          SnackBar(
            content: Text(
              l10n.importPlaylistSuccess(last.name, last.songs.length),
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context)!;
      AppSnackBar.show(
        context,
        ref,
        SnackBar(
          content: Text(l10n.importPlaylistFailed(e.toString())),
        ),
      );
    }
  }

  Future<void> _exportPlaylistAsM3u(
    BuildContext context,
    Playlist playlist,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (playlist.songs.isEmpty) {
      AppSnackBar.show(
        context,
        ref,
        SnackBar(
          content: Text(l10n.noSongsInPlaylist),
        ),
      );
      return;
    }

    try {
      final playlistService = ref.read(playlistServiceProvider);
      final scannerRoots = ref.read(scannerServiceProvider).rootPaths;
      final m3uContent = playlistService.exportPlaylistToM3u(
        playlist,
        rootPaths: scannerRoots,
      );
      final bytes = Uint8List.fromList(utf8.encode(m3uContent));
      final safeName = playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final suggestedName = '$safeName.m3u8';

      final savedPath = await FileSelectorHelper.saveFile(
        suggestedName: suggestedName,
        extensions: ['m3u8', 'm3u'],
        label: 'M3U8 Playlist',
        bytes: bytes,
      );

      if (savedPath != null && context.mounted) {
        AppSnackBar.show(
          context,
          ref,
          SnackBar(
            content: Text(l10n.exportPlaylistSuccess),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        ref,
        SnackBar(
          content: Text(l10n.exportPlaylistFailed(e.toString())),
        ),
      );
    }
  }



  Widget _buildHeader(BuildContext context, Playlist? currentPlaylist) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final hasSongs = currentPlaylist?.songs.isNotEmpty == true;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final horizontalPadding = isPortrait ? 12.0 : 16.0;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.playlist,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => PlaylistManagerDialog.show(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  currentPlaylist == null
                                      ? l10n.emptyList
                                      : localizedPlaylistName(
                                          context,
                                          currentPlaylist,
                                        ),
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.arrow_drop_down,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasSongs) ...[
                  IconButton(
                    tooltip: l10n.clearPlaylist,
                    onPressed: () {
                      if (currentPlaylist != null) {
                        ref
                            .read(playlistServiceProvider)
                            .clearPlaylist(currentPlaylist.id);
                      }
                    },
                    icon: const Icon(Icons.clear_all),
                  ),
                  const SizedBox(width: 8),
                ],
                PopupMenuButton<String>(
                  tooltip: l10n.more,
                  onSelected: (value) {
                    if (value == 'create') {
                      _showCreatePlaylistDialog(context);
                    } else if (value == 'import') {
                      _importM3uPlaylist(context);
                    } else if (value == 'export' && currentPlaylist != null) {
                      _exportPlaylistAsM3u(context, currentPlaylist);
                    }
                  },
                  itemBuilder: (context) => [
                    buildContextMenuItem<String>(
                      value: 'create',
                      label: l10n.createPlaylist,
                      icon: Icons.add_rounded,
                      context: context,
                    ),
                    buildContextMenuItem<String>(
                      value: 'import',
                      label: l10n.importPlaylist,
                      icon: Icons.file_download_outlined,
                      context: context,
                    ),
                    if (currentPlaylist != null && currentPlaylist.songs.isNotEmpty)
                      buildContextMenuItem<String>(
                        value: 'export',
                        label: l10n.exportPlaylist,
                        icon: Icons.file_upload_outlined,
                        context: context,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.playlist_add,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.emptyList,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            if (Platform.isWindows)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  l10n.dragToAddMusic,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isSelectionMode =
        ref.watch(librarySelectionScopeProvider) ==
        LibrarySelectionScope.playlist;
    final audio = ref.read(audioServiceProvider);
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final playlistService = ref.watch(playlistServiceProvider);
    final currentPlaylist = playlistService.currentPlaylist;

    if (currentPlaylist == null || currentPlaylist.songs.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(
          top: widget.contentTopPadding,
          left: widget.contentLeftPadding,
        ),
        child: Column(
          children: [
            _buildHeader(context, currentPlaylist),
            Expanded(child: _buildEmptyState(context)),
          ],
        ),
      );
    }

    final Playlist activePlaylist = currentPlaylist;
    final selectedSongs = selectedKeys
        .map((i) => activePlaylist.songs[i])
        .toList();

    return Padding(
      padding: EdgeInsets.only(left: widget.contentLeftPadding),
      child: Stack(
        children: [
          CustomScrollView(
              controller: _scrollController,
              cacheExtent: 1000,
              slivers: [
                if (widget.contentTopPadding > 0)
                  SliverToBoxAdapter(
                    child: SizedBox(height: widget.contentTopPadding),
                  ),
                SliverToBoxAdapter(child: _buildHeader(context, activePlaylist)),
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom:
                      (currentMusic != null ? 140.0 : 40.0) +
                      (isSelectionMode ? 220.0 : 0.0),
                ),
                sliver: SliverReorderableList(
                  itemCount: activePlaylist.songs.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    reorderSelection(oldIndex, newIndex);
                    playlistService.reorderSongsInPlaylist(
                      activePlaylist.id,
                      oldIndex,
                      newIndex,
                    );
                  },
                  itemBuilder: (context, index) {
                    final song = activePlaylist.songs[index];
                    final isMissing = song.isMissing;
                    final isCurrent =
                        currentIndex == index &&
                        currentMusic?.path == song.path;
                    final isSelected = this.isSelected(index);

                    void handleShowMenu(
                      BuildContext menuContext,
                      Offset position,
                    ) {
                      final songsToAdd = selectedKeys.isNotEmpty
                          ? selectedKeys
                                .map((i) => activePlaylist.songs[i])
                                .toList()
                          : <MusicFile>[song];

                      showSongContextMenu(
                        menuContext,
                        position,
                        song: song,
                        songs: songsToAdd,
                        mode: SongContextMenuMode.full,
                        onAddToPlaylist: () async {
                          _showAddToPlaylistDialog(menuContext, songsToAdd);
                        },
                        onPlayNext: () => ref
                            .read(audioServiceProvider)
                            .enqueueNext(songsToAdd),
                        onAddToQueue: () => ref
                            .read(audioServiceProvider)
                            .appendToQueue(songsToAdd),
                        onRemoveFromPlaylist: isSelectionMode
                            ? null
                            : () {
                                playlistService.removeSongsFromPlaylist(
                                  activePlaylist.id,
                                  [index],
                                );
                              },
                      );
                    }

                    final selectedSongPaths = isSelectionMode
                        ? selectedKeys
                            .map((i) => (i >= 0 && i < activePlaylist.songs.length)
                                ? activePlaylist.songs[i].path
                                : null)
                            .whereType<String>()
                            .toSet()
                        : const <String>{};

                    return Align(
                      key: ObjectKey(song),
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 2,
                          ),
                          child: SongTile(
                            song: song,
                            isCurrent: isCurrent,
                            isSelected: isSelected,
                            isSelectionMode: isSelectionMode,
                            selectedPaths: selectedSongPaths,
                            dragHandle: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                            onTap: () {
                              if (isMissing) {
                                showDeletedSongSnack(
                                  context,
                                  ref,
                                  skipped: false,
                                );
                                return;
                              }

                              handleItemTap(
                                index: index,
                                itemKey: index,
                                allKeys: List.generate(
                                  activePlaylist.songs.length,
                                  (i) => i,
                                ),
                                onNormalTap: () {
                                  audio.playPlaylist(
                                    activePlaylist.songs,
                                    initialIndex: index,
                                    source: PlaybackSource(
                                      type: PlaybackSourceType.playlist,
                                      id: activePlaylist.id,
                                      name: activePlaylist.name,
                                    ),
                                  );
                                },
                              );
                            },
                            onLongPress: () {
                              lastAnchorIndex = index;
                              if (!isSelectionMode) {
                                enterSelectionMode(index);
                              }
                            },
                            onSecondaryTapDown: (details) {
                              handleShowMenu(context, details.globalPosition);
                            },
                            onMorePressed: (buttonContext) {
                              final renderObject = buttonContext.findRenderObject();
                              final renderBox = renderObject is RenderBox
                                  ? renderObject
                                  : null;
                              if (renderBox == null) return;
                              final Offset offset = renderBox.localToGlobal(
                                Offset.zero,
                              );
                              handleShowMenu(buttonContext, offset);
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          AnimatedSelectionPanel(
            isVisible: isSelectionMode,
            child: LibrarySelectionPanel(
              key: const ValueKey('library-selection-panel'),
              selectedSongs: selectedSongs,
              allSongs: activePlaylist.songs,
              onToggleSelectAll: () => toggleSelectAll(
                List.generate(activePlaylist.songs.length, (i) => i),
              ),
              onCancel: cancelSelection,
              replaceFavoritesWithSongDetails: true,
              onDelete: () {
                final indices = selectedKeys.toList()..sort();
                playlistService.removeSongsFromPlaylist(
                  activePlaylist.id,
                  indices,
                );
                AppSnackBar.show(
                  context,
                  ref,
                  SnackBar(
                    content: Text(l10n.deletedSongs(indices.length)),
                  ),
                );
                cancelSelection();
              },
            ),
          ),
        ],
      ),
    );
  }
}


