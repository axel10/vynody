import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/platform/right_queue_drawer_controller.dart';
import 'package:vynody/player/platform/standalone_queue_window_manager.dart';
import 'package:vynody/utils/list_reorder_utils.dart';
import 'package:vynody/utils/queue_sort_utils.dart';
import 'package:vynody/utils/selection_utils.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/utils/time_format_utils.dart';
import 'package:vynody/widgets/app_tooltip.dart';
import 'package:vynody/widgets/queue_file_drop_target.dart';

class RightQueuePanel extends ConsumerStatefulWidget {
  const RightQueuePanel({super.key});

  @override
  ConsumerState<RightQueuePanel> createState() => _RightQueuePanelState();
}

class _RightQueuePanelState extends ConsumerState<RightQueuePanel> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final _keyPool = ReorderableKeyPool(debugPrefix: 'right-queue-tile');
  QueueSortField _sortField = QueueSortField.title;
  bool _sortAscending = true;

  final Set<int> _selectedIndices = {};
  bool _isSelectionMode = false;
  int? _lastAnchorIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    _keyPool.clear();
    super.dispose();
  }

  void _exitSelectionMode() {
    if (!mounted) return;
    setState(() {
      _isSelectionMode = false;
      _selectedIndices.clear();
      _lastAnchorIndex = null;
    });
  }

  void _toggleSelectAll(int totalLength) {
    if (totalLength <= 0) return;
    setState(() {
      _isSelectionMode = true;
      if (_selectedIndices.length == totalLength) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.clear();
        _selectedIndices.addAll(List.generate(totalLength, (i) => i));
      }
    });
  }

  void _removeSelected(List<MusicFile> queue) {
    if (_selectedIndices.isEmpty) return;
    final indices = _selectedIndices.toList()..sort();
    ref.read(audioServiceProvider).removeTracksAt(indices);
    _exitSelectionMode();
  }

  void _addSelectedToPlaylist(BuildContext context, List<MusicFile> queue) {
    final selectedSongs = _selectedIndices
        .where((i) => i >= 0 && i < queue.length)
        .map((i) => queue[i])
        .toList();
    if (selectedSongs.isEmpty) return;
    final playlistService = ref.read(playlistServiceProvider);
    showAddSongsToPlaylistDialog(context, playlistService, selectedSongs);
  }

  void _handleItemTap(int index, List<MusicFile> queue) {
    final isShift = ModifierKeyUtils.isRangeSelectPressed;
    final isCtrl = ModifierKeyUtils.isDiscreteSelectPressed;

    if (isShift) {
      final anchor = _lastAnchorIndex ?? index;
      final range = ModifierKeyUtils.getIndexRange(anchor, index);
      setState(() {
        _isSelectionMode = true;
        _selectedIndices.addAll(range.where((i) => i >= 0 && i < queue.length));
        _lastAnchorIndex = index;
      });
    } else if (isCtrl) {
      setState(() {
        _isSelectionMode = true;
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
          if (_selectedIndices.isEmpty) {
            _isSelectionMode = false;
          }
        } else {
          _selectedIndices.add(index);
        }
        _lastAnchorIndex = index;
      });
    } else if (_isSelectionMode) {
      setState(() {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
          if (_selectedIndices.isEmpty) {
            _isSelectionMode = false;
          }
        } else {
          _selectedIndices.add(index);
        }
        _lastAnchorIndex = index;
      });
    } else {
      _lastAnchorIndex = index;
      ref.read(audioServiceProvider).playAtIndex(index);
    }
  }

  void _handleItemRightClick(
    BuildContext context,
    Offset globalPos,
    int index,
    List<MusicFile> queue,
    int currentIndex,
  ) {
    final isSelected = _selectedIndices.contains(index);
    final List<MusicFile> targetSongs;

    if (isSelected && _selectedIndices.length > 1) {
      targetSongs = _selectedIndices
          .where((i) => i >= 0 && i < queue.length)
          .map((i) => queue[i])
          .toList();
    } else {
      targetSongs = [queue[index]];
    }

    final audioService = ref.read(audioServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);

    showSongContextMenu(
      context,
      globalPos,
      song: queue[index],
      songs: targetSongs,
      mode: SongContextMenuMode.full,
      onAddToPlaylist: () async {
        await showAddSongsToPlaylistDialog(context, playlistService, targetSongs);
      },
      onPlayNext: targetSongs.length > 1
          ? null
          : (index == currentIndex
              ? null
              : () {
                  final curIdx = audioService.currentIndex;
                  if (curIdx < 0) return;
                  final insertIndex = index < curIdx ? curIdx : curIdx + 1;
                  audioService.moveQueueTrack(index, insertIndex);
                }),
      onRemoveFromQueue: () {
        if (isSelected && _selectedIndices.length > 1) {
          _removeSelected(queue);
        } else {
          audioService.removeFromPlaylist(index);
          if (_selectedIndices.contains(index)) {
            setState(() {
              _selectedIndices.remove(index);
              if (_selectedIndices.isEmpty) {
                _isSelectionMode = false;
              }
            });
          }
        }
      },
    );
  }

  Future<void> _showSortDialog(BuildContext context) async {
    final result = await QueueSortUtils.showSortDialog(
      context,
      currentField: _sortField,
      sortAscending: _sortAscending,
      onChanged: (field, ascending) {
        if (mounted) {
          setState(() {
            _sortField = field;
            _sortAscending = ascending;
          });
          final currentQueue = ref.read(audioPlaybackQueueProvider);
          final sortedList = QueueSortUtils.sortQueue(
            currentQueue,
            field,
            ascending,
          );
          ref.read(audioServiceProvider).updateQueue(sortedList);
        }
      },
    );
    if (result != null && mounted) {
      setState(() {
        _sortField = result.field;
        _sortAscending = result.sortAscending;
      });
      final currentQueue = ref.read(audioPlaybackQueueProvider);
      final sortedList = QueueSortUtils.sortQueue(
        currentQueue,
        result.field,
        result.sortAscending,
      );
      await ref.read(audioServiceProvider).updateQueue(sortedList);
    }
  }

  void _scrollToCurrent() {
    final queue = ref.read(audioPlaybackQueueProvider);
    final currentIndex = ref.read(audioCurrentIndexProvider);
    if (currentIndex >= 0 && currentIndex < queue.length) {
      if (_scrollController.hasClients) {
        final offset = (currentIndex * 56.0) - 100;
        _scrollController.animateTo(
          offset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _showClearConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空播放队列'),
        content: const Text('确定要清空当前所有待播放的歌曲吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(audioServiceProvider).clearPlaylist();
              _exitSelectionMode();
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final queue = ref.watch(audioPlaybackQueueProvider);
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    final isPlaying = ref.watch(audioIsPlayingProvider);
    final audioService = ref.read(audioServiceProvider);
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final topPadding = isDesktop ? 32.0 : 0.0;

    _keyPool.syncLength(queue.length);

    // Clean up selected indices if queue shrunk
    _selectedIndices.removeWhere((idx) => idx >= queue.length);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            _removeSelected(queue),
        const SingleActivator(LogicalKeyboardKey.backspace): () =>
            _removeSelected(queue),
        const SingleActivator(LogicalKeyboardKey.escape): _exitSelectionMode,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
            _toggleSelectAll(queue.length),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () =>
            _toggleSelectAll(queue.length),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Container(
          width: kRightQueueDrawerWidth,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              left: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.12),
                width: 1.0,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                offset: const Offset(-2, 0),
                blurRadius: 8,
              ),
            ],
          ),
          child: QueueFileDropTarget(
            enabled: true,
            displayQueue: queue,
            queueSongs: queue,
            itemKeyBuilder: (index, song) => _keyPool.getKey(index),
            showPreview: queue.isNotEmpty,
            indicatorHorizontalPadding: 12.0,
            onFilesDropped: (paths, insertIndex) async {
              await ref
                  .read(standaloneQueueWindowManagerProvider)
                  .handleDroppedPaths(paths, insertIndex: insertIndex);
            },
            child: Column(
              children: [
                if (topPadding > 0) SizedBox(height: topPadding),
                _buildHeader(context, queue),
                Expanded(
                  child: queue.isEmpty
                      ? _buildEmptyView(context)
                      : _buildQueueList(
                          context,
                          queue,
                          currentIndex,
                          isPlaying,
                          audioService,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<MusicFile> queue) {
    final theme = Theme.of(context);
    final queueLength = queue.length;
    final isSelecting = _isSelectionMode || _selectedIndices.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isSelecting
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: isSelecting
                ? theme.colorScheme.primary.withValues(alpha: 0.25)
                : theme.dividerColor.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: isSelecting
          ? Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: _exitSelectionMode,
                  visualDensity: VisualDensity.compact,
                  tooltip: '退出多选',
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 4),
                Text(
                  '已选 ${_selectedIndices.length} 项',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                AppTooltip(
                  message: _selectedIndices.length == queueLength ? '取消全选' : '全选',
                  child: IconButton(
                    icon: Icon(
                      _selectedIndices.length == queueLength
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      size: 19,
                    ),
                    onPressed: () => _toggleSelectAll(queueLength),
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (_selectedIndices.isNotEmpty) ...[
                  AppTooltip(
                    message: '添加到歌单',
                    child: IconButton(
                      icon: const Icon(Icons.playlist_add_rounded, size: 20),
                      onPressed: () => _addSelectedToPlaylist(context, queue),
                      visualDensity: VisualDensity.compact,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  AppTooltip(
                    message: '从队列中移除',
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 19),
                      onPressed: () => _removeSelected(queue),
                      visualDensity: VisualDensity.compact,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            )
          : Row(
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '播放队列',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$queueLength',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                if (queueLength > 0) ...[
                  AppTooltip(
                    message: '定位当前播放',
                    child: IconButton(
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      onPressed: _scrollToCurrent,
                      visualDensity: VisualDensity.compact,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AppTooltip(
                    message: '清空队列',
                    child: IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      onPressed: () => _showClearConfirmDialog(context),
                      visualDensity: VisualDensity.compact,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                AppTooltip(
                  message: '分离为独立窗口',
                  child: IconButton(
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    onPressed: () {
                      ref.read(rightQueueDrawerProvider.notifier).close();
                      ref
                          .read(standaloneQueueWindowManagerProvider)
                          .openOrFocusQueueWindow();
                    },
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.primary,
                  ),
                ),
                AppTooltip(
                  message: '排序',
                  child: IconButton(
                    icon: const Icon(Icons.sort_rounded, size: 18),
                    onPressed:
                        queueLength > 0 ? () => _showSortDialog(context) : null,
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music_rounded,
              size: 52,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 14),
            Text(
              '播放队列为空',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '可从左侧媒体库、目录或专辑\n直接将歌曲拖拽到此处',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueList(
    BuildContext context,
    List<MusicFile> queue,
    int currentIndex,
    bool isPlaying,
    AudioService audioService,
  ) {
    final isSelecting = _isSelectionMode || _selectedIndices.isNotEmpty;

    return ReorderableListView.builder(
      scrollController: _scrollController,
      buildDefaultDragHandles: false,
      itemCount: queue.length,
      onReorderItem: (oldIndex, newIndex) {
        audioService.moveQueueTrack(oldIndex, newIndex);
        _keyPool.moveKey(oldIndex, newIndex);
        if (_selectedIndices.isNotEmpty) {
          final updated = ListReorderUtils.reorderSelectedIndices(
            _selectedIndices,
            oldIndex: oldIndex,
            newIndex: newIndex,
          );
          setState(() {
            _selectedIndices.clear();
            _selectedIndices.addAll(updated);
          });
        }
      },
      itemBuilder: (context, index) {
        final song = queue[index];
        final isCurrent = index == currentIndex;
        final isSelected = _selectedIndices.contains(index);

        return _RightQueueTile(
          key: _keyPool.getKey(index),
          song: song,
          index: index,
          isCurrent: isCurrent,
          isPlaying: isPlaying,
          isSelected: isSelected,
          isSelectionMode: isSelecting,
          durationFormatted: TimeFormatUtils.formatMs(song.durationMillis ?? 0),
          onTap: () => _handleItemTap(index, queue),
          onLongPress: () {
            setState(() {
              _isSelectionMode = true;
              if (!_selectedIndices.contains(index)) {
                _selectedIndices.add(index);
              }
              _lastAnchorIndex = index;
            });
          },
          onToggleSelect: () {
            setState(() {
              if (_selectedIndices.contains(index)) {
                _selectedIndices.remove(index);
                if (_selectedIndices.isEmpty) {
                  _isSelectionMode = false;
                }
              } else {
                _selectedIndices.add(index);
              }
              _lastAnchorIndex = index;
            });
          },
          onSecondaryTap: (pos) => _handleItemRightClick(
            context,
            pos,
            index,
            queue,
            currentIndex,
          ),
          onRemove: () => audioService.removeFromPlaylist(index),
        );
      },
    );
  }
}

class _RightQueueTile extends ConsumerStatefulWidget {
  final MusicFile song;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final bool isSelected;
  final bool isSelectionMode;
  final String durationFormatted;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onToggleSelect;
  final ValueChanged<Offset> onSecondaryTap;
  final VoidCallback onRemove;

  const _RightQueueTile({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.isSelected,
    required this.isSelectionMode,
    required this.durationFormatted,
    required this.onTap,
    this.onLongPress,
    required this.onToggleSelect,
    required this.onSecondaryTap,
    required this.onRemove,
  });

  @override
  ConsumerState<_RightQueueTile> createState() => _RightQueueTileState();
}

class _RightQueueTileState extends ConsumerState<_RightQueueTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.song;

    final metadata = ref.watch(
      scannerServiceProvider.select((s) => s.metadataMap[song.path]),
    );
    final artist = (metadata?.artist ?? song.artist)?.trim();
    final album = (metadata?.album ?? song.album)?.trim();
    final displayArtist = (artist != null && artist.isNotEmpty) ? artist : '未知艺术家';
    final displayAlbum = (album != null && album.isNotEmpty) ? album : null;
    final subtitleText =
        displayAlbum != null ? '$displayArtist - $displayAlbum' : displayArtist;

    final hasThumb = song.thumbnailPath != null &&
        song.thumbnailPath!.isNotEmpty &&
        File(song.thumbnailPath!).existsSync();
    final hasArt = song.artworkPath != null &&
        song.artworkPath!.isNotEmpty &&
        File(song.artworkPath!).existsSync();
    final coverPath =
        hasThumb ? song.thumbnailPath : (hasArt ? song.artworkPath : null);

    final itemColor = widget.isSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : (widget.isCurrent
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
            : (_isHovered
                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
                : Colors.transparent));

    return Material(
      color: itemColor,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTapUp: (details) => widget.onSecondaryTap(details.globalPosition),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.05),
                ),
                left: widget.isSelected
                    ? BorderSide(
                        color: theme.colorScheme.primary,
                        width: 3.0,
                      )
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: _isHovered ? 0.6 : 0.25,
                      ),
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(
                          opacity: widget.isSelectionMode
                              ? (widget.isSelected ? 0.5 : 0.7)
                              : 1.0,
                          child: Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: coverPath != null
                                ? Image.file(
                                    File(coverPath),
                                    fit: BoxFit.cover,
                                    cacheWidth: 80,
                                    cacheHeight: 80,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.music_note_rounded,
                                      size: 18,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                : Icon(
                                    Icons.music_note_rounded,
                                    size: 18,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                          ),
                        ),
                        if (widget.isSelectionMode)
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.center,
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: Checkbox(
                                  value: widget.isSelected,
                                  onChanged: (_) => widget.onToggleSelect(),
                                  fillColor: WidgetStateProperty.all(Colors.white),
                                  checkColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (widget.isCurrent) ...[
                            Icon(
                              widget.isPlaying
                                  ? Icons.volume_up_rounded
                                  : Icons.pause_rounded,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              song.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: widget.isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: widget.isCurrent
                                    ? theme.colorScheme.primary
                                    : (widget.isSelected
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.onSurface),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (_isHovered && !widget.isSelectionMode)
                  AppTooltip(
                    message: '从队列中移除',
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: widget.onRemove,
                      visualDensity: VisualDensity.compact,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else if ((song.durationMillis ?? 0) > 0)
                  Text(
                    widget.durationFormatted,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
