import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/models/album_summary.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/utils/song_context_menu_utils.dart';
import 'package:vibe_flow/dialogs/transcode_dialog.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/song_thumbnail.dart';
import '../widgets/mini_player_wrapper.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';

class AlbumDetailPage extends ConsumerStatefulWidget {
  const AlbumDetailPage({super.key, required this.album});

  final AlbumSummary album;

  @override
  ConsumerState<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends ConsumerState<AlbumDetailPage> {
  bool _isSelectionMode = false;
  final Set<String> _selectedSongPaths = {};

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedSongPaths.clear();
        ref.read(librarySelectionScopeProvider.notifier).clear();
      } else {
        ref
            .read(librarySelectionScopeProvider.notifier)
            .setScope(LibrarySelectionScope.library);
      }
    });
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedSongPaths.contains(path)) {
        _selectedSongPaths.remove(path);
      } else {
        _selectedSongPaths.add(path);
      }
    });
  }

  void _toggleSelectAll() {
    final allSongs = widget.album.songs;
    setState(() {
      if (_selectedSongPaths.length == allSongs.length) {
        _selectedSongPaths.clear();
      } else {
        _selectedSongPaths.addAll(allSongs.map((s) => s.path));
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelectionMode = false;
      _selectedSongPaths.clear();
      ref.read(librarySelectionScopeProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    Future.microtask(() {
      ref.read(librarySelectionScopeProvider.notifier).clear();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    final selectedSongs = widget.album.songs.where((song) => _selectedSongPaths.contains(song.path)).toList();

    Widget content = Scaffold(
      appBar: AppBar(title: Text(widget.album.title)),
      body: Stack(
        children: [
          CustomScrollView(
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
                        tag: 'album-cover-${widget.album.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: SongThumbnail(
                            path: widget.album.representativeSong.path,
                            id: widget.album.representativeSong.id,
                            size: isWide
                                ? 220
                                : math.min(220, constraints.maxWidth),
                          ),
                        ),
                      );
                      final info = _AlbumInfo(
                        album: widget.album,
                        onPlayAll: () => audio.playPlaylist(widget.album.songs),
                        onShufflePlay: () =>
                            audio.playPlaylist(List.of(widget.album.songs)..shuffle()),
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
                itemCount: widget.album.songs.length,
                itemBuilder: (context, index) {
                  final song = widget.album.songs[index];
                  final isCurrent = currentMusic?.path == song.path;
                  final isSelected = _selectedSongPaths.contains(song.path);
                  final durationLabel = _formatDuration(song.durationMillis);
                  final trackLabel = '${index + 1}'.padLeft(2, '0');

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapDown: (details) {
                      if (!_isSelectionMode) {
                        _showSongBottomSheet(context, ref, song);
                      }
                    },
                    onLongPress: () {
                      if (!_isSelectionMode) {
                        _toggleSelectionMode();
                        _toggleSelection(song.path);
                      }
                    },
                    child: ListTile(
                      selected: _isSelectionMode ? isSelected : isCurrent,
                      selectedTileColor: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.35),
                      leading: _isSelectionMode
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(song.path),
                            )
                          : SizedBox(
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
                      onTap: _isSelectionMode
                          ? () => _toggleSelection(song.path)
                          : () => audio.playPlaylist(widget.album.songs, initialIndex: index),
                    ),
                  );
                },
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: (currentMusic != null ? 120 : 20) + (_isSelectionMode ? 220.0 : 0.0),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              reverseDuration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final offsetAnimation = Tween<Offset>(
                  begin: const Offset(0, 1.0),
                  end: Offset.zero,
                ).animate(animation);
                return SlideTransition(position: offsetAnimation, child: child);
              },
              child: _isSelectionMode
                  ? LibrarySelectionPanel(
                      key: const ValueKey('library-selection-panel'),
                      selectedSongs: selectedSongs,
                      allSongs: widget.album.songs,
                      onToggleSelectAll: _toggleSelectAll,
                      onCancel: _cancelSelection,
                    )
                  : const SizedBox.shrink(key: ValueKey('library-selection-panel-hidden')),
            ),
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

    return MiniPlayerWrapper(child: content);
  }

  Future<void> _showSongBottomSheet(
    BuildContext context,
    WidgetRef ref,
    MusicFile song,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);

    final hasFilePath = song.path.trim().isNotEmpty;
    final canOpenLocation =
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
        hasFilePath;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: GestureDetector(
                  onTap: () {}, // Prevent taps on the card itself from closing the sheet
                  child: Material(
                    elevation: 16,
                    color: theme.colorScheme.surface,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header showing Song title and artwork
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: SongThumbnail(
                                    path: song.path,
                                    id: song.id,
                                    size: 52,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      song.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${song.artist ?? l10n.unknownArtist} · ${song.album ?? l10n.unknownAlbum}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          // Actions list
                          _buildBottomSheetItem(
                            context: context,
                            value: 'play_next',
                            label: l10n.playNext,
                            icon: Icons.queue_play_next_rounded,
                          ),
                          _buildBottomSheetItem(
                            context: context,
                            value: 'add_to_queue',
                            label: l10n.addToQueue,
                            icon: Icons.queue_music_rounded,
                          ),
                          _buildBottomSheetItem(
                            context: context,
                            value: 'add_to_playlist',
                            label: l10n.addToPlaylist,
                            icon: Icons.playlist_add_rounded,
                          ),
                          _buildBottomSheetItem(
                            context: context,
                            value: 'add_to_favorites',
                            label: l10n.addToFavorites,
                            icon: Icons.favorite_border_rounded,
                          ),
                          _buildBottomSheetItem(
                            context: context,
                            value: 'transcode',
                            label: l10n.transcodeAction,
                            icon: Icons.sync_rounded,
                          ),
                          _buildBottomSheetItem(
                            context: context,
                            value: 'copy_title',
                            label: l10n.copyTitle,
                            icon: Icons.title_rounded,
                          ),
                          _buildBottomSheetItem(
                            context: context,
                            value: 'copy_artist',
                            label: l10n.copyArtistName,
                            icon: Icons.person_rounded,
                          ),
                          if (canOpenLocation)
                            _buildBottomSheetItem(
                              context: context,
                              value: 'open_location',
                              label: l10n.openFileLocation,
                              icon: Icons.folder_open_rounded,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!context.mounted || selected == null) return;

    switch (selected) {
      case 'play_next':
        await audio.enqueueNext([song]);
        break;
      case 'add_to_queue':
        await audio.appendToQueue([song]);
        break;
      case 'add_to_playlist':
        await showAddSongsToPlaylistDialog(
          context,
          playlistService,
          [song],
        );
        break;
      case 'add_to_favorites':
        await playlistService.addSongToFavorite(song);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n.addToFavorites} · ${song.displayName}'),
            ),
          );
        }
        break;
      case 'transcode':
        await showTranscodeDialog(context, songs: [song]);
        break;
      case 'copy_title':
        await Clipboard.setData(ClipboardData(text: song.displayName));
        break;
      case 'copy_artist':
        if (song.artist != null) {
          await Clipboard.setData(ClipboardData(text: song.artist!));
        }
        break;
      case 'open_location':
        await openSongFileLocation(song.path);
        break;
    }
  }

  Widget _buildBottomSheetItem({
    required BuildContext context,
    required String value,
    required String label,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(
        label,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onTap: () => Navigator.pop(context, value),
    );
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
