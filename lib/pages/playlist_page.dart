import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
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
  final List<String> _audioExtensions = const [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg',
  ];

  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};

  Future<List<MusicFile>> _getFilesFromPath(String path) async {
    final List<MusicFile> results = [];
    final entity = FileSystemEntity.typeSync(path);

    if (entity == FileSystemEntityType.file) {
      final ext = p.extension(path).toLowerCase();
      if (_audioExtensions.contains(ext)) {
        results.add(MusicFile(path: path, name: p.basename(path)));
      }
    } else if (entity == FileSystemEntityType.directory) {
      final dir = Directory(path);
      try {
        await for (final item in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (item is File) {
            final ext = p.extension(item.path).toLowerCase();
            if (_audioExtensions.contains(ext)) {
              results.add(
                MusicFile(path: item.path, name: p.basename(item.path)),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning directory $path: $e');
      }
    }
    return results;
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

  void _selectAll(List<MusicFile> songs) {
    setState(() {
      if (_selectedIndices.length == songs.length) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.clear();
        for (int i = 0; i < songs.length; i++) {
          _selectedIndices.add(i);
        }
      }
    });
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建播放列表'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '播放列表名称',
            hintText: '请输入播放列表名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<PlaylistService>().createPlaylist(name);
                Navigator.pop(context);
              }
            },
            child: const Text('创建'),
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
        title: const Text('重命名播放列表'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '播放列表名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
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
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeletePlaylistDialog(BuildContext context, Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除播放列表'),
        content: Text('确定要删除播放列表"${playlist.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<PlaylistService>().deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: const Text('删除'),
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
        title: const Text('添加到播放列表'),
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
                subtitle: Text('${playlist.songs.length} 首歌曲'),
                onTap: () {
                  playlistService.addSongsToPlaylist(
                    playlist.id,
                    selectedSongs,
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '已添加 ${selectedSongs.length} 首歌曲到${playlist.name}',
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
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showCreatePlaylistAndAddDialog(context, selectedSongs);
            },
            child: const Text('新建列表'),
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
        title: const Text('创建播放列表'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '播放列表名称',
            hintText: '请输入播放列表名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
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
                        '已创建播放列表"$name"并添加 ${selectedSongs.length} 首歌曲',
                      ),
                    ),
                  );
                  _toggleSelectionMode();
                }
              }
            },
            child: const Text('创建'),
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
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(context);
                _showRenamePlaylistDialog(context, playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('删除'),
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

    return DropTarget(
      onDragDone: (details) async {
        final List<MusicFile> allFiles = [];
        for (final file in details.files) {
          final files = await _getFilesFromPath(file.path);
          allFiles.addAll(files);
        }
        if (allFiles.isNotEmpty && currentPlaylist != null) {
          await playlistService.addSongsToPlaylist(
            currentPlaylist.id,
            allFiles,
          );
        }
      },
      child: Scaffold(
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
              : const Text('播放列表'),
          actions: [
            if (currentPlaylist != null && currentPlaylist.songs.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear_all),
                tooltip: '清空列表',
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
                const PopupMenuItem(
                  value: 'create',
                  child: ListTile(
                    leading: Icon(Icons.add),
                    title: Text('创建播放列表'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'manage',
                  child: ListTile(
                    leading: Icon(Icons.list),
                    title: Text('管理播放列表'),
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
                    const Text(
                      '列表为空',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    if (Platform.isWindows)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          '拖入文件或文件夹以添加音乐',
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
                              Text('已选择 ${_selectedIndices.length} 首'),
                              const Spacer(),
                              TextButton(
                                onPressed: _toggleSelectionMode,
                                child: const Text('取消'),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          padding: EdgeInsets.only(
                            bottom: _isSelectionMode
                                ? 80
                                : (Platform.isWindows ? 84 : 0),
                          ),
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
                                audio.currentFilePath == song.path;
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
                                  '${scanner.metadataMap[song.path]?.artist ?? '未知艺术家'} - ${scanner.metadataMap[song.path]?.album ?? '未知专辑'}',
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
                                    label: const Text('添加到播放列表'),
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
                                                  '已删除 ${indices.length} 首歌曲',
                                                ),
                                              ),
                                            );
                                            _toggleSelectionMode();
                                          },
                                    icon: const Icon(Icons.delete),
                                    label: const Text('删除'),
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
                subtitle: Text('${playlist.songs.length} 首歌曲'),
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
              title: const Text('创建新播放列表'),
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
                '管理播放列表',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(),
            ...playlistService.playlists.map(
              (playlist) => ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text(playlist.name),
                subtitle: Text(
                  '${playlist.songs.length} 首歌曲 · ${_formatDate(playlist.updatedAt)}',
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
