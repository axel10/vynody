import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/pages/album_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'playback_ui_tuning.dart';
import 'song_thumbnail.dart';

class LibraryRankedAlbumList extends ConsumerStatefulWidget {
  const LibraryRankedAlbumList({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
    this.selectedRange = LibraryTimeRange.allTime,
    this.onRangeChanged,
    this.showTimeRange = false,
    this.centerAction,
    this.headerTrailing,
    this.headerAction,
    required this.emptyText,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  final String title;
  final String subtitle;
  final List<TimeMachineAlbumEntry> items;
  final LibraryTimeRange selectedRange;
  final ValueChanged<LibraryTimeRange>? onRangeChanged;
  final bool showTimeRange;
  final Widget? centerAction;
  final Widget? headerTrailing;
  final Widget? headerAction;
  final String emptyText;
  final double contentTopPadding;
  final double contentLeftPadding;

  @override
  ConsumerState<LibraryRankedAlbumList> createState() => _LibraryRankedAlbumListState();
}

class _LibraryRankedAlbumListState extends ConsumerState<LibraryRankedAlbumList> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _isSearchExpanded = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<TimeMachineAlbumEntry> _filterItems(List<TimeMachineAlbumEntry> items) {
    if (_searchQuery.isEmpty) return items;
    final q = _searchQuery.toLowerCase();
    return items.where((entry) {
      final title = entry.album.toLowerCase();
      final artist = entry.artist.toLowerCase();
      return title.contains(q) || artist.contains(q);
    }).toList();
  }

  Widget _buildSearchField(ThemeData theme, AppLocalizations l10n) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: (val) {
        setState(() {
          _searchQuery = val.trim();
        });
      },
      decoration: InputDecoration(
        hintText: l10n.search,
        hintStyle: TextStyle(
          color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.6),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
        ),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: l10n.clearSearch,
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
              )
            : null,
        filled: true,
        fillColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      style: TextStyle(
        color: theme.colorScheme.onSecondaryContainer,
        fontSize: 14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    final filteredItems = _filterItems(widget.items);
    final allSongs = filteredItems.expand((e) => e.songs).toList();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null &&
            _searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        }
        return false;
      },
      child: Padding(
        padding: EdgeInsets.only(left: widget.contentLeftPadding),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (widget.contentTopPadding > 0)
              SliverToBoxAdapter(
                child: SizedBox(height: widget.contentTopPadding),
              ),
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 600;
                        return Container(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, isWide ? 12 : 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isWide)
                                if (widget.centerAction != null || widget.headerTrailing != null) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.title,
                                              style: theme.textTheme.headlineSmall?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _searchQuery.isNotEmpty
                                                  ? l10n.albumCount(filteredItems.length)
                                                  : widget.subtitle,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (widget.centerAction != null)
                                        widget.centerAction!,
                                      Expanded(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            if (widget.headerTrailing != null) widget.headerTrailing!,
                                            if (widget.headerAction != null) ...[
                                              const SizedBox(width: 8),
                                              widget.headerAction!,
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildSearchField(theme, l10n),
                                      ),
                                      if (allSongs.isNotEmpty) ...[
                                        const SizedBox(width: 16),
                                        FilledButton.icon(
                                          onPressed: () => audio.playPlaylist(allSongs),
                                          icon: const Icon(Icons.play_arrow_rounded),
                                          label: Text(l10n.playAll),
                                        ),
                                        const SizedBox(width: 12),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            final shuffled = List.of(allSongs)..shuffle();
                                            audio.playPlaylist(shuffled);
                                          },
                                          icon: const Icon(Icons.shuffle_rounded),
                                          label: Text(l10n.shufflePlay),
                                        ),
                                      ],
                                    ],
                                  ),
                                ] else
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.title,
                                              style: theme.textTheme.headlineSmall?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _searchQuery.isNotEmpty
                                                  ? l10n.albumCount(filteredItems.length)
                                                  : widget.subtitle,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 4,
                                        child: _buildSearchField(theme, l10n),
                                      ),
                                      const SizedBox(width: 16),
                                      if (allSongs.isNotEmpty) ...[
                                        FilledButton.icon(
                                          onPressed: () => audio.playPlaylist(allSongs),
                                          icon: const Icon(Icons.play_arrow_rounded),
                                          label: Text(l10n.playAll),
                                        ),
                                        const SizedBox(width: 12),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            final shuffled = List.of(allSongs)..shuffle();
                                            audio.playPlaylist(shuffled);
                                          },
                                          icon: const Icon(Icons.shuffle_rounded),
                                          label: Text(l10n.shufflePlay),
                                        ),
                                      ],
                                      if (widget.headerAction != null) ...[
                                        const SizedBox(width: 8),
                                        widget.headerAction!,
                                      ],
                                    ],
                                  )
                              else
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                widget.title,
                                                style: theme.textTheme.headlineSmall?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _searchQuery.isNotEmpty
                                                    ? l10n.albumCount(filteredItems.length)
                                                    : widget.subtitle,
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  color: theme.colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (widget.headerTrailing != null) ...[
                                          widget.headerTrailing!,
                                          const SizedBox(width: 6),
                                        ],
                                        if (widget.headerAction != null) ...[
                                          widget.headerAction!,
                                          const SizedBox(width: 4),
                                        ],
                                        IconButton(
                                          icon: Icon(
                                            _isSearchExpanded || _searchQuery.isNotEmpty
                                                ? Icons.search_off_rounded
                                                : Icons.search_rounded,
                                          ),
                                          tooltip: l10n.search,
                                          onPressed: () {
                                            setState(() {
                                              _isSearchExpanded = !_isSearchExpanded;
                                              if (_isSearchExpanded) {
                                                _searchFocusNode.requestFocus();
                                              } else {
                                                _searchController.clear();
                                                _searchQuery = '';
                                                _searchFocusNode.unfocus();
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    if (widget.centerAction != null) ...[
                                      const SizedBox(height: 12),
                                      Center(child: widget.centerAction!),
                                    ],
                                    AnimatedCrossFade(
                                      firstChild: const SizedBox.shrink(),
                                      secondChild: Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: _buildSearchField(theme, l10n),
                                      ),
                                      crossFadeState: (_isSearchExpanded || _searchQuery.isNotEmpty)
                                          ? CrossFadeState.showSecond
                                          : CrossFadeState.showFirst,
                                      duration: const Duration(milliseconds: 200),
                                    ),
                                    if (allSongs.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: FilledButton.icon(
                                              onPressed: () => audio.playPlaylist(allSongs),
                                              icon: const Icon(Icons.play_arrow_rounded),
                                              label: Text(l10n.playAll),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () {
                                                final shuffled = List.of(allSongs)..shuffle();
                                                audio.playPlaylist(shuffled);
                                              },
                                              icon: const Icon(Icons.shuffle_rounded),
                                              label: Text(l10n.shufflePlay),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (filteredItems.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.emptyText,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MiniPlayerUiTuning.getListBottomPadding(
                    context,
                    hasPlayingMusic: currentMusic != null,
                  ),
                ),
                sliver: SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final entry = filteredItems[index];
                          return _RankedAlbumTile(
                            index: index + 1,
                            entry: entry,
                            onTap: () {
                              if (entry.songs.isEmpty) return;
                              final albumSummary = AlbumSummary(
                                id: '${entry.album}|${entry.artist}',
                                title: entry.album,
                                artist: entry.artist,
                                songs: entry.songs,
                                representativeSong: entry.songs.first,
                                totalDurationMillis: entry.songs.fold<int>(
                                  0,
                                  (sum, s) => sum + (s.durationMillis ?? 0),
                                ),
                              );
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AlbumDetailPage(album: albumSummary),
                                ),
                              );
                            },
                            onPlay: () {
                              if (entry.songs.isNotEmpty) {
                                audio.playPlaylist(entry.songs);
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RankedAlbumTile extends StatelessWidget {
  const _RankedAlbumTile({
    required this.index,
    required this.entry,
    required this.onTap,
    required this.onPlay,
  });

  final int index;
  final TimeMachineAlbumEntry entry;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isTop3 = index <= 3;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isTop3
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SongThumbnail(
                path: entry.songs.isNotEmpty ? entry.songs.first.path : entry.album,
                artworkPath: entry.artworkPath,
                thumbnailPath: entry.thumbnailPath,
                size: 48,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.artist.isNotEmpty
                          ? '${entry.artist} • ${l10n.songCount(entry.songs.length)}'
                          : l10n.songCount(entry.songs.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.playCountLabel(entry.totalPlayCount),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.play_circle_outline_rounded, size: 24),
                tooltip: l10n.play,
                onPressed: onPlay,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
