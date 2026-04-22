import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../player/audio_riverpod.dart';
import '../player/playlist_service.dart';
import '../widgets/song_thumbnail.dart';
import '../utils/deleted_song_snack.dart';
import 'albums_tab.dart';

class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({super.key});

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage>
    with SingleTickerProviderStateMixin {
  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  late final TabController _tabController;
  int _tabIndex = 0;

  bool get _isPlaylistTab => _tabIndex == 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (_tabController.indexIsChanging) return;
        if (_tabIndex == _tabController.index) return;
        setState(() {
          _tabIndex = _tabController.index;
        });
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isFavoritePlaylist(Playlist playlist) {
    return playlist.id == PlaylistService.favoritePlaylistId;
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
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
                  ScaffoldMessenger.of(context).showSnackBar(
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
                  ScaffoldMessenger.of(context).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final audio = ref.read(audioServiceProvider);
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final playlistService = ref.watch(playlistServiceProvider);
    final scanner = ref.watch(scannerServiceProvider);
    final currentPlaylist = playlistService.currentPlaylist;

    return Scaffold(
      appBar: AppBar(
        title: _buildAppBarTitle(currentPlaylist, l10n),
        actions: _buildAppBarActions(
          context,
          l10n,
          playlistService,
          currentPlaylist,
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.playlist),
            Tab(text: l10n.albums),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildPlaylistBody(
            context,
            l10n,
            audio,
            currentIndex,
            currentMusic,
            playlistService,
            scanner,
            currentPlaylist,
          ),
          const AlbumsTab(),
        ],
      ),
    );
  }

  Widget _buildAppBarTitle(Playlist? currentPlaylist, AppLocalizations l10n) {
    if (!_isPlaylistTab) {
      return Text(l10n.albums);
    }
    if (currentPlaylist == null) {
      return Text(l10n.playlist);
    }
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _showPlaylistSelector(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    currentPlaylist.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAppBarActions(
    BuildContext context,
    AppLocalizations l10n,
    PlaylistService playlistService,
    Playlist? currentPlaylist,
  ) {
    if (!_isPlaylistTab) {
      return const [];
    }

    return [
      if (currentPlaylist != null && currentPlaylist.songs.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear_all),
          tooltip: l10n.emptyList,
          onPressed: () => playlistService.clearPlaylist(currentPlaylist.id),
        ),
      PopupMenuButton<String>(
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
    ];
  }

  Widget _buildPlaylistBody(
    BuildContext context,
    AppLocalizations l10n,
    audio,
    int currentIndex,
    MusicFile? currentMusic,
    PlaylistService playlistService,
    scanner,
    Playlist? currentPlaylist,
  ) {
    if (currentPlaylist == null || currentPlaylist.songs.isEmpty) {
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

    return Stack(
      children: [
        Column(
          children: [
            if (_isSelectionMode)
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
                padding: const EdgeInsets.only(bottom: 160),
                itemCount: currentPlaylist.songs.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  setState(() {
                    _reorderSelectedIndices(oldIndex, newIndex);
                  });
                  playlistService.reorderSongsInPlaylist(
                    currentPlaylist.id,
                    oldIndex,
                    newIndex,
                  );
                },
                itemBuilder: (context, index) {
                  final song = currentPlaylist.songs[index];
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
                      if (!_isSelectionMode) {
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
                                  : _isSelectionMode
                                  ? (isSelected ? 0.5 : 0.7)
                                  : 1.0,
                              child: SongThumbnail(
                                path: song.path,
                                id: song.id,
                                size: 40.0,
                              ),
                            ),
                            if (_isSelectionMode)
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
                      trailing: _isSelectionMode
                          ? ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            )
                          : _buildDurationTrailing(
                              scanner.metadataMap[song.path]?.duration,
                            ),
                      onTap: _isSelectionMode
                          ? () {
                              if (isMissing) {
                                showDeletedSongSnack(context, skipped: false);
                                return;
                              }
                              _toggleSelection(index);
                            }
                          : () {
                              if (isMissing) {
                                showDeletedSongSnack(context, skipped: false);
                                return;
                              }
                              audio.playPlaylist(
                                currentPlaylist.songs,
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
        if (_isSelectionMode)
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
                                      .map((i) => currentPlaylist.songs[i])
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
                                    currentPlaylist.id,
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
}
