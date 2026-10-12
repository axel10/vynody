import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../player/remote/remote_library_navigation.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../utils/remote_context_menu_utils.dart';
import '../../../utils/selection_utils.dart';
import '../../../widgets/draggable_remote_artist_item.dart';
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

    return Row(
      children: [
        Expanded(
          child: RemoteSearchBar(
            controller: searchController,
            focusNode: searchFocusNode,
            hintText: l10n.filterArtists,
            searchQuery: searchQuery,
            onChanged: onSearchChanged,
            onClear: onClearSearch,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          style: IconButton.styleFrom(
            backgroundColor: starredOnly
                ? Colors.redAccent.withValues(alpha: 0.15)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
            minimumSize: const Size(32, 32),
            fixedSize: const Size(32, 32),
            padding: EdgeInsets.zero,
          ),
          icon: Icon(
            starredOnly
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            size: 16,
            color: starredOnly
                ? Colors.redAccent
                : theme.colorScheme.onSurfaceVariant,
          ),
          tooltip: l10n.starredArtists,
          onPressed: () => onToggleStarredOnly(!starredOnly),
        ),
        const SizedBox(width: 8),
        RemoteDropdownButton<String>(
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
        ),
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
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
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
            toolbar: toolbar,
            maxWidth: constraints.maxWidth,
          );
        }

        // Portrait: Vertical List of Artist Cards
        final toolbarSliver = toolbar != null
            ? SliverRemoteContentConstraint(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: toolbar!,
              )
            : null;

        return artists.isEmpty
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
                child: Scrollbar(
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      ?toolbarSliver,
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomOffset),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final artist = artists[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2.0),
                                child: RemoteLibraryArtistItem(
                                  server: server,
                                  password: password,
                                  artist: artist,
                                  index: index,
                                  allArtists: artists,
                                  isSelected: false,
                                  isMultiSelected: selectedArtistIds
                                      .contains(artist['id'] as String? ?? ''),
                                  isStarred: starredArtistIds
                                      .contains(artist['id'] as String? ?? ''),
                                  isSelectionMode: isSelectionMode,
                                  selectedArtistIds: selectedArtistIds,
                                  lastArtistAnchorIndex: lastArtistAnchorIndex,
                                  onSetSelection: onSetSelection,
                                  onToggleSelection: onToggleSelection,
                                  onUpdateAnchor: onUpdateAnchor,
                                  onTap: () {
                                    RemoteLibraryNavUtils.openArtist(
                                      context,
                                      ref,
                                      server: server,
                                      password: password,
                                      artistId: artist['id'] as String? ?? '',
                                      artistName: artist['name'] as String? ??
                                          l10n.unknownArtist,
                                      coverArtId: artist['coverArt'] as String?,
                                      albumCount: artist['albumCount'] as int?,
                                    );
                                  },
                                ),
                              );
                            },
                            childCount: artists.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
      },
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
                    size: 38,
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
      allArtists: allArtists,
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
      child: Column(
        children: [
          if (widget.toolbar != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: widget.toolbar!,
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: Artist Master List
                SizedBox(
                  width: widget.maxWidth >= 1100 ? 300 : 260,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                    ),
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
          ),
        ],
      ),
    );
  }
}

typedef NavidromeArtistsToolbar = RemoteLibraryArtistsToolbar;
typedef NavidromeArtistsView = RemoteLibraryArtistsView;
typedef NavidromeArtistItem = RemoteLibraryArtistItem;

