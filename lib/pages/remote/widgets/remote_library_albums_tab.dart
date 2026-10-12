import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../player/remote/remote_library_navigation.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../utils/remote_context_menu_utils.dart';
import '../../../utils/selection_utils.dart';
import '../../../widgets/default_cover_art.dart';
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

    return Row(
      children: [
        Expanded(
          child: RemoteSearchBar(
            controller: searchController,
            focusNode: searchFocusNode,
            hintText: l10n.filterAlbums,
            searchQuery: searchQuery,
            onChanged: onSearchChanged,
            onClear: onClearSearch,
          ),
        ),
        const SizedBox(width: 8),
        RemoteDropdownButton<String>(
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
        ),
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
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final clampedScale = textScale.clamp(1.0, 1.3);
        final double textHeight = (isPortrait ? 96.0 : 116.0) * clampedScale;
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
                    child: Scrollbar(
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
    final theme = Theme.of(context);

    final itemWidget = GestureDetector(
      behavior: HitTestBehavior.opaque,
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
      onLongPressStart: (details) {
        onUpdateAnchor(index);
        onToggleSelection(albumId);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
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
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isSelectionMode && isSelected
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 1.0,
                      child: RemoteArtworkWidget(
                        server: server,
                        password: password,
                        coverArtId: coverId,
                        size: 300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    if (isSelectionMode)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : Colors.black38,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            isSelected
                                ? Icons.check
                                : Icons.circle_outlined,
                            size: 16,
                            color: isSelected
                                ? theme.colorScheme.onPrimary
                                : Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: isPortrait ? 12 : 13,
                                color: isSelectionMode && isSelected
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              artist,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: isPortrait ? 11 : 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                songCount != null
                                    ? l10n.trackCountShort(songCount!)
                                    : (year != null && year! > 0
                                        ? '$year'
                                        : ''),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: isPortrait ? 10 : 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!isSelectionMode)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                style: const ButtonStyle(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                tooltip: l10n.playAlbum,
                                onPressed: onPlayAlbumDirectly,
                                icon: Icon(
                                  Icons.play_circle_filled_rounded,
                                  size: isPortrait ? 22 : 26,
                                  color: isDesktopPlatform
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return DraggableRemoteAlbumItem(
      server: server,
      album: album,
      albumId: albumId,
      title: title,
      artist: artist,
      coverId: coverId,
      songCount: songCount,
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      selectedAlbumIds: selectedAlbumIds,
      allAlbums: filteredAlbums,
      child: itemWidget,
    );
  }
}

typedef NavidromeAlbumsToolbar = RemoteLibraryAlbumsToolbar;
typedef NavidromeAlbumsView = RemoteLibraryAlbumsView;
typedef NavidromeAlbumCard = RemoteLibraryAlbumCard;
