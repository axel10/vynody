import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
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
  LibraryTimeRange _selectedRange = LibraryTimeRange.allTime;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final asyncItems = ref.watch(allRatedSongsProvider);

    return asyncItems.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (items) => LibraryRankedSongList(
        contentTopPadding: widget.contentTopPadding,
        contentLeftPadding: widget.contentLeftPadding,
        title: l10n.ratedSongs,
        subtitle: l10n.topRatedSubtitle,
        items: items,
        selectedRange: _selectedRange,
        onRangeChanged: (value) {
          setState(() {
            _selectedRange = value;
          });
        },
        emptyText: l10n.emptyTopRated,
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
      ),
    );
  }
}
