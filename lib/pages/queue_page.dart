import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
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
  int _viewIndex = 0; // 0: Normal Queue, 1: Random History, 2: Random Queue

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
        title: Text(AppLocalizations.of(context)!.clearQueue),
        content: Text(AppLocalizations.of(context)!.confirmClearQueue),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              audio.clearPlaylist();
              Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.queueCleared)));
              }
            },
            child: Text(AppLocalizations.of(context)!.clearQueue),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final audio = Provider.of<AudioService>(context);
    
    // Validate current view index against current mode
    if (_viewIndex == 1 && !audio.isRandomMode) {
      _viewIndex = 0;
    }
    if (_viewIndex == 2 && !audio.isShuffleRandomMode) {
      if (audio.isRandomMode) {
        _viewIndex = 1;
      } else {
        _viewIndex = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();
    final scanner = context.watch<ScannerService>();
    final playlist = audio.playlist;

    if (playlist.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.queue),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: null,
              tooltip: AppLocalizations.of(context)!.queueEmpty,
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
              Text(
                AppLocalizations.of(context)!.queueEmpty,
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: audio.isRandomMode
            ? DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _viewIndex,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  dropdownColor: Colors.grey[900],
                  items: [
                    DropdownMenuItem(
                      value: 0,
                      child: Text(
                        AppLocalizations.of(context)!.queue,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text(
                        AppLocalizations.of(context)!.randomHistory,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    if (audio.isShuffleRandomMode)
                      DropdownMenuItem(
                        value: 2,
                        child: Text(
                          AppLocalizations.of(context)!.randomQueue,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _viewIndex = val;
                      });
                    }
                  },
                ),
              )
            : Text(AppLocalizations.of(context)!.queue),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _showClearQueueDialog(context, audio),
            tooltip: AppLocalizations.of(context)!.clearQueue,
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
                  padding: EdgeInsets.only(
                    bottom: _isSelectionMode
                        ? 80
                        : (Platform.isWindows ? 84 : 0),
                  ),
                  itemCount: _viewIndex == 1
                      ? audio.randomHistory.length
                      : _viewIndex == 2
                          ? audio.randomQueue.length
                          : playlist.length,
                  onReorder: (oldIndex, newIndex) {
                    if (_viewIndex != 0) return;
                    if (newIndex > oldIndex) newIndex--;
                    audio.player.playlist.moveTrack(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final isHistoryView = _viewIndex == 1;
                    final isRandomQueueView = _viewIndex == 2;
                    final displayPlaylist = isHistoryView
                        ? audio.randomHistory
                        : isRandomQueueView
                            ? audio.randomQueue
                            : playlist;
                    final song = displayPlaylist[index];

                    final bool isCurrent;
                    if (isHistoryView) {
                      isCurrent = (index == audio.historyCursor);
                    } else if (isRandomQueueView) {
                      isCurrent = (index == audio.deckCursor);
                    } else {
                      isCurrent = (audio.currentIndex == index);
                    }
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
                          song.displayName,
                          style: TextStyle(
                            color: isCurrent
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            fontWeight: isCurrent ? FontWeight.bold : null,
                          ),
                        ),
                        subtitle: Text(
                          scanner.metadataMap[song.path]?.artist ?? AppLocalizations.of(context)!.unknownArtist,
                          style: const TextStyle(fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _isSelectionMode
                            ? ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle),
                              )
                            : isHistoryView
                                ? Icon(
                                    Icons.history,
                                    color: isCurrent
                                        ? Colors.blue
                                        : Colors.grey.withOpacity(0.3),
                                  )
                                : isRandomQueueView
                                    ? Icon(
                                        Icons.shuffle,
                                        color: isCurrent
                                            ? Colors.purpleAccent
                                            : Colors.grey.withOpacity(0.3),
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
                                if (isHistoryView || isRandomQueueView) {
                                  final actualIndex = audio.playlist
                                      .indexWhere((s) => s.path == song.path);
                                  if (actualIndex >= 0) {
                                    audio.playAtIndex(actualIndex);
                                  }
                                } else {
                                  audio.playAtIndex(index);
                                }
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
                                            AppLocalizations.of(context)!.deletedSongs(sortedIndices.length),
                                          ),
                                        ),
                                      );
                                    }
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
}
