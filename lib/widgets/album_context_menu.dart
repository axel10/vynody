import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/dialogs/song_tag_edit_dialog.dart';
import '../dialogs/transcode_dialog.dart';
import '../pages/album_detail_page.dart';
import 'album_cover.dart';
import 'app_context_menu.dart';
import 'library_selection_scope.dart';

/// Shows context menu (at mouse position) for an album.
Future<String?> showAlbumContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required AlbumSummary album,
  void Function(String albumId)? onMultiSelect,
  VoidCallback? onViewDetails,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final songs = album.songs;

  final canEditTags = songs.isNotEmpty &&
      songs.any((s) => !RemoteMediaResolver.isRemoteUri(s.path));

  final items = <PopupMenuEntry<String>>[
    buildContextMenuItem<String>(
      value: 'play_all',
      label: l10n.playAll,
      icon: Icons.play_arrow_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'shuffle',
      label: l10n.shufflePlay,
      icon: Icons.shuffle_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'play_next',
      label: l10n.playNext,
      icon: Icons.queue_play_next_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'add_to_queue',
      label: l10n.addToQueue,
      icon: Icons.queue_music_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'add_to_playlist',
      label: l10n.addToPlaylist,
      icon: Icons.playlist_add_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'add_to_favorites',
      label: l10n.addToFavorites,
      icon: Icons.favorite_border_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'edit_tags',
      label: songs.length > 1
          ? '${l10n.batchEditSongTagsTitle} (${songs.length})'
          : l10n.editSongTagsTitle,
      icon: Icons.edit_note_rounded,
      enabled: canEditTags,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'transcode',
      label: l10n.transcodeAction,
      icon: Icons.sync_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    const PopupMenuDivider(),
    buildContextMenuItem<String>(
      value: 'view_details',
      label: l10n.viewAlbumDetails,
      icon: Icons.album_rounded,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'copy_album',
      label: l10n.copyAlbumTitle,
      icon: Icons.copy_rounded,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'copy_artist',
      label: l10n.copyArtistName,
      icon: Icons.mic_rounded,
      context: context,
    ),
    if (onMultiSelect != null)
      buildContextMenuItem<String>(
        value: 'multi_select',
        label: l10n.multiSelect,
        icon: Icons.checklist_rounded,
        context: context,
      ),
  ];

  final selected = await AppContextMenu.show<String>(
    context: context,
    position: globalPosition,
    items: items,
  );

  if (!context.mounted || selected == null) return null;

  await _handleAlbumMenuAction(
    selected: selected,
    context: context,
    ref: ref,
    album: album,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
  );

  return selected;
}

/// Shows bottom sheet for an album.
Future<String?> showAlbumBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required AlbumSummary album,
  void Function(String albumId)? onMultiSelect,
  VoidCallback? onViewDetails,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final songs = album.songs;

  final canEditTags = songs.isNotEmpty &&
      songs.any((s) => !RemoteMediaResolver.isRemoteUri(s.path));

  final previousScope = ref.read(librarySelectionScopeProvider);
  ref
      .read(librarySelectionScopeProvider.notifier)
      .setScope(LibrarySelectionScope.bottomSheet);

  final String? selected;
  try {
    selected = await AppContextMenu.showModalSheet<String>(
      context: context,
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
                  onTap: () {},
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
                          Row(
                            children: [
                              AlbumCover(
                                album: album,
                                size: 52,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      album.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      album.artist,
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
                          _buildAlbumBottomSheetItem(
                            context: context,
                            value: 'play_all',
                            label: l10n.playAll,
                            icon: Icons.play_arrow_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildAlbumBottomSheetItem(
                            context: context,
                            value: 'shuffle',
                            label: l10n.shufflePlay,
                            icon: Icons.shuffle_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildAlbumBottomSheetItem(
                            context: context,
                            value: 'play_next',
                            label: l10n.playNext,
                            icon: Icons.queue_play_next_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildAlbumBottomSheetItem(
                            context: context,
                            value: 'add_to_queue',
                            label: l10n.addToQueue,
                            icon: Icons.queue_music_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildAlbumBottomSheetItem(
                            context: context,
                            value: 'add_to_playlist',
                            label: l10n.addToPlaylist,
                            icon: Icons.playlist_add_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildAlbumBottomSheetItem(
                            context: context,
                            value: 'add_to_favorites',
                            label: l10n.addToFavorites,
                            icon: Icons.favorite_border_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildAlbumBottomSheetItem(
                            context: context,
                            value: 'edit_tags',
                            label: songs.length > 1
                                ? '${l10n.batchEditSongTagsTitle} (${songs.length})'
                                : l10n.editSongTagsTitle,
                            icon: Icons.edit_note_rounded,
                            enabled: canEditTags,
                          ),
                          _buildAlbumBottomSheetItem(
                            context: context,
                            value: 'transcode',
                            label: l10n.transcodeAction,
                            icon: Icons.sync_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildAlbumBottomSheetItem(
                            context: context,
                            value: 'view_details',
                            label: l10n.viewAlbumDetails,
                            icon: Icons.album_rounded,
                          ),
                          _buildAlbumBottomSheetItem(
                            context: context,
                            value: 'copy_album',
                            label: l10n.copyAlbumTitle,
                            icon: Icons.copy_rounded,
                          ),
                          _buildAlbumBottomSheetItem(
                            context: context,
                            value: 'copy_artist',
                            label: l10n.copyArtistName,
                            icon: Icons.mic_rounded,
                          ),
                          if (onMultiSelect != null)
                            _buildAlbumBottomSheetItem(
                              context: context,
                              value: 'multi_select',
                              label: l10n.multiSelect,
                              icon: Icons.checklist_rounded,
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
  } finally {
    if (ref.read(librarySelectionScopeProvider) ==
        LibrarySelectionScope.bottomSheet) {
      ref
          .read(librarySelectionScopeProvider.notifier)
          .setScope(previousScope);
    }
  }

  if (!context.mounted || selected == null) return null;

  await _handleAlbumMenuAction(
    selected: selected,
    context: context,
    ref: ref,
    album: album,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
  );

  return selected;
}

Future<void> _handleAlbumMenuAction({
  required String selected,
  required BuildContext context,
  required WidgetRef ref,
  required AlbumSummary album,
  void Function(String albumId)? onMultiSelect,
  VoidCallback? onViewDetails,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final audio = ref.read(audioServiceProvider);
  final playlistService = ref.read(playlistServiceProvider);
  final songs = album.songs;

  switch (selected) {
    case 'play_all':
      await audio.playPlaylist(
        songs,
        source: PlaybackSource(
          type: PlaybackSourceType.album,
          id: album.id,
          name: album.title,
        ),
      );
      break;
    case 'shuffle':
      await audio.playPlaylist(
        List.of(songs)..shuffle(),
        source: PlaybackSource(
          type: PlaybackSourceType.album,
          id: album.id,
          name: album.title,
        ),
      );
      break;
    case 'play_next':
      await audio.enqueueNext(songs);
      break;
    case 'add_to_queue':
      await audio.appendToQueue(songs);
      break;
    case 'add_to_playlist':
      await showAddSongsToPlaylistDialog(context, playlistService, songs);
      break;
    case 'add_to_favorites':
      for (final song in songs) {
        await playlistService.addSongToFavorite(song);
      }
      if (context.mounted) {
        AppSnackBar.show(
          context,
          ref,
          SnackBar(
            content: Text('${l10n.addToFavorites} · ${album.trackCount}'),
          ),
        );
      }
      break;
    case 'edit_tags':
      final result = await showSongTagEditSheet(
        context,
        songs: songs,
      );
      if (result != null && context.mounted) {
        await applySongTagEditResult(context, ref, result);
      }
      break;
    case 'transcode':
      await showTranscodeDialog(context, songs: songs);
      break;
    case 'view_details':
      if (onViewDetails != null) {
        onViewDetails();
      } else {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AlbumDetailPage(album: album),
          ),
        );
      }
      break;
    case 'copy_album':
      await Clipboard.setData(ClipboardData(text: album.title));
      break;
    case 'copy_artist':
      await Clipboard.setData(ClipboardData(text: album.artist));
      break;
    case 'multi_select':
      onMultiSelect?.call(album.id);
      break;
  }
}

Widget _buildAlbumBottomSheetItem({
  required BuildContext context,
  required String value,
  required String label,
  required IconData icon,
  bool enabled = true,
  Color? iconColor,
}) {
  final theme = Theme.of(context);
  return ListTile(
    leading: Icon(
      icon,
      color: enabled
          ? (iconColor ?? theme.colorScheme.onSurfaceVariant)
          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
    ),
    title: Text(
      label,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: enabled
            ? (iconColor ?? theme.colorScheme.onSurface)
            : theme.colorScheme.onSurface.withValues(alpha: 0.4),
      ),
    ),
    enabled: enabled,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    onTap: () => Navigator.pop(context, value),
  );
}
