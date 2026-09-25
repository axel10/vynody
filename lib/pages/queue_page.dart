import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import '../widgets/song_tile.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/utils/deleted_song_snack.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import 'package:vynody/widgets/queue_file_drop_target.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/library_selection_panel.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'package:vynody/utils/queue_sort_utils.dart';
import 'package:vynody/utils/list_reorder_utils.dart';


// 队列页面
class QueuePage extends ConsumerStatefulWidget {
  const QueuePage({super.key});

  @override
  ConsumerState<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends ConsumerState<QueuePage>
    with SelectionStateMixin<QueuePage, int> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.queue;

  final _keyPool = ReorderableKeyPool(debugPrefix: 'queue-tile');
  int _viewIndex = 0; // 0: Normal Queue, 1: Random History, 2: Random Queue
  late final ScrollController _scrollController;
  int? _highlightedIndex;
  Timer? _highlightTimer;
  QueueSortField _sortField = QueueSortField.title;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  String _formatDurationText(Duration duration, AppLocalizations l10n) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final isZh = l10n.localeName.startsWith('zh');
    if (isZh) {
      if (hours > 0) {
        return '$hours小时$minutes分钟';
      } else if (minutes > 0) {
        return '$minutes分钟$seconds秒';
      } else {
        return '$seconds秒';
      }
    } else {
      if (hours > 0) {
        return '${hours}h ${minutes}m';
      } else if (minutes > 0) {
        return '${minutes}m ${seconds}s';
      } else {
        return '${seconds}s';
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _keyPool.clear();
    super.dispose();
  }

  List<MusicFile> _selectedSongsFromDisplay(List<MusicFile> displayQueue) {
    return selectedKeys
        .where((index) => index >= 0 && index < displayQueue.length)
        .map((index) => displayQueue[index])
        .toList(growable: false);
  }

  void _scrollToCurrentPlay() {
    final queue = ref.read(audioPlaybackQueueProvider);
    final randomHistory = ref.read(audioRandomHistoryProvider);
    final randomQueue = ref.read(audioRandomQueueProvider);
    final currentIndex = ref.read(audioCurrentIndexProvider);
    final historyCursor = ref.read(audioHistoryCursorProvider);
    final deckCursor = ref.read(audioDeckCursorProvider);

    final displayQueueLength = _viewIndex == 1
        ? randomHistory.length
        : _viewIndex == 2
        ? randomQueue.length
        : queue.length;

    final int? targetIndex;
    if (_viewIndex == 1) {
      targetIndex = historyCursor;
    } else if (_viewIndex == 2) {
      targetIndex = deckCursor;
    } else {
      targetIndex = currentIndex;
    }

    if (targetIndex != null && targetIndex >= 0 && targetIndex < displayQueueLength) {
      if (_scrollController.hasClients) {
        const double itemHeight = 80.0;
        final double viewportHeight = _scrollController.position.viewportDimension;
        double targetOffset = (targetIndex * itemHeight) - (viewportHeight / 2) + (itemHeight / 2);
        
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (targetOffset < 0) {
          targetOffset = 0;
        } else if (targetOffset > maxScroll) {
          targetOffset = maxScroll;
        }

        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ).then((_) {
          if (mounted) {
            _highlightTimer?.cancel();
            setState(() {
              _highlightedIndex = targetIndex;
            });
            _highlightTimer = Timer(const Duration(milliseconds: 1000), () {
              if (mounted) {
                setState(() {
                  _highlightedIndex = null;
                });
              }
            });
          }
        });
      }
    }
  }

  GlobalKey _songTileKeyFor(int index, [MusicFile? song]) {
    return _keyPool.getKey(index);
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
          _applySort(field, ascending);
        }
      },
    );

    if (result != null && mounted) {
      setState(() {
        _sortField = result.field;
        _sortAscending = result.sortAscending;
      });
      _applySort(result.field, result.sortAscending);
    }
  }

  void _applySort(QueueSortField field, bool ascending) {
    final currentQueue = ref.read(audioPlaybackQueueProvider);
    if (currentQueue.isEmpty) return;

    final sortedList = QueueSortUtils.sortQueue(currentQueue, field, ascending);

    if (ref.read(librarySelectionScopeProvider) ==
        LibrarySelectionScope.queue) {
      cancelSelection();
    }
    ref.read(audioServiceProvider).updateQueue(sortedList);
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
    final isSelectionMode =
        ref.watch(librarySelectionScopeProvider) ==
        LibrarySelectionScope.queue;
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final bottomOffset = (currentMusic != null ? 140.0 : 40.0) +
        (isSelectionMode ? 220.0 : 0.0);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
    _keyPool.syncLength(displayQueue.length);
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final headerHorizontalPadding = isPortrait ? 20.0 : 32.0;
    final headerIconColor =
        theme.colorScheme.onSurface.withValues(alpha: 0.85);
    final l10n = AppLocalizations.of(context)!;

    int totalDurationMs = 0;
    for (final song in displayQueue) {
      totalDurationMs += song.durationMillis ?? 0;
    }

    final String countAndDurationText;
    if (displayQueue.isEmpty) {
      countAndDurationText = l10n.songCount(0);
    } else if (totalDurationMs > 0) {
      countAndDurationText =
          '${l10n.songCount(displayQueue.length)} · ${_formatDurationText(Duration(milliseconds: totalDurationMs), l10n)}';
    } else {
      countAndDurationText = l10n.songCount(displayQueue.length);
    }

    final Widget subtitleWidget;
    if (isRandomMode) {
      subtitleWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildViewSelector(
            context,
            theme,
            isDark,
            isShuffleRandomMode,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '· $countAndDurationText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    } else {
      subtitleWidget = Text(
        countAndDurationText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final bool canSort = _viewIndex == 0 && displayQueue.isNotEmpty;
    final bool canLocate = displayQueue.isNotEmpty;
    final bool canClear = queue.isNotEmpty;

    final headerActionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.sort_rounded,
            size: 20,
            color: canSort
                ? headerIconColor
                : headerIconColor.withValues(alpha: 0.38),
          ),
          onPressed: canSort ? () => _showSortDialog(context) : null,
          tooltip: l10n.sort,
        ),
        IconButton(
          icon: Icon(
            Icons.my_location_rounded,
            size: 20,
            color: canLocate
                ? headerIconColor
                : headerIconColor.withValues(alpha: 0.38),
          ),
          onPressed: canLocate ? _scrollToCurrentPlay : null,
          tooltip: l10n.locateCurrentSong,
        ),
        IconButton(
          icon: Icon(
            Icons.delete_sweep_rounded,
            size: 20,
            color: canClear
                ? headerIconColor
                : headerIconColor.withValues(alpha: 0.38),
          ),
          onPressed: canClear ? () => _showClearQueueDialog(context) : null,
          tooltip: canClear ? l10n.clearQueue : l10n.queueEmpty,
        ),
      ],
    );

    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final double safeTopPadding =
        isDesktop ? 32.0 : MediaQuery.of(context).padding.top;
    final double topBarHeight = safeTopPadding + 70.0;

    final Widget listOrEmpty;
    if (displayQueue.isEmpty) {
      listOrEmpty = Padding(
        padding: EdgeInsets.only(top: topBarHeight),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
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
                  l10n.queueEmpty,
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      listOrEmpty = Column(
        children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ReorderableListView.builder(
                          scrollController: _scrollController,
                          buildDefaultDragHandles: false,
                          cacheExtent: 1000.0,
                          padding: EdgeInsets.only(
                            top: topBarHeight,
                            bottom: bottomOffset,
                          ),
                          itemCount: displayQueue.length,
                          onReorderItem: (oldIndex, newIndex) {
                            if (_viewIndex != 0) return;
                            _keyPool.moveKey(oldIndex, newIndex);
                            reorderSelection(oldIndex, newIndex);
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
                            final isSelected = this.isSelected(index);
                            final songsToAdd = selectedKeys.isNotEmpty
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
                                    : () => ref
                                          .read(audioServiceProvider)
                                          .removeFromPlaylist(index),
                              );
                            }

                            return Align(
                              key: _songTileKeyFor(index, song),
                              alignment: Alignment.center,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
                                child: Padding(
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
                                    selectedPaths: isSelectionMode
                                        ? selectedKeys
                                            .map((i) => (i >= 0 &&
                                                    i < displayQueue.length)
                                                ? displayQueue[i].path
                                                : null)
                                            .whereType<String>()
                                            .toSet()
                                        : const <String>{},
                                    isHighlighted: _highlightedIndex == index,
                                    dragHandle: ReorderableDragStartListener(
                                      index: index,
                                      child: const Icon(Icons.drag_handle),
                                    ),
                                    onTap: () {
                                      if (isMissing) {
                                        showDeletedSongSnack(
                                          context,
                                          ref,
                                          skipped: false,
                                        );
                                        return;
                                      }

                                      handleItemTap(
                                        index: index,
                                        itemKey: index,
                                        allKeys: List.generate(
                                          displayQueue.length,
                                          (i) => i,
                                        ),
                                        onNormalTap: () {
                                          if (_viewIndex == 1 ||
                                              _viewIndex == 2) {
                                            final actualIndex = queue
                                                .indexWhere(
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
                                      );
                                    },
                                     onLongPress: () {
                                       lastAnchorIndex = index;
                                       if (!isSelectionMode) {
                                         enterSelectionMode(index);
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
                                      final renderBox =
                                          renderObject is RenderBox
                                              ? renderObject
                                              : null;
                                      if (renderBox == null) return;
                                      final Offset offset = renderBox
                                          .localToGlobal(Offset.zero);
                                      handleShowMenu(buttonContext, offset);
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
    }

    return Scaffold(
      body: QueueFileDropTarget(
        enabled: true,
        displayQueue: displayQueue,
        queueSongs: queue,
        itemKeyBuilder: _songTileKeyFor,
        showPreview: showPreview,
        child: Stack(
          fit: StackFit.expand,
          children: [
            listOrEmpty,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topBarHeight,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: EdgeInsets.only(top: safeTopPadding),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(
                        alpha: isDark ? 0.66 : 0.80,
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kSingleColumnContentMaxWidth,
                        ),
                        child: SizedBox(
                          height: 70.0,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: headerHorizontalPadding,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l10n.queue,
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      subtitleWidget,
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                headerActionButtons,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSelectionPanel(
              isVisible: isSelectionMode,
              child: LibrarySelectionPanel(
                key: const ValueKey('library-selection-panel'),
                selectedSongs: _selectedSongsFromDisplay(
                  displayQueue,
                ),
                allSongs: displayQueue,
                onToggleSelectAll: () => toggleSelectAll(
                  List.generate(displayQueue.length, (i) => i),
                ),
                onCancel: cancelSelection,
                replaceFavoritesWithSongDetails: true,
                onDelete: _viewIndex == 0
                    ? () {
                        final sortedIndices =
                            selectedKeys.toList()..sort();
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
                        cancelSelection();
                        if (context.mounted) {
                          AppSnackBar.show(
                            context,
                            ref,
                            SnackBar(
                              content: Text(
                                AppLocalizations.of(
                                  context,
                                )!.deletedSongs(sortedIndices.length),
                              ),
                            ),
                          );
                        }
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewSelector(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    bool isShuffleRandomMode,
  ) {
    String selectedText = '';
    if (_viewIndex == 0) {
      selectedText = AppLocalizations.of(context)!.queue;
    } else if (_viewIndex == 1) {
      selectedText = AppLocalizations.of(context)!.randomHistory;
    } else if (_viewIndex == 2) {
      selectedText = AppLocalizations.of(context)!.randomQueue;
    }

    return PopupMenuButton<int>(
      offset: const Offset(0, 4),
      position: PopupMenuPosition.under,
      tooltip: AppLocalizations.of(context)!.queue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      color: isDark ? Colors.grey[900] : theme.colorScheme.surface,
      elevation: 8,
      onSelected: (val) {
        setState(() {
          _viewIndex = val;
        });
      },
      itemBuilder: (context) => [
        _buildPopupMenuItem(
          context,
          value: 0,
          text: AppLocalizations.of(context)!.queue,
          icon: Icons.queue_music,
          isSelected: _viewIndex == 0,
        ),
        _buildPopupMenuItem(
          context,
          value: 1,
          text: AppLocalizations.of(context)!.randomHistory,
          icon: Icons.history,
          isSelected: _viewIndex == 1,
        ),
        if (isShuffleRandomMode)
          _buildPopupMenuItem(
            context,
            value: 2,
            text: AppLocalizations.of(context)!.randomQueue,
            icon: Icons.shuffle,
            isSelected: _viewIndex == 2,
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 2,
          vertical: 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selectedText,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<int> _buildPopupMenuItem(
    BuildContext context, {
    required int value,
    required String text,
    required IconData icon,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color getForegroundColor() {
      if (isSelected) {
        return theme.colorScheme.primary;
      }
      return isDark ? Colors.white70 : Colors.black87;
    }

    return PopupMenuItem<int>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: getForegroundColor(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: getForegroundColor(),
              ),
            ),
          ),
          if (isSelected)
            Icon(
              Icons.check_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
        ],
      ),
    );
  }
}
