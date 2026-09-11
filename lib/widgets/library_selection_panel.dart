import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/dialogs/transcode_dialog.dart';
import 'package:vynody/dialogs/song_details_dialog.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/l10n/app_localizations.dart';

class LibrarySelectionPanel extends ConsumerStatefulWidget {
  const LibrarySelectionPanel({
    super.key,
    required this.selectedSongs,
    required this.allSongs,
    required this.onToggleSelectAll,
    required this.onCancel,
    this.onDelete,
    this.deleteLabel,
    this.title,
    this.onOpenLocation,
    this.openLocationLabel,
    this.onImportLyrics,
    this.replaceFavoritesWithSongDetails = false,
    this.hideSongProperties = false,
    this.hideSecondaryActions = false,
    this.onPlayNext,
    this.onAddToQueue,
    this.onAddToPlaylist,
    this.onAddToFavorites,
    this.onAddToCloudFavorites,
    this.favoritesLabel,
    this.cloudFavoritesLabel,
    this.cloudFavoritesIcon,
    this.onDownload,
    this.onTranscode,
    this.isSelectionEmpty,
    this.isAllSelected,
  });

  final List<MusicFile> selectedSongs;
  final List<MusicFile> allSongs;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;
  final String? deleteLabel;
  final String? title;
  final VoidCallback? onOpenLocation;
  final String? openLocationLabel;
  final VoidCallback? onImportLyrics;
  final bool replaceFavoritesWithSongDetails;
  final bool hideSongProperties;
  final bool hideSecondaryActions;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onAddToFavorites;
  final VoidCallback? onAddToCloudFavorites;
  final String? favoritesLabel;
  final String? cloudFavoritesLabel;
  final IconData? cloudFavoritesIcon;
  final VoidCallback? onDownload;
  final VoidCallback? onTranscode;
  final bool? isSelectionEmpty;
  final bool? isAllSelected;

  @override
  ConsumerState<LibrarySelectionPanel> createState() =>
      _LibrarySelectionPanelState();
}

class _LibrarySelectionPanelState extends ConsumerState<LibrarySelectionPanel> {
  final ScrollController _scrollController = ScrollController();

  static const double _singleRowHeight = 58.0;
  static const double _rowSpacing = 8.0;
  static const double _maxVisibleRows = 2.0;
  static const double _maxActionAreaHeight =
      (_singleRowHeight * _maxVisibleRows) +
      (_rowSpacing * (_maxVisibleRows - 1));

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final audio = ref.read(audioServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);

    final isAllSelected = widget.isAllSelected ??
        (widget.selectedSongs.length == widget.allSongs.length &&
            widget.allSongs.isNotEmpty);
    final isEmpty = widget.isSelectionEmpty ?? widget.selectedSongs.isEmpty;
    final isSingleSelected = !isEmpty && widget.selectedSongs.length == 1;

    final isRemote = widget.selectedSongs.isNotEmpty &&
        RemoteMediaResolver.isRemoteUri(widget.selectedSongs.first.path);
    final hasFilePath = isSingleSelected &&
        widget.selectedSongs.isNotEmpty &&
        widget.selectedSongs.first.path.trim().isNotEmpty &&
        !isRemote;
    final canOpenLocation =
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
        (widget.onOpenLocation != null || hasFilePath);

    final selectAllText = isAllSelected ? l10n.deselectAll : l10n.selectAll;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final primaryRow = Row(
      children: [
        Expanded(
          child: _buildSelectionActionButton(
            context: context,
            icon: isAllSelected ? Icons.deselect : Icons.select_all,
            label: selectAllText,
            onPressed: (widget.allSongs.isEmpty && widget.isAllSelected == null)
                ? null
                : widget.onToggleSelectAll,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSelectionActionButton(
            context: context,
            icon: Icons.queue_play_next_rounded,
            label: l10n.playNext,
            onPressed: isEmpty
                ? null
                : () async {
                    if (widget.onPlayNext != null) {
                      widget.onPlayNext!();
                    } else {
                      await audio.enqueueNext(widget.selectedSongs);
                      widget.onCancel();
                    }
                  },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSelectionActionButton(
            context: context,
            icon: Icons.queue_music_rounded,
            label: l10n.addToQueue,
            onPressed: isEmpty
                ? null
                : () async {
                    if (widget.onAddToQueue != null) {
                      widget.onAddToQueue!();
                    } else {
                      await audio.appendToQueue(widget.selectedSongs);
                      widget.onCancel();
                    }
                  },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSelectionActionButton(
            context: context,
            icon: Icons.playlist_add_rounded,
            label: l10n.addToPlaylist,
            onPressed: isEmpty
                ? null
                : () async {
                    if (widget.onAddToPlaylist != null) {
                      widget.onAddToPlaylist!();
                    } else {
                      await showAddSongsToPlaylistDialog(
                        context,
                        playlistService,
                        widget.selectedSongs,
                      );
                      widget.onCancel();
                    }
                  },
          ),
        ),
      ],
    );

    final List<Widget> secondaryActionRows = [];
    if (!widget.hideSecondaryActions) {
      final secondaryActions = <Widget>[];

      if (widget.replaceFavoritesWithSongDetails) {
        if (!widget.hideSongProperties) {
          secondaryActions.add(
            _buildSelectionActionButton(
              context: context,
              icon: Icons.info_outline_rounded,
              label: l10n.songProperties,
              onPressed: widget.selectedSongs.length == 1
                  ? () => showSongDetailsDialog(
                        context,
                        widget.selectedSongs.first,
                      )
                  : null,
            ),
          );
        }
        secondaryActions.add(
          _buildSelectionActionButton(
            context: context,
            icon: Icons.sync_rounded,
            label: l10n.transcodeAction,
            onPressed: isEmpty
                ? null
                : () async {
                    if (widget.onTranscode != null) {
                      widget.onTranscode!();
                    } else {
                      await showTranscodeDialog(
                        context,
                        songs: widget.selectedSongs,
                      );
                      widget.onCancel();
                    }
                  },
          ),
        );
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          if (widget.onOpenLocation != null || hasFilePath) {
            secondaryActions.add(
              _buildSelectionActionButton(
                context: context,
                icon: Icons.folder_open_rounded,
                label: widget.openLocationLabel ?? l10n.openFileLocation,
                onPressed: canOpenLocation
                    ? () async {
                        if (widget.onOpenLocation != null) {
                          widget.onOpenLocation!();
                        } else {
                          await openSongFileLocation(
                            widget.selectedSongs.first.path,
                          );
                        }
                        widget.onCancel();
                      }
                    : null,
              ),
            );
          }
        } else {
          secondaryActions.add(
            _buildSelectionActionButton(
              context: context,
              icon: Icons.lyrics_outlined,
              label: l10n.importLyrics,
              onPressed: isSingleSelected
                  ? () async {
                      if (widget.onImportLyrics != null) {
                        widget.onImportLyrics!();
                      } else {
                        await importLyricsForSong(
                          context,
                          ref,
                          widget.selectedSongs.first,
                        );
                      }
                      widget.onCancel();
                    }
                  : null,
            ),
          );
        }
        if (widget.onDownload != null) {
          secondaryActions.add(
            _buildSelectionActionButton(
              context: context,
              icon: Icons.download_rounded,
              label: l10n.downloadSong.contains('下载') ? '下载' : 'Download',
              onPressed: isEmpty ? null : widget.onDownload,
            ),
          );
        }
        if (widget.onDelete != null) {
          secondaryActions.add(
            _buildSelectionActionButton(
              context: context,
              icon: Icons.delete_outline_rounded,
              label: widget.deleteLabel ?? l10n.delete,
              onPressed: isEmpty ? null : widget.onDelete,
            ),
          );
        }
      } else {
        secondaryActions.add(
          _buildSelectionActionButton(
            context: context,
            icon: Icons.favorite_rounded,
            label: widget.favoritesLabel ??
                (widget.onAddToCloudFavorites != null
                    ? l10n.addToLocalFavorites
                    : l10n.addToFavorites),
            onPressed: isEmpty
                ? null
                : () async {
                    if (widget.onAddToFavorites != null) {
                      widget.onAddToFavorites!();
                    } else {
                      await playlistService.addSongsToPlaylist(
                        PlaylistService.favoritePlaylistId,
                        widget.selectedSongs,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.addedToPlaylist(
                                widget.selectedSongs.length,
                                l10n.favorites,
                              ),
                            ),
                          ),
                        );
                      }
                      widget.onCancel();
                    }
                  },
          ),
        );
        if (widget.onAddToCloudFavorites != null) {
          secondaryActions.add(
            _buildSelectionActionButton(
              context: context,
              icon: widget.cloudFavoritesIcon ?? Icons.cloud_done_rounded,
              label: widget.cloudFavoritesLabel ?? l10n.addToCloudFavorites,
              onPressed: isEmpty ? null : widget.onAddToCloudFavorites,
            ),
          );
        }
        secondaryActions.add(
          _buildSelectionActionButton(
            context: context,
            icon: Icons.sync_rounded,
            label: l10n.transcodeAction,
            onPressed: isEmpty
                ? null
                : () async {
                    if (widget.onTranscode != null) {
                      widget.onTranscode!();
                    } else {
                      await showTranscodeDialog(
                        context,
                        songs: widget.selectedSongs,
                      );
                      widget.onCancel();
                    }
                  },
          ),
        );
        if (!widget.hideSongProperties) {
          secondaryActions.add(
            _buildSelectionActionButton(
              context: context,
              icon: Icons.info_outline_rounded,
              label: l10n.songProperties,
              onPressed: isSingleSelected
                  ? () => showSongDetailsDialog(
                        context,
                        widget.selectedSongs.first,
                      )
                  : null,
            ),
          );
        }
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          if (widget.onOpenLocation != null || hasFilePath) {
            secondaryActions.add(
              _buildSelectionActionButton(
                context: context,
                icon: Icons.folder_open_rounded,
                label: widget.openLocationLabel ?? l10n.openFileLocation,
                onPressed: canOpenLocation
                    ? () async {
                        if (widget.onOpenLocation != null) {
                          widget.onOpenLocation!();
                        } else {
                          await openSongFileLocation(
                            widget.selectedSongs.first.path,
                          );
                        }
                        widget.onCancel();
                      }
                    : null,
              ),
            );
          }
        } else {
          secondaryActions.add(
            _buildSelectionActionButton(
              context: context,
              icon: Icons.lyrics_outlined,
              label: l10n.importLyrics,
              onPressed: isSingleSelected
                  ? () async {
                      if (widget.onImportLyrics != null) {
                        widget.onImportLyrics!();
                      } else {
                        await importLyricsForSong(
                          context,
                          ref,
                          widget.selectedSongs.first,
                        );
                      }
                      widget.onCancel();
                    }
                  : null,
            ),
          );
        }
        if (widget.onDownload != null) {
          secondaryActions.add(
            _buildSelectionActionButton(
              context: context,
              icon: Icons.download_rounded,
              label: l10n.downloadSong.contains('下载') ? '下载' : 'Download',
              onPressed: isEmpty ? null : widget.onDownload,
            ),
          );
        }
        if (widget.onDelete != null) {
          secondaryActions.add(
            _buildSelectionActionButton(
              context: context,
              icon: Icons.delete_outline_rounded,
              label: widget.deleteLabel ?? l10n.delete,
              onPressed: isEmpty ? null : widget.onDelete,
            ),
          );
        }
      }

      for (var i = 0; i < secondaryActions.length; i += 4) {
        final chunk = secondaryActions.sublist(
          i,
          i + 4 > secondaryActions.length ? secondaryActions.length : i + 4,
        );
        while (chunk.length < 4) {
          chunk.add(const SizedBox.shrink());
        }
        secondaryActionRows.add(
          Row(
            children: [
              Expanded(child: chunk[0]),
              const SizedBox(width: 8),
              Expanded(child: chunk[1]),
              const SizedBox(width: 8),
              Expanded(child: chunk[2]),
              const SizedBox(width: 8),
              Expanded(child: chunk[3]),
            ],
          ),
        );
      }
    }

    final allActionRows = <Widget>[
      primaryRow,
      ...secondaryActionRows,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isLandscape ? 620 : 372),
            child: Material(
              elevation: 16,
              color: theme.colorScheme.surface,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        Text(
                          widget.title ??
                              l10n.selectedSongs(widget.selectedSongs.length),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: widget.onCancel,
                          tooltip: l10n.cancel,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: _maxActionAreaHeight,
                      ),
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: allActionRows.length > 2,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          physics: allActionRows.length > 2
                              ? const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                )
                              : const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.only(
                            right: allActionRows.length > 2 ? 6.0 : 0.0,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < allActionRows.length; i++) ...[
                                if (i > 0) const SizedBox(height: _rowSpacing),
                                allActionRows[i],
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context);
    final isEnabled = onPressed != null;
    return SizedBox(
      height: _singleRowHeight,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.38,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
