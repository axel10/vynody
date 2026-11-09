import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/dialogs/song_tag_edit_dialog.dart';
import 'package:vynody/dialogs/transcode_dialog.dart';
import 'package:vynody/dialogs/song_details_dialog.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'generic_selection_panel.dart';

export 'generic_selection_panel.dart' show SelectionActionItem, GenericSelectionPanel;

class LibrarySelectionPanel extends ConsumerWidget {
  const LibrarySelectionPanel({
    super.key,
    this.selectedSongs = const [],
    this.allSongs = const [],
    this.onToggleSelectAll,
    required this.onCancel,
    this.customActions,
    this.columns,
    this.onDelete,
    this.deleteLabel,
    this.title,
    this.onOpenLocation,
    this.openLocationLabel,
    this.onImportLyrics,
    this.onEditTags,
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
    this.onAddToMediaLibrary,
    this.addToMediaLibraryLabel,
    this.isSelectionEmpty,
    this.isAllSelected,
    this.hasSelectableItems,
  });

  final List<MusicFile> selectedSongs;
  final List<MusicFile> allSongs;
  final VoidCallback? onToggleSelectAll;
  final VoidCallback onCancel;
  final List<SelectionActionItem>? customActions;
  final int? columns;
  final VoidCallback? onDelete;
  final String? deleteLabel;
  final String? title;
  final VoidCallback? onOpenLocation;
  final String? openLocationLabel;
  final VoidCallback? onImportLyrics;
  final VoidCallback? onEditTags;
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
  final VoidCallback? onAddToMediaLibrary;
  final String? addToMediaLibraryLabel;
  final bool? isSelectionEmpty;
  final bool? isAllSelected;

  /// 多选对象不是歌曲时（歌单、专辑、艺术家等），面板无法用 [allSongs] 的
  /// 歌曲平铺数反推「到底有没有可选的东西」，由调用方显式给出。
  ///
  /// 不传时沿用旧推导：有歌曲可选，或调用方自己接管了全选态。
  final bool? hasSelectableItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    if (customActions != null) {
      return GenericSelectionPanel(
        title: title ?? l10n.selectedSongs(selectedSongs.length),
        onCancel: onCancel,
        actions: customActions!,
        columns: columns,
      );
    }

    final audio = ref.read(audioServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);

    final effectiveIsAllSelected = isAllSelected ??
        (selectedSongs.length == allSongs.length && allSongs.isNotEmpty);
    final canSelectAll = hasSelectableItems ??
        (allSongs.isNotEmpty || isAllSelected != null);
    final isSongSelectionEmpty = selectedSongs.isEmpty;
    final isEmpty = isSelectionEmpty ?? isSongSelectionEmpty;
    final isSingleSelected = !isEmpty && selectedSongs.length == 1;

    final isRemote = selectedSongs.isNotEmpty &&
        RemoteMediaResolver.isRemoteUri(selectedSongs.first.path);
    final hasFilePath = isSingleSelected &&
        selectedSongs.isNotEmpty &&
        selectedSongs.first.path.trim().isNotEmpty &&
        !isRemote;
    final canOpenLocation =
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
        (onOpenLocation != null || hasFilePath);

    final selectAllText = effectiveIsAllSelected ? l10n.deselectAll : l10n.selectAll;

    final actions = <SelectionActionItem>[
      // 1. 全选 / 取消全选
      SelectionActionItem(
        icon: effectiveIsAllSelected ? Icons.deselect : Icons.select_all,
        label: selectAllText,
        onPressed: (canSelectAll && onToggleSelectAll != null) ? onToggleSelectAll : null,
      ),
      // 2. 播放下一首
      SelectionActionItem(
        icon: Icons.queue_play_next_rounded,
        label: l10n.playNext,
        onPressed: (isEmpty || (onPlayNext == null && isSongSelectionEmpty))
            ? null
            : () async {
                if (onPlayNext != null) {
                  onPlayNext!();
                } else {
                  await audio.enqueueNext(selectedSongs);
                  onCancel();
                }
              },
      ),
      // 3. 添加到队列
      SelectionActionItem(
        icon: Icons.queue_music_rounded,
        label: l10n.addToQueue,
        onPressed: (isEmpty || (onAddToQueue == null && isSongSelectionEmpty))
            ? null
            : () async {
                if (onAddToQueue != null) {
                  onAddToQueue!();
                } else {
                  await audio.appendToQueue(selectedSongs);
                  onCancel();
                }
              },
      ),
      // 4. 添加到歌单
      SelectionActionItem(
        icon: Icons.playlist_add_rounded,
        label: l10n.addToPlaylist,
        onPressed: (isEmpty || (onAddToPlaylist == null && isSongSelectionEmpty))
            ? null
            : () async {
                if (onAddToPlaylist != null) {
                  onAddToPlaylist!();
                } else {
                  await showAddSongsToPlaylistDialog(
                    context,
                    playlistService,
                    selectedSongs,
                  );
                  onCancel();
                }
              },
      ),
    ];

    if (!hideSecondaryActions) {
      if (!replaceFavoritesWithSongDetails) {
        actions.add(
          SelectionActionItem(
            icon: Icons.favorite_rounded,
            label: favoritesLabel ??
                (onAddToCloudFavorites != null
                    ? l10n.addToLocalFavorites
                    : l10n.addToFavorites),
            onPressed: (isEmpty || (onAddToFavorites == null && isSongSelectionEmpty))
                ? null
                : () async {
                    if (onAddToFavorites != null) {
                      onAddToFavorites!();
                    } else {
                      await playlistService.addSongsToPlaylist(
                        PlaylistService.favoritePlaylistId,
                        selectedSongs,
                      );
                      if (context.mounted) {
                        AppSnackBar.show(
                          context,
                          ref,
                          SnackBar(
                            content: Text(
                              l10n.addedToPlaylist(
                                selectedSongs.length,
                                l10n.favorites,
                              ),
                            ),
                          ),
                        );
                      }
                      onCancel();
                    }
                  },
          ),
        );

        if (onAddToCloudFavorites != null) {
          actions.add(
            SelectionActionItem(
              icon: cloudFavoritesIcon ?? Icons.cloud_done_rounded,
              label: cloudFavoritesLabel ?? l10n.addToCloudFavorites,
              onPressed: isEmpty ? null : onAddToCloudFavorites,
            ),
          );
        }
      }

      if (!hideSongProperties) {
        actions.add(
          SelectionActionItem(
            icon: Icons.info_outline_rounded,
            label: l10n.songProperties,
            onPressed: isSingleSelected
                ? () => showSongDetailsDialog(
                      context,
                      selectedSongs.first,
                    )
                : null,
          ),
        );
      }

      final canEditTags = !isEmpty &&
          !isSongSelectionEmpty &&
          !isRemote &&
          selectedSongs.any((s) => !RemoteMediaResolver.isRemoteUri(s.path));
      actions.add(
        SelectionActionItem(
          icon: Icons.edit_note_rounded,
          label: l10n.editTagsAction,
          onPressed: canEditTags
              ? () async {
                  if (onEditTags != null) {
                    onEditTags!();
                  } else {
                    final result = await showSongTagEditSheet(
                      context,
                      songs: selectedSongs,
                    );
                    if (result != null && context.mounted) {
                      await applySongTagEditResult(context, ref, result);
                      onCancel();
                    }
                  }
                }
              : null,
        ),
      );

      actions.add(
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
            ? SelectionActionItem(
                icon: Icons.folder_open_rounded,
                label: openLocationLabel ?? l10n.openFileLocation,
                onPressed: canOpenLocation
                    ? () async {
                        if (onOpenLocation != null) {
                          onOpenLocation!();
                        } else {
                          await openSongFileLocation(
                            selectedSongs.first.path,
                          );
                        }
                        onCancel();
                      }
                    : null,
              )
            : SelectionActionItem(
                icon: Icons.lyrics_outlined,
                label: l10n.importLyrics,
                onPressed: isSingleSelected
                    ? () async {
                        if (onImportLyrics != null) {
                          onImportLyrics!();
                        } else {
                          await importLyricsForSong(
                            context,
                            ref,
                            selectedSongs.first,
                          );
                        }
                        onCancel();
                      }
                    : null,
              ),
      );

      if (onAddToMediaLibrary != null) {
        actions.add(
          SelectionActionItem(
            icon: Icons.library_add_rounded,
            label: addToMediaLibraryLabel ?? l10n.addToMediaLibrary,
            onPressed: isEmpty ? null : onAddToMediaLibrary,
          ),
        );
      }

      if (onDownload != null) {
        actions.add(
          SelectionActionItem(
            icon: Icons.download_rounded,
            label: l10n.download,
            onPressed: isEmpty ? null : onDownload,
          ),
        );
      }

      if (onDelete != null) {
        actions.add(
          SelectionActionItem(
            icon: Icons.delete_outline_rounded,
            label: deleteLabel ?? l10n.delete,
            onPressed: isEmpty ? null : onDelete,
            isDestructive: true,
          ),
        );
      }

      actions.add(
        SelectionActionItem(
          icon: Icons.sync_rounded,
          label: l10n.transcodeAction,
          onPressed: (isEmpty || (onTranscode == null && isSongSelectionEmpty))
              ? null
              : () async {
                  if (onTranscode != null) {
                    onTranscode!();
                  } else {
                    await showTranscodeDialog(
                      context,
                      songs: selectedSongs,
                    );
                    onCancel();
                  }
                },
        ),
      );
    }

    return GenericSelectionPanel(
      title: title ?? l10n.selectedSongs(selectedSongs.length),
      onCancel: onCancel,
      actions: actions,
      columns: 4,
    );
  }
}
