import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../l10n/app_localizations.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/player/library/music_file_utils.dart';
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
  final GlobalKey _dropSurfaceKey = GlobalKey(debugLabel: 'queue-drop-surface');
  final GlobalKey _queueViewportKey = GlobalKey(debugLabel: 'queue-viewport');
  final Map<String, GlobalKey> _songTileKeys = {};
  int _viewIndex = 0; // 0: Normal Queue, 1: Random History, 2: Random Queue
  late final QueueSelectionModeController _queueSelectionModeController;
  bool _isDraggingFiles = false;
  double? _dropIndicatorTop;
  int? _dropInsertIndex;

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

  GlobalKey _songTileKeyFor(MusicFile song) {
    return _songTileKeys.putIfAbsent(
      song.path,
      () => GlobalKey(debugLabel: 'queue-song-${song.path}'),
    );
  }

  void _clearDropPreview() {
    if (!_isDraggingFiles &&
        _dropIndicatorTop == null &&
        _dropInsertIndex == null) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _isDraggingFiles = false;
      _dropIndicatorTop = null;
      _dropInsertIndex = null;
    });
  }

  Future<List<MusicFile>> _getFilesFromPath(String path) async {
    final results = <MusicFile>[];
    final entityType = FileSystemEntity.typeSync(path);

    if (entityType == FileSystemEntityType.file) {
      if (MusicFileUtils.isMusicFilePath(path)) {
        results.add(MusicFile(path: path, name: p.basename(path)));
      }
    } else if (entityType == FileSystemEntityType.directory) {
      final dir = Directory(path);
      try {
        await for (final item in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (item is File && MusicFileUtils.isMusicFilePath(item.path)) {
            results.add(
              MusicFile(path: item.path, name: p.basename(item.path)),
            );
          }
        }
      } catch (e) {
        debugPrint('Error scanning directory $path: $e');
      }
    }

    return results;
  }

  List<MusicFile> _dedupeDroppedFiles(List<MusicFile> files) {
    final uniqueFiles = <MusicFile>[];
    final seenPaths = <String>{};
    for (final song in files) {
      if (seenPaths.add(song.path)) {
        uniqueFiles.add(song);
      }
    }
    return uniqueFiles;
  }

  ({int insertIndex, double indicatorTop})? _calculateDropPreview(
    Offset localPosition,
    List<MusicFile> displayQueue,
  ) {
    final surfaceBox =
        _dropSurfaceKey.currentContext?.findRenderObject() as RenderBox?;
    final viewportBox =
        _queueViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (surfaceBox == null || viewportBox == null) {
      return null;
    }

    final globalPosition = surfaceBox.localToGlobal(localPosition);
    final viewportPosition = viewportBox.globalToLocal(globalPosition);

    final visibleItems = <({int index, double top, double bottom})>[];
    for (var i = 0; i < displayQueue.length; i++) {
      final key = _songTileKeys[displayQueue[i].path];
      final renderObject = key?.currentContext?.findRenderObject();
      final itemBox = renderObject is RenderBox ? renderObject : null;
      if (itemBox == null) continue;

      final topLeft = viewportBox.globalToLocal(
        itemBox.localToGlobal(Offset.zero),
      );
      visibleItems.add((
        index: i,
        top: topLeft.dy,
        bottom: topLeft.dy + itemBox.size.height,
      ));
    }

    if (visibleItems.isEmpty) {
      return (insertIndex: 0, indicatorTop: 0);
    }

    visibleItems.sort((a, b) => a.index.compareTo(b.index));

    final firstItem = visibleItems.first;
    final lastItem = visibleItems.last;
    var insertIndex = lastItem.index + 1;
    var indicatorTop = lastItem.bottom;

    if (viewportPosition.dy <= firstItem.top) {
      return (insertIndex: firstItem.index, indicatorTop: firstItem.top);
    }

    for (final item in visibleItems) {
      final itemMid = item.top + ((item.bottom - item.top) / 2);
      if (viewportPosition.dy < itemMid) {
        insertIndex = item.index;
        indicatorTop = item.top;
        break;
      }
    }

    return (insertIndex: insertIndex, indicatorTop: indicatorTop);
  }

  void _updateDropPreview(
    DropEventDetails details,
    List<MusicFile> displayQueue, {
    required bool showPreview,
  }) {
    if (!mounted) return;

    if (!showPreview) {
      if (!_isDraggingFiles) {
        setState(() {
          _isDraggingFiles = true;
        });
      }
      return;
    }

    final preview = _calculateDropPreview(details.localPosition, displayQueue);
    if (preview == null) return;

    if (_isDraggingFiles &&
        _dropInsertIndex == preview.insertIndex &&
        _dropIndicatorTop == preview.indicatorTop) {
      return;
    }

    setState(() {
      _isDraggingFiles = true;
      _dropInsertIndex = preview.insertIndex;
      _dropIndicatorTop = preview.indicatorTop;
    });
  }

  Future<void> _handleDroppedFiles(
    List<DropItem> droppedItems,
    List<MusicFile> displayQueue, {
    required bool showPreview,
    Offset? dropLocalPosition,
  }) async {
    final audio = ref.read(audioServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final List<MusicFile> allFiles = [];

    for (final item in droppedItems) {
      final files = await _getFilesFromPath(item.path);
      allFiles.addAll(files);
    }

    if (!mounted) return;

    final uniqueFiles = _dedupeDroppedFiles(allFiles);
    if (uniqueFiles.isEmpty) {
      _clearDropPreview();
      return;
    }

    final existingQueuePaths = audio.playbackQueue
        .map((song) => song.path)
        .toSet();
    final newSongs = <MusicFile>[];
    var existingCount = 0;

    for (final song in uniqueFiles) {
      if (existingQueuePaths.contains(song.path)) {
        existingCount++;
        continue;
      }
      newSongs.add(song);
    }

    if (newSongs.isEmpty) {
      _clearDropPreview();
      return;
    }

    if (showPreview) {
      var insertIndex = _dropInsertIndex;
      if (dropLocalPosition != null) {
        final preview = _calculateDropPreview(dropLocalPosition, displayQueue);
        insertIndex = preview?.insertIndex ?? insertIndex;
      }
      insertIndex ??= displayQueue.length;
      insertIndex = insertIndex.clamp(0, audio.playbackQueue.length);
      await audio.insertIntoQueueAt(insertIndex, newSongs);
    } else {
      await audio.appendToQueue(newSongs);
    }

    if (!mounted) return;

    _clearDropPreview();
    final message = existingCount > 0
        ? l10n.dropAddedSongsWithExisting(newSongs.length, existingCount)
        : l10n.dropAddedSongs(newSongs.length);

    messenger.showSnackBar(SnackBar(content: Text(message)));
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

  Widget _buildDropInsertionIndicator(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 3,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.45),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueueDropTarget({
    required Widget child,
    required List<MusicFile> displayQueue,
    required bool showPreview,
  }) {
    return DropTarget(
      enable: true,
      onDragEntered: (details) {
        _updateDropPreview(details, displayQueue, showPreview: showPreview);
      },
      onDragUpdated: (details) {
        _updateDropPreview(details, displayQueue, showPreview: showPreview);
      },
      onDragExited: (_) {
        _clearDropPreview();
      },
      onDragDone: (details) async {
        await _handleDroppedFiles(
          details.files,
          displayQueue,
          showPreview: showPreview,
          dropLocalPosition: details.localPosition,
        );
      },
      child: Container(key: _dropSurfaceKey, child: child),
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
    final showPreview = _viewIndex == 0;
    final displayQueue = _viewIndex == 1
        ? randomHistory
        : _viewIndex == 2
        ? randomQueue
        : queue;

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
        body: _buildQueueDropTarget(
          displayQueue: displayQueue,
          showPreview: showPreview,
          child: Center(
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
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
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
                      _clearDropPreview();
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
      body: _buildQueueDropTarget(
        displayQueue: displayQueue,
        showPreview: showPreview,
        child: Stack(
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
                  child: Stack(
                    key: _queueViewportKey,
                    children: [
                      Positioned.fill(
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          cacheExtent: 1000,
                          padding: const EdgeInsets.only(bottom: 160),
                          itemCount: displayQueue.length,
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
                            final song = displayQueue[index];
                            final isMissing = song.isMissing;

                            final bool isCurrent;
                            if (_viewIndex == 1) {
                              isCurrent = (index == historyCursor);
                            } else if (_viewIndex == 2) {
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
                                onAddToPlaylist: () =>
                                    showAddSongsToPlaylistDialog(
                                      menuContext,
                                      ref.read(playlistServiceProvider),
                                      songsToAdd,
                                    ),
                                onPlayNext:
                                    (isCurrent ||
                                        isSelectionMode ||
                                        _viewIndex == 1 ||
                                        _viewIndex == 2)
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
                                              .moveQueueTrack(
                                                index,
                                                insertIndex,
                                              );
                                        }
                                      },
                                onRemoveFromQueue:
                                    (isSelectionMode ||
                                        _viewIndex == 1 ||
                                        _viewIndex == 2)
                                    ? null
                                    : () {
                                        ref
                                            .read(audioServiceProvider)
                                            .removeFromPlaylist(index);
                                      },
                              );
                            }

                            return Padding(
                              key: _songTileKeyFor(song),
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
                                        if (_viewIndex == 1 ||
                                            _viewIndex == 2) {
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
                                  handleShowMenu(
                                    context,
                                    details.globalPosition,
                                  );
                                },
                                onMorePressed: (buttonContext) {
                                  final renderObject = buttonContext
                                      .findRenderObject();
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
                      if (showPreview && _dropIndicatorTop != null)
                        Positioned(
                          top: _dropIndicatorTop! - 1.5,
                          left: 0,
                          right: 0,
                          child: _buildDropInsertionIndicator(context),
                        ),
                    ],
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
                                            .removeFromPlaylist(
                                              sortedIndices[i],
                                            );
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
      ),
    );
  }
}
