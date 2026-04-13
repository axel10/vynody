import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../player/playlist_service.dart';

enum SongContextMenuMode { full, title, artistAlbum }

bool isVisibleSongText(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  return lower != 'unknown' &&
      lower != 'unknown artist' &&
      lower != 'unknown album';
}

Future<void> openSongFileLocation(String filePath) async {
  if (filePath.trim().isEmpty) return;

  final normalizedPath = File(filePath).absolute.path;
  if (!File(normalizedPath).existsSync()) {
    debugPrint(
      '[SongContextMenu] Cannot open file location, file missing: $normalizedPath',
    );
    return;
  }

  try {
    if (Platform.isWindows) {
      final cmd = 'explorer.exe /select,"$normalizedPath"';
      // windows上只能用Process.run(cmd, [])这种方式打开，不要尝试修改
      await Process.run(cmd, []);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', normalizedPath]);
    } else if (Platform.isLinux) {
      final parentDir = File(normalizedPath).parent.path;

      final launchers = <List<String>>[
        ['nautilus', '--select', normalizedPath],
        ['dolphin', '--select', normalizedPath],
        ['nemo', '--no-desktop', normalizedPath],
        ['thunar', parentDir],
        ['xdg-open', parentDir],
      ];

      for (final launcher in launchers) {
        try {
          final result = await Process.run(
            launcher.first,
            launcher.skip(1).toList(growable: false),
          );
          if (result.exitCode == 0) {
            return;
          }
        } catch (_) {
          // Try the next file manager command.
        }
      }
    }
  } catch (e) {
    debugPrint('[SongContextMenu] Failed to open file location: $e');
  }
}

Future<void> openFolderLocation(String folderPath) async {
  if (folderPath.trim().isEmpty) return;

  final normalizedPath = Directory(folderPath).absolute.path;
  if (!Directory(normalizedPath).existsSync()) {
    debugPrint(
      '[FolderContextMenu] Cannot open folder location, folder missing: $normalizedPath',
    );
    return;
  }

  try {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [normalizedPath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [normalizedPath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [normalizedPath]);
    }
  } catch (e) {
    debugPrint('[FolderContextMenu] Failed to open folder location: $e');
  }
}

Future<void> showSongContextMenu(
  BuildContext context,
  Offset globalPosition, {
  required MusicFile? song,
  SongContextMenuMode mode = SongContextMenuMode.full,
  Future<void> Function()? onAddToPlaylist,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;

  final titleText = song?.displayName.trim() ?? '';
  final artistText = song?.artist?.trim() ?? '';
  final albumText = song?.album?.trim() ?? '';
  final hasTitle = titleText.isNotEmpty;
  final hasArtist = isVisibleSongText(artistText);
  final hasAlbum = isVisibleSongText(albumText);
  final hasFilePath = song != null && song.path.trim().isNotEmpty;
  final canOpenLocation =
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
      hasFilePath;

  final items = <PopupMenuEntry<String>>[];

  switch (mode) {
    case SongContextMenuMode.full:
      items.addAll([
        PopupMenuItem<String>(
          value: 'open_file_location',
          enabled: canOpenLocation,
          child: const Text('打开文件所在位置'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'copy_title',
          enabled: hasTitle,
          child: const Text('复制标题'),
        ),
        PopupMenuItem<String>(
          value: 'copy_album',
          enabled: hasAlbum,
          child: const Text('复制专辑'),
        ),
        PopupMenuItem<String>(
          value: 'copy_artist',
          enabled: hasArtist,
          child: const Text('复制艺术家'),
        ),
      ]);
      break;
    case SongContextMenuMode.title:
      items.addAll([
        PopupMenuItem<String>(
          value: 'copy_title',
          enabled: hasTitle,
          child: const Text('复制标题'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'open_file_location',
          enabled: canOpenLocation,
          child: const Text('打开文件所在位置'),
        ),
      ]);
      break;
    case SongContextMenuMode.artistAlbum:
      items.addAll([
        PopupMenuItem<String>(
          value: 'copy_artist',
          enabled: hasArtist,
          child: const Text('复制艺术家'),
        ),
        PopupMenuItem<String>(
          value: 'copy_album',
          enabled: hasAlbum,
          child: const Text('复制专辑'),
        ),
      ]);
      break;
  }

  if (onAddToPlaylist != null) {
    if (items.isNotEmpty) {
      items.add(const PopupMenuDivider());
    }
    items.add(
      PopupMenuItem<String>(
        value: 'add_to_playlist',
        child: Text(AppLocalizations.of(context)!.addToPlaylist),
      ),
    );
  }

  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    ),
    items: items,
  );

  if (!context.mounted || selected == null) return;

  switch (selected) {
    case 'copy_title':
      if (hasTitle) {
        await Clipboard.setData(ClipboardData(text: titleText));
      }
      break;
    case 'copy_artist':
      if (hasArtist) {
        await Clipboard.setData(ClipboardData(text: artistText));
      }
      break;
    case 'copy_album':
      if (hasAlbum) {
        await Clipboard.setData(ClipboardData(text: albumText));
      }
      break;
    case 'open_file_location':
      if (canOpenLocation) {
        await openSongFileLocation(song.path);
      }
      break;
    case 'add_to_playlist':
      if (onAddToPlaylist != null) {
        await onAddToPlaylist();
      }
      break;
  }
}

Future<void> showAddSongsToPlaylistDialog(
  BuildContext context,
  PlaylistService playlistService,
  List<MusicFile> songs,
) async {
  if (songs.isEmpty) return;

  Future<void> addSongsToPlaylist(Playlist playlist) async {
    await playlistService.addSongsToPlaylist(playlist.id, songs);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(
            context,
          )!.addedToPlaylist(songs.length, playlist.name),
        ),
      ),
    );
  }

  Future<void> showCreatePlaylistDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext)!.createPlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(dialogContext)!.playlistName,
            hintText: AppLocalizations.of(dialogContext)!.enterPlaylistName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(dialogContext)!.cancel),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              final playlist = await playlistService.createPlaylist(name);
              if (!context.mounted) return;
              await playlistService.addSongsToPlaylist(playlist.id, songs);
              if (!context.mounted) return;
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(
                      context,
                    )!.createdPlaylist(name, songs.length),
                  ),
                ),
              );
            },
            child: Text(AppLocalizations.of(dialogContext)!.createPlaylist),
          ),
        ],
      ),
    );
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppLocalizations.of(dialogContext)!.addToPlaylist),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: ListView.builder(
          itemCount: playlistService.playlists.length,
          itemBuilder: (itemContext, index) {
            final playlist = playlistService.playlists[index];
            return ListTile(
              leading: const Icon(Icons.playlist_play),
              title: Text(playlist.name),
              subtitle: Text(
                AppLocalizations.of(
                  itemContext,
                )!.songCount(playlist.songs.length),
              ),
              onTap: () async {
                Navigator.pop(dialogContext);
                await addSongsToPlaylist(playlist);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(AppLocalizations.of(dialogContext)!.cancel),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            await showCreatePlaylistDialog();
          },
          child: Text(AppLocalizations.of(dialogContext)!.createNewList),
        ),
      ],
    ),
  );
}

Future<void> showFolderContextMenu(
  BuildContext context,
  Offset globalPosition, {
  required String folderPath,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;

  final canOpenLocation =
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
      folderPath.trim().isNotEmpty;

  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem<String>(
        value: 'open_folder_location',
        enabled: canOpenLocation,
        child: const Text('打开文件夹所在位置'),
      ),
    ],
  );

  if (!context.mounted || selected == null) return;

  if (selected == 'open_folder_location' && canOpenLocation) {
    await openFolderLocation(folderPath);
  }
}
