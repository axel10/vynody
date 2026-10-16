import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../player/remote/remote_library_navigation.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../utils/remote_context_menu_utils.dart';
import '../../../utils/selection_utils.dart';
import '../../../widgets/album_grid_card.dart';
import '../../../widgets/draggable_remote_album_item.dart';
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
  final bool isJellyfin;
  final int? totalCount;

  const RemoteLibraryAlbumsToolbar({
    super.key,
    required this.searchController,
    this.searchFocusNode,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.sortType,
    required this.onSortTypeChanged,
    this.isJellyfin = false,
    this.totalCount,
  });

  String _getSortLabel(AppLocalizations l10n) {
    switch (sortType) {
      case 'newest':
        return l10n.sortRecentAdded;
      case 'recent':
        return l10n.sortRecentlyPlayed;
      case 'frequent':
        return l10n.sortMostPlayed;
      case 'starred':
        return l10n.sortStarred;
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
    final theme = Theme.of(context);
    final currentLabel = _getSortLabel(l10n);

    final searchBar = RemoteSearchBar(
      controller: searchController,
      focusNode: searchFocusNode,
      hintText: l10n.filterAlbums,
      searchQuery: searchQuery,
      onChanged: onSearchChanged,
      onClear: onClearSearch,
    );

    final sortDropdown = RemoteDropdownButton<String>(
      value: sortType,
      label: currentLabel,
      icon: Icons.sort_rounded,
      tooltip: l10n.sort,
      onSelected: onSortTypeChanged,
      items: [
        buildRemoteMenuItem(
          value: 'alphabeticalByName',
          label: l10n.sortAllAZ,
          icon: Icons.sort_by_alpha_rounded,
          isSelected: sortType == 'alphabeticalByName',
          theme: theme,
        ),
        buildRemoteMenuItem(
          value: 'newest',
          label: l10n.sortRecentAdded,
          icon: Icons.access_time_rounded,
          isSelected: sortType == 'newest',
          theme: theme,
        ),
        if (!isJellyfin) ...[
          buildRemoteMenuItem(
            value: 'recent',
            label: l10n.sortRecentlyPlayed,
            icon: Icons.history_rounded,
            isSelected: sortType == 'recent',
            theme: theme,
          ),
          buildRemoteMenuItem(
            value: 'frequent',
            label: l10n.sortMostPlayed,
            icon: Icons.local_fire_department_rounded,
            isSelected: sortType == 'frequent',
            theme: theme,
          ),
        ],
        buildRemoteMenuItem(
          value: 'starred',
          label: l10n.sortStarred,
          icon: Icons.favorite_rounded,
          isSelected: sortType == 'starred',
          theme: theme,
        ),
        buildRemoteMenuItem(
          value: 'random',
          label: l10n.sortRandom,
          icon: Icons.shuffle_rounded,
          isSelected: sortType == 'random',
          theme: theme,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          final isZh = Localizations.localeOf(context).languageCode == 'zh';
          final countText = totalCount != null
              ? Text(
                  isZh ? '共 $totalCount 张专辑' : l10n.albumCount(totalCount!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                )
              : null;

          return Row(
            children: [
              ?countText,
              const Spacer(),
              SizedBox(
                width: 200,
                child: searchBar,
              ),
              const SizedBox(width: 8),
              sortDropdown,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: searchBar),
            const SizedBox(width: 8),
            sortDropdown,
          ],
        );
      },
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = switch (constraints.maxWidth) {
          >= 1350 => 6,
          >= 1100 => 5,
          >= 850 => 4,
          >= 650 => 3,
          _ => 2,
        };

        final isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final double textHeight =
            calculateAlbumGridTextHeight(context, isPortrait: isPortrait);
        final itemWidth =
            (constraints.maxWidth - 32 - (crossAxisCount - 1) * 16) /
                crossAxisCount;
        final childAspectRatio = itemWidth / (itemWidth + textHeight);

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1600),
            child: albums.isEmpty
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
                            SliverRemoteContentConstraint(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              child: toolbar!,
                            ),
                          SliverPadding(
                            padding:
                                EdgeInsets.fromLTRB(16, 0, 16, bottomOffset),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio: childAspectRatio,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                          final album = albums[index];
                          final albumId = album['id'] as String? ?? '';
                          final isSelected = selectedAlbumIds.contains(albumId);
                          final title = album['title'] as String? ??
                              album['name'] as String? ??
                              l10n.unknownAlbum;
                          final artist = album['artist'] as String? ??
                              l10n.unknownArtist;
                          final coverId = album['coverArt'] as String?;
                          final songCount = album['songCount'] as int?;
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
                            lastAlbumAnchorIndex: lastAlbumAnchorIndex,
                            isPortrait: isPortrait,
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
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class RemoteLibraryAlbumCard extends ConsumerWidget {
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
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    required this.onPlayAlbumDirectly,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    final extraInfo = songCount != null
        ? l10n.trackCountShort(songCount!)
        : (year != null && year! > 0 ? '$year' : '');
    final subtitle = extraInfo.isNotEmpty ? '$artist · $extraInfo' : artist;

    final card = AlbumGridCard(
      cover: RemoteArtworkWidget(
        server: server,
        password: password,
        coverArtId: coverId,
        size: 300,
        borderRadius: BorderRadius.zero,
      ),
      title: title,
      subtitle: subtitle,
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      onTap: () {
        SelectionActionHelper.handleItemTap(
          index: index,
          itemKey: albumId,
          items: filteredAlbums,
          keySelector: (a) => a['id'] as String? ?? '',
          isSelectionMode: isSelectionMode,
          selectedKeys: selectedAlbumIds,
          lastAnchorIndex: lastAlbumAnchorIndex,
          onUpdateAnchor: onUpdateAnchor,
          onSetSelection: onSetSelection,
          onToggleSelection: onToggleSelection,
          onNormalTap: () {
            RemoteLibraryNavUtils.openAlbum(
              context,
              ref,
              server: server,
              password: password,
              albumId: albumId,
              albumName: title,
              artistName: artist,
              coverArtId: coverId,
            );
          },
        );
      },
      onToggleSelect: () => onToggleSelection(albumId),
      onLongPress: () {
        onUpdateAnchor(index);
        onToggleSelection(albumId);
      },
      onSecondaryTapDown: (details) {
        if (!isSelectionMode) {
          showRemoteAlbumContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            ref: ref,
            server: server,
            password: password,
            albumId: albumId,
            albumTitle: title,
            artistName: artist,
            coverArtId: coverId,
            onViewDetails: () {
              RemoteLibraryNavUtils.openAlbum(
                context,
                ref,
                server: server,
                password: password,
                albumId: albumId,
                albumName: title,
                artistName: artist,
                coverArtId: coverId,
              );
            },
          );
        }
      },
      onPlay: onPlayAlbumDirectly,
    );

    return DraggableRemoteAlbumItem(
      server: server,
      albumId: albumId,
      title: title,
      artist: artist,
      songCount: songCount,
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      selectedAlbumIds: selectedAlbumIds,
      child: card,
    );
  }
}

typedef NavidromeAlbumsToolbar = RemoteLibraryAlbumsToolbar;
typedef NavidromeAlbumsView = RemoteLibraryAlbumsView;
typedef NavidromeAlbumCard = RemoteLibraryAlbumCard;
