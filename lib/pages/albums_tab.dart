import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/album_summary.dart';
import '../player/album_library.dart';
import '../player/audio_riverpod.dart';
import '../utils/song_context_menu_utils.dart';
import '../widgets/song_thumbnail.dart';
import 'album_detail_page.dart';

enum _AlbumSortField { artist, title, trackCount, duration, recentAdded }

class AlbumsTab extends ConsumerStatefulWidget {
  const AlbumsTab({super.key});

  @override
  ConsumerState<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends ConsumerState<AlbumsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _AlbumSortField _sortField = _AlbumSortField.artist;
  bool _sortAscending = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(albumLibraryProvider);
    final l10n = AppLocalizations.of(context)!;
    final visibleAlbums = _filterAndSortAlbums(albums);

    if (albums.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.album_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(l10n.noAlbums, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;
        final crossAxisCount = switch (constraints.maxWidth) {
          >= 1200 => 5,
          >= 900 => 4,
          >= 700 => 3,
          _ => 2,
        };

        return Column(
          children: [
            _AlbumsToolbar(
              searchController: _searchController,
              searchQuery: _searchQuery,
              sortField: _sortField,
              sortAscending: _sortAscending,
              albumCount: visibleAlbums.length,
              isWide: isWide,
              onSearchChanged: (value) {
                setState(() {
                  _searchQuery = value.trim();
                });
              },
              onSearchCleared: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                });
              },
              onSortFieldSelected: (field) {
                setState(() {
                  _sortField = field;
                });
              },
              onSortOrderToggled: () {
                setState(() {
                  _sortAscending = !_sortAscending;
                });
              },
            ),
            Expanded(
              child: visibleAlbums.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noAlbums,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: visibleAlbums.length,
                      itemBuilder: (context, index) {
                        final album = visibleAlbums[index];
                        return _AlbumCard(album: album);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  List<AlbumSummary> _filterAndSortAlbums(List<AlbumSummary> albums) {
    final query = _searchQuery.toLowerCase();
    final filtered = albums.where((album) {
      if (query.isEmpty) return true;
      return album.title.toLowerCase().contains(query) ||
          album.artist.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      final compare = switch (_sortField) {
        _AlbumSortField.artist => a.artist.toLowerCase().compareTo(
          b.artist.toLowerCase(),
        ),
        _AlbumSortField.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        _AlbumSortField.trackCount => a.trackCount.compareTo(b.trackCount),
        _AlbumSortField.duration => a.totalDurationMillis.compareTo(
          b.totalDurationMillis,
        ),
        _AlbumSortField.recentAdded => a.latestTimestampMillis.compareTo(
          b.latestTimestampMillis,
        ),
      };
      if (compare != 0) {
        return _sortAscending ? compare : -compare;
      }
      final fallback = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return _sortAscending ? fallback : -fallback;
    });
    return filtered;
  }
}

class _AlbumCard extends ConsumerWidget {
  const _AlbumCard({required this.album});

  final AlbumSummary album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) {
          _showAlbumContextMenu(context, ref, details.globalPosition);
        },
        onLongPressStart: (details) {
          _showAlbumContextMenu(context, ref, details.globalPosition);
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _openAlbumDetail(context),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
                  theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                ],
              ),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Hero(
                      tag: 'album-cover-${album.id}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: SongThumbnail(
                            path: album.representativeSong.path,
                            id: album.representativeSong.id,
                            size: 220,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    album.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.songCount(album.trackCount),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.playAll,
                        onPressed: () => audio.playPlaylist(album.songs),
                        icon: const Icon(Icons.play_arrow),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openAlbumDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AlbumDetailPage(album: album)),
    );
  }

  Future<void> _showAlbumContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'play_all', child: Text(l10n.playAll)),
        PopupMenuItem(value: 'shuffle', child: Text(l10n.shufflePlay)),
        PopupMenuItem(value: 'play_next', child: Text(l10n.playNext)),
        PopupMenuItem(
          value: 'add_to_playlist',
          child: Text(l10n.addToPlaylist),
        ),
        PopupMenuItem(
          value: 'add_to_favorites',
          child: Text(l10n.addToFavorites),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'view_details',
          child: Text(l10n.viewAlbumDetails),
        ),
        PopupMenuItem(
          value: 'open_location',
          child: Text(l10n.openFileLocation),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'copy_album', child: Text(l10n.copyAlbumTitle)),
        PopupMenuItem(value: 'copy_artist', child: Text(l10n.copyArtistName)),
      ],
    );

    if (!context.mounted || selected == null) return;

    switch (selected) {
      case 'play_all':
        await ref.read(audioServiceProvider).playPlaylist(album.songs);
        break;
      case 'shuffle':
        await ref
            .read(audioServiceProvider)
            .playPlaylist(List.of(album.songs)..shuffle());
        break;
      case 'play_next':
        await ref.read(audioServiceProvider).enqueueNext(album.songs);
        break;
      case 'add_to_playlist':
        await showAddSongsToPlaylistDialog(
          context,
          ref.read(playlistServiceProvider),
          album.songs,
        );
        break;
      case 'add_to_favorites':
        for (final song in album.songs) {
          await ref.read(playlistServiceProvider).addSongToFavorite(song);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n.addToFavorites} · ${album.trackCount}'),
            ),
          );
        }
        break;
      case 'view_details':
        _openAlbumDetail(context);
        break;
      case 'open_location':
        await openSongFileLocation(album.representativeSong.path);
        break;
      case 'copy_album':
        await Clipboard.setData(ClipboardData(text: album.title));
        break;
      case 'copy_artist':
        await Clipboard.setData(ClipboardData(text: album.artist));
        break;
    }
  }
}

class _AlbumsToolbar extends StatelessWidget {
  const _AlbumsToolbar({
    required this.searchController,
    required this.searchQuery,
    required this.sortField,
    required this.sortAscending,
    required this.albumCount,
    required this.isWide,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onSortFieldSelected,
    required this.onSortOrderToggled,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final _AlbumSortField sortField;
  final bool sortAscending;
  final int albumCount;
  final bool isWide;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final ValueChanged<_AlbumSortField> onSortFieldSelected;
  final VoidCallback onSortOrderToggled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.albums,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.albumCount(albumCount),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final searchField = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        hintText: l10n.searchAlbums,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: onSearchCleared,
                icon: const Icon(Icons.close),
              ),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );

    final sortControls = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<_AlbumSortField>(
          tooltip: l10n.albumSort,
          onSelected: onSortFieldSelected,
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _AlbumSortField.artist,
              child: Text(l10n.sortArtistAsc),
            ),
            PopupMenuItem(
              value: _AlbumSortField.title,
              child: Text(l10n.sortTitleAsc),
            ),
            PopupMenuItem(
              value: _AlbumSortField.trackCount,
              child: Text(l10n.sortTrackCount),
            ),
            PopupMenuItem(
              value: _AlbumSortField.duration,
              child: Text(l10n.sortDuration),
            ),
            PopupMenuItem(
              value: _AlbumSortField.recentAdded,
              child: Text(l10n.sortRecentAdded),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sort_rounded, size: 18),
                const SizedBox(width: 8),
                Text(_sortFieldLabel(l10n, sortField)),
              ],
            ),
          ),
        ),
        IconButton.filledTonal(
          tooltip: sortAscending ? l10n.sortAscending : l10n.sortDescending,
          onPressed: onSortOrderToggled,
          icon: Icon(
            sortAscending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: isWide
          ? Row(
              children: [
                Expanded(flex: 3, child: titleBlock),
                Expanded(flex: 5, child: searchField),
                const SizedBox(width: 12),
                sortControls,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: titleBlock),
                    sortControls,
                  ],
                ),
                const SizedBox(height: 12),
                searchField,
              ],
            ),
    );
  }

  String _sortFieldLabel(AppLocalizations l10n, _AlbumSortField field) {
    return switch (field) {
      _AlbumSortField.artist => l10n.sortArtistAsc,
      _AlbumSortField.title => l10n.sortTitleAsc,
      _AlbumSortField.trackCount => l10n.sortTrackCount,
      _AlbumSortField.duration => l10n.sortDuration,
      _AlbumSortField.recentAdded => l10n.sortRecentAdded,
    };
  }
}
