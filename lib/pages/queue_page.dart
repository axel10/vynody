import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import '../widgets/song_tile.dart';
import 'package:vibe_flow/utils/song_context_menu_utils.dart';
import 'package:vibe_flow/utils/deleted_song_snack.dart';
import 'package:vibe_flow/utils/app_snack_bar.dart';
import 'queue_page_riverpod.dart';

// 队列页面
class QueuePage extends ConsumerStatefulWidget {
  const QueuePage({super.key});

  @override
  ConsumerState<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends ConsumerState<QueuePage> {
  final Set<int> _selectedIndices = {};
  int _viewIndex = 0; // 0: Normal Queue, 1: Random History, 2: Random Queue
  late final QueueSelectionModeController _queueSelectionModeController;

  @override
  void initState() {
    super.initState();
    _queueSelectionModeController = ref.read(
      queueSelectionModeProvider.notifier,
    );
  }

  @override
  void dispose() {
    Future.microtask(() {
      _queueSelectionModeController.setEnabled(false);
    });
    super.dispose();
  }

  void _toggleSelectionMode() {
    final isSelectionMode = ref.read(queueSelectionModeProvider);
    ref.read(queueSelectionModeProvider.notifier).setEnabled(!isSelectionMode);
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

  List<MusicFile> _selectedSongsFromDisplay(List<MusicFile> displayQueue) {
    return _selectedIndices
        .where((index) => index >= 0 && index < displayQueue.length)
        .map((index) => displayQueue[index])
        .toList(growable: false);
  }

  void _showClearQueueDialog(BuildContext context) {
    final audio = ref.read(audioServiceProvider);
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
                if (context.mounted) {
                  AppSnackBar.show(
                    context,
                    ref,
                    SnackBar(
                      content: Text(AppLocalizations.of(context)!.queueCleared),
                    ),
                  );
                }
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

    // Validate current view index against current mode
    if (_viewIndex == 1 && !ref.read(audioIsRandomModeProvider)) {
      _viewIndex = 0;
    }
    if (_viewIndex == 2 && !ref.read(audioIsShuffleRandomModeProvider)) {
      if (ref.read(audioIsRandomModeProvider)) {
        _viewIndex = 1;
      } else {
        _viewIndex = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelectionMode = ref.watch(queueSelectionModeProvider);
    final isRandomMode = ref.watch(audioIsRandomModeProvider);
    final isShuffleRandomMode = ref.watch(audioIsShuffleRandomModeProvider);
    final queue = ref.watch(audioPlaybackQueueProvider);
    final randomHistory = ref.watch(audioRandomHistoryProvider);
    final randomQueue = ref.watch(audioRandomQueueProvider);
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    final historyCursor = ref.watch(audioHistoryCursorProvider);
    final deckCursor = ref.watch(audioDeckCursorProvider);

    if (queue.isEmpty) {
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
                color: Colors.grey.withValues(alpha: 0.5),
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
        title: isRandomMode
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
                    if (isShuffleRandomMode)
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
            onPressed: () => _showClearQueueDialog(context),
            tooltip: AppLocalizations.of(context)!.clearQueue,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (isSelectionMode)
                Container(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Text(
                        AppLocalizations.of(
                          context,
                        )!.selectedSongs(_selectedIndices.length),
                      ),
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
                  cacheExtent: 1000,
                  padding: const EdgeInsets.only(bottom: 160),
                  itemCount: _viewIndex == 1
                      ? randomHistory.length
                      : _viewIndex == 2
                      ? randomQueue.length
                      : queue.length,
                  onReorder: (oldIndex, newIndex) {
                    if (_viewIndex != 0) return;
                    if (newIndex > oldIndex) newIndex--;
                    setState(() {
                      _reorderSelectedIndices(oldIndex, newIndex);
                    });
                    ref
                        .read(audioServiceProvider)
                        .moveQueueTrack(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final isHistoryView = _viewIndex == 1;
                    final isRandomQueueView = _viewIndex == 2;
                    final displayQueue = isHistoryView
                        ? randomHistory
                        : isRandomQueueView
                        ? randomQueue
                        : queue;
                    final song = displayQueue[index];
                    final isMissing = song.isMissing;

                    final bool isCurrent;
                    if (isHistoryView) {
                      isCurrent = (index == historyCursor);
                    } else if (isRandomQueueView) {
                      isCurrent = (index == deckCursor);
                    } else {
                      isCurrent = (currentIndex == index);
                    }
                    final isSelected = _selectedIndices.contains(index);
                    final songsToAdd = _selectedIndices.isNotEmpty
                        ? _selectedSongsFromDisplay(displayQueue)
                        : <MusicFile>[song];

                    void handleShowMenu(
                      BuildContext menuContext,
                      Offset position,
                    ) {
                      showSongContextMenu(
                        menuContext,
                        position,
                        song: song,
                        songs: songsToAdd,
                        mode: SongContextMenuMode.full,
                        onAddToPlaylist: () => showAddSongsToPlaylistDialog(
                          menuContext,
                          ref.read(playlistServiceProvider),
                          songsToAdd,
                        ),
                        onPlayNext:
                            (isCurrent ||
                                isSelectionMode ||
                                isHistoryView ||
                                isRandomQueueView)
                            ? null
                            : () {
                                final curIdx = ref.read(
                                  audioCurrentIndexProvider,
                                );
                                if (curIdx >= 0) {
                                  final insertIndex = index < curIdx
                                      ? curIdx
                                      : curIdx + 1;
                                  ref
                                      .read(audioServiceProvider)
                                      .moveQueueTrack(index, insertIndex);
                                }
                              },
                        onRemoveFromQueue:
                            (isSelectionMode ||
                                isHistoryView ||
                                isRandomQueueView)
                            ? null
                            : () {
                                ref
                                    .read(audioServiceProvider)
                                    .removeFromPlaylist(index);
                              },
                      );
                    }

                    return Padding(
                      key: ObjectKey(song),
                      padding: EdgeInsets.symmetric(
                        horizontal:
                            MediaQuery.of(context).orientation ==
                                Orientation.portrait
                            ? 8
                            : 16,
                        vertical: 4,
                      ),
                      child: SongTile(
                        song: song,
                        isCurrent: isCurrent,
                        isSelected: isSelected,
                        isSelectionMode: isSelectionMode,
                        dragHandle: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                        onTap: isSelectionMode
                            ? () {
                                if (isMissing) {
                                  showDeletedSongSnack(
                                    context,
                                    ref,
                                    skipped: false,
                                  );
                                  return;
                                }
                                _toggleSelection(index);
                              }
                            : () {
                                if (isMissing) {
                                  showDeletedSongSnack(
                                    context,
                                    ref,
                                    skipped: false,
                                  );
                                  return;
                                }
                                if (isHistoryView || isRandomQueueView) {
                                  final actualIndex = queue.indexWhere(
                                    (s) => s.path == song.path,
                                  );
                                  if (actualIndex >= 0) {
                                    ref
                                        .read(audioServiceProvider)
                                        .playAtIndex(actualIndex);
                                  }
                                } else {
                                  ref
                                      .read(audioServiceProvider)
                                      .playAtIndex(index);
                                }
                              },
                        onLongPress: () {
                          if (!isSelectionMode) {
                            _toggleSelectionMode();
                            _toggleSelection(index);
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
                                    final sortedIndices =
                                        _selectedIndices.toList()..sort();
                                    // Remove in reverse order to maintain indices
                                    for (
                                      int i = sortedIndices.length - 1;
                                      i >= 0;
                                      i--
                                    ) {
                                      ref
                                          .read(audioServiceProvider)
                                          .removeFromPlaylist(sortedIndices[i]);
                                    }
                                    _selectedIndices.clear();
                                    _toggleSelectionMode();
                                    if (context.mounted) {
                                      AppSnackBar.show(
                                        context,
                                        ref,
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(
                                              context,
                                            )!.deletedSongs(
                                              sortedIndices.length,
                                            ),
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
