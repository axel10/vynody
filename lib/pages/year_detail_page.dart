import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/year_summary.dart';
import 'package:vynody/player/audio/playback_source.dart';
import '../widgets/collection_detail_content.dart';
import '../widgets/detail_page_shell.dart';
import '../widgets/library_selection_back_guard.dart';

class YearDetailPage extends StatelessWidget {
  const YearDetailPage({
    super.key,
    required this.year,
    this.onGoBack,
  });

  final YearSummary year;
  final VoidCallback? onGoBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final String title = year.labelWith(l10n.unknownYear);

    return LibrarySelectionBackGuard(
      child: DetailPageShell(
        title: title,
        titleKey: const ValueKey('year_title'),
        onGoBack: onGoBack,
        contentBuilder: (context, scrollController, topPadding) =>
            YearDetailContent(
          year: year,
          scrollController: scrollController,
          topPadding: topPadding,
        ),
      ),
    );
  }
}

class YearDetailContent extends StatelessWidget {
  const YearDetailContent({
    super.key,
    required this.year,
    this.showSelectionPanel = true,
    this.hasBottomPanel = false,
    this.scrollController,
    this.topPadding = 0.0,
  });

  final YearSummary year;
  final bool showSelectionPanel;
  final bool hasBottomPanel;
  final ScrollController? scrollController;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final String title = year.labelWith(l10n.unknownYear);

    return CollectionDetailContent(
      title: title,
      songCount: year.songCount,
      albumCount: year.albumCount,
      totalDurationMillis: year.totalDurationMillis,
      songs: year.songs,
      source: PlaybackSource(
        type: PlaybackSourceType.year,
        id: year.queryKey,
        name: title,
      ),
      showSelectionPanel: showSelectionPanel,
      hasBottomPanel: hasBottomPanel,
      scrollController: scrollController,
      topPadding: topPadding,
    );
  }
}
