import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/player/library/library_insights_service.dart';
import '../widgets/library_ranked_song_list.dart';

class MostPlayedTab extends ConsumerStatefulWidget {
  const MostPlayedTab({super.key});

  @override
  ConsumerState<MostPlayedTab> createState() => _MostPlayedTabState();
}

class _MostPlayedTabState extends ConsumerState<MostPlayedTab> {
  LibraryTimeRange _selectedRange = LibraryTimeRange.allTime;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final asyncItems = ref.watch(mostPlayedSongsProvider(_selectedRange));

    return asyncItems.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (items) => LibraryRankedSongList(
        title: l10n.mostPlayed,
        subtitle: l10n.mostPlayedDescription,
        items: items,
        selectedRange: _selectedRange,
        onRangeChanged: (value) {
          setState(() {
            _selectedRange = value;
          });
        },
        emptyText: _selectedRange == LibraryTimeRange.allTime
            ? l10n.noPlayHistory
            : l10n.noPlayHistoryInRange,
        trailingBuilder: (context, entry) => InsightMetricText(
          primary: l10n.playCountLabel(entry.playCount),
          secondary: entry.lastPlayedAt == null
              ? null
              : '${l10n.lastPlayed} ${formatInsightDate(context, entry.lastPlayedAt)}',
        ),
      ),
    );
  }
}
