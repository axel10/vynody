import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import '../widgets/insight_metric_text.dart';
import '../widgets/library_selection_scope.dart';
import 'library_insight_tab.dart';

class RecentlyPlayedTab extends StatelessWidget {
  final double contentTopPadding;
  final double contentLeftPadding;

  const RecentlyPlayedTab({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LibraryInsightTab(
      filter: recentlyPlayedFilterProvider,
      watchSongs: (ref, range) => ref.watch(recentlyPlayedSongsProvider(range)),
      watchAlbums: (ref, range) =>
          ref.watch(recentlyPlayedAlbumsProvider(range)),
      selectionScope: LibrarySelectionScope.recentlyPlayed,
      title: l10n.recentlyPlayed,
      subtitle: l10n.recentlyPlayedDescription,
      emptyText: (loc, range) => range == LibraryTimeRange.allTime
          ? loc.noRecentlyPlayedSongs
          : loc.noRecentlyPlayedInRange,
      songTrailing: (context, entry) => InsightMetricText(
        primary: formatRelativeInsightDate(context, entry.lastPlayedAt),
        secondary: l10n.playCountLabel(entry.playCount),
      ),
      albumTrailing: (context, entry) => InsightMetricText(
        primary: formatRelativeInsightDate(context, entry.lastPlayedAt),
        secondary: l10n.playCountLabel(entry.totalPlayCount),
      ),
      contentTopPadding: contentTopPadding,
      contentLeftPadding: contentLeftPadding,
    );
  }
}
