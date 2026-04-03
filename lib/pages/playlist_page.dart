import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../player/audio_service.dart';
import '../player/scanner_service.dart';
import '../player/playlist_service.dart';
import '../widgets/song_thumbnail.dart';

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {

  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};


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
                context.read<PlaylistService>().createPlaylist(name);
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
          decoration: InputDecoration(labelText: AppLocalizations.of(context)!.playlistName),
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
                context.read<PlaylistService>().renamePlaylist(
                  playlist.id,
                  name,
                );
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deletePlaylist),
        content: Text(AppLocalizations.of(context)!.confirmDeletePlaylist(playlist.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              context.read<PlaylistService>().deletePlaylist(playlist.id);
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
    final playlistService = context.read<PlaylistService>();

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
                subtitle: Text(AppLocalizations.of(context)!.songCount(playlist.songs.length)),
                onTap: () {
                  playlistService.addSongsToPlaylist(
                    playlist.id,
                    selectedSongs,
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.addedToPlaylist(selectedSongs.length, playlist.name),
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
                final playlist = await context
                    .read<PlaylistService>()
                    .createPlaylist(name);
                if (context.mounted) {
                  context.read<PlaylistService>().addSongsToPlaylist(
                    playlist.id,
                    selectedSongs,
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.createdPlaylist(name, selectedSongs.length),
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
              onTap: () {
                Navigator.pop(context);
                _showRenamePlaylistDialog(context, playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text(AppLocalizations.of(context)!.delete),
              onTap: () {
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
    final audio = context.watch<AudioService>();
    final playlistService = context.watch<PlaylistService>();
    final scanner = context.watch<ScannerService>();
    final currentPlaylist = playlistService.currentPlaylist;

    return Scaffold(
        appBar: AppBar(
          title: currentPlaylist != null
              ? Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _showPlaylistSelector(context),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(currentPlaylist.name),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Text(AppLocalizations.of(context)!.playlist),
          actions: [
            if (currentPlaylist != null && currentPlaylist.songs.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear_all),
                tooltip: AppLocalizations.of(context)!.emptyList,
                onPressed: () =>
                    playlistService.clearPlaylist(currentPlaylist.id),
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
                    leading: Icon(Icons.add),
                    title: Text(AppLocalizations.of(context)!.createPlaylist),
                  ),
                ),
                PopupMenuItem(
                  value: 'manage',
                  child: ListTile(
                    leading: Icon(Icons.list),
                    title: Text(AppLocalizations.of(context)!.managePlaylists),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: currentPlaylist == null || currentPlaylist.songs.isEmpty
            ? Center(
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
                      AppLocalizations.of(context)!.emptyList,
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    if (Platform.isWindows)
                      Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          AppLocalizations.of(context)!.dragToAddMusic,
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              )
            : Stack(
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
                              Text(AppLocalizations.of(context)!.selectedSongs(_selectedIndices.length)),
                              const Spacer(),
                              TextButton(
                                onPressed: _toggleSelectionMode,
                                child: Text(AppLocalizations.of(context)!.cancel),
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
                            playlistService.reorderSongsInPlaylist(
                              currentPlaylist.id,
                              oldIndex,
                              newIndex,
                            );
                          },
                          itemBuilder: (context, index) {
                            final song = currentPlaylist.songs[index];
                            final isCurrent =
                                audio.currentIndex == index &&
                                audio.currentMusic?.path == song.path;
                            final isSelected = _selectedIndices.contains(index);

                            return GestureDetector(
                              key: Key(
                                '${currentPlaylist.id}-${song.path}-$index',
                              ),
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
                                        opacity: _isSelectionMode
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
                                                onChanged: (_) =>
                                                    _toggleSelection(index),
                                                fillColor:
                                                    WidgetStateProperty.all(
                                                      Colors.white,
                                                    ),
                                                checkColor: Colors.black,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
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
                                  style: TextStyle(
                                    color: isCurrent
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                    fontWeight: isCurrent
                                        ? FontWeight.bold
                                        : null,
                                  ),
                                ),
                                subtitle: Text(
                                  '${scanner.metadataMap[song.path]?.artist ?? AppLocalizations.of(context)!.unknownArtist} - ${scanner.metadataMap[song.path]?.album ?? AppLocalizations.of(context)!.unknownAlbum}',
                                  style: const TextStyle(fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: _isSelectionMode
                                    ? ReorderableDragStartListener(
                                        index: index,
                                        child: const Icon(Icons.drag_handle),
                                      )
                                    : _buildDurationTrailing(
                                        scanner
                                            .metadataMap[song.path]
                                            ?.duration,
                                      ),
                                onTap: _isSelectionMode
                                    ? () => _toggleSelection(index)
                                    : () {
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
                                            final selectedSongs =
                                                _selectedIndices
                                                    .map(
                                                      (i) => currentPlaylist
                                                          .songs[i],
                                                    )
                                                    .toList();
                                            _showAddToPlaylistDialog(
                                              context,
                                              selectedSongs,
                                            );
                                          },
                                    icon: const Icon(Icons.playlist_add),
                                    label: Text(AppLocalizations.of(context)!.addToPlaylist),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: _selectedIndices.isEmpty
                                        ? null
                                        : () {
                                            final indices =
                                                _selectedIndices.toList()
                                                  ..sort();
                                            playlistService
                                                .removeSongsFromPlaylist(
                                                  currentPlaylist.id,
                                                  indices,
                                                );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  AppLocalizations.of(context)!.deletedSongs(indices.length),
                                                ),
                                              ),
                                            );
                                            _toggleSelectionMode();
                                          },
                                    icon: const Icon(Icons.delete),
                                    label: Text(AppLocalizations.of(context)!.delete),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
    );
  }

  void _showPlaylistSelector(BuildContext context) {
    final playlistService = context.read<PlaylistService>();

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...playlistService.playlists.map(
              (playlist) => ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text(playlist.name),
                subtitle: Text(AppLocalizations.of(context)!.songCount(playlist.songs.length)),
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
    final playlistService = context.read<PlaylistService>();

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
                leading: const Icon(Icons.playlist_play),
                title: Text(playlist.name),
                subtitle: Text(
                  '${AppLocalizations.of(context)!.songCount(playlist.songs.length)} · ${_formatDate(playlist.updatedAt)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {
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
