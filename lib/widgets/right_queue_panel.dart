import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart' as dd;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/platform/right_queue_drawer_controller.dart';
import 'package:vynody/player/platform/standalone_queue_window_manager.dart';
import 'package:vynody/utils/drop_data_utils.dart';
import 'package:vynody/utils/queue_sort_utils.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/utils/time_format_utils.dart';
import 'package:vynody/widgets/app_tooltip.dart';

class RightQueuePanel extends ConsumerStatefulWidget {
  const RightQueuePanel({super.key});

  @override
  ConsumerState<RightQueuePanel> createState() => _RightQueuePanelState();
}

class _RightQueuePanelState extends ConsumerState<RightQueuePanel> {
  final ScrollController _scrollController = ScrollController();
  bool _isDraggingOver = false;
  int? _dropInsertIndex;
  QueueSortField _sortField = QueueSortField.title;
  bool _sortAscending = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  void _onPerformSuperDrop(PerformDropEvent event) async {
    final uniquePaths = await DropDataUtils.extractPathsFromDrop(event);
    if (uniquePaths.isNotEmpty) {
      await ref
          .read(standaloneQueueWindowManagerProvider)
          .handleDroppedPaths(uniquePaths, insertIndex: _dropInsertIndex);
    }
  }

  void _onPerformDesktopDrop(dd.DropDoneDetails details) async {
    final paths = details.files.map((f) => f.path).toList();
    if (paths.isNotEmpty) {
      await ref
          .read(standaloneQueueWindowManagerProvider)
          .handleDroppedPaths(paths, insertIndex: _dropInsertIndex);
    }
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

    return Container(
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
      child: dd.DropTarget(
        onDragDone: _onPerformDesktopDrop,
        onDragEntered: (_) => setState(() => _isDraggingOver = true),
        onDragExited: (_) => setState(() => _isDraggingOver = false),
        child: DropRegion(
          formats: const [Formats.fileUri, Formats.plainText, Formats.uri],
          hitTestBehavior: HitTestBehavior.opaque,
          onDropOver: (event) {
            final y = event.position.local.dy - (52.0 + topPadding); // Subtract header height
            if (y <= 0) {
              _dropInsertIndex = 0;
            } else {
              final idx = (y / 54.0).floor();
              _dropInsertIndex = idx.clamp(0, queue.length);
            }
            return DropOperation.copy;
          },
          onDropEnter: (_) => setState(() => _isDraggingOver = true),
          onDropLeave: (_) => setState(() => _isDraggingOver = false),
          onDropEnded: (_) => setState(() => _isDraggingOver = false),
          onPerformDrop: (event) async {
            _onPerformSuperDrop(event);
          },
          child: Column(
            children: [
              if (topPadding > 0) SizedBox(height: topPadding),
              _buildHeader(context, queue.length),
              Expanded(
                child: Stack(
                  children: [
                    queue.isEmpty
                        ? _buildEmptyView(context)
                        : _buildQueueList(
                            context,
                            queue,
                            currentIndex,
                            isPlaying,
                            audioService,
                          ),
                    if (_isDraggingOver)
                      Container(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        child: Center(
                          child: Card(
                            elevation: 6,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.playlist_add_rounded,
                                    size: 28,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _dropInsertIndex != null &&
                                            _dropInsertIndex! < queue.length
                                        ? '插入至第 ${_dropInsertIndex! + 1} 首'
                                        : '添加到队列末尾',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int queueLength) {
    final theme = Theme.of(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
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
              onPressed: queueLength > 0 ? () => _showSortDialog(context) : null,
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
    return ReorderableListView.builder(
      scrollController: _scrollController,
      buildDefaultDragHandles: false,
      itemCount: queue.length,
      onReorderItem: (oldIndex, newIndex) {
        audioService.moveQueueTrack(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final song = queue[index];
        final isCurrent = index == currentIndex;

        return _RightQueueTile(
          key: ObjectKey(song),
          song: song,
          index: index,
          isCurrent: isCurrent,
          isPlaying: isPlaying,
          durationFormatted: TimeFormatUtils.formatMs(song.durationMillis ?? 0),
          onTap: () => audioService.playAtIndex(index),
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
  final String durationFormatted;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RightQueueTile({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.durationFormatted,
    required this.onTap,
    required this.onRemove,
  });

  @override
  ConsumerState<_RightQueueTile> createState() => _RightQueueTileState();
}

class _RightQueueTileState extends ConsumerState<_RightQueueTile> {
  bool _isHovered = false;

  void _showContextMenu(Offset globalPos) {
    final playlistService = ref.read(playlistServiceProvider);
    final audioService = ref.read(audioServiceProvider);

    showSongContextMenu(
      context,
      globalPos,
      song: widget.song,
      songs: [widget.song],
      mode: SongContextMenuMode.full,
      onAddToPlaylist: () async {
        await showAddSongsToPlaylistDialog(context, playlistService, [widget.song]);
      },
      onPlayNext: widget.isCurrent
          ? null
          : () {
              final queue = audioService.playbackQueue;
              final currentIndex = audioService.currentIndex;
              final queueIndex =
                  queue.indexWhere((s) => s.path == widget.song.path);
              if (queueIndex < 0 || currentIndex < 0) return;
              final insertIndex =
                  queueIndex < currentIndex ? currentIndex : currentIndex + 1;
              audioService.moveQueueTrack(queueIndex, insertIndex);
            },
      onRemoveFromQueue: widget.onRemove,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.song;

    final hasThumb = song.thumbnailPath != null &&
        song.thumbnailPath!.isNotEmpty &&
        File(song.thumbnailPath!).existsSync();
    final hasArt = song.artworkPath != null &&
        song.artworkPath!.isNotEmpty &&
        File(song.artworkPath!).existsSync();
    final coverPath = hasThumb ? song.thumbnailPath : (hasArt ? song.artworkPath : null);

    return Material(
      color: widget.isCurrent
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.32)
          : (_isHovered
              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
              : Colors.transparent),
      child: InkWell(
        onTap: widget.onTap,
        onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
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
                  child: Container(
                    width: 36,
                    height: 36,
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
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist ?? '',
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
                if (_isHovered)
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
