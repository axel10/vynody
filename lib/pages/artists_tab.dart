import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/artist_summary.dart';
import '../player/artist_library.dart';
import '../player/audio_riverpod.dart';
import 'artist_detail_page.dart';
import '../widgets/artist_avatar.dart';

enum _ArtistSortField { artist, songCount }

class ArtistsTab extends ConsumerStatefulWidget {
  const ArtistsTab({super.key});

  @override
  ConsumerState<ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends ConsumerState<ArtistsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _ArtistSortField _sortField = _ArtistSortField.artist;
  bool _sortAscending = true;
  String? _selectedArtistKey;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artistsAsync = ref.watch(artistLibraryProvider);
    debugPrint(
      '[ArtistsTab] build loading=${artistsAsync.isLoading} '
      'hasValue=${artistsAsync.hasValue} hasError=${artistsAsync.hasError}',
    );
    final l10n = AppLocalizations.of(context)!;
    final artistsLabel = l10n.artists;
    final noArtistsLabel = l10n.noArtists;

    return artistsAsync.when(
      loading: () => const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
      data: (artists) {
        final visibleArtists = _filterAndSortArtists(artists);

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 980;
            final isPortrait =
                MediaQuery.orientationOf(context) == Orientation.portrait;
            final selectedArtist = _resolveSelectedArtist(visibleArtists);

            if (isWide) {
              _syncSelectedArtist(visibleArtists);
              return Column(
                children: [
                  _ArtistsToolbar(
                    searchController: _searchController,
                    searchQuery: _searchQuery,
                    sortField: _sortField,
                    sortAscending: _sortAscending,
                    artistCount: visibleArtists.length,
                    artistsLabel: artistsLabel,
                    isWide: true,
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
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 360,
                            child: _ArtistListPane(
                              artists: visibleArtists,
                              selectedArtistKey: selectedArtist?.queryKey,
                              noArtistsLabel: noArtistsLabel,
                              onArtistSelected: (artist) {
                                setState(() {
                                  _selectedArtistKey = artist.queryKey;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ArtistDetailPane(
                              artist: selectedArtist,
                              emptyLabel: noArtistsLabel,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            if (isPortrait) {
              return Column(
                children: [
                  _ArtistsToolbar(
                    searchController: _searchController,
                    searchQuery: _searchQuery,
                    sortField: _sortField,
                    sortAscending: _sortAscending,
                    artistCount: visibleArtists.length,
                    artistsLabel: artistsLabel,
                    isWide: false,
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
                    child: visibleArtists.isEmpty
                        ? Center(
                            child: Text(
                              noArtistsLabel,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: visibleArtists.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final artist = visibleArtists[index];
                              return _ArtistListItem(
                                artist: artist,
                                selected: false,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          ArtistDetailPage(artist: artist),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              );
            }

            return CustomScrollView(
              cacheExtent: 1000,
              slivers: [
                SliverToBoxAdapter(
                  child: _ArtistsToolbar(
                    searchController: _searchController,
                    searchQuery: _searchQuery,
                    sortField: _sortField,
                    sortAscending: _sortAscending,
                    artistCount: visibleArtists.length,
                    artistsLabel: artistsLabel,
                    isWide: false,
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
                ),
                if (visibleArtists.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        noArtistsLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: switch (constraints.maxWidth) {
                          >= 1200 => 5,
                          >= 900 => 4,
                          >= 700 => 3,
                          _ => 2,
                        },
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.72,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => KeyedSubtree(
                          key: ValueKey(visibleArtists[index].queryKey),
                          child: _ArtistCard(artist: visibleArtists[index]),
                        ),
                        childCount: visibleArtists.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ],
            );
          },
        );
      },
    );
  }

  List<ArtistSummary> _filterAndSortArtists(List<ArtistSummary> artists) {
    final query = _searchQuery.toLowerCase();
    final filtered = artists
        .where(
          (artist) =>
              query.isEmpty ||
              artist.name.toLowerCase().contains(query) ||
              artist.disambiguation?.toLowerCase().contains(query) == true ||
              artist.country?.toLowerCase().contains(query) == true ||
              artist.tags.any((tag) => tag.toLowerCase().contains(query)),
        )
        .toList();

    filtered.sort((a, b) {
      final compare = switch (_sortField) {
        _ArtistSortField.artist => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        _ArtistSortField.songCount => a.songCount.compareTo(b.songCount),
      };
      if (compare != 0) {
        return _sortAscending ? compare : -compare;
      }

      final fallback = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return _sortAscending ? fallback : -fallback;
    });

    return filtered;
  }

  ArtistSummary? _resolveSelectedArtist(List<ArtistSummary> visibleArtists) {
    if (visibleArtists.isEmpty) return null;

    final selectedKey = _selectedArtistKey;
    if (selectedKey != null) {
      for (final artist in visibleArtists) {
        if (artist.queryKey == selectedKey) {
          return artist;
        }
      }
    }

    return visibleArtists.first;
  }

  void _syncSelectedArtist(List<ArtistSummary> visibleArtists) {
    if (visibleArtists.isEmpty) return;

    final selectedKey = _selectedArtistKey;
    if (selectedKey != null &&
        visibleArtists.any((artist) => artist.queryKey == selectedKey)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || visibleArtists.isEmpty) return;
      final fallbackKey = visibleArtists.first.queryKey;
      if (_selectedArtistKey == fallbackKey) return;
      setState(() {
        _selectedArtistKey = fallbackKey;
      });
    });
  }
}

class _ArtistListPane extends StatelessWidget {
  const _ArtistListPane({
    required this.artists,
    required this.selectedArtistKey,
    required this.noArtistsLabel,
    required this.onArtistSelected,
  });

  final List<ArtistSummary> artists;
  final String? selectedArtistKey;
  final String noArtistsLabel;
  final ValueChanged<ArtistSummary> onArtistSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: artists.isEmpty
          ? Center(
              child: Text(noArtistsLabel, style: theme.textTheme.titleMedium),
            )
          : Scrollbar(
              thumbVisibility: true,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: artists.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  final selected = artist.queryKey == selectedArtistKey;
                  return _ArtistListItem(
                    artist: artist,
                    selected: selected,
                    onTap: () => onArtistSelected(artist),
                  );
                },
              ),
            ),
    );
  }
}

class _ArtistListItem extends ConsumerWidget {
  const _ArtistListItem({
    required this.artist,
    required this.selected,
    required this.onTap,
  });

  final ArtistSummary artist;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final audio = ref.read(audioServiceProvider);
    final playAllLabel = l10n.playAll;
    final songCountLabel = l10n.songCount(artist.songCount);
    final subtitleParts = <String>[
      songCountLabel,
      if ((artist.country?.trim().isNotEmpty ?? false)) artist.country!.trim(),
    ];
    if (artist.disambiguation?.trim().isNotEmpty ?? false) {
      subtitleParts.add(artist.disambiguation!.trim());
    }

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(18),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) {
          _showArtistContextMenuForArtist(
            context,
            ref,
            details.globalPosition,
            artist,
          );
        },
        onLongPressStart: (details) {
          _showArtistContextMenuForArtist(
            context,
            ref,
            details.globalPosition,
            artist,
          );
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: ArtistAvatar(diameter: 48)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitleParts.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: playAllLabel,
                  onPressed: () => audio.playPlaylist(artist.songs),
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtistDetailPane extends StatelessWidget {
  const _ArtistDetailPane({required this.artist, required this.emptyLabel});

  final ArtistSummary? artist;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentArtist = artist;
    if (currentArtist == null) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                emptyLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ArtistDetailContent(artist: currentArtist),
      ),
    );
  }
}

Future<void> _showArtistContextMenuForArtist(
  BuildContext context,
  WidgetRef ref,
  Offset globalPosition,
  ArtistSummary artist,
) async {
  final l10n = AppLocalizations.of(context)!;
  final playAllLabel = l10n.playAll;
  final shufflePlayLabel = l10n.shufflePlay;
  final viewArtistDetailsLabel = l10n.viewArtistDetails;
  final copyArtistNameLabel = l10n.copyArtistName;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;

  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(value: 'play_all', child: Text(playAllLabel)),
      PopupMenuItem(value: 'shuffle', child: Text(shufflePlayLabel)),
      const PopupMenuDivider(),
      PopupMenuItem(value: 'view_details', child: Text(viewArtistDetailsLabel)),
      PopupMenuItem(value: 'copy_artist', child: Text(copyArtistNameLabel)),
    ],
  );

  if (!context.mounted || selected == null) return;

  switch (selected) {
    case 'play_all':
      await ref.read(audioServiceProvider).playPlaylist(artist.songs);
      break;
    case 'shuffle':
      await ref
          .read(audioServiceProvider)
          .playPlaylist(List.of(artist.songs)..shuffle());
      break;
    case 'view_details':
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArtistDetailPage(artist: artist),
        ),
      );
      break;
    case 'copy_artist':
      await Clipboard.setData(ClipboardData(text: artist.name));
      break;
  }
}

class _ArtistCard extends ConsumerWidget {
  const _ArtistCard({required this.artist});

  final ArtistSummary artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final playAllLabel = l10n.playAll;
    final songCountLabel = l10n.songCount(artist.songCount);
    final audio = ref.read(audioServiceProvider);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) {
          _showArtistContextMenu(context, ref, details.globalPosition);
        },
        onLongPressStart: (details) {
          _showArtistContextMenu(context, ref, details.globalPosition);
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _openArtistDetail(context),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
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
                    child: Center(
                      child: Hero(
                        tag: 'artist-cover-${artist.queryKey}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: const _ArtistCover(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          songCountLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: playAllLabel,
                        onPressed: () => audio.playPlaylist(artist.songs),
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

  void _openArtistDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ArtistDetailPage(artist: artist)),
    );
  }

  Future<void> _showArtistContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
  ) async {
    await _showArtistContextMenuForArtist(context, ref, globalPosition, artist);
  }
}

class _ArtistCover extends StatelessWidget {
  const _ArtistCover();

  @override
  Widget build(BuildContext context) {
    return const Center(child: ArtistAvatar(diameter: 100));
  }
}

class _ArtistsToolbar extends StatelessWidget {
  const _ArtistsToolbar({
    required this.searchController,
    required this.searchQuery,
    required this.sortField,
    required this.sortAscending,
    required this.artistCount,
    required this.artistsLabel,
    required this.isWide,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onSortFieldSelected,
    required this.onSortOrderToggled,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final _ArtistSortField sortField;
  final bool sortAscending;
  final int artistCount;
  final String artistsLabel;
  final bool isWide;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final ValueChanged<_ArtistSortField> onSortFieldSelected;
  final VoidCallback onSortOrderToggled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final searchArtistsLabel = l10n.searchArtists;
    final artistCountLabel = '$artistCount $artistsLabel';
    final sortControls = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<_ArtistSortField>(
          tooltip: l10n.albumSort,
          onSelected: onSortFieldSelected,
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _ArtistSortField.artist,
              child: Text(l10n.sortArtistAsc),
            ),
            PopupMenuItem(
              value: _ArtistSortField.songCount,
              child: Text(l10n.sortTrackCount),
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
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artistsLabel,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        artistCountLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: searchArtistsLabel,
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
                  ),
                ),
                const SizedBox(width: 12),
                sortControls,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artistsLabel,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            artistCountLabel,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    sortControls,
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: searchArtistsLabel,
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
                ),
              ],
            ),
    );
  }

  String _sortFieldLabel(AppLocalizations? l10n, _ArtistSortField field) {
    return switch (field) {
      _ArtistSortField.artist => l10n!.sortArtistAsc,
      _ArtistSortField.songCount => l10n!.sortTrackCount,
    };
  }
}
