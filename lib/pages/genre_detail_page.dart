import 'package:flutter/material.dart';

import 'package:vynody/models/genre_summary.dart';
import 'package:vynody/player/audio/playback_source.dart';
import '../widgets/collection_detail_content.dart';
import '../widgets/detail_page_shell.dart';
import '../widgets/library_selection_back_guard.dart';

class GenreDetailPage extends StatelessWidget {
  const GenreDetailPage({
    super.key,
    required this.genre,
    this.onGoBack,
  });

  final GenreSummary genre;
  final VoidCallback? onGoBack;

  @override
  Widget build(BuildContext context) {
    return LibrarySelectionBackGuard(
      child: DetailPageShell(
        title: genre.name,
        titleKey: const ValueKey('genre_title'),
        onGoBack: onGoBack,
        contentBuilder: (context, scrollController, topPadding) =>
            GenreDetailContent(
          genre: genre,
          scrollController: scrollController,
          topPadding: topPadding,
        ),
      ),
    );
  }
}

class GenreDetailContent extends StatelessWidget {
  const GenreDetailContent({
    super.key,
    required this.genre,
    this.showSelectionPanel = true,
    this.hasBottomPanel = false,
    this.scrollController,
    this.topPadding = 0.0,
  });

  final GenreSummary genre;
  final bool showSelectionPanel;
  final bool hasBottomPanel;
  final ScrollController? scrollController;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return CollectionDetailContent(
      title: genre.name,
      songCount: genre.songCount,
      albumCount: genre.albumCount,
      totalDurationMillis: genre.totalDurationMillis,
      songs: genre.songs,
      source: PlaybackSource(
        type: PlaybackSourceType.genre,
        id: genre.queryKey,
        name: genre.name,
      ),
      showSelectionPanel: showSelectionPanel,
      hasBottomPanel: hasBottomPanel,
      scrollController: scrollController,
      topPadding: topPadding,
    );
  }
}
