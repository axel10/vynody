import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import '../widgets/insight_metric_text.dart';
import '../widgets/library_selection_scope.dart';
import 'library_insight_tab.dart';

class RecentlyAddedTab extends StatelessWidget {
  final double contentTopPadding;
  final double contentLeftPadding;

  const RecentlyAddedTab({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LibraryInsightTab(
      filter: recentlyAddedFilterProvider,
      watchSongs: (ref, range) => ref.watch(recentlyAddedSongsProvider(range)),
      watchAlbums: (ref, range) =>
          ref.watch(recentlyAddedAlbumsRankedProvider(range)),
      selectionScope: LibrarySelectionScope.recentlyAdded,
      title: l10n.recentlyAdded,
      subtitle: l10n.recentlyAddedDescription,
      emptyText: (loc, range) => range == LibraryTimeRange.allTime
          ? loc.noRecentlyAddedSongs
          : loc.noRecentlyAddedInRange,
      songTrailing: (context, entry) => InsightMetricText(
        primary: formatInsightDate(context, entry.createdAt),
        secondary: l10n.addedOn,
      ),
      albumTrailing: (context, entry) => InsightMetricText(
        primary: formatInsightDate(context, entry.latestAddedAt),
        secondary: l10n.addedOn,
      ),
      contentTopPadding: contentTopPadding,
      contentLeftPadding: contentLeftPadding,
    );
  }
}
