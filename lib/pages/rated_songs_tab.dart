import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dialogs/sort_options_dialog.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import 'package:vynody/player/settings/settings_service.dart';
import '../widgets/library_ranked_song_list.dart';

class RatedSongsTab extends ConsumerStatefulWidget {
  final double contentTopPadding;
  final double contentLeftPadding;

  const RatedSongsTab({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  @override
  ConsumerState<RatedSongsTab> createState() => _RatedSongsTabState();
}

class _RatedSongsTabState extends ConsumerState<RatedSongsTab> {
  int? _selectedStarFilter;
  late RatedSongSortField _sortField;
  late bool _sortAscending;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final settings = ref.read(settingsServiceProvider);
      _sortField = settings.ratedSongSortField;
      _sortAscending = settings.ratedSongSortAscending;
      _initialized = true;
    }
  }

  List<LibraryInsightSongEntry> _sortAndFilterItems(List<LibraryInsightSongEntry> items) {
    var result = items;
    if (_selectedStarFilter != null) {
      result = result.where((e) => e.playCount == _selectedStarFilter).toList();
    } else {
      result = List<LibraryInsightSongEntry>.from(result);
    }

    result.sort((a, b) {
      final int cmp = switch (_sortField) {
        RatedSongSortField.rating => a.playCount.compareTo(b.playCount),
        RatedSongSortField.title => a.song.displayName.toLowerCase().compareTo(b.song.displayName.toLowerCase()),
        RatedSongSortField.artist => (a.song.artist ?? '').toLowerCase().compareTo((b.song.artist ?? '').toLowerCase()),
        RatedSongSortField.recentAdded => (a.createdAt ?? 0).compareTo(b.createdAt ?? 0),
      };
      if (cmp != 0) {
        return _sortAscending ? cmp : -cmp;
      }
      if (_sortField != RatedSongSortField.rating) {
        final rCmp = b.playCount.compareTo(a.playCount);
        if (rCmp != 0) return rCmp;
      }
      return (b.createdAt ?? 0).compareTo(a.createdAt ?? 0);
    });

    return result;
  }

  Future<void> _showSortDialog(BuildContext context, AppLocalizations l10n) async {
    final result = await showDialog<SortResult<RatedSongSortField>>(
      context: context,
      builder: (context) => SortOptionsDialog<RatedSongSortField>(
        title: l10n.sort,
        currentField: _sortField,
        sortAscending: _sortAscending,
        options: [
          SortOptionItem(
            value: RatedSongSortField.rating,
            label: l10n.sortRating,
            icon: Icons.star_rounded,
          ),
          SortOptionItem(
            value: RatedSongSortField.recentAdded,
            label: l10n.sortRecentAdded,
            icon: Icons.access_time_rounded,
          ),
          SortOptionItem(
            value: RatedSongSortField.title,
            label: l10n.sortSongTitle,
            icon: Icons.title_rounded,
          ),
          SortOptionItem(
            value: RatedSongSortField.artist,
            label: l10n.sortArtist,
            icon: Icons.mic_rounded,
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _sortField = result.field;
        _sortAscending = result.sortAscending;
      });
      final settings = ref.read(settingsServiceProvider);
      settings.ratedSongSortField = result.field;
      settings.ratedSongSortAscending = result.sortAscending;
    }
  }

  Widget _buildFilterBar(ThemeData theme, AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(l10n.allStars),
            selected: _selectedStarFilter == null,
            onSelected: (_) {
              setState(() {
                _selectedStarFilter = null;
              });
            },
          ),
          for (int star = 5; star >= 1; star--) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              avatar: const Icon(
                Icons.star_rounded,
                size: 16,
                color: Color(0xFFF59E0B),
              ),
              label: Text('$star'),
              selected: _selectedStarFilter == star,
              onSelected: (selected) {
                setState(() {
                  _selectedStarFilter = selected ? star : null;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final asyncItems = ref.watch(allRatedSongsProvider);

    return asyncItems.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (items) {
        final processedItems = _sortAndFilterItems(items);

        return LibraryRankedSongList(
          contentTopPadding: widget.contentTopPadding,
          contentLeftPadding: widget.contentLeftPadding,
          title: l10n.ratedSongs,
          subtitle: l10n.ratedSongsSubtitle,
          items: processedItems,
          showTimeRange: false,
          customFilterBar: _buildFilterBar(theme, l10n),
          headerAction: IconButton(
            tooltip: l10n.sort,
            icon: const Icon(Icons.sort_rounded),
            onPressed: () => _showSortDialog(context, l10n),
          ),
          emptyText: items.isEmpty
              ? l10n.emptyRatedSongs
              : l10n.noMatchingResults,
          trailingBuilder: (context, entry) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.star_rounded,
                size: 18,
                color: Color(0xFFF59E0B),
              ),
              const SizedBox(width: 4),
              Text(
                '${entry.playCount}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
