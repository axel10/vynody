import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/dialogs/song_tag_edit_dialog.dart';
import '../dialogs/transcode_dialog.dart';
import '../pages/artist_detail_page.dart';
import 'app_context_menu.dart';
import 'artist_avatar.dart';
import 'library_selection_scope.dart';

/// Shared menu configuration for both the popup context menu and the
/// long-press bottom sheet.
List<List<ContextMenuAction>> _buildArtistMenuActionGroups(
  AppLocalizations l10n,
  ArtistSummary artist, {
  required bool showViewDetails,
  required bool showMultiSelect,
}) {
  final songs = artist.songs;
  final canEditTags = songs.isNotEmpty &&
      songs.any((s) => !RemoteMediaResolver.isRemoteUri(s.path));

  return [
    [
      ContextMenuAction(
        value: 'play_all',
        label: l10n.playAll,
        icon: Icons.play_arrow_rounded,
        enabled: songs.isNotEmpty,
      ),
      ContextMenuAction(
        value: 'shuffle',
        label: l10n.shufflePlay,
        icon: Icons.shuffle_rounded,
        enabled: songs.isNotEmpty,
      ),
      ContextMenuAction(
        value: 'play_next',
        label: l10n.playNext,
        icon: Icons.queue_play_next_rounded,
        enabled: songs.isNotEmpty,
      ),
      ContextMenuAction(
        value: 'add_to_queue',
        label: l10n.addToQueue,
        icon: Icons.queue_music_rounded,
        enabled: songs.isNotEmpty,
      ),
      ContextMenuAction(
        value: 'add_to_playlist',
        label: l10n.addToPlaylist,
        icon: Icons.playlist_add_rounded,
        enabled: songs.isNotEmpty,
      ),
      ContextMenuAction(
        value: 'edit_tags',
        label: songs.length > 1
            ? '${l10n.batchEditSongTagsTitle} (${songs.length})'
            : l10n.editSongTagsTitle,
        icon: Icons.edit_note_rounded,
        enabled: canEditTags,
      ),
      ContextMenuAction(
        value: 'transcode',
        label: l10n.transcodeAction,
        icon: Icons.sync_rounded,
        enabled: songs.isNotEmpty,
      ),
    ],
    [
      if (showViewDetails)
        ContextMenuAction(
          value: 'view_details',
          label: l10n.viewArtistDetails,
          icon: Icons.mic_rounded,
        ),
      ContextMenuAction(
        value: 'copy_artist',
        label: l10n.copyArtistName,
        icon: Icons.copy_rounded,
      ),
      if (showMultiSelect)
        ContextMenuAction(
          value: 'multi_select',
          label: l10n.multiSelect,
          icon: Icons.checklist_rounded,
        ),
    ],
  ];
}

/// Shows context menu (at mouse position) for an artist.
Future<String?> showArtistContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required ArtistSummary artist,
  void Function(String artistKey)? onMultiSelect,
  VoidCallback? onViewDetails,
  bool showViewDetails = true,
}) async {
  final l10n = AppLocalizations.of(context)!;

  final items = buildContextMenuPopupItems(
    context,
    _buildArtistMenuActionGroups(
      l10n,
      artist,
      showViewDetails: showViewDetails,
      showMultiSelect: onMultiSelect != null,
    ),
  );

  final selected = await AppContextMenu.show<String>(
    context: context,
    position: globalPosition,
    items: items,
  );

  if (!context.mounted || selected == null) return null;

  await _handleArtistMenuAction(
    selected: selected,
    context: context,
    ref: ref,
    artist: artist,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
  );

  return selected;
}

/// Shows bottom sheet for an artist.
Future<String?> showArtistBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ArtistSummary artist,
  void Function(String artistKey)? onMultiSelect,
  VoidCallback? onViewDetails,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);

  final subtitleParts = <String>[
    l10n.songCount(artist.songCount),
    if ((artist.country?.trim().isNotEmpty ?? false)) artist.country!.trim(),
  ];
  if (artist.disambiguation?.trim().isNotEmpty ?? false) {
    subtitleParts.add(artist.disambiguation!.trim());
  }

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
                              ArtistAvatar(
                                diameter: 52,
                                imagePath: artist.cachedImagePath,
                                imageUrl: artist.imageUrl,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      artist.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitleParts.join(' · '),
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
                          ...buildContextMenuSheetItems(
                            context,
                            _buildArtistMenuActionGroups(
                              l10n,
                              artist,
                              showViewDetails: true,
                              showMultiSelect: onMultiSelect != null,
                            ),
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

  await _handleArtistMenuAction(
    selected: selected,
    context: context,
    ref: ref,
    artist: artist,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
  );

  return selected;
}

Future<void> _handleArtistMenuAction({
  required String selected,
  required BuildContext context,
  required WidgetRef ref,
  required ArtistSummary artist,
  void Function(String artistKey)? onMultiSelect,
  VoidCallback? onViewDetails,
}) async {
  final audio = ref.read(audioServiceProvider);
  final playlistService = ref.read(playlistServiceProvider);
  final songs = artist.songs;

  switch (selected) {
    case 'play_all':
      await audio.playPlaylist(
        songs,
        source: PlaybackSource(
          type: PlaybackSourceType.artist,
          id: artist.queryKey,
          name: artist.name,
        ),
      );
      break;
    case 'shuffle':
      await audio.playPlaylist(
        List.of(songs)..shuffle(),
        source: PlaybackSource(
          type: PlaybackSourceType.artist,
          id: artist.queryKey,
          name: artist.name,
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
            builder: (_) => ArtistDetailPage(artist: artist),
          ),
        );
      }
      break;
    case 'copy_artist':
      await Clipboard.setData(ClipboardData(text: artist.name));
      break;
    case 'multi_select':
      onMultiSelect?.call(artist.queryKey);
      break;
  }
}
