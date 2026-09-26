import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/player/platform/right_queue_drawer_controller.dart';
import 'package:vynody/player/platform/standalone_queue_window_manager.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import 'package:vynody/utils/list_reorder_utils.dart';
import 'package:vynody/utils/playlist_name.dart';
import 'package:vynody/utils/queue_sort_utils.dart';
import 'package:vynody/utils/selection_utils.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/utils/time_format_utils.dart';
import 'package:vynody/widgets/app_tooltip.dart';
import 'package:vynody/widgets/draggable_song_item.dart';
import 'package:vynody/widgets/queue_file_drop_target.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

class RightQueuePanel extends ConsumerStatefulWidget {
  const RightQueuePanel({super.key});

  @override
  ConsumerState<RightQueuePanel> createState() => _RightQueuePanelState();
}

class _RightQueuePanelState extends ConsumerState<RightQueuePanel> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _playlistScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final _queueReorderController =
      ReorderableListController<MusicFile>(debugPrefix: 'right-queue-tile');
  final _playlistSongReorderController =
      ReorderableListController<MusicFile>(debugPrefix: 'right-playlist-song-tile');
  QueueSortField _sortField = QueueSortField.title;
  bool _sortAscending = true;

  int _currentTabIndex = 0; // 0: 播放队列, 1: 播放列表
  Timer? _tabHoverTimer;
  String? _selectedPlaylistId;

  final Set<int> _selectedIndices = {};
  bool _isSelectionMode = false;
  int? _lastAnchorIndex;

  @override
  void dispose() {
    _tabHoverTimer?.cancel();
    _scrollController.dispose();
    _playlistScrollController.dispose();
    _focusNode.dispose();
    _queueReorderController.clear();
    _playlistSongReorderController.clear();
    super.dispose();
  }

  void _onTabHoverEnter(int targetTab) {
    _tabHoverTimer?.cancel();
    if (_currentTabIndex != targetTab) {
      _tabHoverTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _currentTabIndex = targetTab;
            if (_currentTabIndex != 0) {
              _exitSelectionMode();
            }
          });
        }
      });
    }
  }

  void _onTabHoverExit() {
    _tabHoverTimer?.cancel();
    _tabHoverTimer = null;
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

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建歌单'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '歌单名称',
              hintText: '请输入歌单名称',
              errorText: errorText,
            ),
            onChanged: (val) {
              if (errorText != null) {
                setDialogState(() => errorText = null);
              }
            },
            onSubmitted: (val) async {
              final name = val.trim();
              if (name.isNotEmpty) {
                final playlistService = ref.read(playlistServiceProvider);
                if (playlistService.playlistExists(name)) {
                  setDialogState(() => errorText = '已存在同名歌单');
                  return;
                }
                await playlistService.createPlaylist(name);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final playlistService = ref.read(playlistServiceProvider);
                  if (playlistService.playlistExists(name)) {
                    setDialogState(() => errorText = '已存在同名歌单');
                    return;
                  }
                  await playlistService.createPlaylist(name);
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final queue = ref.watch(audioPlaybackQueueProvider);
    final playlists = ref.watch(playlistServiceProvider).playlists;
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    final isPlaying = ref.watch(audioIsPlayingProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final audioService = ref.read(audioServiceProvider);
    final playlistService = ref.watch(playlistServiceProvider);
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final topPadding = isDesktop ? 32.0 : 0.0;

    final activePlaylist = playlists.isNotEmpty
        ? (playlists.firstWhereOrNull((p) => p.id == _selectedPlaylistId) ??
            playlists.firstWhereOrNull((p) => p.id == playlistService.currentPlaylist?.id) ??
            playlists.first)
        : null;
    final activePlaylistSongs = activePlaylist?.songs ?? const <MusicFile>[];

    _queueReorderController.syncLength(queue.length);
    if (activePlaylist != null) {
      _playlistSongReorderController.syncLength(activePlaylist.songs.length);
    }

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
            displayQueue: _currentTabIndex == 0 ? queue : activePlaylistSongs,
            queueSongs: _currentTabIndex == 0 ? queue : activePlaylistSongs,
            itemKeyBuilder: (index, song) => _currentTabIndex == 0
                ? _queueReorderController.getKey(index)
                : _playlistSongReorderController.getKey(index),
            showPreview: (_currentTabIndex == 0 ? queue : activePlaylistSongs).isNotEmpty,
            indicatorHorizontalPadding: 12.0,
            onFilesDropped: (paths, insertIndex) async {
              if (_currentTabIndex == 0) {
                await ref
                    .read(standaloneQueueWindowManagerProvider)
                    .handleDroppedPaths(paths, insertIndex: insertIndex);
              } else if (activePlaylist != null) {
                await ref
                    .read(standaloneQueueWindowManagerProvider)
                    .addPathsToPlaylist(activePlaylist.id, paths);
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isSelecting =
                    _isSelectionMode || _selectedIndices.isNotEmpty;
                final isWide = constraints.maxWidth >= 390;

                return Column(
                  children: [
                    if (topPadding > 0) SizedBox(height: topPadding),
                    _buildHeader(context, queue, playlists, isWide: isWide),
                    if (!isWide && !isSelecting)
                      _buildTabBarRow(context, queue.length, playlists.length),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _currentTabIndex == 0
                            ? (queue.isEmpty
                                ? _buildEmptyView(context)
                                : _buildQueueList(
                                    context,
                                    queue,
                                    currentIndex,
                                    isPlaying,
                                    audioService,
                                  ))
                            : _buildPlaylistsView(
                                context,
                                playlists,
                                activePlaylist,
                                audioService,
                                playlistService,
                                currentMusic,
                                isPlaying,
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    List<MusicFile> queue,
    List<Playlist> playlists, {
    required bool isWide,
  }) {
    final theme = Theme.of(context);
    final queueLength = queue.length;
    final isSelecting = _isSelectionMode || _selectedIndices.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
                if (isWide)
                  _buildInlineTabBar(context, queue.length, playlists.length)
                else ...[
                  Icon(
                    _currentTabIndex == 0
                        ? Icons.queue_music_rounded
                        : Icons.playlist_play_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentTabIndex == 0 ? '播放队列' : '播放列表',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
                const Spacer(),
                if (_currentTabIndex == 0) ...[
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
                      message: '排序',
                      child: IconButton(
                        icon: const Icon(Icons.sort_rounded, size: 18),
                        onPressed: () => _showSortDialog(context),
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
                  message: '关闭抽屉',
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      ref.read(rightQueueDrawerProvider.notifier).close();
                    },
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInlineTabBar(
    BuildContext context,
    int queueCount,
    int playlistCount,
  ) {
    final theme = Theme.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPillTabItem(
            context: context,
            title: '播放队列',
            count: queueCount,
            index: 0,
            isSelected: _currentTabIndex == 0,
            isCompact: true,
          ),
          const SizedBox(width: 4),
          _buildPillTabItem(
            context: context,
            title: '播放列表',
            count: playlistCount,
            index: 1,
            isSelected: _currentTabIndex == 1,
            isCompact: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBarRow(
    BuildContext context,
    int queueCount,
    int playlistCount,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: Container(
        height: 34,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildPillTabItem(
                context: context,
                title: '播放队列',
                count: queueCount,
                index: 0,
                isSelected: _currentTabIndex == 0,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _buildPillTabItem(
                context: context,
                title: '播放列表',
                count: playlistCount,
                index: 1,
                isSelected: _currentTabIndex == 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillTabItem({
    required BuildContext context,
    required String title,
    required int count,
    required int index,
    required bool isSelected,
    bool isCompact = false,
  }) {
    final theme = Theme.of(context);

    return DropRegion(
      formats: const [Formats.fileUri, Formats.plainText, Formats.uri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropEnter: (_) => _onTabHoverEnter(index),
      onDropLeave: (_) => _onTabHoverExit(),
      onDropEnded: (_) => _onTabHoverExit(),
      onDropOver: (event) => DropOperation.copy,
      onPerformDrop: (event) async {},
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _currentTabIndex = index;
            if (_currentTabIndex != 0) {
              _exitSelectionMode();
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          padding: isCompact
              ? const EdgeInsets.symmetric(horizontal: 10)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
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
              '可从左侧媒体库、目录或歌单\n直接将歌曲拖拽到此处',
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
    _queueReorderController.syncLength(queue.length);

    return ReorderableListView.builder(
      scrollController: _scrollController,
      buildDefaultDragHandles: false,
      itemCount: queue.length,
      onReorderItem: (oldIndex, newIndex) {
        setState(() {
          _queueReorderController.handleReorder(
            oldIndex: oldIndex,
            newIndex: newIndex,
            selectedIndices: _selectedIndices,
            onPersist: () => audioService.moveQueueTrack(oldIndex, newIndex),
          );
        });
      },
      itemBuilder: (context, index) {
        final song = queue[index];
        final isCurrent = index == currentIndex;
        final isSelected = _selectedIndices.contains(index);

        return _RightQueueTile(
          key: _queueReorderController.getKey(index),
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

  Widget _buildPlaylistsView(
    BuildContext context,
    List<Playlist> playlists,
    Playlist? activePlaylist,
    AudioService audioService,
    PlaylistService playlistService,
    MusicFile? currentMusic,
    bool isPlaying,
  ) {
    final theme = Theme.of(context);

    if (playlists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.playlist_play_rounded,
                size: 52,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 14),
              Text(
                '暂无播放列表',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => _showCreatePlaylistDialog(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新建歌单'),
              ),
            ],
          ),
        ),
      );
    }

    if (activePlaylist == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        _buildPlaylistSelectorHeader(
          context,
          playlists,
          activePlaylist,
          audioService,
          playlistService,
        ),
        Expanded(
          child: activePlaylist.songs.isEmpty
              ? _buildEmptyPlaylistSongsView(context, activePlaylist)
              : _buildPlaylistSongsList(
                  context,
                  activePlaylist,
                  audioService,
                  playlistService,
                  currentMusic,
                  isPlaying,
                ),
        ),
      ],
    );
  }

  Widget _buildPlaylistSelectorHeader(
    BuildContext context,
    List<Playlist> playlists,
    Playlist activePlaylist,
    AudioService audioService,
    PlaylistService playlistService,
  ) {
    final theme = Theme.of(context);
    final isFavorite = activePlaylist.id == PlaylistService.favoritePlaylistId;
    final isDefault = activePlaylist.id == 'default';
    final isBuiltin = isFavorite || isDefault;
    final plName = localizedPlaylistName(context, activePlaylist);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Builder(
              builder: (btnContext) => InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  final box = btnContext.findRenderObject() as RenderBox?;
                  final overlay =
                      Overlay.of(context).context.findRenderObject() as RenderBox?;
                  if (box != null && overlay != null) {
                    final pos = box.localToGlobal(Offset.zero);
                    showMenu<String>(
                      context: context,
                      position: RelativeRect.fromRect(
                        pos & box.size,
                        Offset.zero & overlay.size,
                      ),
                      items: playlists.map((p) {
                        final isFav = p.id == PlaylistService.favoritePlaylistId;
                        final isDef = p.id == 'default';
                        final name = localizedPlaylistName(context, p);
                        final isSelected = p.id == activePlaylist.id;
                        return PopupMenuItem<String>(
                          value: p.id,
                          child: Row(
                            children: [
                              Icon(
                                isFav
                                    ? Icons.favorite_rounded
                                    : (isDef
                                        ? Icons.queue_music_rounded
                                        : Icons.playlist_play_rounded),
                                size: 18,
                                color: isFav
                                    ? Colors.redAccent
                                    : (isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${p.songs.length} 首',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    ).then((selectedId) {
                      if (selectedId != null && mounted) {
                        setState(() => _selectedPlaylistId = selectedId);
                        playlistService.setCurrentPlaylist(selectedId);
                      }
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isFavorite
                            ? Icons.favorite_rounded
                            : (isDefault
                                ? Icons.queue_music_rounded
                                : Icons.playlist_play_rounded),
                        size: 16,
                        color: isFavorite
                            ? Colors.redAccent
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$plName (${activePlaylist.songs.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (activePlaylist.songs.isNotEmpty) ...[
            AppTooltip(
              message: '播放全部',
              child: IconButton(
                icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
                onPressed: () => audioService.playPlaylist(
                  activePlaylist.songs,
                  source: PlaybackSource(
                    type: PlaybackSourceType.playlist,
                    id: activePlaylist.id,
                    name: activePlaylist.name,
                  ),
                ),
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.primary,
              ),
            ),
            AppTooltip(
              message: '追加到队列末尾',
              child: IconButton(
                icon: const Icon(Icons.playlist_add_rounded, size: 20),
                onPressed: () {
                  audioService.appendToQueue(activePlaylist.songs);
                  AppSnackBar.show(
                    context,
                    ref,
                    SnackBar(
                      content: Text('已将 ${activePlaylist.songs.length} 首歌曲追加到队列末尾'),
                    ),
                  );
                },
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          AppTooltip(
            message: '新建歌单',
            child: IconButton(
              icon: const Icon(Icons.add_rounded, size: 20),
              onPressed: () => _showCreatePlaylistDialog(context),
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            tooltip: '更多选项',
            color: theme.colorScheme.surface,
            onSelected: (action) async {
              if (action == 'clear') {
                await playlistService.clearPlaylist(activePlaylist.id);
                if (context.mounted) {
                  AppSnackBar.show(
                    context,
                    ref,
                    SnackBar(content: Text('已清空【$plName】')),
                  );
                }
              } else if (action == 'rename') {
                _showRenameDialog(context, activePlaylist);
              } else if (action == 'delete') {
                await playlistService.deletePlaylist(activePlaylist.id);
                if (context.mounted) {
                  AppSnackBar.show(
                    context,
                    ref,
                    SnackBar(content: Text('已删除歌单【$plName】')),
                  );
                }
              }
            },
            itemBuilder: (ctx) => [
              if (activePlaylist.songs.isNotEmpty)
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.clear_all_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('清空歌曲'),
                    ],
                  ),
                ),
              if (!isBuiltin) ...[
                const PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('重命名歌单'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('删除歌单', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPlaylistSongsView(BuildContext context, Playlist playlist) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_add_rounded,
              size: 52,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 14),
            Text(
              '歌单内暂无歌曲',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '可从左侧媒体库拖拽歌曲\n或直接拖拽本地音频文件至此',
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

  Widget _buildPlaylistSongsList(
    BuildContext context,
    Playlist playlist,
    AudioService audioService,
    PlaylistService playlistService,
    MusicFile? currentMusic,
    bool isPlaying,
  ) {
    _playlistSongReorderController.syncLength(playlist.songs.length);

    return ReorderableListView.builder(
      scrollController: _playlistScrollController,
      buildDefaultDragHandles: false,
      itemCount: playlist.songs.length,
      onReorderItem: (oldIndex, newIndex) {
        _playlistSongReorderController.handleReorder(
          oldIndex: oldIndex,
          newIndex: newIndex,
          onPersist: () => playlistService.reorderSongsInPlaylist(
            playlist.id,
            oldIndex,
            newIndex,
          ),
        );
      },
      itemBuilder: (context, index) {
        final song = playlist.songs[index];
        final isCurrent = currentMusic?.path == song.path;

        return _RightPlaylistSongTile(
          key: _playlistSongReorderController.getKey(index),
          song: song,
          index: index,
          isCurrent: isCurrent,
          isPlaying: isCurrent && isPlaying,
          durationFormatted: TimeFormatUtils.formatMs(song.durationMillis ?? 0),
          onTap: () => audioService.playPlaylist(
            playlist.songs,
            initialIndex: index,
            source: PlaybackSource(
              type: PlaybackSourceType.playlist,
              id: playlist.id,
              name: playlist.name,
            ),
          ),
          onSecondaryTap: (pos) => _handlePlaylistSongRightClick(
            context,
            pos,
            song,
            index,
            playlist,
            audioService,
            playlistService,
          ),
          onRemove: () =>
              playlistService.removeSongsFromPlaylist(playlist.id, [index]),
        );
      },
    );
  }

  void _handlePlaylistSongRightClick(
    BuildContext context,
    Offset globalPos,
    MusicFile song,
    int index,
    Playlist playlist,
    AudioService audioService,
    PlaylistService playlistService,
  ) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showSongContextMenu(
      context,
      globalPos,
      song: song,
      songs: [song],
      mode: SongContextMenuMode.full,
      onPlayNext: () => audioService.enqueueNext([song]),
      onAddToQueue: () => audioService.appendToQueue([song]),
      onRemoveFromPlaylist: () =>
          playlistService.removeSongsFromPlaylist(playlist.id, [index]),
    );
  }

  void _showRenameDialog(BuildContext context, Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('重命名歌单'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '歌单名称',
              errorText: errorText,
            ),
            onSubmitted: (val) async {
              final newName = val.trim();
              if (newName.isNotEmpty && newName != playlist.name) {
                final playlistService = ref.read(playlistServiceProvider);
                if (playlistService.playlistExists(newName, excludeId: playlist.id)) {
                  setDialogState(() => errorText = '已存在同名歌单');
                  return;
                }
                await playlistService.renamePlaylist(playlist.id, newName);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isNotEmpty && newName != playlist.name) {
                  final playlistService = ref.read(playlistServiceProvider);
                  if (playlistService.playlistExists(newName, excludeId: playlist.id)) {
                    setDialogState(() => errorText = '已存在同名歌单');
                    return;
                  }
                  await playlistService.renamePlaylist(playlist.id, newName);
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RightPlaylistSongTile extends ConsumerStatefulWidget {
  final MusicFile song;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final String durationFormatted;
  final VoidCallback onTap;
  final ValueChanged<Offset> onSecondaryTap;
  final VoidCallback onRemove;

  const _RightPlaylistSongTile({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.durationFormatted,
    required this.onTap,
    required this.onSecondaryTap,
    required this.onRemove,
  });

  @override
  ConsumerState<_RightPlaylistSongTile> createState() =>
      _RightPlaylistSongTileState();
}

class _RightPlaylistSongTileState
    extends ConsumerState<_RightPlaylistSongTile> {
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
    final displayArtist =
        (artist != null && artist.isNotEmpty) ? artist : '未知艺术家';
    final displayAlbum = (album != null && album.isNotEmpty) ? album : null;
    final subtitleText =
        displayAlbum != null ? '$displayArtist - $displayAlbum' : displayArtist;

    final itemColor = widget.isCurrent
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
        : (_isHovered
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : Colors.transparent);

    return Material(
      color: itemColor,
      child: InkWell(
        onTap: widget.onTap,
        onSecondaryTapUp: (details) =>
            widget.onSecondaryTap(details.globalPosition),
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
                Expanded(
                  child: DraggableSongItem(
                    song: song,
                    child: Row(
                      children: [
                        SongThumbnail.fromSong(
                          song,
                          size: 36.0,
                          borderRadius: BorderRadius.circular(6),
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
                                            : FontWeight.w500,
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
                                subtitleText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.durationFormatted.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    widget.durationFormatted,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: _isHovered ? 0.8 : 0.4),
                  ),
                  onPressed: widget.onRemove,
                  visualDensity: VisualDensity.compact,
                  tooltip: '从歌单中移除',
                ),
              ],
            ),
          ),
        ),
      ),
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
                Expanded(
                  child: DraggableSongItem(
                    song: song,
                    isSelected: widget.isSelected,
                    isSelectionMode: widget.isSelectionMode,
                    child: Row(
                      children: [
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
                                  child: SongThumbnail.fromSong(
                                    song,
                                    size: 36.0,
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
                      ],
                    ),
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
