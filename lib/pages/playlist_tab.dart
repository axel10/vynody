import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../player/audio_riverpod.dart';
import '../player/playlist_service.dart';
import '../utils/deleted_song_snack.dart';
import '../widgets/song_thumbnail.dart';
import '../utils/app_snack_bar.dart';
import 'playlist_page_riverpod.dart';

class PlaylistTab extends ConsumerStatefulWidget {
  const PlaylistTab({super.key});

  @override
  ConsumerState<PlaylistTab> createState() => _PlaylistTabState();
}

class _PlaylistTabState extends ConsumerState<PlaylistTab> {
  final Set<int> _selectedIndices = {};

  @override
  void dispose() {
    Future.microtask(() {
      ref.read(playlistSelectionModeProvider.notifier).setEnabled(false);
    });
    super.dispose();
  }

  void _toggleSelectionMode() {
    final isSelectionMode = ref.read(playlistSelectionModeProvider);
    ref.read(playlistSelectionModeProvider.notifier).setEnabled(!isSelectionMode);
    setState(() {
      if (isSelectionMode) {
        _selectedIndices.clear();
      }
    });
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _reorderSelectedIndices(int oldIndex, int newIndex) {
    if (_selectedIndices.isEmpty) return;

    final updated = <int>{};
    for (final index in _selectedIndices) {
      if (index == oldIndex) {
        updated.add(newIndex);
      } else if (oldIndex < newIndex) {
        if (index > oldIndex && index <= newIndex) {
          updated.add(index - 1);
        } else {
          updated.add(index);
        }
      } else if (newIndex < oldIndex) {
        if (index >= newIndex && index < oldIndex) {
          updated.add(index + 1);
        } else {
          updated.add(index);
        }
      } else {
        updated.add(index);
      }
    }

    _selectedIndices
      ..clear()
      ..addAll(updated);
  }

  void _showAddToPlaylistDialog(
    BuildContext context,
    List<MusicFile> selectedSongs,
  ) {
    final playlistService = ref.read(playlistServiceProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.addToPlaylist),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: playlistService.playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlistService.playlists[index];
              return ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text(playlist.name),
                subtitle: Text(
                  AppLocalizations.of(
                    context,
                  )!.songCount(playlist.songs.length),
                ),
                onTap: () {
                  playlistService.addSongsToPlaylist(
                    playlist.id,
                    selectedSongs,
                  );
                  Navigator.pop(context);
                  AppSnackBar.show(
                    context,
                    ref,
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.addedToPlaylist(selectedSongs.length, playlist.name),
                      ),
                    ),
                  );
                  _toggleSelectionMode();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showCreatePlaylistAndAddDialog(context, selectedSongs);
            },
            child: Text(AppLocalizations.of(context)!.createNewList),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistAndAddDialog(
    BuildContext context,
    List<MusicFile> selectedSongs,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.createPlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.playlistName,
            hintText: AppLocalizations.of(context)!.enterPlaylistName,
          ),
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
                final playlist = await ref
                    .read(playlistServiceProvider)
                    .createPlaylist(name);
                if (context.mounted) {
                  ref
                      .read(playlistServiceProvider)
                      .addSongsToPlaylist(playlist.id, selectedSongs);
                  Navigator.pop(context);
                  AppSnackBar.show(
                    context,
                    ref,
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.createdPlaylist(name, selectedSongs.length),
                      ),
                    ),
                  );
                  _toggleSelectionMode();
                }
              }
            },
            child: Text(AppLocalizations.of(context)!.createPlaylist),
          ),
        ],
      ),
    );
  }

  Widget? _buildDurationTrailing(int? durationMs) {
    if (durationMs == null) return null;
    final d = Duration(milliseconds: durationMs);
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return Text(
      '$minutes:$seconds',
      style: const TextStyle(fontSize: 12, color: Colors.grey),
    );
  }

  bool _isFavoritePlaylist(Playlist playlist) {
    return playlist.id == PlaylistService.favoritePlaylistId;
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.createPlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.playlistName,
            hintText: AppLocalizations.of(context)!.enterPlaylistName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(playlistServiceProvider).createPlaylist(name);
                Navigator.pop(context);
              }
            },
            child: Text(AppLocalizations.of(context)!.createPlaylist),
          ),
        ],
      ),
    );
  }

  void _showRenamePlaylistDialog(BuildContext context, Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.renamePlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.playlistName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref
                    .read(playlistServiceProvider)
                    .renamePlaylist(playlist.id, name);
                Navigator.pop(context);
              }
            },
            child: Text(AppLocalizations.of(context)!.confirm),
          ),
        ],
      ),
    );
  }

  void _showDeletePlaylistDialog(BuildContext context, Playlist playlist) {
    if (_isFavoritePlaylist(playlist)) {
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deletePlaylist),
        content: Text(
          AppLocalizations.of(context)!.confirmDeletePlaylist(playlist.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(playlistServiceProvider).deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
  }

  void _showPlaylistOptions(BuildContext context, Playlist playlist) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(AppLocalizations.of(context)!.rename),
              enabled: !_isFavoritePlaylist(playlist),
              onTap: () {
                if (_isFavoritePlaylist(playlist)) return;
                Navigator.pop(context);
                _showRenamePlaylistDialog(context, playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text(AppLocalizations.of(context)!.delete),
              enabled: !_isFavoritePlaylist(playlist),
              onTap: () {
                if (_isFavoritePlaylist(playlist)) return;
                Navigator.pop(context);
                _showDeletePlaylistDialog(context, playlist);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaylistSelector(BuildContext context) {
    final playlistService = ref.read(playlistServiceProvider);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...playlistService.playlists.map(
              (playlist) => ListTile(
                leading: Icon(
                  _isFavoritePlaylist(playlist)
                      ? Icons.favorite_rounded
                      : Icons.playlist_play,
                  color: _isFavoritePlaylist(playlist)
                      ? Colors.redAccent
                      : null,
                ),
                title: Text(playlist.name),
                subtitle: Text(
                  AppLocalizations.of(
                    context,
                  )!.songCount(playlist.songs.length),
                ),
                trailing: playlist.id == playlistService.currentPlaylist?.id
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  playlistService.setCurrentPlaylist(playlist.id);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(AppLocalizations.of(context)!.createNewPlaylist),
              onTap: () {
                Navigator.pop(context);
                _showCreatePlaylistDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaylistManager(BuildContext context) {
    final playlistService = ref.read(playlistServiceProvider);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                AppLocalizations.of(context)!.managePlaylists,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(),
            ...playlistService.playlists.map(
              (playlist) => ListTile(
                leading: Icon(
                  _isFavoritePlaylist(playlist)
                      ? Icons.favorite_rounded
                      : Icons.playlist_play,
                  color: _isFavoritePlaylist(playlist)
                      ? Colors.redAccent
                      : null,
                ),
                title: Text(playlist.name),
                subtitle: Text(
                  '${AppLocalizations.of(context)!.songCount(playlist.songs.length)} · ${_formatDate(playlist.updatedAt)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: _isFavoritePlaylist(playlist)
                      ? null
                      : () {
                          Navigator.pop(context);
                          _showPlaylistOptions(context, playlist);
                        },
                ),
                onTap: () {
                  playlistService.setCurrentPlaylist(playlist.id);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildHeader(BuildContext context, Playlist? currentPlaylist) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final hasSongs = currentPlaylist?.songs.isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
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
                  onTap: () => _showPlaylistSelector(context),
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
                            currentPlaylist?.name ?? l10n.emptyList,
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
            IconButton.filledTonal(
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
            tooltip: l10n.managePlaylists,
            onSelected: (value) {
              if (value == 'create') {
                _showCreatePlaylistDialog(context);
              } else if (value == 'manage') {
                _showPlaylistManager(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'create',
                child: ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(l10n.createPlaylist),
                ),
              ),
              PopupMenuItem(
                value: 'manage',
                child: ListTile(
                  leading: const Icon(Icons.list),
                  title: Text(l10n.managePlaylists),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isSelectionMode = ref.watch(playlistSelectionModeProvider);
    final audio = ref.read(audioServiceProvider);
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final playlistService = ref.watch(playlistServiceProvider);
    ref.watch(
      scannerServiceProvider.select(
        (scanner) => (scanner.metadataRevision, scanner.isScanning),
      ),
    );
    final scanner = ref.read(scannerServiceProvider);
    final currentPlaylist = playlistService.currentPlaylist;

    if (currentPlaylist == null || currentPlaylist.songs.isEmpty) {
      return Column(
        children: [
          _buildHeader(context, currentPlaylist),
          Expanded(child: _buildEmptyState(context)),
        ],
      );
    }

    final Playlist activePlaylist = currentPlaylist;

    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(context, activePlaylist),
            if (isSelectionMode)
              Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(l10n.selectedSongs(_selectedIndices.length)),
                    const Spacer(),
                    TextButton(
                      onPressed: _toggleSelectionMode,
                      child: Text(l10n.cancel),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                cacheExtent: 1000,
                padding: const EdgeInsets.only(bottom: 160),
                itemCount: activePlaylist.songs.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  setState(() {
                    _reorderSelectedIndices(oldIndex, newIndex);
                  });
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
                      currentIndex == index && currentMusic?.path == song.path;
                  final isSelected = _selectedIndices.contains(index);
                  final textColor = isMissing
                      ? Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
                      : isCurrent
                      ? Theme.of(context).colorScheme.primary
                      : null;

                  return GestureDetector(
                    key: ObjectKey(song),
                    onLongPress: () {
                      if (!isSelectionMode) {
                        _toggleSelectionMode();
                        _toggleSelection(index);
                      }
                    },
                    child: ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Opacity(
                              opacity: isMissing
                                  ? 0.35
                                  : isSelectionMode
                                  ? (isSelected ? 0.5 : 0.7)
                                  : 1.0,
                              child: SongThumbnail(
                                path: song.path,
                                id: song.id,
                                size: 40.0,
                              ),
                            ),
                            if (isSelectionMode)
                              Positioned.fill(
                                child: Align(
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Checkbox(
                                      value: isSelected,
                                      onChanged: (_) => _toggleSelection(index),
                                      fillColor: WidgetStateProperty.all(
                                        Colors.white,
                                      ),
                                      checkColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      title: Text(
                        song.title ?? song.name,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: textColor,
                          fontWeight: isCurrent && !isMissing
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        '${scanner.metadataMap[song.path]?.artist ?? l10n.unknownArtist} - ${scanner.metadataMap[song.path]?.album ?? l10n.unknownAlbum}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: isMissing
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5)
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isSelectionMode
                          ? ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            )
                          : _buildDurationTrailing(
                              scanner.metadataMap[song.path]?.duration,
                            ),
                      onTap: isSelectionMode
                          ? () {
                              if (isMissing) {
                                showDeletedSongSnack(context, ref, skipped: false);
                                return;
                              }
                              _toggleSelection(index);
                            }
                          : () {
                              if (isMissing) {
                                showDeletedSongSnack(context, ref, skipped: false);
                                return;
                              }
                              audio.playPlaylist(
                                activePlaylist.songs,
                                initialIndex: index,
                              );
                            },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        if (isSelectionMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              elevation: 8,
              child: Container(
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: _selectedIndices.isEmpty
                              ? null
                              : () {
                                  final selectedSongs = _selectedIndices
                                      .map((i) => activePlaylist.songs[i])
                                      .toList();
                                  _showAddToPlaylistDialog(
                                    context,
                                    selectedSongs,
                                  );
                                },
                          icon: const Icon(Icons.playlist_add),
                          label: Text(l10n.addToPlaylist),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _selectedIndices.isEmpty
                              ? null
                              : () {
                                  final indices = _selectedIndices.toList()
                                    ..sort();
                                  playlistService.removeSongsFromPlaylist(
                                    activePlaylist.id,
                                    indices,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        l10n.deletedSongs(indices.length),
                                      ),
                                    ),
                                  );
                                  _toggleSelectionMode();
                                },
                          icon: const Icon(Icons.delete),
                          label: Text(l10n.delete),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
