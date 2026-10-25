import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../pages/playlist_detail_page.dart';
import '../player/audio/audio_riverpod.dart';
import '../player/audio/playback_source.dart';
import '../player/library/playlist_service.dart';
import '../utils/app_snack_bar.dart';
import '../utils/file_selector_helper.dart';
import '../utils/playlist_name.dart';
import 'app_context_menu.dart';
import 'entity_context_menu.dart';
import 'playlist_cover.dart';

Future<void> showPlaylistRenameDialog(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final controller = TextEditingController(text: playlist.name);
  String? errorText;
  final l10n = AppLocalizations.of(context)!;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(l10n.renamePlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.playlistName,
            errorText: errorText,
          ),
          onChanged: (val) {
            if (errorText != null) {
              setDialogState(() {
                errorText = null;
              });
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty && name != playlist.name) {
                final playlistService = ref.read(playlistServiceProvider);
                if (playlistService.playlistExists(name)) {
                  setDialogState(() {
                    errorText = l10n.playlistNameExists;
                  });
                  return;
                }
                await playlistService.renamePlaylist(playlist.id, name);
              }
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    ),
  );
}

Future<void> showPlaylistClearConfirmDialog(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final plName = localizedPlaylistName(context, playlist);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.clearPlaylist),
      content: Text(l10n.confirmClearPlaylist(plName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () async {
            Navigator.pop(dialogContext);
            await ref.read(playlistServiceProvider).clearPlaylist(playlist.id);
            if (context.mounted) {
              AppSnackBar.show(
                context,
                ref,
                SnackBar(
                  content: Text(l10n.playlistSongsCleared(plName)),
                ),
              );
            }
          },
          child: Text(l10n.clear),
        ),
      ],
    ),
  );
}

Future<void> showPlaylistDeleteConfirmDialog(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist, {
  VoidCallback? onDeleted,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final plName = localizedPlaylistName(context, playlist);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.deletePlaylist),
      content: Text(l10n.confirmDeletePlaylist(plName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () async {
            Navigator.pop(dialogContext);
            await ref.read(playlistServiceProvider).deletePlaylist(playlist.id);
            onDeleted?.call();
          },
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
}

Future<void> exportPlaylistAsM3u(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final l10n = AppLocalizations.of(context)!;
  if (playlist.songs.isEmpty) {
    AppSnackBar.show(
      context,
      ref,
      SnackBar(content: Text(l10n.noSongsInPlaylist)),
    );
    return;
  }

  try {
    final playlistService = ref.read(playlistServiceProvider);
    final scannerRoots = ref.read(scannerServiceProvider).rootPaths;
    final m3uContent = playlistService.exportPlaylistToM3u(
      playlist,
      rootPaths: scannerRoots,
    );
    final bytes = Uint8List.fromList(utf8.encode(m3uContent));
    final safeName = playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final suggestedName = '$safeName.m3u8';

    final savedPath = await FileSelectorHelper.saveFile(
      suggestedName: suggestedName,
      extensions: ['m3u8', 'm3u'],
      label: 'M3U8 Playlist',
      bytes: bytes,
    );

    if (savedPath != null && context.mounted) {
      AppSnackBar.show(
        context,
        ref,
        SnackBar(content: Text(l10n.exportPlaylistSuccess)),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    AppSnackBar.show(
      context,
      ref,
      SnackBar(content: Text(l10n.exportPlaylistFailed(e.toString()))),
    );
  }
}

/// 本地播放列表菜单声明
final EntityContextMenuSpec<Playlist> playlistMenuSpec =
    EntityContextMenuSpec<Playlist>(
  songs: (playlist) => playlist.songs,
  selectionKey: (playlist) => playlist.id,
  title: (l10n, playlist) => playlist.name,
  subtitle: (l10n, playlist) => l10n.songCount(playlist.songs.length),
  cover: (context, playlist) => PlaylistCover(playlist: playlist, size: 52),
  playbackSource: (l10n, playlist) => PlaybackSource(
    type: PlaybackSourceType.playlist,
    id: playlist.id,
    name: playlist.name,
  ),
  detailIcon: Icons.queue_music_rounded,
  detailLabel: (l10n) => l10n.viewPlaylistDetails,
  detailPageBuilder: (playlist) => PlaylistDetailPage(playlist: playlist),
  secondaryActions: (l10n, playlist) {
    final isCustom = playlist.id != 'default' &&
        playlist.id != PlaylistService.favoritePlaylistId;
    return [
      if (isCustom)
        ContextMenuAction(
          value: 'rename_playlist',
          label: l10n.renamePlaylist,
          icon: Icons.edit_outlined,
        ),
      ContextMenuAction(
        value: 'export_playlist',
        label: l10n.exportPlaylist,
        icon: Icons.file_upload_outlined,
        enabled: playlist.songs.isNotEmpty,
      ),
      ContextMenuAction(
        value: 'clear_playlist',
        label: l10n.clearPlaylist,
        icon: Icons.clear_all_rounded,
        enabled: playlist.songs.isNotEmpty,
      ),
      if (isCustom)
        ContextMenuAction(
          value: 'delete_playlist',
          label: l10n.deletePlaylist,
          icon: Icons.delete_outline_rounded,
        ),
    ];
  },
  handleCustomAction: (context, ref, playlist, action) async {
    switch (action) {
      case 'rename_playlist':
        await showPlaylistRenameDialog(context, ref, playlist);
        break;
      case 'export_playlist':
        await exportPlaylistAsM3u(context, ref, playlist);
        break;
      case 'clear_playlist':
        await showPlaylistClearConfirmDialog(context, ref, playlist);
        break;
      case 'delete_playlist':
        await showPlaylistDeleteConfirmDialog(context, ref, playlist);
        break;
    }
  },
);

/// 弹出播放列表右键菜单
Future<String?> showPlaylistContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required Playlist playlist,
  void Function(String id)? onMultiSelect,
  VoidCallback? onViewDetails,
}) =>
    showEntityContextMenu<Playlist>(
      context: context,
      globalPosition: globalPosition,
      ref: ref,
      spec: playlistMenuSpec,
      entity: playlist,
      onMultiSelect: onMultiSelect,
      onViewDetails: onViewDetails,
    );
