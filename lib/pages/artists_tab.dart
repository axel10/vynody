import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'artist_detail_page.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/draggable_artist_item.dart';
import '../widgets/remote_media_badge.dart';
import '../widgets/scroll_to_top_wrapper.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/library_selection_panel.dart';
import '../models/music_file.dart';
import '../dialogs/sort_options_dialog.dart';
import '../dialogs/library_source_filter_dialog.dart';
import 'package:vynody/player/library/library_source_filter.dart';
import 'package:vynody/player/settings/settings_service.dart';
import '../widgets/artist_context_menu.dart';

class ArtistsTab extends ConsumerStatefulWidget {
  final double contentTopPadding;
  final double contentLeftPadding;

  const ArtistsTab({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  @override
  ConsumerState<ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends ConsumerState<ArtistsTab>
    with SelectionStateMixin<ArtistsTab, String> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.artist;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  ArtistSortField _sortField = ArtistSortField.artist;
  bool _sortAscending = true;
  String? _selectedArtistKey;

  List<ArtistSummary>? _lastRawArtists;
  String? _lastSearchQuery;
  ArtistSortField? _lastSortField;
  bool? _lastSortAscending;
  List<ArtistSummary>? _cachedFilteredArtists;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsServiceProvider);
    _sortField = settings.artistSortField;
    _sortAscending = settings.artistSortAscending;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artistsAsync = ref.watch(artistLibraryProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final selectionScope = ref.watch(librarySelectionScopeProvider);
    final isSongSelectionMode = selectionScope == LibrarySelectionScope.library;
    final currentSelection = ref.watch(librarySelectionStateProvider);
    final isSelectionMode = selectionScope == LibrarySelectionScope.artist;

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
        if (!identical(_lastRawArtists, artists) ||
            _lastSearchQuery != _searchQuery ||
            _lastSortField != _sortField ||
            _lastSortAscending != _sortAscending) {
          _lastRawArtists = artists;
          _lastSearchQuery = _searchQuery;
          _lastSortField = _sortField;
          _lastSortAscending = _sortAscending;
          _cachedFilteredArtists = _filterAndSortArtists(artists);
        }
        final visibleArtists = _cachedFilteredArtists!;

        final List<MusicFile> selectedSongs;
        final List<MusicFile> allSongs;

        if (isSelectionMode) {
          selectedSongs = <MusicFile>[];
          final seenSelectedPaths = <String>{};
          for (final artist in visibleArtists) {
            if (isSelected(artist.queryKey)) {
              for (final song in artist.songs) {
                if (seenSelectedPaths.add(song.path)) {
                  selectedSongs.add(song);
                }
              }
            }
          }

          allSongs = <MusicFile>[];
          final seenAllPaths = <String>{};
          for (final artist in visibleArtists) {
            for (final song in artist.songs) {
              if (seenAllPaths.add(song.path)) {
                allSongs.add(song);
              }
            }
          }
        } else {
          selectedSongs = const [];
          allSongs = const [];
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape =
                MediaQuery.orientationOf(context) == Orientation.landscape;
            final selectedArtist = _resolveSelectedArtist(visibleArtists);

            Widget mainContent;

            if (isLandscape) {
              _syncSelectedArtist(visibleArtists);
              final showBottomPanel = isSelectionMode || (isLandscape && isSongSelectionMode);
              mainContent = Padding(
                padding: EdgeInsets.only(
                  top: widget.contentTopPadding,
                  left: widget.contentLeftPadding,
                ),
                child: Column(
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
                    onSortChanged: (field, sortAscending) {
                      setState(() {
                        _sortField = field;
                        _sortAscending = sortAscending;
                      });
                      final settings = ref.read(settingsServiceProvider);
                      settings.artistSortField = field;
                      settings.artistSortAscending = sortAscending;
                    },
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth >= 1100 ? 300 : 260,
                          child: _ArtistListPane(
                            artists: visibleArtists,
                            selectedArtistKey: selectedArtist?.queryKey,
                            noArtistsLabel: noArtistsLabel,
                            scrollController: _scrollController,
                            isSelectionMode: isSelectionMode,
                            selectedArtistKeysInSelectionMode: selectedKeys,
                            hasBottomPanel: showBottomPanel,
                            onArtistSelected: (artist) {
                              final artistIndex = visibleArtists.indexOf(artist);
                              handleItemTap(
                                index: artistIndex >= 0 ? artistIndex : 0,
                                itemKey: artist.queryKey,
                                allKeys: visibleArtists.map((a) => a.queryKey).toList(),
                                onNormalTap: () {
                                  if (!isSongSelectionMode) {
                                    setState(() {
                                      _selectedArtistKey = artist.queryKey;
                                    });
                                  }
                                },
                              );
                            },
                            onArtistLongPressed: (artist) {
                              final artistIndex = visibleArtists.indexOf(artist);
                              if (artistIndex >= 0) {
                                lastAnchorIndex = artistIndex;
                              }
                              if (isSelectionMode) {
                                toggleSelection(artist.queryKey);
                              } else if (!isSongSelectionMode) {
                                enterSelectionMode(artist.queryKey);
                              }
                            },
                          ),
                        ),
                        Expanded(
                          child: _ArtistDetailPane(
                            artist: selectedArtist,
                            emptyLabel: noArtistsLabel,
                            hasBottomPanel: showBottomPanel,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          } else {
              final bottomOffset = (currentMusic != null ? 140.0 : 40.0) + (isSelectionMode ? 220.0 : 0.0);
              mainContent = Padding(
                padding: EdgeInsets.only(
                  left: widget.contentLeftPadding,
                ),
                child: ScrollToTopWrapper(
                  scrollController: _scrollController,
                  bottomOffset: bottomOffset,
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      if (widget.contentTopPadding > 0)
                        SliverToBoxAdapter(
                          child: SizedBox(height: widget.contentTopPadding),
                        ),
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
                        onSortChanged: (field, sortAscending) {
                          setState(() {
                            _sortField = field;
                            _sortAscending = sortAscending;
                          });
                          final settings = ref.read(settingsServiceProvider);
                          settings.artistSortField = field;
                          settings.artistSortAscending = sortAscending;
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
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomOffset),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index.isOdd) {
                                return const SizedBox(height: 8);
                              }
                              final artistIndex = index ~/ 2;
                              final artist = visibleArtists[artistIndex];
                              final isSelected = this.isSelected(artist.queryKey);
                              return _ArtistListItem(
                                artist: artist,
                                selected: false,
                                isSelectionMode: isSelectionMode,
                                isSelectedInSelectionMode: isSelected,
                                selectedArtists: isSelectionMode
                                    ? visibleArtists
                                        .where((a) => this.isSelected(a.queryKey))
                                        .toList()
                                    : null,
                                onTap: () {
                                  handleItemTap(
                                    index: artistIndex,
                                    itemKey: artist.queryKey,
                                    allKeys: visibleArtists.map((a) => a.queryKey).toList(),
                                    onNormalTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              ArtistDetailPage(artist: artist),
                                        ),
                                      );
                                    },
                                  );
                                },
                                onLongPress: () {
                                  lastAnchorIndex = artistIndex;
                                  if (isSelectionMode) {
                                    toggleSelection(artist.queryKey);
                                  } else {
                                    enterSelectionMode(artist.queryKey);
                                  }
                                },
                                onSelectionToggled: () => toggleSelection(artist.queryKey),
                                onMultiSelect: (key) => enterSelectionMode(key),
                              );
                            },
                            childCount: visibleArtists.length * 2 - 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }

            return Stack(
              children: [
                Positioned.fill(child: mainContent),
                AnimatedSelectionPanel(
                  isVisible: isSelectionMode || (isLandscape && isSongSelectionMode),
                  child: isSelectionMode
                      ? LibrarySelectionPanel(
                          key: const ValueKey('artist-selection-panel'),
                          selectedSongs: selectedSongs,
                          allSongs: allSongs,
                          title: l10n.selectedArtistsCount(selectedCount),
                          onToggleSelectAll: () =>
                              toggleSelectAll(visibleArtists.map((a) => a.queryKey)),
                          onCancel: cancelSelection,
                        )
                      : (isLandscape && isSongSelectionMode
                          ? LibrarySelectionPanel(
                              key: const ValueKey('song-selection-panel'),
                              selectedSongs: (selectedArtist?.songs ?? const <MusicFile>[])
                                  .where((s) => currentSelection.selectedKeys.contains(s.path))
                                  .toList(),
                              allSongs: selectedArtist?.songs ?? const <MusicFile>[],
                              onToggleSelectAll: () {
                                if (selectedArtist != null) {
                                  ref.read(librarySelectionStateProvider.notifier).toggleSelectAll(
                                    selectedArtist.songs.map((s) => s.path),
                                    scope: LibrarySelectionScope.library,
                                  );
                                }
                              },
                              onCancel: () {
                                ref.read(librarySelectionStateProvider.notifier).clear();
                              },
                            )
                          : const SizedBox.shrink(key: ValueKey('artist-selection-panel-hidden'))),
                ),
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
        ArtistSortField.artist => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        ArtistSortField.songCount => a.songCount.compareTo(b.songCount),
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
    required this.scrollController,
    required this.onArtistSelected,
    this.isSelectionMode = false,
    this.selectedArtistKeysInSelectionMode = const {},
    this.onArtistLongPressed,
    this.hasBottomPanel = false,
  });

  final List<ArtistSummary> artists;
  final String? selectedArtistKey;
  final String noArtistsLabel;
  final ScrollController scrollController;
  final ValueChanged<ArtistSummary> onArtistSelected;
  final bool isSelectionMode;
  final Set<String> selectedArtistKeysInSelectionMode;
  final ValueChanged<ArtistSummary>? onArtistLongPressed;
  final bool hasBottomPanel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = hasBottomPanel ? 180.0 : 12.0;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: artists.isEmpty
          ? Center(
              child: Text(noArtistsLabel, style: theme.textTheme.titleMedium),
            )
          : Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(8, 8, 8, bottomPadding),
                itemCount: artists.length,
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  final selected = artist.queryKey == selectedArtistKey;
                  final isSelected = selectedArtistKeysInSelectionMode.contains(artist.queryKey);
                  return Padding(
                    key: ValueKey(artist.queryKey),
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _ArtistListItem(
                      artist: artist,
                      selected: selected,
                      isSelectionMode: isSelectionMode,
                      isSelectedInSelectionMode: isSelected,
                      selectedArtists: isSelectionMode
                          ? artists
                              .where((a) => selectedArtistKeysInSelectionMode
                                  .contains(a.queryKey))
                              .toList()
                          : null,
                      onTap: () => onArtistSelected(artist),
                      onLongPress: onArtistLongPressed != null ? () => onArtistLongPressed!(artist) : null,
                      onMultiSelect: onArtistLongPressed != null ? (key) => onArtistLongPressed!(artist) : null,
                      onSelectionToggled: () => onArtistSelected(artist),
                    ),
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
    this.isSelectionMode = false,
    this.isSelectedInSelectionMode = false,
    this.selectedArtists,
    this.onSelectionToggled,
    this.onLongPress,
    this.onMultiSelect,
  });

  final ArtistSummary artist;
  final bool selected;
  final VoidCallback onTap;
  final bool isSelectionMode;
  final bool isSelectedInSelectionMode;
  final List<ArtistSummary>? selectedArtists;
  final VoidCallback? onSelectionToggled;
  final VoidCallback? onLongPress;
  final void Function(String artistKey)? onMultiSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final songCountLabel = l10n.songCount(artist.songCount);
    final subtitleParts = <String>[
      songCountLabel,
      if ((artist.country?.trim().isNotEmpty ?? false)) artist.country!.trim(),
    ];
    if (artist.disambiguation?.trim().isNotEmpty ?? false) {
      subtitleParts.add(artist.disambiguation!.trim());
    }

    final isItemHighlighted = isSelectionMode ? isSelectedInSelectionMode : selected;
    final backgroundColor = isItemHighlighted
        ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.7)
        : Colors.transparent;

    return DraggableArtistItem(
      artist: artist,
      isSelectionMode: isSelectionMode,
      isSelected: isItemHighlighted,
      selectedArtists: selectedArtists,
      child: RepaintBoundary(
        child: Material(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) {
              if (!isSelectionMode) {
                showArtistContextMenu(
                  context: context,
                  globalPosition: details.globalPosition,
                  ref: ref,
                  artist: artist,
                  onMultiSelect: onMultiSelect,
                );
              }
            },
            onLongPress: () {
              if (onLongPress != null) {
                onLongPress!();
              } else if (!isSelectionMode) {
                showArtistBottomSheet(
                  context: context,
                  ref: ref,
                  artist: artist,
                  onMultiSelect: onMultiSelect,
                );
              }
            },
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              enableFeedback: false,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    if (isSelectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: isSelectedInSelectionMode,
                            onChanged: (_) => onSelectionToggled?.call(),
                          ),
                        ),
                      ),
                    const ArtistAvatar(diameter: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  artist.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: isItemHighlighted
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                              RemoteMediaBadge.pillTrailing(
                                songs: artist.songs,
                                title: artist.name,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitleParts.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11.5,
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

class _ArtistDetailPane extends StatelessWidget {
  const _ArtistDetailPane({
    required this.artist,
    required this.emptyLabel,
    this.hasBottomPanel = false,
  });

  final ArtistSummary? artist;
  final String emptyLabel;
  final bool hasBottomPanel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentArtist = artist;
    if (currentArtist == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtistMicIcon(
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
      );
    }

    return ArtistDetailContent(
      artist: currentArtist,
      showSelectionPanel: false,
      hasBottomPanel: hasBottomPanel,
    );
  }
}

class _ArtistsToolbar extends ConsumerWidget {
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
    required this.onSortChanged,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final ArtistSortField sortField;
  final bool sortAscending;
  final int artistCount;
  final String artistsLabel;
  final bool isWide;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final void Function(ArtistSortField field, bool sortAscending) onSortChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final searchArtistsLabel = l10n.searchArtists;
    final artistCountLabel = '$artistCount $artistsLabel';
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final currentFilter = ref.watch(librarySourceFilterProvider);
    final isFiltered = currentFilter.type != LibrarySourceType.all;

    final sortControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: isZh ? '渠道与来源筛选' : 'Filter by Source',
          onPressed: () => showLibrarySourceFilterDialog(context),
          icon: Badge(
            isLabelVisible: isFiltered,
            smallSize: 8,
            child: Icon(
              Icons.tune_rounded,
              color: isFiltered ? theme.colorScheme.primary : null,
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.albumSort,
          onPressed: () async {
            final result = await showDialog<SortResult<ArtistSortField>>(
              context: context,
              builder: (context) => SortOptionsDialog<ArtistSortField>(
                title: l10n.albumSort,
                currentField: sortField,
                sortAscending: sortAscending,
                options: [
                  SortOptionItem(
                    value: ArtistSortField.artist,
                    label: l10n.sortArtistAsc,
                    icon: Icons.mic_rounded,
                  ),
                  SortOptionItem(
                    value: ArtistSortField.songCount,
                    label: l10n.sortTrackCount,
                    icon: Icons.format_list_numbered_rounded,
                  ),
                ],
              ),
            );
            if (result != null) {
              onSortChanged(result.field, result.sortAscending);
            }
          },
          icon: const Icon(Icons.sort_rounded),
        ),
      ],
    );

    Widget buildTextField() {
      return SizedBox(
        height: 36,
        child: TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: searchArtistsLabel,
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
              fontSize: 13,
            ),
            prefixIcon: Icon(
              Icons.search,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            suffixIcon: searchQuery.isEmpty
                ? null
                : IconButton(
                    onPressed: onSearchCleared,
                    icon: Icon(
                      Icons.close,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      size: 16,
                    ),
                  ),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 13,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: isWide
          ? Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      artistsLabel,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      artistCountLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: 240,
                  child: buildTextField(),
                ),
                const SizedBox(width: 8),
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
                buildTextField(),
              ],
            ),
    );
  }
}
