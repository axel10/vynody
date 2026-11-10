import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/library_action_bar.dart';
import '../../../player/audio/audio_riverpod.dart';
import '../../../player/remote/remote_library_navigation.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../utils/remote_context_menu_utils.dart';
import '../../../utils/selection_utils.dart';
import '../../../widgets/draggable_remote_album_item.dart';
import '../../../widgets/folder_layout_utils.dart';
import '../../../widgets/folder_zoom_gesture_layer.dart';
import '../../../widgets/hoverable_card.dart';
import '../../../widgets/library_zoom_popover.dart';
import '../../../widgets/remote_artwork_widget.dart';
import 'remote_library_common_widgets.dart';
import 'remote_library_toolbar_widgets.dart';

class RemoteLibraryAlbumsToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final FocusNode? searchFocusNode;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final String sortType;
  final ValueChanged<String> onSortTypeChanged;
  final bool starredOnly;
  final ValueChanged<bool> onToggleStarredOnly;
  final bool isJellyfin;
  final int? totalCount;

  /// 页头大标题与返回概览页（与本地专辑页同形）。
  final String? title;
  final VoidCallback? onBack;

  /// 库级动作（定位当前播放、下载管理器），由父页统一提供。
  final List<LibraryToolbarAction> trailingActions;

  /// 播放全部 / 随机播放：播放当前列出的这些专辑里的歌。
  /// 开着「只看收藏」时列表本身就只剩收藏专辑，因此无需另行判断。
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;

  const RemoteLibraryAlbumsToolbar({
    super.key,
    required this.searchController,
    this.searchFocusNode,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.sortType,
    required this.onSortTypeChanged,
    required this.starredOnly,
    required this.onToggleStarredOnly,
    this.isJellyfin = false,
    this.totalCount,
    this.title,
    this.onBack,
    this.trailingActions = const <LibraryToolbarAction>[],
    this.onPlayAll,
    this.onShufflePlay,
  });

  String _getSortLabel(AppLocalizations l10n) {
    switch (sortType) {
      case 'newest':
        return l10n.sortRecentAdded;
      case 'recent':
        return l10n.sortRecentlyPlayed;
      case 'frequent':
        return l10n.sortMostPlayed;
      case 'random':
        return l10n.sortRandom;
      case 'alphabeticalByName':
      default:
        return l10n.sortAllAZ;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final currentLabel = _getSortLabel(l10n);

    final sortOptions = <RemoteSortOption>[
      RemoteSortOption(
        value: 'alphabeticalByName',
        label: l10n.sortAllAZ,
        icon: Icons.sort_by_alpha_rounded,
        selected: sortType == 'alphabeticalByName',
      ),
      RemoteSortOption(
        value: 'newest',
        label: l10n.sortRecentAdded,
        icon: Icons.access_time_rounded,
        selected: sortType == 'newest',
      ),
      if (!isJellyfin) ...[
        RemoteSortOption(
          value: 'recent',
          label: l10n.sortRecentlyPlayed,
          icon: Icons.history_rounded,
          selected: sortType == 'recent',
        ),
        RemoteSortOption(
          value: 'frequent',
          label: l10n.sortMostPlayed,
          icon: Icons.local_fire_department_rounded,
          selected: sortType == 'frequent',
        ),
      ],
      RemoteSortOption(
        value: 'random',
        label: l10n.sortRandom,
        icon: Icons.shuffle_rounded,
        selected: sortType == 'random',
      ),
    ];

    return RemoteLibraryActionBar(
      title: title,
      onBack: onBack,
      trailingActions: trailingActions,
      searchController: searchController,
      searchFocusNode: searchFocusNode,
      searchQuery: searchQuery,
      searchHintText: l10n.filterAlbums,
      onSearchChanged: onSearchChanged,
      onSearchCleared: onClearSearch,
      onPlayAll: onPlayAll,
      onShufflePlay: onShufflePlay,
      countLabel: totalCount == null
          ? null
          : (isZh ? '共 $totalCount 张专辑' : l10n.albumCount(totalCount!)),
      actions: [
        remoteStarAction(
          active: starredOnly,
          label: l10n.starredAlbums,
          onToggle: onToggleStarredOnly,
        ),
        remoteSortAction(
          label: '${l10n.sort} · $currentLabel',
          options: sortOptions,
          onSelected: onSortTypeChanged,
        ),
        remoteZoomAction(label: l10n.listView, scope: LibraryZoomScope.album),
      ],
    );
  }
}

class RemoteLibraryAlbumsView extends ConsumerWidget {
  final RemoteServer server;
  final String password;
  final List<Map<String, dynamic>> albums;
  final bool isLoading;
  final String? error;
  final Future<void> Function() onRefresh;
  final String searchQuery;
  final double bottomOffset;
  final bool isSelectionMode;
  final Set<String> selectedAlbumIds;
  final int? lastAlbumAnchorIndex;
  final void Function(Set<String> keys) onSetSelection;
  final void Function(String albumId) onToggleSelection;
  final void Function(int? index) onUpdateAnchor;
  final void Function(String albumId, String title) onPlayAlbumDirectly;
  final Widget? toolbar;

  const RemoteLibraryAlbumsView({
    super.key,
    required this.server,
    required this.password,
    required this.albums,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.searchQuery,
    required this.bottomOffset,
    required this.isSelectionMode,
    required this.selectedAlbumIds,
    required this.lastAlbumAnchorIndex,
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    required this.onPlayAlbumDirectly,
    this.toolbar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (isLoading && albums.isEmpty) {
      return RemoteLibraryLoadingView(
        server: server,
        icon: Icons.album_rounded,
      );
    }
    if (error != null && albums.isEmpty) {
      return RemoteLibraryErrorView(
        error: l10n.errorLoadingAlbums(error!),
        onRetry: onRefresh,
      );
    }

    final albumZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.albumZoomScale),
    );

    return FolderZoomGestureLayer(
      scope: LibraryZoomScope.album,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isPortrait =
              MediaQuery.orientationOf(context) == Orientation.portrait;
          final contentWidth = math.min(
            constraints.maxWidth,
            kFolderPageMaxWidth,
          );

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: albums.isEmpty
                  ? Column(
                      children: [
                        if (toolbar != null)
                          RemotePageHeaderSlot(child: toolbar!),
                        Expanded(
                          child: Center(
                            child: Text(
                              searchQuery.isEmpty
                                  ? l10n.noAlbumsOnServer
                                  : l10n.noMatchingAlbums,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : RefreshIndicator(
                      onRefresh: onRefresh,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (toolbar != null)
                            SliverRemotePageHeaderSlot(child: toolbar!),
                          FolderZoomSliverBuilder(
                            zoomScale: snapFolderZoomScale(albumZoomScale),
                            width: contentWidth,
                            builder: (context, metrics) {
                              return SliverPadding(
                                // 与顶部动作行同源、且不随档位变化。
                                padding: EdgeInsets.fromLTRB(
                                  kGridHorizontalPadding,
                                  0,
                                  kGridHorizontalPadding,
                                  bottomOffset,
                                ),
                                sliver: SliverGrid(
                                  gridDelegate:
                                      SliverAnimatedZoomGridDelegate(
                                    metrics: metrics,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final album = albums[index];
                                      final albumId =
                                          album['id'] as String? ?? '';
                                      final isSelected =
                                          selectedAlbumIds.contains(albumId);
                                      final title = album['title'] as String? ??
                                          album['name'] as String? ??
                                          l10n.unknownAlbum;
                                      final artist =
                                          album['artist'] as String? ??
                                              l10n.unknownArtist;
                                      final coverId =
                                          album['coverArt'] as String?;
                                      final songCount =
                                          album['songCount'] as int?;
                                      final year = album['year'] as int?;

                                      return RemoteLibraryAlbumCard(
                                        server: server,
                                        password: password,
                                        album: album,
                                        albumId: albumId,
                                        title: title,
                                        artist: artist,
                                        coverId: coverId,
                                        songCount: songCount,
                                        year: year,
                                        index: index,
                                        isSelected: isSelected,
                                        isSelectionMode: isSelectionMode,
                                        filteredAlbums: albums,
                                        selectedAlbumIds: selectedAlbumIds,
                                        lastAlbumAnchorIndex:
                                            lastAlbumAnchorIndex,
                                        isPortrait: isPortrait,
                                        metrics: metrics,
                                        onSetSelection: onSetSelection,
                                        onToggleSelection: onToggleSelection,
                                        onUpdateAnchor: onUpdateAnchor,
                                        onPlayAlbumDirectly: () =>
                                            onPlayAlbumDirectly(albumId, title),
                                      );
                                    },
                                    childCount: albums.length,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class RemoteLibraryAlbumCard extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final Map<String, dynamic> album;
  final String albumId;
  final String title;
  final String artist;
  final String? coverId;
  final int? songCount;
  final int? year;
  final int index;
  final bool isSelected;
  final bool isSelectionMode;
  final List<Map<String, dynamic>> filteredAlbums;
  final Set<String> selectedAlbumIds;
  final int? lastAlbumAnchorIndex;
  final bool isPortrait;
  final FolderZoomLayoutMetrics metrics;
  final void Function(Set<String> keys) onSetSelection;
  final void Function(String albumId) onToggleSelection;
  final void Function(int? index) onUpdateAnchor;
  final VoidCallback onPlayAlbumDirectly;

  const RemoteLibraryAlbumCard({
    super.key,
    required this.server,
    required this.password,
    required this.album,
    required this.albumId,
    required this.title,
    required this.artist,
    required this.coverId,
    required this.songCount,
    required this.year,
    required this.index,
    required this.isSelected,
    required this.isSelectionMode,
    required this.filteredAlbums,
    required this.selectedAlbumIds,
    required this.lastAlbumAnchorIndex,
    required this.isPortrait,
    required this.metrics,
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    required this.onPlayAlbumDirectly,
  });

  @override
  ConsumerState<RemoteLibraryAlbumCard> createState() =>
      _RemoteLibraryAlbumCardState();
}

class _RemoteLibraryAlbumCardState
    extends ConsumerState<RemoteLibraryAlbumCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final metrics = widget.metrics;
    final gridMorph = metrics.gridMorph;
    final isGridTarget = metrics.isGridTarget;

    final extraInfo = widget.songCount != null
        ? l10n.trackCountShort(widget.songCount!)
        : (widget.year != null && widget.year! > 0 ? '${widget.year}' : '');
    final subtitle = extraInfo.isNotEmpty
        ? '${widget.artist} · $extraInfo'
        : widget.artist;

    final coverRadiusValue = lerpDouble(8.0, 12.0, gridMorph)!;
    final coverRadius = BorderRadius.circular(coverRadiusValue);

    final coverWidget = RemoteArtworkWidget(
      server: widget.server,
      password: widget.password,
      coverArtId: widget.coverId,
      size: 300,
      borderRadius: coverRadius,
    );

    final coverStack = ZoomItemCover(
      metrics: metrics,
      isSelected: widget.isSelected,
      isSelectionMode: widget.isSelectionMode,
      onToggleSelect: () => widget.onToggleSelection(widget.albumId),
      onPlay: widget.onPlayAlbumDirectly,
      child: coverWidget,
    );

    final titleColor = widget.isSelectionMode && widget.isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    final listCoverSize = getFolderListCoverSize(metrics.animatedZoomScale);
    final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
    final selectionOffset = (widget.isSelectionMode && gridMorph < 0.5)
        ? (28.0 * (1.0 - coverProgress))
        : 0.0;

    final scaffold = ZoomItemScaffold(
      metrics: metrics,
      cover: coverStack,
      titleText: widget.title,
      subtitleText: subtitle,
      titleColor: titleColor,
      listTitleFontWeight: FontWeight.normal,
      isSelected: widget.isSelected,
      isSelectionMode: widget.isSelectionMode,
      selectionOffset: selectionOffset,
      wrapHoverableCard: false,
      onTap: () {
        SelectionActionHelper.handleItemTap(
          index: widget.index,
          itemKey: widget.albumId,
          items: widget.filteredAlbums,
          keySelector: (a) => a['id'] as String? ?? '',
          isSelectionMode: widget.isSelectionMode,
          selectedKeys: widget.selectedAlbumIds,
          lastAnchorIndex: widget.lastAlbumAnchorIndex,
          onUpdateAnchor: widget.onUpdateAnchor,
          onSetSelection: widget.onSetSelection,
          onToggleSelection: widget.onToggleSelection,
          onNormalTap: () {
            RemoteLibraryNavUtils.openAlbum(
              context,
              ref,
              server: widget.server,
              password: widget.password,
              albumId: widget.albumId,
              albumName: widget.title,
              artistName: widget.artist,
              coverArtId: widget.coverId,
            );
          },
        );
      },
      onLongPress: () {
        widget.onUpdateAnchor(widget.index);
        widget.onToggleSelection(widget.albumId);
      },
      onSecondaryTapDown: (details) {
        if (!widget.isSelectionMode) {
          showRemoteAlbumContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            ref: ref,
            server: widget.server,
            password: widget.password,
            albumId: widget.albumId,
            albumTitle: widget.title,
            artistName: widget.artist,
            coverArtId: widget.coverId,
            onViewDetails: () {
              RemoteLibraryNavUtils.openAlbum(
                context,
                ref,
                server: widget.server,
                password: widget.password,
                albumId: widget.albumId,
                albumName: widget.title,
                artistName: widget.artist,
                coverArtId: widget.coverId,
              );
            },
            onMultiSelect: widget.isSelectionMode
                ? null
                : () {
                    widget.onUpdateAnchor(widget.index);
                    widget.onToggleSelection(widget.albumId);
                  },
          );
        }
      },
      fallbackLeadingWhenNoCover: widget.isSelectionMode && gridMorph < 0.5
          ? Checkbox(
              value: widget.isSelected,
              onChanged: (_) => widget.onToggleSelection(widget.albumId),
              fillColor: WidgetStateProperty.all(Colors.white),
              checkColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            )
          : null,
    );

    final cardContent = MouseRegion(
      onEnter: (_) {
        if (isGridTarget && !_isHovered) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (_isHovered) setState(() => _isHovered = false);
      },
      cursor: SystemMouseCursors.click,
      child: isGridTarget ? HoverableCard(child: scaffold) : scaffold,
    );

    return DraggableRemoteAlbumItem(
      server: widget.server,
      albumId: widget.albumId,
      title: widget.title,
      artist: widget.artist,
      songCount: widget.songCount,
      isSelectionMode: widget.isSelectionMode,
      isSelected: widget.isSelected,
      selectedAlbumIds: widget.selectedAlbumIds,
      child: cardContent,
    );
  }
}

typedef NavidromeAlbumsToolbar = RemoteLibraryAlbumsToolbar;
typedef NavidromeAlbumsView = RemoteLibraryAlbumsView;
typedef NavidromeAlbumCard = RemoteLibraryAlbumCard;
