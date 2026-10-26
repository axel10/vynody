import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import '../widgets/insight_metric_text.dart';
import '../widgets/library_selection_scope.dart';
import 'library_insight_tab.dart';

class MostPlayedTab extends StatelessWidget {
  final double contentTopPadding;
  final double contentLeftPadding;

  const MostPlayedTab({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LibraryInsightTab(
      filter: mostPlayedFilterProvider,
      watchSongs: (ref, range) => ref.watch(mostPlayedSongsProvider(range)),
      watchAlbums: (ref, range) => ref.watch(mostPlayedAlbumsProvider(range)),
      selectionScope: LibrarySelectionScope.mostPlayed,
      title: l10n.mostPlayed,
      emptyText: (loc, range) => range == LibraryTimeRange.allTime
          ? loc.noPlayHistory
          : loc.noPlayHistoryInRange,
      songTrailing: (context, entry) => InsightMetricText(
        primary: l10n.playCountLabel(entry.playCount),
        secondary: entry.lastPlayedAt == null
            ? null
            : formatInsightDate(context, entry.lastPlayedAt),
      ),
      contentTopPadding: contentTopPadding,
      contentLeftPadding: contentLeftPadding,
    );
  }
}
