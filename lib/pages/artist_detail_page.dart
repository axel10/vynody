import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/models/artist_summary.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/utils/song_context_menu_utils.dart';
import 'package:vibe_flow/dialogs/transcode_dialog.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/song_thumbnail.dart';
import '../widgets/mini_player_wrapper.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';

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

class ArtistDetailContent extends ConsumerStatefulWidget {
  const ArtistDetailContent({super.key, required this.artist});

  final ArtistSummary artist;

  @override
  ConsumerState<ArtistDetailContent> createState() => _ArtistDetailContentState();
}

class _ArtistDetailContentState extends ConsumerState<ArtistDetailContent> {
  bool _isSelectionMode = false;
  final Set<String> _selectedSongPaths = {};
  late final LibrarySelectionScopeController _librarySelectionScopeController;

  @override
  void initState() {
    super.initState();
    _librarySelectionScopeController =
        ref.read(librarySelectionScopeProvider.notifier);
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedSongPaths.clear();
        _librarySelectionScopeController.clear();
      } else {
        _librarySelectionScopeController.setScope(
          LibrarySelectionScope.library,
        );
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

  void _cancelSelection() {
    setState(() {
      _isSelectionMode = false;
      _selectedSongPaths.clear();
      _librarySelectionScopeController.clear();
    });
  }

  @override
  void dispose() {
    Future.microtask(() {
      _librarySelectionScopeController.clear();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final unknownAlbumLabel = l10n.unknownAlbum;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final headerColor = theme.colorScheme.tertiaryContainer.withValues(
      alpha: 0.65,
    );
    final albumSections = _buildAlbumSections(widget.artist.songs, unknownAlbumLabel);
    final displaySongs = albumSections
        .expand((section) => section.songs)
        .toList(growable: false);

    final selectedSongs = displaySongs.where((song) => _selectedSongPaths.contains(song.path)).toList();

    void toggleSelectAll() {
      setState(() {
        if (_selectedSongPaths.length == displaySongs.length) {
          _selectedSongPaths.clear();
        } else {
          _selectedSongPaths.addAll(displaySongs.map((s) => s.path));
        }
      });
    }

    return Stack(
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
                child: _ArtistInfo(
                  artist: widget.artist,
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
                        onSongTap: (songIndex) {
                          final song = section.songs[songIndex];
                          if (_isSelectionMode) {
                            _toggleSelection(song.path);
                          } else {
                            audio.playPlaylist(
                              displaySongs,
                              initialIndex: section.startIndex + songIndex,
                            );
                          }
                        },
                        onSongSecondaryTapDown: (details, song) {
                          if (!_isSelectionMode) {
                            _showSongBottomSheet(context, ref, song);
                          }
                        },
                        onSongLongPress: (song) {
                          if (!_isSelectionMode) {
                            _toggleSelectionMode();
                            _toggleSelection(song.path);
                          }
                        },
                        isSelectionMode: _isSelectionMode,
                        selectedSongPaths: _selectedSongPaths,
                      ),
                    );
                  },
                ),
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
                    allSongs: displaySongs,
                    onToggleSelectAll: toggleSelectAll,
                    onCancel: _cancelSelection,
                  )
                : const SizedBox.shrink(key: ValueKey('library-selection-panel-hidden')),
          ),
        ),
      ],
    );
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
    this.isSelectionMode = false,
    required this.selectedSongPaths,
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
  final bool isSelectionMode;
  final Set<String> selectedSongPaths;

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
                      isSelectionMode: isSelectionMode,
                      isSelected: selectedSongPaths.contains(section.songs[i].path),
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
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  final MusicFile song;
  final bool isCurrent;
  final ThemeData theme;
  final VoidCallback onTap;
  final void Function(TapDownDetails details) onSecondaryTapDown;
  final VoidCallback onLongPress;
  final bool isSelectionMode;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final durationLabel = _formatDuration(song.durationMillis);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTapDown,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        selected: isSelectionMode ? isSelected : isCurrent,
        selectedTileColor: theme.colorScheme.primaryContainer.withValues(
          alpha: 0.35,
        ),
        leading: isSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => onTap(),
              )
            : null,
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
