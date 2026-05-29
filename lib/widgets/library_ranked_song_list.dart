import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/player/audio/audio_service.dart';
import 'package:vibe_flow/player/library/library_insights_service.dart';
import 'package:vibe_flow/player/library/playlist_service.dart';
import 'package:vibe_flow/utils/song_context_menu_utils.dart';
import 'song_thumbnail.dart';

class LibraryRankedSongList extends ConsumerWidget {
  const LibraryRankedSongList({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.selectedRange,
    required this.onRangeChanged,
    required this.emptyText,
    required this.trailingBuilder,
  });

  final String title;
  final String subtitle;
  final List<LibraryInsightSongEntry> items;
  final LibraryTimeRange selectedRange;
  final ValueChanged<LibraryTimeRange> onRangeChanged;
  final String emptyText;
  final Widget Function(BuildContext, LibraryInsightSongEntry) trailingBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final audio = ref.read(audioServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (items.isNotEmpty) ...[
                    FilledButton.tonalIcon(
                      onPressed: () {
                        audio.playPlaylist(
                          items
                              .map((entry) => entry.song)
                              .toList(growable: false),
                        );
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l10n.playAll),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        final songs = items.map((entry) => entry.song).toList()
                          ..shuffle();
                        audio.playPlaylist(songs);
                      },
                      icon: const Icon(Icons.shuffle_rounded),
                      label: Text(l10n.shufflePlay),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final range in LibraryTimeRange.values)
                    ChoiceChip(
                      label: Text(_timeRangeLabel(l10n, range)),
                      selected: selectedRange == range,
                      onSelected: (_) => onRangeChanged(range),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      emptyText,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
                : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 140),
                  itemCount: items.length,
                  cacheExtent: 1000,
                  prototypeItem: items.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _SongListItem(
                            entry: items.first,
                            index: 0,
                            l10n: l10n,
                            audio: audio,
                            playlistService: playlistService,
                            items: items,
                            trailingBuilder: trailingBuilder,
                          ),
                        )
                      : null,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SongListItem(
                        entry: items[index],
                        index: index,
                        l10n: l10n,
                        audio: audio,
                        playlistService: playlistService,
                        items: items,
                        trailingBuilder: trailingBuilder,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _timeRangeLabel(AppLocalizations l10n, LibraryTimeRange range) {
    return switch (range) {
      LibraryTimeRange.allTime => l10n.allTime,
      LibraryTimeRange.last7Days => l10n.pastWeek,
      LibraryTimeRange.last30Days => l10n.pastMonth,
      LibraryTimeRange.last90Days => l10n.past90Days,
    };
  }
}

class _SongListItem extends StatelessWidget {
  const _SongListItem({
    required this.entry,
    required this.index,
    required this.l10n,
    required this.audio,
    required this.playlistService,
    required this.items,
    required this.trailingBuilder,
  });

  final LibraryInsightSongEntry entry;
  final int index;
  final AppLocalizations l10n;
  final AudioService audio;
  final PlaylistService playlistService;
  final List<LibraryInsightSongEntry> items;
  final Widget Function(BuildContext, LibraryInsightSongEntry) trailingBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = entry.song;

    return RepaintBoundary(
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            audio.playPlaylist(
              items.map((item) => item.song).toList(growable: false),
              initialIndex: index,
            );
          },
          onLongPress: () async {
            await showAddSongsToPlaylistDialog(
              context,
              playlistService,
              [song],
            );
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) async {
              await showSongContextMenu(
                context,
                details.globalPosition,
                song: song,
                onAddToPlaylist: () => showAddSongsToPlaylistDialog(
                  context,
                  playlistService,
                  [song],
                ),
              );
            },
            child: ListTile(
              isThreeLine: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              leading: SizedBox(
                width: 72,
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SongThumbnail(
                      path: song.path,
                      id: song.id,
                      size: 40,
                    ),
                  ],
                ),
              ),
              title: Text(
                song.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _songSubtitle(l10n, song),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 96),
                child: trailingBuilder(context, entry),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _songSubtitle(AppLocalizations l10n, MusicFile song) {
    final artist = isVisibleSongText(song.artist)
        ? song.artist!.trim()
        : l10n.unknownArtist;
    final album = isVisibleSongText(song.album)
        ? song.album!.trim()
        : l10n.unknownAlbum;
    return '$artist · $album';
  }
}

class InsightMetricText extends StatelessWidget {
  const InsightMetricText({super.key, required this.primary, this.secondary});

  final String primary;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          primary,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.right,
        ),
        if (secondary != null) ...[
          const SizedBox(height: 2),
          Text(
            secondary!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ],
    );
  }
}

String formatInsightDate(BuildContext context, int? millis) {
  if (millis == null) return '';
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMd(
    locale,
  ).format(DateTime.fromMillisecondsSinceEpoch(millis));
}
