import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/artist_summary.dart';
import '../player/audio_riverpod.dart';
import '../utils/song_context_menu_utils.dart';
import '../widgets/desktop_window_title_bar.dart';

class ArtistDetailPage extends ConsumerWidget {
  const ArtistDetailPage({super.key, required this.artist});

  final ArtistSummary artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final headerColor = theme.colorScheme.tertiaryContainer.withValues(
      alpha: 0.65,
    );

    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    Widget content = Scaffold(
      appBar: AppBar(title: Text(artist.name)),
      body: CustomScrollView(
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 700;
                  final cover = Hero(
                    tag: 'artist-cover-${artist.queryKey}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: _ArtistCover(
                        artist: artist,
                        size: isWide ? 220 : math.min(220, constraints.maxWidth),
                      ),
                    ),
                  );
                  final info = _ArtistInfo(
                    artist: artist,
                    onPlayAll: () => audio.playPlaylist(artist.songs),
                    onShufflePlay: () =>
                        audio.playPlaylist(List.of(artist.songs)..shuffle()),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        cover,
                        const SizedBox(width: 24),
                        Expanded(child: info),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: cover),
                      const SizedBox(height: 20),
                      info,
                    ],
                  );
                },
              ),
            ),
          ),
          SliverList.builder(
            itemCount: artist.songs.length,
            itemBuilder: (context, index) {
              final song = artist.songs[index];
              final isCurrent = currentMusic?.path == song.path;
              final durationLabel = _formatDuration(song.durationMillis);
              final trackLabel = '${index + 1}'.padLeft(2, '0');

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) {
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
                child: ListTile(
                  selected: isCurrent,
                  selectedTileColor: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.35),
                  leading: SizedBox(
                    width: 32,
                    child: Text(
                      trackLabel,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isCurrent ? theme.colorScheme.primary : null,
                        fontWeight: isCurrent ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                  title: Text(
                    song.displayName,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: isCurrent ? theme.colorScheme.primary : null,
                      fontWeight: isCurrent ? FontWeight.w700 : null,
                    ),
                  ),
                  subtitle: Text(song.album ?? l10n.unknownAlbum),
                  trailing: durationLabel == null ? null : Text(durationLabel),
                  onTap: () =>
                      audio.playPlaylist(artist.songs, initialIndex: index),
                  onLongPress: () {
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
        ],
      ),
    );

    if (isDesktop) {
      content = Material(
        color: theme.colorScheme.surface,
        child: Column(
          children: [
            DesktopWindowTitleBar(
              brightness: theme.brightness,
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return content;
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
    final chips = <Widget>[
      _InfoChip(label: l10n.songCount(artist.songCount)),
      if (artist.country != null && artist.country!.trim().isNotEmpty)
        _InfoChip(label: artist.country!.trim()),
      if (artist.beginDate != null && artist.beginDate!.trim().isNotEmpty)
        _InfoChip(label: artist.beginDate!.trim()),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.artists,
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
        if (artist.disambiguation != null &&
            artist.disambiguation!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            artist.disambiguation!.trim(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (artist.areaName != null && artist.areaName!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            artist.areaName!.trim(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips,
        ),
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
              label: Text(l10n.playAll),
            ),
            OutlinedButton.icon(
              onPressed: onShufflePlay,
              icon: const Icon(Icons.shuffle),
              label: Text(l10n.shufflePlay),
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

class _ArtistCover extends StatelessWidget {
  const _ArtistCover({required this.artist, required this.size});

  final ArtistSummary artist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = artist.imageUrl?.trim();
    if (imageUrl == null || imageUrl.isEmpty) {
      return _fallback(theme);
    }

    return Image.network(
      imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _fallback(theme),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: size,
          height: size,
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      },
    );
  }

  Widget _fallback(ThemeData theme) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
            theme.colorScheme.secondaryContainer.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Icon(
        Icons.person_rounded,
        size: 54,
        color: theme.colorScheme.onPrimaryContainer,
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
