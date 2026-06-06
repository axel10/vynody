import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/player/audio/audio_service.dart';
import 'package:vibe_flow/player/library/library_insights_service.dart';
import 'package:vibe_flow/player/library/playlist_service.dart';
import 'package:vibe_flow/utils/song_context_menu_utils.dart';
import 'package:vibe_flow/dialogs/transcode_dialog.dart';
import 'song_thumbnail.dart';
import 'library_selection_panel.dart';
import 'scroll_to_top_wrapper.dart';

class LibraryRankedSongList extends ConsumerStatefulWidget {
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
  ConsumerState<LibraryRankedSongList> createState() => _LibraryRankedSongListState();
}

class _LibraryRankedSongListState extends ConsumerState<LibraryRankedSongList> {
  bool _isSelectionMode = false;
  final Set<String> _selectedSongPaths = {};
  final ScrollController _scrollController = ScrollController();

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedSongPaths.clear();
        ref.read(librarySelectionActiveProvider.notifier).state = false;
      } else {
        ref.read(librarySelectionActiveProvider.notifier).state = true;
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
      ref.read(librarySelectionActiveProvider.notifier).state = false;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    Future.microtask(() {
      if (mounted) {
        ref.read(librarySelectionActiveProvider.notifier).state = false;
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final audio = ref.read(audioServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);

    final allSongs = widget.items.map((entry) => entry.song).toList();
    final selectedSongs = allSongs.where((song) => _selectedSongPaths.contains(song.path)).toList();

    void toggleSelectAll() {
      setState(() {
        if (_selectedSongPaths.length == allSongs.length) {
          _selectedSongPaths.clear();
        } else {
          _selectedSongPaths.addAll(allSongs.map((s) => s.path));
        }
      });
    }

    Widget currentBody = CustomScrollView(
      controller: _scrollController,
      cacheExtent: 1000,
      slivers: [
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 600;
              return Container(
                padding: EdgeInsets.fromLTRB(16, 16, 16, isWide ? 12 : 16),
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
                    if (isWide)
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
                                  widget.subtitle,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.items.isNotEmpty) ...[
                            FilledButton.icon(
                              onPressed: () {
                                audio.playPlaylist(allSongs);
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(l10n.playAll),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                final songs = List<MusicFile>.from(allSongs)..shuffle();
                                audio.playPlaylist(songs);
                              },
                              icon: const Icon(Icons.shuffle_rounded),
                              label: Text(l10n.shufflePlay),
                            ),
                          ],
                        ],
                      )
                    else
                      Column(
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
                            widget.subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (widget.items.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      audio.playPlaylist(allSongs);
                                    },
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: Text(l10n.playAll),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      final songs = List<MusicFile>.from(allSongs)..shuffle();
                                      audio.playPlaylist(songs);
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
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          for (int i = 0; i < LibraryTimeRange.values.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text(_timeRangeLabel(l10n, LibraryTimeRange.values[i])),
                              selected: widget.selectedRange == LibraryTimeRange.values[i],
                              onSelected: (_) => widget.onRangeChanged(LibraryTimeRange.values[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (widget.items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.emptyText,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 140 + (_isSelectionMode ? 220.0 : 0.0)),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = widget.items[index];
                  final isSelected = _selectedSongPaths.contains(entry.song.path);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SongListItem(
                      entry: entry,
                      index: index,
                      l10n: l10n,
                      audio: audio,
                      playlistService: playlistService,
                      items: widget.items,
                      trailingBuilder: widget.trailingBuilder,
                      isSelectionMode: _isSelectionMode,
                      isSelected: isSelected,
                      onTap: () {
                        if (_isSelectionMode) {
                          _toggleSelection(entry.song.path);
                        } else {
                          audio.playPlaylist(
                            allSongs,
                            initialIndex: index,
                          );
                        }
                      },
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          _toggleSelectionMode();
                          _toggleSelection(entry.song.path);
                        }
                      },
                    ),
                  );
                },
                childCount: widget.items.length,
              ),
            ),
          ),
      ],
    );

    return ScrollToTopWrapper(
      scrollController: _scrollController,
      bottomOffset: 140.0 + (_isSelectionMode ? 220.0 : 0.0),
      child: Stack(
        children: [
          currentBody,
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
                    allSongs: allSongs,
                    onToggleSelectAll: toggleSelectAll,
                    onCancel: _cancelSelection,
                  )
                : const SizedBox.shrink(key: ValueKey('library-selection-panel-hidden')),
          ),
        ),
      ],
    ),
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
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.onTap,
    required this.onLongPress,
  });

  final LibraryInsightSongEntry entry;
  final int index;
  final AppLocalizations l10n;
  final AudioService audio;
  final PlaylistService playlistService;
  final List<LibraryInsightSongEntry> items;
  final Widget Function(BuildContext, LibraryInsightSongEntry) trailingBuilder;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = entry.song;

    return RepaintBoundary(
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: isSelectionMode && isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerLow,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) async {
              if (!isSelectionMode) {
                await _showSongBottomSheet(context, song);
              }
            },
            child: ListTile(
              isThreeLine: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              selected: isSelectionMode ? isSelected : false,
              selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              leading: SizedBox(
                width: 72,
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: isSelectionMode
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (_) => onTap(),
                            )
                          : Text(
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

  Future<void> _showSongBottomSheet(
    BuildContext context,
    MusicFile song,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

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
