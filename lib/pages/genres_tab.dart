import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/genre_library.dart';
import 'genre_detail_page.dart';
import '../widgets/master_detail_scaffold.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/draggable_genre_item.dart';
import '../widgets/genre_context_menu.dart';
import 'main_layout_riverpod.dart';

class GenresTab extends ConsumerStatefulWidget {
  final double contentTopPadding;
  final double contentLeftPadding;

  const GenresTab({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  @override
  ConsumerState<GenresTab> createState() => _GenresTabState();
}

class _GenresTabState extends ConsumerState<GenresTab>
    with SelectionStateMixin<GenresTab, String> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.genre;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  GenreSortField _sortField = GenreSortField.genre;
  bool _sortAscending = true;

  List<GenreSummary>? _lastRawGenres;
  String? _lastSearchQuery;
  GenreSortField? _lastSortField;
  bool? _lastSortAscending;
  List<GenreSummary>? _cachedFilteredGenres;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsServiceProvider);
    _sortField = settings.genreSortField;
    _sortAscending = settings.genreSortAscending;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<GenreSummary> _filterAndSortGenres(List<GenreSummary> genres) {
    final query = _searchQuery.toLowerCase();
    final filtered = genres
        .where(
          (genre) =>
              query.isEmpty || genre.name.toLowerCase().contains(query),
        )
        .toList();

    filtered.sort((a, b) {
      final compare = switch (_sortField) {
        GenreSortField.genre => a.name.toLowerCase().compareTo(
              b.name.toLowerCase(),
            ),
        GenreSortField.songCount => a.songCount.compareTo(b.songCount),
      };
      if (compare != 0) {
        return _sortAscending ? compare : -compare;
      }
      final fallback = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return _sortAscending ? fallback : -fallback;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final genresAsync = ref.watch(genreLibraryProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final selectionScope = ref.watch(librarySelectionScopeProvider);
    final isSongSelectionMode = selectionScope == LibrarySelectionScope.library;
    final currentSelection = ref.watch(librarySelectionStateProvider);
    final isSelectionMode = selectionScope == LibrarySelectionScope.genre;

    final l10n = AppLocalizations.of(context)!;
    final genresLabel = l10n.genres;
    final noGenresLabel = l10n.emptyList;

    return genresAsync.when(
      loading: () => const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
      data: (genres) {
        if (!identical(_lastRawGenres, genres) ||
            _lastSearchQuery != _searchQuery ||
            _lastSortField != _sortField ||
            _lastSortAscending != _sortAscending) {
          _lastRawGenres = genres;
          _lastSearchQuery = _searchQuery;
          _lastSortField = _sortField;
          _lastSortAscending = _sortAscending;
          _cachedFilteredGenres = _filterAndSortGenres(genres);
        }
        final visibleGenres = _cachedFilteredGenres!;

        final List<MusicFile> selectedSongs;
        final List<MusicFile> allSongs;

        if (isSelectionMode) {
          selectedSongs = <MusicFile>[];
          final seenSelectedPaths = <String>{};
          for (final genre in visibleGenres) {
            if (isSelected(genre.queryKey)) {
              for (final song in genre.songs) {
                if (seenSelectedPaths.add(song.path)) {
                  selectedSongs.add(song);
                }
              }
            }
          }

          allSongs = <MusicFile>[];
          final seenAllPaths = <String>{};
          for (final genre in visibleGenres) {
            for (final song in genre.songs) {
              if (seenAllPaths.add(song.path)) {
                allSongs.add(song);
              }
            }
          }
        } else {
          selectedSongs = const [];
          allSongs = const [];
        }

        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final currentGenreKey = ref.watch(selectedGenreKeyProvider);
        final selectedGenre = visibleGenres.isNotEmpty
            ? visibleGenres.firstWhere(
                (g) => g.queryKey == currentGenreKey,
                orElse: () => visibleGenres.first,
              )
            : null;

        final Widget? selectionPanel = isSelectionMode
            ? LibrarySelectionPanel(
                key: const ValueKey('genre-selection-panel'),
                selectedSongs: selectedSongs,
                allSongs: allSongs,
                title: l10n.selectedItemsCount(selectedCount),
                onToggleSelectAll: () =>
                    toggleSelectAll(visibleGenres.map((g) => g.queryKey)),
                onCancel: cancelSelection,
              )
            : (isLandscape && isSongSelectionMode
                ? LibrarySelectionPanel(
                    key: const ValueKey('song-selection-panel'),
                    selectedSongs: (selectedGenre?.songs ?? const <MusicFile>[])
                        .where((s) => currentSelection.selectedKeys.contains(s.path))
                        .toList(),
                    allSongs: selectedGenre?.songs ?? const <MusicFile>[],
                    onToggleSelectAll: () {
                      if (selectedGenre != null) {
                        ref.read(librarySelectionStateProvider.notifier).toggleSelectAll(
                              selectedGenre.songs.map((s) => s.path),
                              scope: LibrarySelectionScope.library,
                            );
                      }
                    },
                    onCancel: () {
                      ref.read(librarySelectionStateProvider.notifier).clear();
                    },
                  )
                : null);

        return MasterDetailScaffold<GenreSummary>(
          items: visibleGenres,
          itemKey: (genre) => genre.queryKey,
          selectedKeyProvider: selectedGenreKeyProvider,
          onKeySelected: (ref, key) =>
              ref.read(selectedGenreKeyProvider.notifier).set(key),
          routeName: 'genre_detail',
          contentTopPadding: widget.contentTopPadding,
          contentLeftPadding: widget.contentLeftPadding,
          masterScrollController: _scrollController,
          hasPlayingMusic: currentMusic != null,
          isSelectionMode: isSelectionMode || (isLandscape && isSongSelectionMode),
          selectionPanel: selectionPanel,
          masterToolbarBuilder: (context, isWide) => _GenresToolbar(
            searchController: _searchController,
            searchQuery: _searchQuery,
            sortField: _sortField,
            sortAscending: _sortAscending,
            genreCount: visibleGenres.length,
            genresLabel: genresLabel,
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
            onSortChanged: (field, sortAscending) {
              setState(() {
                _sortField = field;
                _sortAscending = sortAscending;
              });
              final settings = ref.read(settingsServiceProvider);
              settings.genreSortField = field;
              settings.genreSortAscending = sortAscending;
            },
          ),
          masterItemBuilder: (context, genre, index, isSelected, isWide, onTap) {
            final isItemSelection = this.isSelected(genre.queryKey);
            return _GenreListItem(
              genre: genre,
              selected: isWide && isSelected,
              isSelectionMode: isSelectionMode,
              isSelectedInSelectionMode: isItemSelection,
              selectedGenres: isSelectionMode
                  ? visibleGenres
                      .where((g) => this.isSelected(g.queryKey))
                      .toList()
                  : null,
              onTap: () {
                final genreIndex = visibleGenres.indexOf(genre);
                handleItemTap(
                  index: genreIndex >= 0 ? genreIndex : 0,
                  itemKey: genre.queryKey,
                  allKeys: visibleGenres.map((g) => g.queryKey).toList(),
                  onNormalTap: onTap,
                );
              },
              onLongPress: () {
                final genreIndex = visibleGenres.indexOf(genre);
                if (genreIndex >= 0) {
                  lastAnchorIndex = genreIndex;
                }
                if (isSelectionMode) {
                  toggleSelection(genre.queryKey);
                } else if (!isSongSelectionMode) {
                  enterSelectionMode(genre.queryKey);
                }
              },
              onSelectionToggled: () => toggleSelection(genre.queryKey),
              onMultiSelect: (key) => enterSelectionMode(key),
            );
          },
          detailBuilder: (context, genre) => GenreDetailContent(
            genre: genre,
            showSelectionPanel: false,
            hasBottomPanel: isSelectionMode || (isLandscape && isSongSelectionMode),
          ),
          detailPageBuilder: (context, genre) => GenreDetailPage(genre: genre),
          emptyMasterBuilder: (context) => Center(
            child: Text(
              noGenresLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          emptyDetailBuilder: (context) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.style_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  noGenresLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _GenreListItem extends ConsumerWidget {
  const _GenreListItem({
    required this.genre,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelectedInSelectionMode = false,
    this.selectedGenres,
    this.onSelectionToggled,
    this.onMultiSelect,
  });

  final GenreSummary genre;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelectedInSelectionMode;
  final List<GenreSummary>? selectedGenres;
  final VoidCallback? onSelectionToggled;
  final void Function(String genreKey)? onMultiSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isItemHighlighted =
        isSelectionMode ? isSelectedInSelectionMode : selected;
    final backgroundColor = isItemHighlighted
        ? (isSelectionMode
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5)
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.6))
        : Colors.transparent;
    final iconPath = genre.iconAssetPath;

    return DraggableGenreItem(
      genre: genre,
      isSelectionMode: isSelectionMode,
      isSelected: isItemHighlighted,
      selectedGenres: selectedGenres,
      child: RepaintBoundary(
        child: Material(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) {
              if (!isSelectionMode) {
                showGenreContextMenu(
                  context: context,
                  globalPosition: details.globalPosition,
                  ref: ref,
                  genre: genre,
                  onMultiSelect: onMultiSelect,
                );
              }
            },
            onLongPress: () {
              if (onLongPress != null) {
                onLongPress!();
              } else if (!isSelectionMode) {
                showGenreBottomSheet(
                  context: context,
                  ref: ref,
                  genre: genre,
                  onMultiSelect: onMultiSelect,
                );
              }
            },
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    if (isSelectionMode) ...[
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: isSelectedInSelectionMode,
                          onChanged: (_) {
                            if (onSelectionToggled != null) {
                              onSelectionToggled!();
                            } else {
                              onTap();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        // 流派封面为 2:3 竖版，缩略图同比，否则 cover 会裁掉构图
                        width: 36,
                        height: 54,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              genre.imageAssetPath,
                              fit: BoxFit.cover,
                              cacheWidth: 72,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  ColoredBox(
                                color: theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                            if (iconPath != null)
                              Positioned(
                                left: 3,
                                bottom: 3,
                                child: SvgPicture.asset(
                                  iconPath,
                                  width: 12,
                                  height: 12,
                                  colorFilter: const ColorFilter.mode(
                                    Colors.white,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            genre.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                              color: selected ? theme.colorScheme.primary : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${l10n.songCount(genre.songCount)} · ${l10n.albumCount(genre.albumCount)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GenresToolbar extends StatelessWidget {
  const _GenresToolbar({
    required this.searchController,
    required this.searchQuery,
    required this.sortField,
    required this.sortAscending,
    required this.genreCount,
    required this.genresLabel,
    required this.isWide,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onSortChanged,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final GenreSortField sortField;
  final bool sortAscending;
  final int genreCount;
  final String genresLabel;
  final bool isWide;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final void Function(GenreSortField field, bool ascending) onSortChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isWide ? 12 : 16,
        8,
        isWide ? 12 : 16,
        8,
      ),
      child: Row(
        children: [
          Text(
            '$genresLabel ($genreCount)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: isWide ? 180 : 130,
            height: 36,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: l10n.search,
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: onSearchCleared,
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 20,
            ),
            tooltip: sortAscending ? l10n.ascending : l10n.descending,
            onPressed: () => onSortChanged(sortField, !sortAscending),
          ),
          PopupMenuButton<GenreSortField>(
            icon: const Icon(Icons.sort_rounded, size: 20),
            tooltip: l10n.sort,
            initialValue: sortField,
            onSelected: (field) => onSortChanged(field, sortAscending),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: GenreSortField.genre,
                child: Text(l10n.genres),
              ),
              PopupMenuItem(
                value: GenreSortField.songCount,
                child: Text(l10n.sortTrackCount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
