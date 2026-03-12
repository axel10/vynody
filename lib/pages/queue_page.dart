import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../player/audio_service.dart';
import '../player/scanner_service.dart';
import '../widgets/song_thumbnail.dart';

// 队列页面
class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
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

  void _showClearQueueDialog(BuildContext context, AudioService audio) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空队列'),
        content: const Text('确定要清空当前队列吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              audio.clearPlaylist();
              Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('队列已清空')));
              }
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();
    final scanner = context.watch<ScannerService>();
    final playlist = audio.playlist;

    if (playlist.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('队列'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: null,
              tooltip: '队列为空',
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.queue_music,
                size: 64,
                color: Colors.grey.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              const Text(
                '队列为空',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('队列'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _showClearQueueDialog(context, audio),
            tooltip: '清空队列',
          ),
        ],
      ),
      body: Stack(
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
                  itemCount: playlist.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    audio.player.moveTrack(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final song = playlist[index];
                    final isCurrent = audio.currentIndex == index;
                    final isSelected = _selectedIndices.contains(index);

                    return GestureDetector(
                      key: Key('queue-${song.path}-$index'),
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
                                        fillColor: WidgetStateProperty.all(
                                          Colors.white,
                                        ),
                                        checkColor: Colors.black,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        title: Text(
                          song.name,
                          style: TextStyle(
                            color: isCurrent
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            fontWeight: isCurrent ? FontWeight.bold : null,
                          ),
                        ),
                        subtitle: Text(
                          scanner.metadataMap[song.path]?.artist ?? '未知艺术家',
                          style: const TextStyle(fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _isSelectionMode
                            ? ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle),
                              )
                            : Icon(
                                isCurrent
                                    ? Icons.play_circle
                                    : Icons.play_circle_outline,
                                color: isCurrent
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                        onTap: _isSelectionMode
                            ? () => _toggleSelection(index)
                            : () {
                                audio.player.playAt(index);
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
                                    final sortedIndices =
                                        _selectedIndices.toList()..sort();
                                    // Remove in reverse order to maintain indices
                                    for (
                                      int i = sortedIndices.length - 1;
                                      i >= 0;
                                      i--
                                    ) {
                                      audio.removeFromPlaylist(
                                        sortedIndices[i],
                                      );
                                    }
                                    _selectedIndices.clear();
                                    _toggleSelectionMode();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '已删除 ${sortedIndices.length} 首歌曲',
                                          ),
                                        ),
                                      );
                                    }
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
    );
  }
}
