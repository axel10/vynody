import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import '../widgets/library_ranked_album_list.dart';
import '../widgets/library_ranked_song_list.dart';
import '../widgets/section_type_toggle.dart';
import '../widgets/time_range_dropdown.dart';

class RecentlyPlayedTab extends ConsumerWidget {
  final double contentTopPadding;
  final double contentLeftPadding;

  const RecentlyPlayedTab({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final filterState = ref.watch(recentlyPlayedFilterProvider);
    final filterNotifier = ref.read(recentlyPlayedFilterProvider.notifier);

    final centerAction = SectionTypeToggle(
      selected: filterState.type,
      onChanged: (val) => filterNotifier.setType(val),
      songsLabel: l10n.songs,
      albumsLabel: l10n.albums,
    );

    final headerTrailing = TimeRangeDropdown(
      selected: filterState.range,
      onChanged: (val) => filterNotifier.setRange(val),
    );

    final isAlbums = filterState.type == SectionItemType.albums;

    if (isAlbums) {
      final asyncAlbums = ref.watch(recentlyPlayedAlbumsProvider(filterState.range));
      return asyncAlbums.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (albums) => LibraryRankedAlbumList(
          contentTopPadding: contentTopPadding,
          contentLeftPadding: contentLeftPadding,
          title: l10n.recentlyPlayed,
          subtitle: l10n.recentlyPlayedDescription,
          items: albums,
          selectedRange: filterState.range,
          onRangeChanged: (val) => filterNotifier.setRange(val),
          showTimeRange: false,
          showRankIndex: false,
          centerAction: centerAction,
          headerTrailing: headerTrailing,
          emptyText: filterState.range == LibraryTimeRange.allTime
              ? l10n.noRecentlyPlayedSongs
              : l10n.noRecentlyPlayedInRange,
          trailingBuilder: (context, entry) => InsightMetricText(
            primary: formatRelativeInsightDate(context, entry.lastPlayedAt),
            secondary: l10n.playCountLabel(entry.totalPlayCount),
          ),
        ),
      );
    } else {
      final asyncSongs = ref.watch(recentlyPlayedSongsProvider(filterState.range));
      return asyncSongs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (songs) => LibraryRankedSongList(
          contentTopPadding: contentTopPadding,
          contentLeftPadding: contentLeftPadding,
          title: l10n.recentlyPlayed,
          subtitle: l10n.recentlyPlayedDescription,
          items: songs,
          selectedRange: filterState.range,
          onRangeChanged: (val) => filterNotifier.setRange(val),
          showTimeRange: false,
          centerAction: centerAction,
          headerTrailing: headerTrailing,
          emptyText: filterState.range == LibraryTimeRange.allTime
              ? l10n.noRecentlyPlayedSongs
              : l10n.noRecentlyPlayedInRange,
          trailingBuilder: (context, entry) => InsightMetricText(
            primary: formatRelativeInsightDate(context, entry.lastPlayedAt),
            secondary: l10n.playCountLabel(entry.playCount),
          ),
        ),
      );
    }
  }
}
