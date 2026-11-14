import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../dialogs/sort_options_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/library_action_bar.dart';
import '../../../player/audio/audio_riverpod.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../utils/remote_context_menu_utils.dart';
import '../../../utils/selection_utils.dart';
import '../../../widgets/draggable_remote_artist_item.dart';
import '../../../widgets/folder_layout_utils.dart';
import '../../../widgets/folder_zoom_gesture_layer.dart';
import '../../../widgets/library_master_pane_header.dart';
import '../../../widgets/library_zoom_popover.dart';
import '../../../widgets/master_detail_scaffold.dart';
import '../../../widgets/remote_artwork_widget.dart';
import '../remote_artist_detail_page.dart';
import 'remote_library_common_widgets.dart';
import 'remote_library_toolbar_widgets.dart';

List<SortOptionItem<String>> _remoteArtistSortOptions(AppLocalizations l10n) =>
    <SortOptionItem<String>>[
      SortOptionItem(
        value: 'name',
        label: l10n.sortByName,
        icon: Icons.sort_by_alpha_rounded,
      ),
      SortOptionItem(
        value: 'albumCount',
        label: l10n.sortAlbumCount,
        icon: Icons.album_rounded,
      ),
    ];

Future<void> _openRemoteArtistSortDialog({
  required BuildContext context,
  required AppLocalizations l10n,
  required String sortField,
  required bool sortAsc,
  required void Function(String field, bool asc) onSortChanged,
}) async {
  final result = await showSortOptionsDialog<String>(
    context: context,
    title: l10n.sort,
    currentField: sortField,
    sortAscending: sortAsc,
    options: _remoteArtistSortOptions(l10n),
  );
  if (result != null) {
    onSortChanged(result.field, result.sortAscending);
  }
}

class RemoteLibraryArtistsToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final FocusNode? searchFocusNode;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final bool starredOnly;
  final ValueChanged<bool> onToggleStarredOnly;
  final bool sortAsc;
  final String sortField; // 'name' or 'albumCount'
  final void Function(String field, bool asc) onSortChanged;
  final int? totalCount;

  /// 页头大标题与返回概览页（与本地艺术家页同形）。
  /// 横屏主从分栏时由 `compact` 形态把它渲染在左栏顶部。
  final String? title;
  final VoidCallback? onBack;

  /// 库级动作（定位当前播放、下载管理器），由父页统一提供。
  final List<LibraryToolbarAction> trailingActions;

  /// 播放全部 / 随机播放：播放当前列出的这些艺术家的歌。
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;

  /// 是否处于横屏主从分栏模式。
  /// 为真时搜索、收藏筛选、排序都收进左栏顶部，页头只保留标题与全局动作。
  final bool isMasterDetailWide;

  const RemoteLibraryArtistsToolbar({
    super.key,
    required this.searchController,
    this.searchFocusNode,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.starredOnly,
    required this.onToggleStarredOnly,
    required this.sortAsc,
    required this.sortField,
    required this.onSortChanged,
    this.totalCount,
    this.title,
    this.onBack,
    this.trailingActions = const <LibraryToolbarAction>[],
    this.onPlayAll,
    this.onShufflePlay,
    this.isMasterDetailWide = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final countLabel = totalCount == null
        ? null
        : (isZh ? '共 $totalCount 位艺术家' : '$totalCount ${l10n.artists}');

    return RemoteLibraryActionBar(
      title: title,
      onBack: onBack,
      trailingActions: trailingActions,
      searchController: searchController,
      searchFocusNode: searchFocusNode,
      searchQuery: searchQuery,
      searchHintText: l10n.filterArtists,
      onSearchChanged: onSearchChanged,
      onSearchCleared: onClearSearch,
      onPlayAll: onPlayAll,
      onShufflePlay: onShufflePlay,
      countLabel: countLabel,
      showSearch: !isMasterDetailWide,
      showSortActionInWide: false,
      actions: [
        if (!isMasterDetailWide) ...[
          remoteStarAction(
            active: starredOnly,
            label: l10n.starredArtists,
            onToggle: onToggleStarredOnly,
          ),
          remoteSortAction<String>(
            context: context,
            label: l10n.sort,
            currentField: sortField,
            sortAscending: sortAsc,
            options: _remoteArtistSortOptions(l10n),
            onSelected: onSortChanged,
          ),
          remoteZoomAction(
            label: l10n.listView,
            scope: LibraryZoomScope.artist,
          ),
        ],
      ],
    );
  }
}

class RemoteLibraryArtistsView extends ConsumerWidget {
  final RemoteServer server;
  final String password;
  final List<Map<String, dynamic>> artists;
  final Set<String> starredArtistIds;
  final String? selectedArtistId;
  final bool isLoading;
  final String? error;
  final Future<void> Function() onRefresh;
  final String searchQuery;
  final double bottomOffset;
  final bool isSelectionMode;
  final Set<String> selectedArtistIds;
  final int? lastArtistAnchorIndex;
  final ValueChanged<String?> onSelectArtistId;
  final void Function(Set<String> keys) onSetSelection;
  final void Function(String artistId) onToggleSelection;
  final void Function(int? index) onUpdateAnchor;
  final Widget? toolbar;

  /// 按横竖屏构建顶部页头（由 [MasterDetailScaffold] 传入 `isWide`）。
  final Widget Function(BuildContext context, bool isWide)? toolbarBuilder;

  /// 左栏搜索/收藏筛选/排序控件参数（横屏时渲染在左栏顶部）。
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onClearSearch;
  final bool starredOnly;
  final ValueChanged<bool>? onToggleStarredOnly;
  final String sortField;
  final bool sortAsc;
  final void Function(String field, bool asc)? onSortChanged;

  const RemoteLibraryArtistsView({
    super.key,
    required this.server,
    required this.password,
    required this.artists,
    required this.starredArtistIds,
    required this.selectedArtistId,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.searchQuery,
    required this.bottomOffset,
    required this.isSelectionMode,
    required this.selectedArtistIds,
    required this.lastArtistAnchorIndex,
    required this.onSelectArtistId,
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    this.toolbar,
    this.toolbarBuilder,
    this.searchController,
    this.searchFocusNode,
    this.onSearchChanged,
    this.onClearSearch,
    this.starredOnly = false,
    this.onToggleStarredOnly,
    this.sortField = 'name',
    this.sortAsc = true,
    this.onSortChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final artistZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.artistZoomScale),
    );
    final hasPlayingMusic = ref.watch(
      audioCurrentMusicProvider.select((m) => m != null),
    );

    if (isLoading) {
      return RemoteLibraryLoadingView(
        server: server,
        icon: Icons.mic_rounded,
      );
    }
    if (error != null) {
      return RemoteLibraryErrorView(
        error: l10n.errorLoadingArtists(error!),
        onRetry: onRefresh,
      );
    }

    return MasterDetailScaffold<Map<String, dynamic>>(
      items: artists,
      itemKey: (artist) => artist['id'] as String? ?? '',
      selectedKey: selectedArtistId,
      onSelectedKeyChanged: onSelectArtistId,
      routeName: 'remote_artist_detail',
      hasPlayingMusic: hasPlayingMusic,
      isSelectionMode: isSelectionMode,
      onRefresh: onRefresh,
      masterPaneHeaderBuilder: searchController != null &&
              onSearchChanged != null &&
              onClearSearch != null
          ? (headerContext) => LibraryMasterPaneHeader(
                searchController: searchController!,
                searchFocusNode: searchFocusNode,
                searchQuery: searchQuery,
                searchHintText: l10n.filterArtists,
                onSearchChanged: onSearchChanged!,
                onSearchCleared: onClearSearch!,
                extraActions: [
                  if (onToggleStarredOnly != null)
                    IconButton(
                      style: LibraryMasterPaneHeader.compactIconStyle,
                      tooltip: l10n.starredArtists,
                      onPressed: () => onToggleStarredOnly!(!starredOnly),
                      iconSize: 18,
                      color: starredOnly ? Colors.redAccent : null,
                      icon: Icon(
                        starredOnly
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                      ),
                    ),
                ],
                onSortPressed: onSortChanged != null
                    ? () => _openRemoteArtistSortDialog(
                          context: headerContext,
                          l10n: l10n,
                          sortField: sortField,
                          sortAsc: sortAsc,
                          onSortChanged: onSortChanged!,
                        )
                    : null,
              )
          : null,
      masterToolbarBuilder: (context, isWide) =>
          toolbarBuilder?.call(context, isWide) ??
          toolbar ??
          const SizedBox.shrink(),
      portraitScrollWrapper: (context, child) => FolderZoomGestureLayer(
        scope: LibraryZoomScope.artist,
        child: child,
      ),
      portraitSliverBuilder: (context, items, constraints, bottomPadding) {
        final contentWidth = math.min(
          constraints.maxWidth,
          kFolderPageMaxWidth,
        );
        final outerPad = math.max(0.0, (constraints.maxWidth - contentWidth) / 2);

        return [
          FolderZoomSliverBuilder(
            zoomScale: snapFolderZoomScale(artistZoomScale),
            width: contentWidth,
            builder: (context, metrics) {
              return SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  outerPad + kGridHorizontalPadding,
                  0,
                  outerPad + kGridHorizontalPadding,
                  bottomPadding,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final artist = items[index];
                      final artistId = artist['id'] as String? ?? '';
                      final isMultiSelected =
                          selectedArtistIds.contains(artistId);
                      final isStarred = starredArtistIds.contains(artistId);

                      return RemoteLibraryArtistZoomItem(
                        server: server,
                        password: password,
                        artist: artist,
                        index: index,
                        allArtists: items,
                        isMultiSelected: isMultiSelected,
                        isStarred: isStarred,
                        isSelectionMode: isSelectionMode,
                        selectedArtistIds: selectedArtistIds,
                        lastArtistAnchorIndex: lastArtistAnchorIndex,
                        metrics: metrics,
                        onSetSelection: onSetSelection,
                        onToggleSelection: onToggleSelection,
                        onUpdateAnchor: onUpdateAnchor,
                        onTap: () {
                          onSelectArtistId(artistId);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              settings: const RouteSettings(
                                name: 'remote_artist_detail',
                              ),
                              builder: (_) => RemoteArtistDetailPage(
                                server: server,
                                password: password,
                                artistId: artistId,
                                artistName: artist['name'] as String? ??
                                    l10n.unknownArtist,
                                coverArtId: artist['coverArt'] as String?,
                                albumCount: artist['albumCount'] as int?,
                              ),
                            ),
                          );
                        },
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              );
            },
          ),
        ];
      },
      masterItemBuilder: (context, artist, index, isSelected, isWide, onTap) {
        final artistId = artist['id'] as String? ?? '';
        return RemoteLibraryArtistItem(
          server: server,
          password: password,
          artist: artist,
          index: index,
          allArtists: artists,
          isSelected: isWide && isSelected,
          isMultiSelected: selectedArtistIds.contains(artistId),
          isStarred: starredArtistIds.contains(artistId),
          isSelectionMode: isSelectionMode,
          selectedArtistIds: selectedArtistIds,
          lastArtistAnchorIndex: lastArtistAnchorIndex,
          onSetSelection: onSetSelection,
          onToggleSelection: onToggleSelection,
          onUpdateAnchor: onUpdateAnchor,
          onTap: onTap,
        );
      },
      detailBuilder: (context, artist) => RemoteArtistDetailContent(
        key: ValueKey(artist['id']),
        server: server,
        password: password,
        artistId: artist['id'] as String? ?? '',
        artistName: artist['name'] as String? ?? l10n.unknownArtist,
        coverArtId: artist['coverArt'] as String?,
        albumCount: artist['albumCount'] as int?,
      ),
      detailPageBuilder: (context, artist) => RemoteArtistDetailPage(
        server: server,
        password: password,
        artistId: artist['id'] as String? ?? '',
        artistName: artist['name'] as String? ?? l10n.unknownArtist,
        coverArtId: artist['coverArt'] as String?,
        albumCount: artist['albumCount'] as int?,
      ),
      emptyMasterBuilder: (context) => Center(
        child: Text(
          searchQuery.isEmpty ? l10n.noArtistsFound : l10n.noMatchingArtists,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
      emptyDetailBuilder: (context) => Center(
        child: Text(l10n.noArtistSelected),
      ),
    );
  }
}

class RemoteLibraryArtistZoomItem extends ConsumerWidget {
  final RemoteServer server;
  final String password;
  final Map<String, dynamic> artist;
  final int index;
  final List<Map<String, dynamic>> allArtists;
  final bool isMultiSelected;
  final bool isStarred;
  final bool isSelectionMode;
  final Set<String> selectedArtistIds;
  final int? lastArtistAnchorIndex;
  final FolderZoomLayoutMetrics metrics;
  final void Function(Set<String> keys) onSetSelection;
  final void Function(String artistId) onToggleSelection;
  final void Function(int? index) onUpdateAnchor;
  final VoidCallback onTap;

  const RemoteLibraryArtistZoomItem({
    super.key,
    required this.server,
    required this.password,
    required this.artist,
    required this.index,
    required this.allArtists,
    required this.isMultiSelected,
    required this.isStarred,
    required this.isSelectionMode,
    required this.selectedArtistIds,
    required this.lastArtistAnchorIndex,
    required this.metrics,
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = artist['name'] as String? ?? l10n.unknownArtist;
    final albumCount = artist['albumCount'] as int? ?? 0;
    final coverArtId = artist['coverArt'] as String?;
    final artistId = artist['id'] as String? ?? '';
    final gridMorph = metrics.gridMorph;

    final avatar = LayoutBuilder(
      builder: (context, constraints) {
        final size =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 48.0;
        return ClipOval(
          child: RemoteArtworkWidget(
            server: server,
            password: password,
            coverArtId: coverArtId,
            size: 200,
            width: size,
            height: size,
            isArtist: true,
          ),
        );
      },
    );

    final cover = ZoomItemCover(
      metrics: metrics,
      isSelected: isMultiSelected,
      isSelectionMode: isSelectionMode,
      isCircle: true,
      centerCheckboxInGrid: true,
      selectionOverlayColor: Colors.black38,
      onToggleSelect: () {
        onUpdateAnchor(index);
        onToggleSelection(artistId);
      },
      child: avatar,
    );

    final titleColor = isSelectionMode && isMultiSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    final listCoverSize = getFolderListCoverSize(metrics.animatedZoomScale);
    final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
    final selectionOffset = (isSelectionMode && gridMorph < 0.5)
        ? (28.0 * (1.0 - coverProgress))
        : 0.0;

    final fallbackCheckbox = Checkbox(
      value: isMultiSelected,
      onChanged: (_) {
        onUpdateAnchor(index);
        onToggleSelection(artistId);
      },
      fillColor: WidgetStateProperty.all(Colors.white),
      checkColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    );

    final titleSuffix = isStarred
        ? const Padding(
            padding: EdgeInsets.only(left: 4.0),
            child: Icon(
              Icons.favorite_rounded,
              size: 14,
              color: Colors.redAccent,
            ),
          )
        : null;

    final subtitle = albumCount > 0 ? l10n.albumCount(albumCount) : null;

    final scaffold = ZoomItemScaffold(
      metrics: metrics,
      cover: cover,
      titleText: name,
      subtitleText: subtitle,
      titleSuffix: titleSuffix,
      gridAlignment: Alignment.topCenter,
      gridCrossAxisAlignment: CrossAxisAlignment.center,
      titleColor: titleColor,
      listTitleFontWeight:
          isMultiSelected ? FontWeight.w700 : FontWeight.w500,
      listTitleFontSize: 13.5,
      isSelected: isMultiSelected,
      isSelectionMode: isSelectionMode,
      selectionOffset: selectionOffset,
      wrapHoverableCard: false,
      fallbackLeadingWhenNoCover: isSelectionMode && gridMorph < 0.5
          ? fallbackCheckbox
          : null,
      onTap: () {
        SelectionActionHelper.handleItemTap(
          index: index,
          itemKey: artistId,
          items: allArtists,
          keySelector: (a) => a['id'] as String? ?? '',
          isSelectionMode: isSelectionMode,
          selectedKeys: selectedArtistIds,
          lastAnchorIndex: lastArtistAnchorIndex,
          onUpdateAnchor: onUpdateAnchor,
          onSetSelection: onSetSelection,
          onToggleSelection: onToggleSelection,
          onNormalTap: onTap,
        );
      },
      onLongPress: () {
        onUpdateAnchor(index);
        onToggleSelection(artistId);
      },
      onSecondaryTapDown: (details) {
        if (!isSelectionMode) {
          showRemoteArtistContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            ref: ref,
            server: server,
            password: password,
            artistId: artistId,
            artistName: name,
            isStarred: isStarred,
            onViewDetails: onTap,
            onMultiSelect: () {
              onUpdateAnchor(index);
              onToggleSelection(artistId);
            },
          );
        }
      },
    );

    return DraggableRemoteArtistItem(
      server: server,
      artist: artist,
      isSelectionMode: isSelectionMode,
      isSelected: isMultiSelected,
      selectedArtistIds: selectedArtistIds,
      child: scaffold,
    );
  }
}

class RemoteLibraryArtistItem extends ConsumerWidget {
  final RemoteServer server;
  final String password;
  final Map<String, dynamic> artist;
  final int index;
  final List<Map<String, dynamic>> allArtists;
  final bool isSelected;
  final bool isMultiSelected;
  final bool isStarred;
  final bool isSelectionMode;
  final Set<String> selectedArtistIds;
  final int? lastArtistAnchorIndex;
  final void Function(Set<String> keys) onSetSelection;
  final void Function(String artistId) onToggleSelection;
  final void Function(int? index) onUpdateAnchor;
  final VoidCallback onTap;

  const RemoteLibraryArtistItem({
    super.key,
    required this.server,
    required this.password,
    required this.artist,
    required this.index,
    required this.allArtists,
    required this.isSelected,
    required this.isMultiSelected,
    required this.isStarred,
    required this.isSelectionMode,
    required this.selectedArtistIds,
    required this.lastArtistAnchorIndex,
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = artist['name'] as String? ?? l10n.unknownArtist;
    final albumCount = artist['albumCount'] as int? ?? 0;
    final coverArtId = artist['coverArt'] as String?;
    final artistId = artist['id'] as String? ?? '';

    final isItemHighlighted =
        (isSelectionMode && isMultiSelected) || isSelected;
    final backgroundColor = isItemHighlighted
        ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.7)
        : Colors.transparent;

    final itemWidget = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) {
        if (!isSelectionMode) {
          showRemoteArtistContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            ref: ref,
            server: server,
            password: password,
            artistId: artistId,
            artistName: name,
            isStarred: isStarred,
            onViewDetails: onTap,
            onMultiSelect: isSelectionMode
                ? null
                : () {
                    onUpdateAnchor(index);
                    onToggleSelection(artistId);
                },
          );
        }
      },
      onLongPressStart: (details) {
        onUpdateAnchor(index);
        onToggleSelection(artistId);
      },
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          enableFeedback: false,
          onTap: () {
            SelectionActionHelper.handleItemTap(
              index: index,
              itemKey: artistId,
              items: allArtists,
              keySelector: (a) => a['id'] as String? ?? '',
              isSelectionMode: isSelectionMode,
              selectedKeys: selectedArtistIds,
              lastAnchorIndex: lastArtistAnchorIndex,
              onUpdateAnchor: onUpdateAnchor,
              onSetSelection: onSetSelection,
              onToggleSelection: onToggleSelection,
              onNormalTap: onTap,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                ClipOval(
                  child: RemoteArtworkWidget(
                    server: server,
                    password: password,
                    coverArtId: coverArtId,
                    size: 200,
                    width: 38,
                    height: 38,
                    isArtist: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontWeight: (isSelectionMode &&
                                            isMultiSelected) ||
                                        isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                fontSize: 13,
                                color: (isSelectionMode &&
                                            isMultiSelected) ||
                                        isSelected
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isStarred)
                            const Padding(
                              padding: EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.favorite_rounded,
                                size: 14,
                                color: Colors.redAccent,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.albumCount(albumCount),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelectionMode)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isMultiSelected,
                      onChanged: (_) {
                        onToggleSelection(artistId);
                      },
                    ),
                  )
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    tooltip: l10n.more,
                    onPressed: () {
                      final box = context.findRenderObject() as RenderBox?;
                      final pos = box != null
                          ? box.localToGlobal(
                              Offset(box.size.width / 2, box.size.height / 2))
                          : Offset.zero;
                      showRemoteArtistContextMenu(
                        context: context,
                        globalPosition: pos,
                        ref: ref,
                        server: server,
                        password: password,
                        artistId: artistId,
                        artistName: name,
                        onViewDetails: onTap,
                        onMultiSelect: isSelectionMode
                            ? null
                            : () {
                                onUpdateAnchor(index);
                                onToggleSelection(artistId);
                            },
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return DraggableRemoteArtistItem(
      server: server,
      artist: artist,
      isSelectionMode: isSelectionMode,
      isSelected: isMultiSelected,
      selectedArtistIds: selectedArtistIds,
      child: itemWidget,
    );
  }
}

typedef NavidromeArtistsToolbar = RemoteLibraryArtistsToolbar;
typedef NavidromeArtistsView = RemoteLibraryArtistsView;
typedef NavidromeArtistItem = RemoteLibraryArtistItem;

