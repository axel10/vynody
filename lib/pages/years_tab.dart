import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/year_library.dart';
import 'year_detail_page.dart';
import '../widgets/master_detail_scaffold.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/draggable_year_item.dart';
import '../widgets/year_context_menu.dart';
import 'main_layout_riverpod.dart';

class YearsTab extends ConsumerStatefulWidget {
  final double contentTopPadding;
  final double contentLeftPadding;

  const YearsTab({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  @override
  ConsumerState<YearsTab> createState() => _YearsTabState();
}

class _YearsTabState extends ConsumerState<YearsTab>
    with SelectionStateMixin<YearsTab, String> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.year;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  YearSortField _sortField = YearSortField.year;
  bool _sortAscending = false;

  List<YearSummary>? _lastRawYears;
  String? _lastSearchQuery;
  YearSortField? _lastSortField;
  bool? _lastSortAscending;
  String? _lastUnknownYearLabel;
  List<YearSummary>? _cachedFilteredYears;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsServiceProvider);
    _sortField = settings.yearSortField;
    _sortAscending = settings.yearSortAscending;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<YearSummary> _filterAndSortYears(
    List<YearSummary> years,
    String unknownYearLabel,
  ) {
    final query = _searchQuery.toLowerCase();
    final filtered = years
        .where((year) {
          if (query.isEmpty) return true;
          final label =
              (year.year?.toString() ?? unknownYearLabel).toLowerCase();
          return label.contains(query);
        })
        .toList();

    filtered.sort((a, b) {
      // 「未知年份」分组固定沉底，不随排序方向翻转
      if (a.isUnknownYear != b.isUnknownYear) {
        return a.isUnknownYear ? 1 : -1;
      }
      final compare = switch (_sortField) {
        YearSortField.year => a.year!.compareTo(b.year!),
        YearSortField.songCount => a.songCount.compareTo(b.songCount),
      };
      if (compare != 0) {
        return _sortAscending ? compare : -compare;
      }
      final fallback = a.queryKey.compareTo(b.queryKey);
      return _sortAscending ? fallback : -fallback;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final yearsAsync = ref.watch(yearLibraryProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final selectionScope = ref.watch(librarySelectionScopeProvider);
    final isSongSelectionMode = selectionScope == LibrarySelectionScope.library;
    final currentSelection = ref.watch(librarySelectionStateProvider);
    final isSelectionMode = selectionScope == LibrarySelectionScope.year;

    final l10n = AppLocalizations.of(context)!;
    final yearsLabel = l10n.years;
    final unknownYearLabel = l10n.unknownYear;
    final noYearsLabel = l10n.emptyList;

    return yearsAsync.when(
      // 曲库快照重算时保留上一次的列表，避免整页闪加载圈。
      skipLoadingOnReload: true,
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
      data: (years) {
        if (!identical(_lastRawYears, years) ||
            _lastSearchQuery != _searchQuery ||
            _lastSortField != _sortField ||
            _lastSortAscending != _sortAscending ||
            _lastUnknownYearLabel != unknownYearLabel) {
          _lastRawYears = years;
          _lastSearchQuery = _searchQuery;
          _lastSortField = _sortField;
          _lastSortAscending = _sortAscending;
          _lastUnknownYearLabel = unknownYearLabel;
          _cachedFilteredYears = _filterAndSortYears(years, unknownYearLabel);
        }
        final visibleYears = _cachedFilteredYears!;

        final List<MusicFile> selectedSongs;
        final List<MusicFile> allSongs;

        if (isSelectionMode) {
          selectedSongs = <MusicFile>[];
          final seenSelectedPaths = <String>{};
          for (final year in visibleYears) {
            if (isSelected(year.queryKey)) {
              for (final song in year.songs) {
                if (seenSelectedPaths.add(song.path)) {
                  selectedSongs.add(song);
                }
              }
            }
          }

          allSongs = <MusicFile>[];
          final seenAllPaths = <String>{};
          for (final year in visibleYears) {
            for (final song in year.songs) {
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
        final currentYearKey = ref.watch(selectedYearKeyProvider);
        final selectedYear = visibleYears.isNotEmpty
            ? visibleYears.firstWhere(
                (y) => y.queryKey == currentYearKey,
                orElse: () => visibleYears.first,
              )
            : null;

        final Widget? selectionPanel = isSelectionMode
            ? LibrarySelectionPanel(
                key: const ValueKey('year-selection-panel'),
                selectedSongs: selectedSongs,
                allSongs: allSongs,
                title: l10n.selectedItemsCount(selectedCount),
                onToggleSelectAll: () =>
                    toggleSelectAll(visibleYears.map((y) => y.queryKey)),
                onCancel: cancelSelection,
              )
            : (isLandscape && isSongSelectionMode
                ? LibrarySelectionPanel(
                    key: const ValueKey('song-selection-panel'),
                    selectedSongs: (selectedYear?.songs ?? const <MusicFile>[])
                        .where(
                          (s) => currentSelection.selectedKeys.contains(s.path),
                        )
                        .toList(),
                    allSongs: selectedYear?.songs ?? const <MusicFile>[],
                    onToggleSelectAll: () {
                      if (selectedYear != null) {
                        ref
                            .read(librarySelectionStateProvider.notifier)
                            .toggleSelectAll(
                              selectedYear.songs.map((s) => s.path),
                              scope: LibrarySelectionScope.library,
                            );
                      }
                    },
                    onCancel: () {
                      ref.read(librarySelectionStateProvider.notifier).clear();
                    },
                  )
                : null);

        return MasterDetailScaffold<YearSummary>(
          items: visibleYears,
          itemKey: (year) => year.queryKey,
          selectedKeyProvider: selectedYearKeyProvider,
          onKeySelected: (ref, key) =>
              ref.read(selectedYearKeyProvider.notifier).set(key),
          routeName: 'year_detail',
          contentTopPadding: widget.contentTopPadding,
          contentLeftPadding: widget.contentLeftPadding,
          masterScrollController: _scrollController,
          hasPlayingMusic: currentMusic != null,
          isSelectionMode: isSelectionMode || (isLandscape && isSongSelectionMode),
          selectionPanel: selectionPanel,
          masterToolbarBuilder: (context, isWide) => _YearsToolbar(
            searchController: _searchController,
            searchQuery: _searchQuery,
            sortField: _sortField,
            sortAscending: _sortAscending,
            yearCount: visibleYears.length,
            yearsLabel: yearsLabel,
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
              settings.yearSortField = field;
              settings.yearSortAscending = sortAscending;
            },
          ),
          masterItemBuilder: (context, year, index, isSelected, isWide, onTap) {
            final isItemSelection = this.isSelected(year.queryKey);
            final yearIndex = visibleYears.indexOf(year);
            return _YearListItem(
              year: year,
              label: year.labelWith(unknownYearLabel),
              selected: isWide && isSelected,
              isSelectionMode: isSelectionMode,
              isSelectedInSelectionMode: isItemSelection,
              selectedYears: isSelectionMode
                  ? visibleYears
                      .where((y) => this.isSelected(y.queryKey))
                      .toList()
                  : null,
              onTap: () {
                handleItemTap(
                  index: yearIndex >= 0 ? yearIndex : 0,
                  itemKey: year.queryKey,
                  allKeys: visibleYears.map((y) => y.queryKey).toList(),
                  onNormalTap: onTap,
                );
              },
              onLongPress: () {
                if (yearIndex >= 0) {
                  lastAnchorIndex = yearIndex;
                }
                if (isSelectionMode) {
                  toggleSelection(year.queryKey);
                } else if (!isSongSelectionMode) {
                  enterSelectionMode(year.queryKey);
                }
              },
              onMultiSelect: (key) => enterSelectionMode(key),
            );
          },
          detailBuilder: (context, year) => YearDetailContent(
            year: year,
            showSelectionPanel: false,
            hasBottomPanel: isSelectionMode || (isLandscape && isSongSelectionMode),
          ),
          detailPageBuilder: (context, year) => YearDetailPage(year: year),
          emptyMasterBuilder: (context) => Center(
            child: Text(
              noYearsLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          emptyDetailBuilder: (context) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  noYearsLabel,
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

class _YearListItem extends ConsumerWidget {
  const _YearListItem({
    required this.year,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelectedInSelectionMode = false,
    this.selectedYears,
    this.onMultiSelect,
  });

  final YearSummary year;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelectedInSelectionMode;

  /// 多选模式下已选中的年份分组（用于批量拖拽）
  final List<YearSummary>? selectedYears;
  final void Function(String yearKey)? onMultiSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final isItemHighlighted =
        isSelectionMode ? isSelectedInSelectionMode : selected;

    final content = Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
          : (isSelectedInSelectionMode
              ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5)
              : Colors.transparent),
      borderRadius: BorderRadius.circular(10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) {
          if (!isSelectionMode) {
            showYearContextMenu(
              context: context,
              globalPosition: details.globalPosition,
              ref: ref,
              year: year,
              onMultiSelect: onMultiSelect,
            );
          }
        },
        onLongPress: () {
          if (onLongPress != null) {
            onLongPress!();
          } else if (!isSelectionMode) {
            showYearBottomSheet(
              context: context,
              ref: ref,
              year: year,
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
                  Checkbox(
                    value: isSelectedInSelectionMode,
                    onChanged: (_) => onTap(),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.w500,
                          color: selected ? theme.colorScheme.primary : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${l10n.songCount(year.songCount)} · ${l10n.albumCount(year.albumCount)}',
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
    );

    return DraggableYearItem(
      year: year,
      isSelectionMode: isSelectionMode,
      isSelected: isItemHighlighted,
      selectedYears: selectedYears,
      child: RepaintBoundary(child: content),
    );
  }
}

class _YearsToolbar extends StatelessWidget {
  const _YearsToolbar({
    required this.searchController,
    required this.searchQuery,
    required this.sortField,
    required this.sortAscending,
    required this.yearCount,
    required this.yearsLabel,
    required this.isWide,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onSortChanged,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final YearSortField sortField;
  final bool sortAscending;
  final int yearCount;
  final String yearsLabel;
  final bool isWide;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final void Function(YearSortField field, bool ascending) onSortChanged;

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
            '$yearsLabel ($yearCount)',
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
                fillColor:
                    theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: onSearchCleared,
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              sortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 20,
            ),
            tooltip: sortAscending ? l10n.ascending : l10n.descending,
            onPressed: () => onSortChanged(sortField, !sortAscending),
          ),
          PopupMenuButton<YearSortField>(
            icon: const Icon(Icons.sort_rounded, size: 20),
            tooltip: l10n.sort,
            initialValue: sortField,
            onSelected: (field) => onSortChanged(field, sortAscending),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: YearSortField.year,
                child: Text(l10n.years),
              ),
              PopupMenuItem(
                value: YearSortField.songCount,
                child: Text(l10n.sortTrackCount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
