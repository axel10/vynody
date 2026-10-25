import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../player/audio/audio_riverpod.dart';
import '../player/audio/playback_source.dart';
import '../player/library/playlist_service.dart';
import '../utils/app_log.dart';
import '../utils/playlist_name.dart';
import '../utils/song_context_menu_utils.dart';
import '../widgets/album_detail_widgets.dart';
import '../widgets/app_context_menu.dart';
import '../widgets/app_top_nav_bar.dart';
import '../widgets/auto_hide_header.dart';
import '../widgets/folder_layout_utils.dart';
import '../widgets/folder_zoom_gesture_layer.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/mini_player_wrapper.dart';
import '../widgets/playlist_context_menu.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/song_zoom_item.dart';
import 'main_layout_riverpod.dart';

/// 播放列表详情页（第二级页面）
class PlaylistDetailPage extends ConsumerStatefulWidget {
  const PlaylistDetailPage({super.key, required this.playlist, this.onGoBack});

  final Playlist playlist;
  final VoidCallback? onGoBack;

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage>
    with
        SelectionStateMixin<PlaylistDetailPage, String>,
        SongSelectionMixin<PlaylistDetailPage> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.playlist;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    AppLog.log(
      '[NavTrace] PlaylistDetailPage.initState: playlist="${widget.playlist.name}" (id=${widget.playlist.id}, songs=${widget.playlist.songs.length})',
      mirrorToConsole: true,
    );
  }

  @override
  void dispose() {
    AppLog.log(
      '[NavTrace] PlaylistDetailPage.dispose: playlist="${widget.playlist.name}" (id=${widget.playlist.id})',
      mirrorToConsole: true,
    );
    _scrollController.dispose();
    super.dispose();
  }

  static double getBarHeight(BuildContext context) =>
      AppTopNavBar.getBarHeight(context);

  String? _formatDuration(int? durationMs) {
    if (durationMs == null) return null;
    final duration = Duration(milliseconds: durationMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${duration.inMinutes}:${seconds.toString().padLeft(2, '0')}';
  }

  void _handleBack() {
    ref.read(selectedPlaylistIdProvider.notifier).set(null);
    if (widget.onGoBack != null) {
      widget.onGoBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final playlistService = ref.watch(playlistServiceProvider);
    final settings = ref.watch(settingsServiceProvider);
    final zoomScale = settings.folderZoomScale;

    final Playlist activePlaylist =
        playlistService.playlists.firstWhereOrNull(
          (p) => p.id == widget.playlist.id,
        ) ??
        widget.playlist;

    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final isLandscape = !isPortrait;
    final double leftPadding = isLandscape
        ? sidebarRailWidthFor(MediaQuery.of(context).size.width)
        : 0.0;

    final selectedSongs = isSelectionMode
        ? getSelectedSongs(activePlaylist.songs)
        : const <MusicFile>[];
    final selectedSongPaths = selectedSongs.map((s) => s.path).toSet();

    final totalDurationMillis = activePlaylist.songs.fold<int>(
      0,
      (sum, s) => sum + (s.durationMillis ?? 0),
    );
    final durationText =
        _formatDuration(totalDurationMillis) ?? l10n.durationZero;
    final trackCountText = l10n.songCount(activePlaylist.songs.length);
    final plName = localizedPlaylistName(context, activePlaylist);
    final double barHeight = getBarHeight(context);

    final isCustomPlaylist =
        activePlaylist.id != 'default' &&
        activePlaylist.id != PlaylistService.favoritePlaylistId;

    final metadataWidget = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          '$trackCountText · $durationText',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

    final actionButtons = <Widget>[
      ElevatedButton.icon(
        onPressed: activePlaylist.songs.isNotEmpty
            ? () => audio.playPlaylist(
                activePlaylist.songs,
                source: PlaybackSource(
                  type: PlaybackSourceType.playlist,
                  id: activePlaylist.id,
                  name: activePlaylist.name,
                ),
              )
            : null,
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(l10n.playAll),
        style: isPortrait
            ? ElevatedButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              )
            : null,
      ),
      isPortrait
          ? OutlinedButton.icon(
              onPressed: activePlaylist.songs.isNotEmpty
                  ? () => audio.playPlaylist(
                      List.of(activePlaylist.songs)..shuffle(),
                      source: PlaybackSource(
                        type: PlaybackSourceType.playlist,
                        id: activePlaylist.id,
                        name: activePlaylist.name,
                      ),
                    )
                  : null,
              icon: const Icon(Icons.shuffle),
              label: Text(l10n.shufflePlay),
            )
          : FilledButton.tonalIcon(
              onPressed: activePlaylist.songs.isNotEmpty
                  ? () => audio.playPlaylist(
                      List.of(activePlaylist.songs)..shuffle(),
                      source: PlaybackSource(
                        type: PlaybackSourceType.playlist,
                        id: activePlaylist.id,
                        name: activePlaylist.name,
                      ),
                    )
                  : null,
              icon: const Icon(Icons.shuffle),
              label: Text(l10n.shufflePlay),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
      PopupMenuButton<String>(
        tooltip: l10n.more,
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (value) async {
          switch (value) {
            case 'rename':
              await showPlaylistRenameDialog(context, ref, activePlaylist);
              break;
            case 'export':
              await exportPlaylistAsM3u(context, ref, activePlaylist);
              break;
            case 'clear':
              await showPlaylistClearConfirmDialog(
                context,
                ref,
                activePlaylist,
              );
              break;
            case 'delete':
              await showPlaylistDeleteConfirmDialog(
                context,
                ref,
                activePlaylist,
                onDeleted: () {
                  _handleBack();
                },
              );
              break;
            case 'multi_select':
              enterSelectionMode(activePlaylist.songs.first.path);
              break;
          }
        },
        itemBuilder: (context) => [
          if (isCustomPlaylist)
            buildContextMenuItem<String>(
              value: 'rename',
              label: l10n.renamePlaylist,
              icon: Icons.edit_outlined,
              context: context,
            ),
          if (activePlaylist.songs.isNotEmpty) ...[
            buildContextMenuItem<String>(
              value: 'export',
              label: l10n.exportPlaylist,
              icon: Icons.file_upload_outlined,
              context: context,
            ),
            buildContextMenuItem<String>(
              value: 'clear',
              label: l10n.clearPlaylist,
              icon: Icons.clear_all_rounded,
              iconColor: theme.colorScheme.error,
              context: context,
            ),
            buildContextMenuItem<String>(
              value: 'multi_select',
              label: l10n.multiSelect,
              icon: Icons.checklist_rounded,
              context: context,
            ),
          ],
          if (isCustomPlaylist)
            buildContextMenuItem<String>(
              value: 'delete',
              label: l10n.deletePlaylist,
              icon: Icons.delete_outline_rounded,
              iconColor: theme.colorScheme.error,
              context: context,
            ),
        ],
      ),
    ];

    Widget buildSongSlivers(FolderZoomLayoutMetrics metrics) {
      if (activePlaylist.songs.isEmpty) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 64.0),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    size: 64,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.emptyList,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      final isPlaying = ref.watch(audioIsPlayingProvider);
      final isGrid = metrics.gridMorph > 0.05;

      if (!isGrid) {
        // 列表模式：支持拖拽重排与缩放
        return SliverReorderableList(
          itemCount: activePlaylist.songs.length,
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex--;
            reorderSelection(oldIndex, newIndex);
            playlistService.reorderSongsInPlaylist(
              activePlaylist.id,
              oldIndex,
              newIndex,
            );
          },
          itemBuilder: (context, index) {
            final song = activePlaylist.songs[index];
            final isCurrent = currentMusic?.path == song.path;
            final isSelected = isSongSelected(song.path);

            return Align(
              key: ValueKey('${song.path}_$index'),
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kFolderPageMaxWidth,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isPortrait ? 8 : 16,
                    vertical: 2,
                  ),
                  child: SizedBox(
                    height: metrics.animatedListExtent,
                    child: SongZoomItem(
                      song: song,
                      metrics: metrics,
                      isCurrent: isCurrent,
                      isPlaying: isPlaying && isCurrent,
                      isSelected: isSelected,
                      isSelectionMode: isSelectionMode,
                      selectedPaths: selectedSongPaths,
                      dragHandle: isSelectionMode
                          ? ReorderableDragStartListener(
                              index: index,
                              child: const MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: Icon(Icons.drag_handle_rounded),
                                ),
                              ),
                            )
                          : null,
                      onTap: () {
                        handleSongTap(
                          index: index,
                          songPath: song.path,
                          allSongs: activePlaylist.songs,
                          onNormalTap: () {
                            audio.playPlaylist(
                              activePlaylist.songs,
                              initialIndex: index,
                              source: PlaybackSource(
                                type: PlaybackSourceType.playlist,
                                id: activePlaylist.id,
                                name: activePlaylist.name,
                              ),
                            );
                          },
                        );
                      },
                      onLongPress: () {
                        lastAnchorIndex = index;
                        if (!isSelectionMode) {
                          enterSongSelectionMode(song.path);
                        }
                      },
                      onSecondaryTapDown: (details) {
                        if (!isSelectionMode) {
                          showSongContextMenu(
                            context,
                            details.globalPosition,
                            song: song,
                            songs: activePlaylist.songs,
                            onMultiSelect: () =>
                                enterSongSelectionMode(song.path),
                            onRemoveFromPlaylist: () {
                              playlistService.removeSongsFromPlaylist(
                                activePlaylist.id,
                                [index],
                              );
                            },
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }

      // 网格模式：缩放网格卡片
      final hPad = folderContentHorizontalPadding(
        isPortrait: isPortrait,
        gridMorph: metrics.gridMorph,
      );

      return SliverPadding(
        padding: EdgeInsets.only(left: hPad, right: hPad),
        sliver: SliverGrid(
          gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
          delegate: SliverChildBuilderDelegate((context, index) {
            final song = activePlaylist.songs[index];
            final isCurrent = currentMusic?.path == song.path;
            final isSelected = isSongSelected(song.path);

            return SongZoomItem(
              key: ValueKey(song.path),
              song: song,
              metrics: metrics,
              isCurrent: isCurrent,
              isPlaying: isPlaying && isCurrent,
              isSelected: isSelected,
              isSelectionMode: isSelectionMode,
              selectedPaths: selectedSongPaths,
              onTap: () {
                handleSongTap(
                  index: index,
                  songPath: song.path,
                  allSongs: activePlaylist.songs,
                  onNormalTap: () {
                    audio.playPlaylist(
                      activePlaylist.songs,
                      initialIndex: index,
                      source: PlaybackSource(
                        type: PlaybackSourceType.playlist,
                        id: activePlaylist.id,
                        name: activePlaylist.name,
                      ),
                    );
                  },
                );
              },
              onLongPress: () {
                lastAnchorIndex = index;
                if (!isSelectionMode) {
                  enterSongSelectionMode(song.path);
                }
              },
              onSecondaryTapDown: (details) {
                if (!isSelectionMode) {
                  showSongContextMenu(
                    context,
                    details.globalPosition,
                    song: song,
                    songs: activePlaylist.songs,
                    onMultiSelect: () => enterSongSelectionMode(song.path),
                    onRemoveFromPlaylist: () {
                      playlistService.removeSongsFromPlaylist(
                        activePlaylist.id,
                        [index],
                      );
                    },
                  );
                }
              },
            );
          }, childCount: activePlaylist.songs.length),
        ),
      );
    }

    final Widget scrollBody = FolderZoomGestureLayer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.min(
            constraints.maxWidth,
            kFolderPageMaxWidth,
          );
          return FolderZoomSliverBuilder(
            zoomScale: snapFolderZoomScale(zoomScale),
            width: contentWidth,
            builder: (context, metrics) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kFolderPageMaxWidth,
                  ),
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      if (!isPortrait)
                        SliverToBoxAdapter(child: SizedBox(height: barHeight)),
                      SliverToBoxAdapter(
                        child: isPortrait
                            ? AlbumPortraitHeaderBanner(
                                title: plName,
                                metadata: metadataWidget,
                                actionButtons: actionButtons,
                                coverBackground: _PlaylistCoverBackground(
                                  playlist: activePlaylist,
                                ),
                                coverWidget: PlaylistCover(
                                  playlist: activePlaylist,
                                  size: 260,
                                  enableHero: true,
                                ),
                                barHeight: barHeight,
                              )
                            : AlbumLandscapeHeaderBanner(
                                title: plName,
                                metadata: metadataWidget,
                                actionButtons: actionButtons,
                                alignActionsToBottom: true,
                                maxWidth: kFolderPageMaxWidth,
                                coverWidget: PlaylistCover(
                                  playlist: activePlaylist,
                                  size: 220,
                                  enableHero: true,
                                ),
                              ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.only(
                          bottom: MiniPlayerUiTuning.getListBottomPadding(
                            context,
                            hasPlayingMusic: currentMusic != null,
                            isSelectionMode: isSelectionMode,
                          ),
                        ),
                        sliver: buildSongSlivers(metrics),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );

    return PopScope(
      canPop: !isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          ref.read(selectedPlaylistIdProvider.notifier).set(null);
          return;
        }
        if (isSelectionMode) {
          cancelSongSelection();
        }
      },
      child: AutoHideHeaderScope(
        builder: (context, isHeaderVisible) {
          final Widget content = Scaffold(
            body: Padding(
              padding: EdgeInsets.only(left: leftPadding),
              child: Stack(
                children: [
                  scrollBody,
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AutoHideHeader(
                      isVisible: isHeaderVisible,
                      child: AppTopNavBar(
                        title: plName,
                        titleKey: ValueKey(
                          'playlist_title_${activePlaylist.id}',
                        ),
                        onBack: _handleBack,
                      ),
                    ),
                  ),
                  AnimatedSelectionPanel(
                    isVisible: isSelectionMode,
                    child: LibrarySelectionPanel(
                      key: const ValueKey('playlist-song-selection-panel'),
                      selectedSongs: selectedSongs,
                      allSongs: activePlaylist.songs,
                      onToggleSelectAll: () =>
                          toggleSelectAllSongs(activePlaylist.songs),
                      onCancel: cancelSongSelection,
                      deleteLabel: l10n.removeFromPlaylist,
                      onDelete: () async {
                        final toRemove = <int>[];
                        for (int i = 0; i < activePlaylist.songs.length; i++) {
                          if (isSongSelected(activePlaylist.songs[i].path)) {
                            toRemove.add(i);
                          }
                        }
                        if (toRemove.isNotEmpty) {
                          await playlistService.removeSongsFromPlaylist(
                            activePlaylist.id,
                            toRemove,
                          );
                          cancelSongSelection();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          );

          return MiniPlayerWrapper(child: content);
        },
      ),
    );
  }
}

class _PlaylistCoverBackground extends StatelessWidget {
  const _PlaylistCoverBackground({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    return PlaylistCover(
      playlist: playlist,
      size: double.infinity,
      width: double.infinity,
      height: double.infinity,
      borderRadius: 0,
    );
  }
}
