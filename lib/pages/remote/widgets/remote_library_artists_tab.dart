import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../player/audio/audio_riverpod.dart';
import '../../../player/remote/remote_library_navigation.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../utils/remote_context_menu_utils.dart';
import '../../../utils/selection_utils.dart';
import '../../../widgets/draggable_remote_artist_item.dart';
import '../../../widgets/folder_layout_utils.dart';
import '../../../widgets/folder_zoom_gesture_layer.dart';
import '../../../widgets/library_zoom_popover.dart';
import '../../../widgets/remote_artwork_widget.dart';
import '../remote_artist_detail_page.dart';
import 'remote_library_common_widgets.dart';
import 'remote_library_toolbar_widgets.dart';

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

  /// 给横屏左栏用的紧凑形态：搜索独占一行，计数 / 收藏 / 排序占第二行。
  /// 左栏只有 260~300 宽，横排四个控件会把搜索框挤到放不下 hint。
  final bool compact;

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
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final String currentSortKey = '${sortField}_$sortAsc';
    final String currentLabel = switch (sortField) {
      'albumCount' => l10n.albums,
      _ => 'A-Z',
    };

    final searchBar = RemoteSearchBar(
      controller: searchController,
      focusNode: searchFocusNode,
      hintText: l10n.filterArtists,
      searchQuery: searchQuery,
      onChanged: onSearchChanged,
      onClear: onClearSearch,
    );

    final starButton = RemoteStarFilterButton(
      active: starredOnly,
      tooltip: l10n.starredArtists,
      onToggle: onToggleStarredOnly,
    );

    final sortDropdown = RemoteDropdownButton<String>(
      value: currentSortKey,
      label: currentLabel,
      icon: sortAsc
          ? Icons.arrow_upward_rounded
          : Icons.arrow_downward_rounded,
      tooltip: l10n.sort,
      onSelected: (key) {
        final parts = key.split('_');
        onSortChanged(parts[0], parts[1] == 'true');
      },
      items: [
        buildRemoteMenuItem(
          value: 'name_true',
          label: 'A-Z (${l10n.sortAscending})',
          icon: Icons.sort_by_alpha_rounded,
          isSelected: sortField == 'name' && sortAsc,
          theme: theme,
        ),
        buildRemoteMenuItem(
          value: 'name_false',
          label: 'Z-A (${l10n.sortDescending})',
          icon: Icons.sort_by_alpha_rounded,
          isSelected: sortField == 'name' && !sortAsc,
          theme: theme,
        ),
        buildRemoteMenuItem(
          value: 'albumCount_false',
          label: '${l10n.albums} (${l10n.sortDescending})',
          icon: Icons.album_rounded,
          isSelected: sortField == 'albumCount' && !sortAsc,
          theme: theme,
        ),
        buildRemoteMenuItem(
          value: 'albumCount_true',
          label: '${l10n.albums} (${l10n.sortAscending})',
          icon: Icons.album_rounded,
          isSelected: sortField == 'albumCount' && sortAsc,
          theme: theme,
        ),
      ],
    );

    final countText = totalCount != null
        ? Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '共 $totalCount 位艺术家'
                : '$totalCount ${l10n.artists}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          )
        : null;

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchBar,
          const SizedBox(height: 8),
          Row(
            children: [
              if (countText != null)
                Expanded(child: countText)
              else
                const Spacer(),
              starButton,
              const SizedBox(width: 6),
              sortDropdown,
            ],
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return Row(
            children: [
              ?countText,
              const Spacer(),
              SizedBox(
                width: 200,
                child: searchBar,
              ),
              const SizedBox(width: 8),
              starButton,
              const SizedBox(width: 8),
              sortDropdown,
              const SizedBox(width: 4),
              const LibraryZoomButton(scope: LibraryZoomScope.artist),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: searchBar),
            const SizedBox(width: 8),
            starButton,
            const SizedBox(width: 8),
            sortDropdown,
            const SizedBox(width: 4),
            const LibraryZoomButton(scope: LibraryZoomScope.artist),
          ],
        );
      },
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

  /// 横屏左栏专用的工具条（通常传 [RemoteLibraryArtistsToolbar] 的 compact 形态）。
  ///
  /// 横屏时工具条收进左栏内部，「左边搜艺术家、右边搜这位艺术家的内容」
  /// 才和流派栏目一致；不传则回落到 [toolbar]。
  final Widget? landscapeToolbar;

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
    this.landscapeToolbar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final artistZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.artistZoomScale),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth >= 750;

        final selectedArtist = artists
                .where((a) => a['id'] == selectedArtistId)
                .firstOrNull ??
            (artists.isNotEmpty ? artists.first : const <String, dynamic>{});

        if (isLandscape && artists.isNotEmpty) {
          return _LandscapeArtistsSplitView(
            server: server,
            password: password,
            artists: artists,
            starredArtistIds: starredArtistIds,
            selectedArtist: selectedArtist,
            onRefresh: onRefresh,
            bottomOffset: bottomOffset,
            isSelectionMode: isSelectionMode,
            selectedArtistIds: selectedArtistIds,
            lastArtistAnchorIndex: lastArtistAnchorIndex,
            onSelectArtistId: onSelectArtistId,
            onSetSelection: onSetSelection,
            onToggleSelection: onToggleSelection,
            onUpdateAnchor: onUpdateAnchor,
            toolbar: landscapeToolbar ?? toolbar,
            maxWidth: constraints.maxWidth,
          );
        }

        // Portrait: Zoomable List / Grid of Artist Cards
        final toolbarSliver = toolbar != null
            ? SliverRemoteContentConstraint(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: toolbar!,
              )
            : null;

        final isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final contentWidth = math.min(
          constraints.maxWidth,
          kFolderPageMaxWidth,
        );

        return FolderZoomGestureLayer(
          scope: LibraryZoomScope.artist,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: artists.isEmpty
                  ? Column(
                      children: [
                        if (toolbar != null)
                          RemoteContentConstraint(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            child: toolbar!,
                          ),
                        Expanded(
                          child: Center(
                            child: Text(
                              searchQuery.isEmpty
                                  ? l10n.noArtistsFound
                                  : l10n.noMatchingArtists,
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
                          ?toolbarSliver,
                          FolderZoomSliverBuilder(
                            zoomScale: snapFolderZoomScale(artistZoomScale),
                            width: contentWidth,
                            builder: (context, metrics) {
                              final hPad = folderContentHorizontalPadding(
                                isPortrait: isPortrait,
                                gridMorph: metrics.gridMorph,
                              );

                              return SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  hPad,
                                  0,
                                  hPad,
                                  bottomOffset,
                                ),
                                sliver: SliverGrid(
                                  gridDelegate:
                                      SliverAnimatedZoomGridDelegate(
                                    metrics: metrics,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final artist = artists[index];
                                      final artistId =
                                          artist['id'] as String? ?? '';
                                      final isMultiSelected = selectedArtistIds
                                          .contains(artistId);
                                      final isStarred = starredArtistIds
                                          .contains(artistId);

                                      return RemoteLibraryArtistZoomItem(
                                        server: server,
                                        password: password,
                                        artist: artist,
                                        index: index,
                                        allArtists: artists,
                                        isMultiSelected: isMultiSelected,
                                        isStarred: isStarred,
                                        isSelectionMode: isSelectionMode,
                                        selectedArtistIds: selectedArtistIds,
                                        lastArtistAnchorIndex:
                                            lastArtistAnchorIndex,
                                        metrics: metrics,
                                        onSetSelection: onSetSelection,
                                        onToggleSelection: onToggleSelection,
                                        onUpdateAnchor: onUpdateAnchor,
                                        onTap: () {
                                          RemoteLibraryNavUtils.openArtist(
                                            context,
                                            ref,
                                            server: server,
                                            password: password,
                                            artistId: artistId,
                                            artistName: artist['name'] as String? ??
                                                l10n.unknownArtist,
                                            coverArtId: artist['coverArt'] as String?,
                                            albumCount: artist['albumCount'] as int?,
                                          );
                                        },
                                      );
                                    },
                                    childCount: artists.length,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
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

class _LandscapeArtistsSplitView extends StatefulWidget {
  final RemoteServer server;
  final String password;
  final List<Map<String, dynamic>> artists;
  final Set<String> starredArtistIds;
  final Map<String, dynamic> selectedArtist;
  final Future<void> Function() onRefresh;
  final double bottomOffset;
  final bool isSelectionMode;
  final Set<String> selectedArtistIds;
  final int? lastArtistAnchorIndex;
  final ValueChanged<String?> onSelectArtistId;
  final void Function(Set<String> keys) onSetSelection;
  final void Function(String artistId) onToggleSelection;
  final void Function(int? index) onUpdateAnchor;
  final Widget? toolbar;
  final double maxWidth;

  const _LandscapeArtistsSplitView({
    required this.server,
    required this.password,
    required this.artists,
    required this.starredArtistIds,
    required this.selectedArtist,
    required this.onRefresh,
    required this.bottomOffset,
    required this.isSelectionMode,
    required this.selectedArtistIds,
    required this.lastArtistAnchorIndex,
    required this.onSelectArtistId,
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    this.toolbar,
    required this.maxWidth,
  });

  @override
  State<_LandscapeArtistsSplitView> createState() =>
      _LandscapeArtistsSplitViewState();
}

class _LandscapeArtistsSplitViewState
    extends State<_LandscapeArtistsSplitView> {
  late final ScrollController _leftScrollController;
  late final ScrollController _rightScrollController;

  @override
  void initState() {
    super.initState();
    _leftScrollController = ScrollController();
    _rightScrollController = ScrollController();
  }

  @override
  void dispose() {
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final selectedArtist = widget.selectedArtist;

    return NotificationListener<ScrollNotification>(
      onNotification: (_) => true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left: Artist Master List，工具条收进这一栏内部
          SizedBox(
            width: widget.maxWidth >= 1100 ? 300 : 260,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  if (widget.toolbar != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                      child: widget.toolbar!,
                    ),
                  Expanded(
                    child: PrimaryScrollController.none(
                      child: RefreshIndicator(
                        onRefresh: widget.onRefresh,
                        child: Scrollbar(
                          controller: _leftScrollController,
                          child: ListView.builder(
                            controller: _leftScrollController,
                            primary: false,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              12,
                              6,
                              12,
                              widget.bottomOffset,
                            ),
                            itemCount: widget.artists.length,
                            itemBuilder: (context, index) {
                              final artist = widget.artists[index];
                              final isSelected =
                                  artist['id'] == selectedArtist['id'];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2.0),
                                child: RemoteLibraryArtistItem(
                                  server: widget.server,
                                  password: widget.password,
                                  artist: artist,
                                  index: index,
                                  allArtists: widget.artists,
                                  isSelected: isSelected,
                                  isMultiSelected: widget.selectedArtistIds
                                      .contains(artist['id'] as String? ?? ''),
                                  isStarred: widget.starredArtistIds
                                      .contains(artist['id'] as String? ?? ''),
                                  isSelectionMode: widget.isSelectionMode,
                                  selectedArtistIds: widget.selectedArtistIds,
                                  lastArtistAnchorIndex:
                                      widget.lastArtistAnchorIndex,
                                  onSetSelection: widget.onSetSelection,
                                  onToggleSelection: widget.onToggleSelection,
                                  onUpdateAnchor: widget.onUpdateAnchor,
                                  onTap: () {
                                    final id = artist['id'] as String?;
                                    widget.onSelectArtistId(id);
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Right: Artist Detail View
          Expanded(
            child: PrimaryScrollController.none(
              child: selectedArtist.isNotEmpty
                  ? RemoteArtistDetailContent(
                      key: ValueKey(selectedArtist['id']),
                      server: widget.server,
                      password: widget.password,
                      artistId: selectedArtist['id'] as String? ?? '',
                      artistName: selectedArtist['name'] as String? ??
                          l10n.unknownArtist,
                      coverArtId: selectedArtist['coverArt'] as String?,
                      albumCount: selectedArtist['albumCount'] as int?,
                      scrollController: _rightScrollController,
                    )
                  : Center(child: Text(l10n.noArtistSelected)),
            ),
          ),
        ],
      ),
    );
  }
}

typedef NavidromeArtistsToolbar = RemoteLibraryArtistsToolbar;
typedef NavidromeArtistsView = RemoteLibraryArtistsView;
typedef NavidromeArtistItem = RemoteLibraryArtistItem;

