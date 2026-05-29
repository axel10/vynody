import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/models/album_summary.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/utils/song_context_menu_utils.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/song_thumbnail.dart';
import 'dart:io';

class AlbumDetailPage extends ConsumerWidget {
  const AlbumDetailPage({super.key, required this.album});

  final AlbumSummary album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final headerColor = theme.colorScheme.secondaryContainer.withValues(
      alpha: 0.65,
    );

    final isMacOS = Platform.isMacOS;
    final bool showCustomTitleBar =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    Widget content = Scaffold(
      appBar: AppBar(title: Text(album.title)),
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
                    tag: 'album-cover-${album.id}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SongThumbnail(
                        path: album.representativeSong.path,
                        id: album.representativeSong.id,
                        size: isWide
                            ? 220
                            : math.min(220, constraints.maxWidth),
                      ),
                    ),
                  );
                  final info = _AlbumInfo(
                    album: album,
                    onPlayAll: () => audio.playPlaylist(album.songs),
                    onShufflePlay: () =>
                        audio.playPlaylist(List.of(album.songs)..shuffle()),
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
            itemCount: album.songs.length,
            itemBuilder: (context, index) {
              final song = album.songs[index];
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
                  subtitle: Text(song.artist ?? l10n.unknownArtist),
                  trailing: durationLabel == null ? null : Text(durationLabel),
                  onTap: () =>
                      audio.playPlaylist(album.songs, initialIndex: index),
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

    if (showCustomTitleBar || isMacOS) {
      content = Material(
        color: theme.colorScheme.surface,
        child: Column(
          children: [
            if (showCustomTitleBar)
              DesktopWindowTitleBar(
                brightness: theme.brightness,
              )
            else
              const DragToMoveArea(child: SizedBox(height: 32)),
            Expanded(child: content),
          ],
        ),
      );
    }

    return content;
  }
}

class _AlbumInfo extends StatelessWidget {
  const _AlbumInfo({
    required this.album,
    required this.onPlayAll,
    required this.onShufflePlay,
  });

  final AlbumSummary album;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.albums,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          album.title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          album.artist,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${l10n.songCount(album.trackCount)} · ${_formatDuration(album.totalDurationMillis) ?? l10n.durationZero}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
