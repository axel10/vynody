import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/models/artist_summary.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/utils/song_context_menu_utils.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/song_thumbnail.dart';
import '../widgets/mini_player_wrapper.dart';

class ArtistDetailPage extends ConsumerWidget {
  const ArtistDetailPage({super.key, required this.artist});

  final ArtistSummary artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget content = Scaffold(
      appBar: AppBar(title: Text(artist.name)),
      body: ArtistDetailContent(artist: artist),
    );

    final isMacOS = Platform.isMacOS;
    final bool showCustomTitleBar =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    if (showCustomTitleBar || isMacOS) {
      content = Material(
        color: theme.colorScheme.surface,
        child: Column(
          children: [
            if (showCustomTitleBar)
              DesktopWindowTitleBar(brightness: theme.brightness)
            else
              const DragToMoveArea(child: SizedBox(height: 32)),
            Expanded(child: content),
          ],
        ),
      );
    }

    return MiniPlayerWrapper(child: content);
  }
}

class ArtistDetailContent extends ConsumerWidget {
  const ArtistDetailContent({super.key, required this.artist});

  final ArtistSummary artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final unknownAlbumLabel = l10n.unknownAlbum;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final headerColor = theme.colorScheme.tertiaryContainer.withValues(
      alpha: 0.65,
    );
    final albumSections = _buildAlbumSections(artist.songs, unknownAlbumLabel);
    final displaySongs = albumSections
        .expand((section) => section.songs)
        .toList(growable: false);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [headerColor, theme.colorScheme.surface],
              ),
            ),
            child: _ArtistInfo(
              artist: artist,
              onPlayAll: () => audio.playPlaylist(displaySongs),
              onShufflePlay: () =>
                  audio.playPlaylist(List.of(displaySongs)..shuffle()),
            ),
          ),
        ),
        if (albumSections.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(l10n.emptyList, style: theme.textTheme.titleMedium),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            sliver: SliverList.builder(
              itemCount: albumSections.length,
              itemBuilder: (context, index) {
                final section = albumSections[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == albumSections.length - 1 ? 0 : 12,
                  ),
                  child: _AlbumSectionCard(
                    section: section,
                    currentMusic: currentMusic,
                    theme: theme,
                    onPlayAlbum: () => audio.playPlaylist(section.songs),
                    onShufflePlayAlbum: () =>
                        audio.playPlaylist(List.of(section.songs)..shuffle()),
                    onSongTap: (songIndex) => audio.playPlaylist(
                      displaySongs,
                      initialIndex: section.startIndex + songIndex,
                    ),
                    onSongSecondaryTapDown: (details, song) {
                      showSongContextMenu(
                        context,
                        details.globalPosition,
                        song: song,
                        onAddToPlaylist: () => showAddSongsToPlaylistDialog(
                          context,
                          ref.read(playlistServiceProvider),
                          [song],
                        ),
                      );
                    },
                    onSongLongPress: (song) {
                      showAddSongsToPlaylistDialog(
                        context,
                        ref.read(playlistServiceProvider),
                        [song],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: currentMusic != null ? 120 : 20),
        ),
      ],
    );
  }
}

class _ArtistInfo extends StatelessWidget {
  const _ArtistInfo({
    required this.artist,
    required this.onPlayAll,
    required this.onShufflePlay,
  });

  final ArtistSummary artist;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final artistCountLabel = l10n.songCount(artist.songCount);
    final artistsLabel = l10n.artists;
    final playAllLabel = l10n.playAll;
    final shufflePlayLabel = l10n.shufflePlay;
    final chips = <Widget>[
      _InfoChip(label: artistCountLabel),
      if (artist.country?.trim().isNotEmpty ?? false)
        _InfoChip(label: artist.country!.trim()),
      if (artist.beginDate?.trim().isNotEmpty ?? false)
        _InfoChip(label: artist.beginDate!.trim()),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          artistsLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          artist.name,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (artist.disambiguation?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 8),
          Text(
            artist.disambiguation!.trim(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (artist.areaName?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 8),
          Text(
            artist.areaName!.trim(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
        if (artist.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            artist.tags.take(6).join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onPlayAll,
              icon: const Icon(Icons.play_arrow),
              label: Text(playAllLabel),
            ),
            OutlinedButton.icon(
              onPressed: onShufflePlay,
              icon: const Icon(Icons.shuffle),
              label: Text(shufflePlayLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AlbumSectionCard extends StatelessWidget {
  const _AlbumSectionCard({
    required this.section,
    required this.currentMusic,
    required this.theme,
    required this.onPlayAlbum,
    required this.onShufflePlayAlbum,
    required this.onSongTap,
    required this.onSongSecondaryTapDown,
    required this.onSongLongPress,
  });

  final _AlbumSection section;
  final MusicFile? currentMusic;
  final ThemeData theme;
  final VoidCallback onPlayAlbum;
  final VoidCallback onShufflePlayAlbum;
  final ValueChanged<int> onSongTap;
  final void Function(TapDownDetails details, MusicFile song)
  onSongSecondaryTapDown;
  final ValueChanged<MusicFile> onSongLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final durationLabel =
        _formatDuration(section.totalDurationMillis) ?? l10n.durationZero;
    final countLabel = l10n.songCount(section.songs.length);
    final subtitle = '$countLabel · $durationLabel';

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 500;
                final cover = ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SongThumbnail(
                    path: section.representativeSong.path,
                    id: section.representativeSong.id,
                    size: 104,
                  ),
                );
                final info = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: onPlayAlbum,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l10n.playAll),
                        ),
                        OutlinedButton.icon(
                          onPressed: onShufflePlayAlbum,
                          icon: const Icon(Icons.shuffle),
                          label: Text(l10n.shufflePlay),
                        ),
                      ],
                    ),
                  ],
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cover,
                      const SizedBox(width: 16),
                      Expanded(child: info),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(alignment: Alignment.centerLeft, child: cover),
                    const SizedBox(height: 16),
                    info,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.35,
                  ),
                ),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < section.songs.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 16,
                        endIndent: 16,
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    _AlbumSongTile(
                      song: section.songs[i],
                      isCurrent: currentMusic?.path == section.songs[i].path,
                      theme: theme,
                      onTap: () => onSongTap(i),
                      onSecondaryTapDown: (details) =>
                          onSongSecondaryTapDown(details, section.songs[i]),
                      onLongPress: () => onSongLongPress(section.songs[i]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumSongTile extends StatelessWidget {
  const _AlbumSongTile({
    required this.song,
    required this.isCurrent,
    required this.theme,
    required this.onTap,
    required this.onSecondaryTapDown,
    required this.onLongPress,
  });

  final MusicFile song;
  final bool isCurrent;
  final ThemeData theme;
  final VoidCallback onTap;
  final void Function(TapDownDetails details) onSecondaryTapDown;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final durationLabel = _formatDuration(song.durationMillis);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTapDown,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        selected: isCurrent,
        selectedTileColor: theme.colorScheme.primaryContainer.withValues(
          alpha: 0.35,
        ),

        title: Text(
          song.displayName,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: isCurrent ? theme.colorScheme.primary : null,
            fontWeight: isCurrent ? FontWeight.w700 : null,
          ),
        ),
        trailing: durationLabel == null ? null : Text(durationLabel),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

String? _formatDuration(int? durationMs) {
  if (durationMs == null) return null;
  final duration = Duration(milliseconds: durationMs);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${duration.inMinutes}:${seconds.toString().padLeft(2, '0')}';
}

class _AlbumSection {
  const _AlbumSection({
    required this.title,
    required this.songs,
    required this.representativeSong,
    required this.totalDurationMillis,
    required this.startIndex,
  });

  final String title;
  final List<MusicFile> songs;
  final MusicFile representativeSong;
  final int totalDurationMillis;
  final int startIndex;

}

List<_AlbumSection> _buildAlbumSections(
  List<MusicFile> songs,
  String unknownAlbumLabel,
) {
  final grouped = <String, List<MusicFile>>{};
  final titles = <String, String>{};
  final unknownKey = unknownAlbumLabel.toLowerCase();

  for (final song in songs) {
    final rawAlbum = song.album?.trim();
    final isUnknown = rawAlbum == null || rawAlbum.isEmpty;
    final normalizedTitle = isUnknown ? unknownAlbumLabel : rawAlbum;
    final key = normalizedTitle.toLowerCase();

    grouped.putIfAbsent(key, () => <MusicFile>[]).add(song);
    titles[key] = normalizedTitle;
  }

  final orderedKeys = grouped.keys.toList()
    ..sort((a, b) {
      final leftUnknown = a == unknownKey;
      final rightUnknown = b == unknownKey;
      if (leftUnknown != rightUnknown) {
        return leftUnknown ? 1 : -1;
      }
      return titles[a]!.toLowerCase().compareTo(titles[b]!.toLowerCase());
    });

  final sections = <_AlbumSection>[];
  var startIndex = 0;

  for (final key in orderedKeys) {
    final albumSongs = List<MusicFile>.from(grouped[key]!)
      ..sort(_compareAlbumSongs);
    final representativeSong = albumSongs.firstWhere(
      (song) => _hasArtwork(song),
      orElse: () => albumSongs.first,
    );
    final totalDurationMillis = albumSongs.fold<int>(
      0,
      (sum, song) => sum + (song.durationMillis ?? 0),
    );
    final title = titles[key]!;

    sections.add(
      _AlbumSection(
        title: title,
        songs: albumSongs,
        representativeSong: representativeSong,
        totalDurationMillis: totalDurationMillis,
        startIndex: startIndex,
      ),
    );
    startIndex += albumSongs.length;
  }

  return sections;
}

bool _hasArtwork(MusicFile song) {
  final hasBytes = song.artworkBytes?.isNotEmpty ?? false;
  final hasArtworkPath = song.artworkPath?.isNotEmpty ?? false;
  final hasThumbnailPath = song.thumbnailPath?.isNotEmpty ?? false;
  return hasBytes || hasArtworkPath || hasThumbnailPath;
}

int _compareAlbumSongs(MusicFile a, MusicFile b) {
  final leftTrack = a.trackNumber;
  final rightTrack = b.trackNumber;
  if (leftTrack != null && rightTrack != null && leftTrack != rightTrack) {
    return leftTrack.compareTo(rightTrack);
  }
  if (leftTrack != null && rightTrack == null) return -1;
  if (leftTrack == null && rightTrack != null) return 1;

  final titleCompare = a.displayName.toLowerCase().compareTo(
    b.displayName.toLowerCase(),
  );
  if (titleCompare != 0) return titleCompare;
  return a.path.toLowerCase().compareTo(b.path.toLowerCase());
}
