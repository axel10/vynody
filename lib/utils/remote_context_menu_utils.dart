import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';
import '../dialogs/remote_playlist_dialog.dart';
import '../dialogs/remote_track_load_progress_dialog.dart';
import '../dialogs/song_details_dialog.dart';
import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../player/audio/audio_riverpod.dart';
import '../player/audio/playback_source.dart';
import '../player/remote/clients/remote_media_library_client.dart';
import '../player/remote/clients/webdav_client.dart';
import '../player/remote/clients/smb_client.dart';
import '../player/remote/proxy/remote_media_resolver.dart';
import '../player/remote/remote_server_models.dart';
import '../player/remote/remote_server_riverpod.dart';
import '../player/remote/services/remote_download_service.dart';
import '../player/remote/services/remote_track_load_progress.dart';
import '../player/remote/services/remote_scan_root.dart';
import '../player/remote/services/remote_directory_scanner.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/remote_artwork_widget.dart';
import 'remote_download_feedback.dart';
import 'song_context_menu_utils.dart';
import '../widgets/app_context_menu.dart';

/// Helper to fetch tracks of an album on-demand if not already supplied
Future<List<MusicFile>> fetchSubsonicAlbumTracks(
  RemoteMediaLibraryClient client,
  RemoteServer server,
  String albumId,
) async {
  try {
    final album = await client.getAlbum(albumId);
    final songList = album?['song'] as List?;
    if (songList != null && songList.isNotEmpty) {
      final List<MusicFile> parsed = [];
      for (final item in songList) {
        if (item is Map<String, dynamic>) {
          parsed.add(
            client.buildMusicFile(item),
          );
        }
      }
      return parsed;
    }
  } catch (_) {}
  return [];
}

Future<List<MusicFile>> _fetchAlbumTracks(
  RemoteMediaLibraryClient client,
  RemoteServer server,
  String albumId,
) => fetchSubsonicAlbumTracks(client, server, albumId);

/// Helper to fetch tracks of an artist on-demand
Future<List<MusicFile>> fetchSubsonicArtistTracks(
  RemoteMediaLibraryClient client,
  RemoteServer server,
  String artistId,
) async {
  try {
    final artistMap = await client.getArtist(artistId);
    if (artistMap != null) {
      final dynamic rawAlbums = artistMap['album'];
      final List<Map<String, dynamic>> albumList = [];
      if (rawAlbums is List) {
        albumList.addAll(rawAlbums.whereType<Map<String, dynamic>>());
      } else if (rawAlbums is Map<String, dynamic>) {
        albumList.add(rawAlbums);
      }

      final List<MusicFile> allSongs = [];
      final dynamic directSongs = artistMap['song'];
      if (directSongs is List) {
        for (final s in directSongs) {
          if (s is Map<String, dynamic>) {
            allSongs.add(client.buildMusicFile(s));
          }
        }
      }

      // 专辑列表自带 songCount，先据此估出总曲目数，进度才有分母可显示。
      // 多选多个艺术家时这里是连续调用的，所以分母用累加、已加载按本次起点叠加，
      // 不能用覆盖式 setTotal / setLoaded（否则只剩最后一个艺术家的刻度）。
      final progress = remoteTrackLoadProgress;
      final baseLoaded = progress.loaded;
      final expectedTotal = albumList.fold<int>(0, (sum, al) {
        final count = al['songCount'];
        return sum + (count is int ? count : 0);
      });
      progress.addToTotal(expectedTotal);
      progress.setLoaded(baseLoaded + allSongs.length);

      for (final al in albumList) {
        progress.throwIfCancelled();
        final aId = al['id'] as String?;
        if (aId != null) {
          final fullAlbum = await client.getAlbum(aId);
          final sData = fullAlbum?['song'] as List?;
          if (sData != null) {
            for (final s in sData) {
              if (s is Map<String, dynamic>) {
                allSongs.add(
                  client.buildMusicFile(s),
                );
              }
            }
          }
          progress.setLoaded(baseLoaded + allSongs.length);
        }
      }
      return allSongs;
    }
  } on RemoteTrackLoadCancelled {
    // 取消要穿透出去，不能被下面兜底的 catch 吞掉，
    // 否则多选艺术家时会逐个白跑一遍 getArtist。
    rethrow;
  } catch (_) {}
  return [];
}

Future<List<MusicFile>> _fetchArtistTracks(
  RemoteMediaLibraryClient client,
  RemoteServer server,
  String artistId,
) => fetchSubsonicArtistTracks(client, server, artistId);

/// Helper to fetch tracks of a playlist on-demand
Future<List<MusicFile>> fetchSubsonicPlaylistTracks(
  RemoteMediaLibraryClient client,
  RemoteServer server,
  String playlistId,
) async {
  try {
    if (playlistId == '__navidrome_starred_songs__' ||
        playlistId == 'starred_songs') {
      final songList = await client.getStarredSongs();
      if (songList.isNotEmpty) {
        final List<MusicFile> parsed = [];
        for (final item in songList) {
          parsed.add(
            client.buildMusicFile(item),
          );
        }
        return parsed;
      }
    } else {
      final pl = await client.getPlaylist(playlistId);
      final entryList = pl?['entry'] as List?;
      if (entryList != null && entryList.isNotEmpty) {
        final List<MusicFile> parsed = [];
        for (final item in entryList) {
          if (item is Map<String, dynamic>) {
            parsed.add(
              client.buildMusicFile(item),
            );
          }
        }
        return parsed;
      }
    }
  } catch (_) {}
  return [];
}


/// Shows context menu for a remote Navidrome album.
/// Shows context menu for a remote Navidrome album.
///
/// 弹窗（右键）与底部面板（长按）共用同一份动作分组，两个入口不会再有
/// 「桌面能复制、移动端没有」这类分叉。
Future<void> showRemoteAlbumContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required RemoteServer server,
  required String password,
  required String albumId,
  required String albumTitle,
  required String artistName,
  String? coverArtId,
  List<MusicFile>? songs,
  VoidCallback? onViewDetails,
  VoidCallback? onViewArtist,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final client = RemoteMediaLibraryClient.create(
    server: server,
    password: password,
  );

  final groups = <List<ContextMenuAction>>[
    [
      ContextMenuAction(
        value: 'play',
        label: l10n.playAll,
        icon: Icons.play_arrow_rounded,
      ),
      ContextMenuAction(
        value: 'shuffle',
        label: l10n.shufflePlay,
        icon: Icons.shuffle_rounded,
      ),
      ContextMenuAction(
        value: 'play_next',
        label: l10n.playNext,
        icon: Icons.queue_play_next_rounded,
      ),
      ContextMenuAction(
        value: 'add_to_queue',
        label: l10n.addToQueue,
        icon: Icons.queue_music_rounded,
      ),
    ],
    [
      ContextMenuAction(
        value: 'add_to_playlist',
        label: l10n.addToPlaylist,
        icon: Icons.playlist_add_rounded,
      ),
      ContextMenuAction(
        value: 'star',
        label: l10n.starItem,
        icon: Icons.favorite_border_rounded,
      ),
    ],
    [
      ContextMenuAction(
        value: 'download',
        label: l10n.downloadAlbum,
        icon: Icons.download_rounded,
      ),
    ],
    [
      if (onViewDetails != null)
        ContextMenuAction(
          value: 'view_details',
          label: l10n.viewAlbumDetails,
          icon: Icons.album_rounded,
        ),
      if (onViewArtist != null)
        ContextMenuAction(
          value: 'view_artist',
          label: l10n.viewArtistDetails,
          icon: Icons.mic_rounded,
        ),
      ContextMenuAction(
        value: 'copy_title',
        label: l10n.copyAlbumTitle,
        icon: Icons.copy_rounded,
      ),
    ],
  ];

  final selected = Platform.isAndroid || Platform.isIOS
      ? await showAppActionSheet<String>(
          context: context,
          header: ActionSheetHeader(
            title: albumTitle,
            subtitle: artistName,
            leading: (coverArtId == null || coverArtId.isEmpty)
                ? null
                : RemoteArtworkWidget(
                    server: server,
                    password: password,
                    coverArtId: coverArtId,
                    size: 52,
                    borderRadius: BorderRadius.circular(12),
                  ),
          ),
          itemsBuilder: (sheetContext) =>
              buildContextMenuSheetItems(sheetContext, groups),
        )
      : await AppContextMenu.show<String>(
          context: context,
          position: globalPosition,
          items: buildContextMenuPopupItems(context, groups),
        );

  if (!context.mounted || selected == null) return;
  await _handleAlbumMenuSelection(
    selected: selected,
    context: context,
    ref: ref,
    client: client,
    server: server,
    password: password,
    albumId: albumId,
    albumTitle: albumTitle,
    artistName: artistName,
    songs: songs,
    onViewDetails: onViewDetails,
    onViewArtist: onViewArtist,
  );
}


Future<void> _handleAlbumMenuSelection({
  required String selected,
  required BuildContext context,
  required WidgetRef ref,
  required RemoteMediaLibraryClient client,
  required RemoteServer server,
  required String password,
  required String albumId,
  required String albumTitle,
  required String artistName,
  List<MusicFile>? songs,
  VoidCallback? onViewDetails,
  VoidCallback? onViewArtist,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final audio = ref.read(audioServiceProvider);

  Future<List<MusicFile>> getOrFetchSongs() async {
    if (songs != null && songs.isNotEmpty) return songs;
    showToast(l10n.loadingAlbumTracks);
    return await _fetchAlbumTracks(client, server, albumId);
  }

  switch (selected) {
    case 'play':
      final trackList = await getOrFetchSongs();
      if (trackList.isNotEmpty) {
        await audio.playPlaylist(
          trackList,
          source: PlaybackSource(
            type: PlaybackSourceType.album,
            id: 'remote-${server.id}-$albumId',
            name: albumTitle,
          ),
        );
      }
      break;
    case 'shuffle':
      final trackList = await getOrFetchSongs();
      if (trackList.isNotEmpty) {
        await audio.playPlaylist(
          List.of(trackList)..shuffle(),
          source: PlaybackSource(
            type: PlaybackSourceType.album,
            id: 'remote-${server.id}-$albumId',
            name: albumTitle,
          ),
        );
      }
      break;
    case 'play_next':
      final trackList = await getOrFetchSongs();
      if (trackList.isNotEmpty) {
        await audio.enqueueNext(trackList);
        showToast(l10n.addedToQueue);
      }
      break;
    case 'add_to_queue':
      final trackList = await getOrFetchSongs();
      if (trackList.isNotEmpty) {
        await audio.appendToQueue(trackList);
        showToast(l10n.addedToQueue);
      }
      break;
    case 'add_to_playlist':
    case 'add_to_server_playlist':
      final trackList = await getOrFetchSongs();
      if (trackList.isNotEmpty && context.mounted) {
        await RemoteAddToPlaylistDialog.show(
          context,
          ref: ref,
          server: server,
          password: password,
          songs: trackList,
        );
      }
      break;
    case 'star':
      final ok = await client.star(albumId: albumId);
      showToast(ok ? l10n.starredSuccess : l10n.starFailed);
      break;
    case 'download':
      // 拉曲目和入队都按「首」上报进度，集合较大时才有可感知的反馈。
      final trackList = await runWithRemoteTrackLoadProgress<List<MusicFile>>(
        context: context,
        task: () async {
          final list = (songs != null && songs.isNotEmpty)
              ? songs
              : await _fetchAlbumTracks(client, server, albumId);
          if (list.isEmpty) return list;
          await ref.read(remoteDownloadTasksProvider.notifier).enqueue(
                RemoteDownloadRequest(
                  server: server,
                  password: password,
                  songs: list,
                ),
              );
          return list;
        },
      );
      if (trackList != null && trackList.isNotEmpty) {
        showRemoteDownloadQueuedFeedback(context, ref, trackList.length);
      }
      break;
    case 'view_details':
      onViewDetails?.call();
      break;
    case 'view_artist':
      onViewArtist?.call();
      break;
    case 'copy_title':
      await Clipboard.setData(ClipboardData(text: albumTitle));
      break;
  }
}

/// Shows context menu for a remote song.
///
/// [downloadLayout] / [downloadCollectionFolder] 描述曲目所在页面的目录维度
/// （艺术家页传 artist + 艺术家名，歌单页传 playlist + 歌单名），
/// 保证单曲下载的落盘结构与同页面批量下载一致。
/// Shows context menu for a remote song.
///
/// [downloadLayout] / [downloadCollectionFolder] 描述曲目所在页面的目录维度
/// （艺术家页传 artist + 艺术家名，歌单页传 playlist + 歌单名），
/// 保证单曲下载的落盘结构与同页面批量下载一致。
Future<void> showRemoteSongContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required RemoteServer server,
  required String password,
  required MusicFile song,
  List<MusicFile>? playlist,
  VoidCallback? onViewAlbum,
  VoidCallback? onViewArtist,
  VoidCallback? onRemoveFromPlaylist,
  RemoteDownloadLayout downloadLayout = RemoteDownloadLayout.album,
  String? downloadCollectionFolder,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final client = RemoteMediaLibraryClient.create(
    server: server,
    password: password,
  );

  // Extract trackId
  final trackId = RemoteMediaResolver.extractTrackId(song) ??
      (song.id != null && song.id! > 0 ? song.id.toString() : '');

  final groups = <List<ContextMenuAction>>[
    [
      ContextMenuAction(
        value: 'play_next',
        label: l10n.playNext,
        icon: Icons.queue_play_next_rounded,
      ),
      ContextMenuAction(
        value: 'add_to_queue',
        label: l10n.addToQueue,
        icon: Icons.queue_music_rounded,
      ),
    ],
    [
      ContextMenuAction(
        value: 'add_to_playlist',
        label: l10n.addToPlaylist,
        icon: Icons.playlist_add_rounded,
      ),
      ContextMenuAction(
        value: 'star',
        label: l10n.starItem,
        icon: Icons.favorite_border_rounded,
      ),
    ],
    [
      ContextMenuAction(
        value: 'download',
        label: l10n.downloadSong,
        icon: Icons.download_rounded,
      ),
    ],
    [
      if (onRemoveFromPlaylist != null)
        ContextMenuAction(
          value: 'remove_from_playlist',
          label: l10n.removeFromPlaylist,
          icon: Icons.remove_circle_outline_rounded,
          accentColor: theme.colorScheme.error,
        ),
    ],
    [
      if (onViewAlbum != null)
        ContextMenuAction(
          value: 'view_album',
          label: l10n.viewAlbum,
          icon: Icons.album_rounded,
        ),
      if (onViewArtist != null)
        ContextMenuAction(
          value: 'view_artist',
          label: l10n.viewArtist,
          icon: Icons.mic_rounded,
        ),
      ContextMenuAction(
        value: 'details',
        label: l10n.songProperties,
        icon: Icons.info_outline_rounded,
      ),
    ],
    [
      ContextMenuAction(
        value: 'copy_title',
        label: l10n.copyTitle,
        icon: Icons.title_rounded,
      ),
      if (song.artist != null && song.artist!.isNotEmpty)
        ContextMenuAction(
          value: 'copy_artist',
          label: l10n.copyArtistName,
          icon: Icons.mic_rounded,
        ),
    ],
  ];

  final selected = Platform.isAndroid || Platform.isIOS
      ? await showAppActionSheet<String>(
          context: context,
          header: ActionSheetHeader(
            title: song.displayName,
            subtitle:
                '${song.artist ?? l10n.unknownArtist} · ${song.album ?? l10n.unknownAlbum}',
          ),
          itemsBuilder: (sheetContext) =>
              buildContextMenuSheetItems(sheetContext, groups),
        )
      : await AppContextMenu.show<String>(
          context: context,
          position: globalPosition,
          items: buildContextMenuPopupItems(context, groups),
        );

  if (!context.mounted || selected == null) return;
  await _handleSongMenuSelection(
    selected: selected,
    context: context,
    ref: ref,
    client: client,
    server: server,
    password: password,
    song: song,
    trackId: trackId,
    onViewAlbum: onViewAlbum,
    onViewArtist: onViewArtist,
    onRemoveFromPlaylist: onRemoveFromPlaylist,
    downloadLayout: downloadLayout,
    downloadCollectionFolder: downloadCollectionFolder,
  );
}


Future<void> _handleSongMenuSelection({
  required String selected,
  required BuildContext context,
  required WidgetRef ref,
  required RemoteMediaLibraryClient client,
  required RemoteServer server,
  required String password,
  required MusicFile song,
  required String trackId,
  VoidCallback? onViewAlbum,
  VoidCallback? onViewArtist,
  VoidCallback? onRemoveFromPlaylist,
  RemoteDownloadLayout downloadLayout = RemoteDownloadLayout.album,
  String? downloadCollectionFolder,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final audio = ref.read(audioServiceProvider);

  switch (selected) {
    case 'play_next':
      await audio.enqueueNext([song]);
      showToast(l10n.addedToQueue);
      break;
    case 'add_to_queue':
      await audio.appendToQueue([song]);
      showToast(l10n.addedToQueue);
      break;
    case 'add_to_playlist':
    case 'add_to_server_playlist':
      if (context.mounted) {
        await RemoteAddToPlaylistDialog.show(
          context,
          ref: ref,
          server: server,
          password: password,
          songs: [song],
        );
      }
      break;
    case 'add_to_local_playlist':
      final playlistService = ref.read(playlistServiceProvider);
      if (context.mounted) {
        await showAddSongsToPlaylistDialog(context, playlistService, [song]);
      }
      break;
    case 'star':
      final ok = await client.star(id: trackId);
      showToast(ok ? l10n.starredSuccess : l10n.starFailed);
      break;
    case 'download':
      await ref.read(remoteDownloadTasksProvider.notifier).enqueue(
            RemoteDownloadRequest(
              server: server,
              password: password,
              songs: [song],
              layout: downloadLayout,
              collectionFolder: downloadCollectionFolder,
            ),
          );
      showRemoteDownloadQueuedFeedback(context, ref, 1);
      break;
    case 'remove_from_playlist':
      onRemoveFromPlaylist?.call();
      break;
    case 'view_album':
      onViewAlbum?.call();
      break;
    case 'view_artist':
      onViewArtist?.call();
      break;
    case 'details':
      if (context.mounted) {
        await showSongDetailsDialog(context, song);
      }
      break;
    case 'copy_title':
      await Clipboard.setData(ClipboardData(text: song.displayName));
      break;
    case 'copy_artist':
      if (song.artist != null) {
        await Clipboard.setData(ClipboardData(text: song.artist!));
      }
      break;
  }
}

/// Shows context menu for a remote Navidrome artist.
/// Shows context menu for a remote Navidrome artist.
Future<void> showRemoteArtistContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required RemoteServer server,
  required String password,
  required String artistId,
  required String artistName,
  bool isStarred = false,
  void Function(bool isStarred)? onStarredChanged,
  VoidCallback? onViewDetails,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final client = RemoteMediaLibraryClient.create(
    server: server,
    password: password,
  );

  final groups = <List<ContextMenuAction>>[
    [
      ContextMenuAction(
        value: 'play_all',
        label: l10n.playAll,
        icon: Icons.play_arrow_rounded,
      ),
      ContextMenuAction(
        value: 'shuffle',
        label: l10n.shufflePlay,
        icon: Icons.shuffle_rounded,
      ),
      ContextMenuAction(
        value: 'play_next',
        label: l10n.playNext,
        icon: Icons.queue_play_next_rounded,
      ),
      ContextMenuAction(
        value: 'add_to_queue',
        label: l10n.addToQueue,
        icon: Icons.queue_music_rounded,
      ),
    ],
    [
      ContextMenuAction(
        value: isStarred ? 'unstar' : 'star',
        label: isStarred ? l10n.unstarItem : l10n.starItem,
        icon: isStarred
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
        accentColor: isStarred ? Colors.redAccent : null,
      ),
    ],
    [
      ContextMenuAction(
        value: 'download',
        label: l10n.downloadArtist,
        icon: Icons.download_rounded,
      ),
    ],
    [
      if (onViewDetails != null)
        ContextMenuAction(
          value: 'view_details',
          label: l10n.viewArtistDetails,
          icon: Icons.mic_rounded,
        ),
      ContextMenuAction(
        value: 'copy_name',
        label: l10n.copyArtistName,
        icon: Icons.copy_rounded,
      ),
    ],
  ];

  final selected = Platform.isAndroid || Platform.isIOS
      ? await showAppActionSheet<String>(
          context: context,
          header: ActionSheetHeader(title: artistName),
          itemsBuilder: (sheetContext) =>
              buildContextMenuSheetItems(sheetContext, groups),
        )
      : await AppContextMenu.show<String>(
          context: context,
          position: globalPosition,
          items: buildContextMenuPopupItems(context, groups),
        );

  if (!context.mounted || selected == null) return;
  await _handleArtistMenuSelection(
    selected: selected,
    context: context,
    ref: ref,
    client: client,
    server: server,
    password: password,
    artistId: artistId,
    artistName: artistName,
    isStarred: isStarred,
    onStarredChanged: onStarredChanged,
    onViewDetails: onViewDetails,
  );
}


Future<void> _handleArtistMenuSelection({
  required String selected,
  required BuildContext context,
  required WidgetRef ref,
  required RemoteMediaLibraryClient client,
  required RemoteServer server,
  required String password,
  required String artistId,
  required String artistName,
  bool isStarred = false,
  void Function(bool isStarred)? onStarredChanged,
  VoidCallback? onViewDetails,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final audio = ref.read(audioServiceProvider);

  Future<List<MusicFile>> getArtistSongs() async {
    showToast(l10n.loadingArtistTracks);
    return await _fetchArtistTracks(client, server, artistId);
  }

  switch (selected) {
    case 'play_all':
      final trackList = await getArtistSongs();
      if (trackList.isNotEmpty) {
        await audio.playPlaylist(
          trackList,
          source: PlaybackSource(
            type: PlaybackSourceType.artist,
            id: 'remote-${server.id}-$artistId',
            name: artistName,
          ),
        );
      }
      break;
    case 'shuffle':
      final trackList = await getArtistSongs();
      if (trackList.isNotEmpty) {
        await audio.playPlaylist(
          List.of(trackList)..shuffle(),
          source: PlaybackSource(
            type: PlaybackSourceType.artist,
            id: 'remote-${server.id}-$artistId',
            name: artistName,
          ),
        );
      }
      break;
    case 'play_next':
      final trackList = await getArtistSongs();
      if (trackList.isNotEmpty) {
        await audio.enqueueNext(trackList);
        showToast(l10n.addedToQueue);
      }
      break;
    case 'add_to_queue':
      final trackList = await getArtistSongs();
      if (trackList.isNotEmpty) {
        await audio.appendToQueue(trackList);
        showToast(l10n.addedToQueue);
      }
      break;
    case 'star':
      final ok = await client.star(artistId: artistId);
      if (ok) {
        onStarredChanged?.call(true);
        final currentStarred = Set<String>.from(
            ref.read(activeRemoteSessionProvider)?.navidromeStarredArtistIds ??
                {});
        currentStarred.add(artistId);
        ref.read(activeRemoteSessionProvider.notifier).updateNavidromeArtists(
              starredArtistIds: currentStarred,
            );
      }
      showToast(ok ? l10n.starredSuccess : l10n.starFailed);
      break;
    case 'unstar':
      final ok = await client.unstar(artistId: artistId);
      if (ok) {
        onStarredChanged?.call(false);
        final currentStarred = Set<String>.from(
            ref.read(activeRemoteSessionProvider)?.navidromeStarredArtistIds ??
                {});
        currentStarred.remove(artistId);
        ref.read(activeRemoteSessionProvider.notifier).updateNavidromeArtists(
              starredArtistIds: currentStarred,
            );
      }
      showToast(ok ? l10n.unstarredSuccess : l10n.starFailed);
      break;
    case 'download':
      // 艺术家要逐张专辑拉曲目，是最需要「共 N 首 / 已加载 M 首」的场景。
      final trackList = await runWithRemoteTrackLoadProgress<List<MusicFile>>(
        context: context,
        task: () async {
          final list = await _fetchArtistTracks(client, server, artistId);
          if (list.isEmpty) return list;
          await ref.read(remoteDownloadTasksProvider.notifier).enqueue(
                RemoteDownloadRequest(
                  server: server,
                  password: password,
                  songs: list,
                  layout: RemoteDownloadLayout.artist,
                  collectionFolder: artistName,
                ),
              );
          return list;
        },
      );
      if (trackList != null && trackList.isNotEmpty) {
        showRemoteDownloadQueuedFeedback(context, ref, trackList.length);
      }
      break;
    case 'view_details':
      onViewDetails?.call();
      break;
    case 'copy_name':
      await Clipboard.setData(ClipboardData(text: artistName));
      break;
  }
}

/// Helper to fetch tracks of a playlist on-demand if not already supplied
Future<List<MusicFile>> _fetchPlaylistTracks(
  RemoteMediaLibraryClient client,
  RemoteServer server,
  String playlistId,
) async {
  try {
    final playlist = await client.getPlaylist(playlistId);
    final songList = playlist?['entry'] as List?;
    if (songList != null && songList.isNotEmpty) {
      final List<MusicFile> parsed = [];
      for (final item in songList) {
        if (item is Map<String, dynamic>) {
          parsed.add(
            client.buildMusicFile(item),
          );
        }
      }
      return parsed;
    }
  } catch (_) {}
  return [];
}

/// Shows context menu for a remote Navidrome playlist.
/// Shows context menu for a remote Navidrome playlist.
Future<void> showRemotePlaylistContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required RemoteServer server,
  required String password,
  required String playlistId,
  required String playlistName,
  List<MusicFile>? songs,
  VoidCallback? onViewDetails,
  VoidCallback? onRename,
  VoidCallback? onDelete,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final client = RemoteMediaLibraryClient.create(
    server: server,
    password: password,
  );

  final groups = <List<ContextMenuAction>>[
    [
      ContextMenuAction(
        value: 'play_all',
        label: l10n.playAll,
        icon: Icons.play_arrow_rounded,
      ),
      ContextMenuAction(
        value: 'play_next',
        label: l10n.playNext,
        icon: Icons.queue_play_next_rounded,
      ),
      ContextMenuAction(
        value: 'add_to_queue',
        label: l10n.addToQueue,
        icon: Icons.queue_music_rounded,
      ),
    ],
    [
      ContextMenuAction(
        value: 'download',
        label: l10n.downloadAlbum,
        icon: Icons.download_rounded,
      ),
    ],
    [
      if (onRename != null)
        ContextMenuAction(
          value: 'rename',
          label: l10n.renamePlaylist,
          icon: Icons.edit_rounded,
        ),
      if (onDelete != null)
        ContextMenuAction(
          value: 'delete',
          label: l10n.deletePlaylist,
          icon: Icons.delete_outline_rounded,
          accentColor: theme.colorScheme.error,
        ),
    ],
    [
      if (onViewDetails != null)
        ContextMenuAction(
          value: 'view_details',
          label: l10n.viewAlbumDetails,
          icon: Icons.info_outline_rounded,
        ),
      ContextMenuAction(
        value: 'copy_name',
        label: l10n.copyTitle,
        icon: Icons.title_rounded,
      ),
    ],
  ];

  final selected = Platform.isAndroid || Platform.isIOS
      ? await showAppActionSheet<String>(
          context: context,
          header: ActionSheetHeader(
            title: playlistName,
            subtitle: songs != null ? l10n.songCount(songs.length) : l10n.playlist,
            leading: const ActionSheetSquareIcon(
              icon: Icons.playlist_play_rounded,
            ),
          ),
          itemsBuilder: (sheetContext) =>
              buildContextMenuSheetItems(sheetContext, groups),
        )
      : await AppContextMenu.show<String>(
          context: context,
          position: globalPosition,
          items: buildContextMenuPopupItems(context, groups),
        );

  if (!context.mounted || selected == null) return;
  await _handlePlaylistMenuSelection(
    selected: selected,
    context: context,
    ref: ref,
    client: client,
    server: server,
    password: password,
    playlistId: playlistId,
    playlistName: playlistName,
    songs: songs,
    onViewDetails: onViewDetails,
    onRename: onRename,
    onDelete: onDelete,
  );
}


Future<void> _handlePlaylistMenuSelection({
  required String selected,
  required BuildContext context,
  required WidgetRef ref,
  required RemoteMediaLibraryClient client,
  required RemoteServer server,
  required String password,
  required String playlistId,
  required String playlistName,
  List<MusicFile>? songs,
  VoidCallback? onViewDetails,
  VoidCallback? onRename,
  VoidCallback? onDelete,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final audio = ref.read(audioServiceProvider);

  Future<List<MusicFile>> getPlaylistSongs() async {
    if (songs != null && songs.isNotEmpty) return songs;
    return await _fetchPlaylistTracks(client, server, playlistId);
  }

  switch (selected) {
    case 'play_all':
      final trackList = await getPlaylistSongs();
      if (trackList.isNotEmpty) {
        await audio.playPlaylist(
          trackList,
          source: PlaybackSource(
            type: PlaybackSourceType.playlist,
            id: 'remote-${server.id}-$playlistId',
            name: playlistName,
          ),
        );
      }
      break;
    case 'play_next':
      final trackList = await getPlaylistSongs();
      if (trackList.isNotEmpty) {
        await audio.enqueueNext(trackList);
        showToast(l10n.addedToQueue);
      }
      break;
    case 'add_to_queue':
      final trackList = await getPlaylistSongs();
      if (trackList.isNotEmpty) {
        await audio.appendToQueue(trackList);
        showToast(l10n.addedToQueue);
      }
      break;
    case 'download':
      final trackList = await runWithRemoteTrackLoadProgress<List<MusicFile>>(
        context: context,
        task: () async {
          final list = (songs != null && songs.isNotEmpty)
              ? songs
              : await _fetchPlaylistTracks(client, server, playlistId);
          if (list.isEmpty) return list;
          await ref.read(remoteDownloadTasksProvider.notifier).enqueue(
                RemoteDownloadRequest(
                  server: server,
                  password: password,
                  songs: list,
                  layout: RemoteDownloadLayout.playlist,
                  collectionFolder: playlistName,
                ),
              );
          return list;
        },
      );
      if (trackList != null && trackList.isNotEmpty) {
        showRemoteDownloadQueuedFeedback(context, ref, trackList.length);
      }
      break;
    case 'rename':
      onRename?.call();
      break;
    case 'delete':
      onDelete?.call();
      break;
    case 'view_details':
      onViewDetails?.call();
      break;
    case 'copy_name':
      await Clipboard.setData(ClipboardData(text: playlistName));
      break;
  }
}

String _formatWebDavFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB'];
  var i = 0;
  double size = bytes.toDouble();
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(1)} ${suffixes[i]}';
}

/// Helper to fetch tracks of a WebDAV/SMB folder on-demand
Future<List<MusicFile>> fetchWebDavFolderAudioFiles(
  RemoteDirectoryClient client,
  RemoteServer server,
  String folderPath,
) async {
  try {
    final list = await client.listFiles(folderPath);
    return list
        .where((item) => item.isAudio)
        .map((item) => RemoteMediaResolver.buildMusicFile(item, server))
        .toList();
  } catch (_) {
    return [];
  }
}

/// Helper to recursively fetch all audio files in a remote directory and its subdirectories.
Future<List<WebDavFile>> fetchAllWebDavAudioFilesRecursive(
  RemoteDirectoryClient client,
  String folderPath, {
  int maxDepth = 10,
}) async {
  final List<WebDavFile> result = [];
  final List<({String path, int depth})> queue = [(path: folderPath, depth: 0)];

  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    try {
      final items = await client.listFiles(current.path);
      for (final item in items) {
        if (item.isDirectory) {
          if (current.depth + 1 < maxDepth) {
            queue.add((path: item.path, depth: current.depth + 1));
          }
        } else if (item.isAudio) {
          result.add(item);
        }
      }
    } catch (_) {}
  }
  return result;
}

/// Shows context menu for a remote WebDAV file (audio or generic file).
/// Shows context menu for a remote WebDAV file (audio or generic file).
Future<void> showWebDavFileContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required RemoteServer server,
  required String password,
  required WebDavFile file,
  List<MusicFile>? currentAudioFiles,
  VoidCallback? onPlay,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final isAudio = file.isAudio;
  final virtualUri = RemoteMediaResolver.buildRemoteUri(server, file.path);
  final meta = ref.read(scannerServiceProvider).metadataMap[virtualUri];
  final song = isAudio
      ? RemoteMediaResolver.buildMusicFile(file, server, metadata: meta)
      : null;

  final groups = <List<ContextMenuAction>>[
    [
      if (isAudio)
        ContextMenuAction(
          value: 'play',
          label: l10n.play,
          icon: Icons.play_arrow_rounded,
        ),
      if (isAudio)
        ContextMenuAction(
          value: 'play_next',
          label: l10n.playNext,
          icon: Icons.queue_play_next_rounded,
        ),
      if (isAudio)
        ContextMenuAction(
          value: 'add_to_queue',
          label: l10n.addToQueue,
          icon: Icons.queue_music_rounded,
        ),
    ],
    [
      if (isAudio)
        ContextMenuAction(
          value: 'add_to_local_playlist',
          label: l10n.addToLocalPlaylist,
          icon: Icons.library_add_outlined,
        ),
      if (isAudio)
        ContextMenuAction(
          value: 'download',
          label: l10n.downloadSong,
          icon: Icons.download_rounded,
        ),
    ],
    [
      if (isAudio)
        ContextMenuAction(
          value: 'details',
          label: l10n.songProperties,
          icon: Icons.info_outline_rounded,
        ),
    ],
    [
      ContextMenuAction(
        value: 'copy_title',
        label: l10n.copyTitle,
        icon: Icons.title_rounded,
      ),
      ContextMenuAction(
        value: 'copy_path',
        label: l10n.copyFilePath,
        icon: Icons.link_rounded,
      ),
    ],
  ];

  final selected = Platform.isAndroid || Platform.isIOS
      ? await showAppActionSheet<String>(
          context: context,
          header: ActionSheetHeader(
            title: file.name,
            subtitle: _formatWebDavFileSize(file.contentLength),
            leading: ActionSheetSquareIcon(
              icon: isAudio
                  ? Icons.music_note_rounded
                  : Icons.insert_drive_file_outlined,
              color: isAudio ? theme.colorScheme.primary : null,
            ),
          ),
          itemsBuilder: (sheetContext) =>
              buildContextMenuSheetItems(sheetContext, groups),
        )
      : await AppContextMenu.show<String>(
          context: context,
          position: globalPosition,
          items: buildContextMenuPopupItems(context, groups),
        );

  if (!context.mounted || selected == null) return;
  await _handleWebDavFileMenuSelection(
    selected: selected,
    context: context,
    ref: ref,
    server: server,
    password: password,
    file: file,
    song: song,
    currentAudioFiles: currentAudioFiles,
    onPlay: onPlay,
  );
}


Future<void> _handleWebDavFileMenuSelection({
  required String selected,
  required BuildContext context,
  required WidgetRef ref,
  required RemoteServer server,
  required String password,
  required WebDavFile file,
  required MusicFile? song,
  List<MusicFile>? currentAudioFiles,
  VoidCallback? onPlay,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final audio = ref.read(audioServiceProvider);

  switch (selected) {
    case 'play':
      if (onPlay != null) {
        onPlay();
      } else if (song != null) {
        final list = currentAudioFiles ?? [song];
        final initialIndex = list.indexWhere((s) => s.path == song.path);
        await audio.playPlaylist(
          list,
          initialIndex: initialIndex >= 0 ? initialIndex : 0,
        );
      }
      break;
    case 'play_next':
      if (song != null) {
        await audio.enqueueNext([song]);
        showToast(l10n.addedToQueue);
      }
      break;
    case 'add_to_queue':
      if (song != null) {
        await audio.appendToQueue([song]);
        showToast(l10n.addedToQueue);
      }
      break;
    case 'add_to_local_playlist':
      if (song != null && context.mounted) {
        final playlistService = ref.read(playlistServiceProvider);
        await showAddSongsToPlaylistDialog(context, playlistService, [song]);
      }
      break;
    case 'download':
      await ref.read(remoteDownloadTasksProvider.notifier).enqueueWebDavFile(
            server: server,
            password: password,
            file: file,
          );
      showRemoteDownloadQueuedFeedback(context, ref, 1);
      break;
    case 'details':
      if (song != null && context.mounted) {
        await showSongDetailsDialog(context, song);
      }
      break;
    case 'copy_title':
      await Clipboard.setData(ClipboardData(text: file.name));
      break;
    case 'copy_path':
      await Clipboard.setData(ClipboardData(text: file.path));
      break;
  }
}

/// Shows context menu for a remote WebDAV folder.
/// Shows bottom sheet for a remote WebDAV folder, aligned with showFolderBottomSheet design.
/// 远程文件夹菜单的动作分组：底部面板与弹窗共用，避免「是否收录进媒体库」
/// 这类按状态翻转的条目在两个入口各判一次、判出两种结果。
List<List<ContextMenuAction>> _webDavFolderActionGroups({
  required AppLocalizations l10n,
  required ThemeData theme,
  required bool isIndexed,
  required VoidCallback? onOpen,
  required void Function(String folderPath)? onMultiSelect,
}) {
  return [
    [
      ContextMenuAction(
        value: 'play_all',
        label: l10n.playAll,
        icon: Icons.play_arrow_rounded,
      ),
      ContextMenuAction(
        value: 'shuffle',
        label: l10n.shufflePlay,
        icon: Icons.shuffle_rounded,
      ),
      ContextMenuAction(
        value: 'play_next',
        label: l10n.playNext,
        icon: Icons.queue_play_next_rounded,
      ),
      ContextMenuAction(
        value: 'add_to_queue',
        label: l10n.addToQueue,
        icon: Icons.queue_music_rounded,
      ),
      ContextMenuAction(
        value: 'add_to_playlist',
        label: l10n.addToPlaylist,
        icon: Icons.playlist_add_rounded,
      ),
    ],
    [
      ContextMenuAction(
        value: 'download_folder',
        label: l10n.downloadAllAudio,
        icon: Icons.download_rounded,
      ),
      ContextMenuAction(
        value: isIndexed ? 'remove_from_media_library' : 'add_to_media_library',
        label:
            isIndexed ? l10n.removeFromMediaLibrary : l10n.addToMediaLibrary,
        icon: isIndexed
            ? Icons.bookmark_remove_rounded
            : Icons.library_add_rounded,
        accentColor: isIndexed ? Colors.orangeAccent : theme.colorScheme.primary,
      ),
    ],
    [
      if (onOpen != null)
        ContextMenuAction(
          value: 'open',
          label: l10n.openFolder,
          icon: Icons.folder_open_rounded,
        ),
      if (onMultiSelect != null)
        ContextMenuAction(
          value: 'multi_select',
          label: l10n.selectFolders,
          icon: Icons.checklist_rounded,
        ),
    ],
    [
      ContextMenuAction(
        value: 'copy_name',
        label: l10n.copyFolderName,
        icon: Icons.copy_rounded,
      ),
      ContextMenuAction(
        value: 'copy_path',
        label: l10n.copyFolderPath,
        icon: Icons.link_rounded,
      ),
    ],
  ];
}

/// Shows bottom sheet for a remote WebDAV folder, aligned with showFolderBottomSheet design.
Future<String?> showWebDavFolderBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required RemoteServer server,
  required String password,
  required WebDavFile folder,
  VoidCallback? onOpen,
  void Function(String folderPath)? onMultiSelect,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final RemoteDirectoryClient client = server.type == RemoteServerType.smb
      ? SmbClient(server: server, password: password)
      : WebDavClient(server: server, password: password);
  final isIndexed = ref
      .read(remoteScanRootsProvider.notifier)
      .isFolderIndexed(server.id, folder.path);

  // 面板本身会读一下选择态，先切到独立作用域，避免把页面上的多选带进面板。
  final previousScope = ref.read(librarySelectionScopeProvider);
  ref
      .read(librarySelectionScopeProvider.notifier)
      .setScope(LibrarySelectionScope.bottomSheet);

  final String? selected;
  try {
    selected = await showAppActionSheet<String>(
      context: context,
      header: ActionSheetHeader(
        title: folder.name,
        subtitle: folder.path,
        leading: const ActionSheetSquareIcon(
          icon: Icons.folder_rounded,
          color: Colors.amber,
        ),
      ),
      itemsBuilder: (sheetContext) => buildContextMenuSheetItems(
        sheetContext,
        _webDavFolderActionGroups(
          l10n: l10n,
          theme: theme,
          isIndexed: isIndexed,
          onOpen: onOpen,
          onMultiSelect: onMultiSelect,
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

  if (selected == 'multi_select') {
    onMultiSelect?.call(folder.path);
    return selected;
  }

  await _handleWebDavFolderMenuSelection(
    selected: selected,
    context: context,
    ref: ref,
    client: client,
    server: server,
    password: password,
    folder: folder,
    onOpen: onOpen,
  );

  return selected;
}


/// Shows context menu / bottom sheet for a remote WebDAV folder.
/// Shows context menu / bottom sheet for a remote WebDAV folder.
Future<void> showWebDavFolderContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required RemoteServer server,
  required String password,
  required WebDavFile folder,
  VoidCallback? onOpen,
  void Function(String folderPath)? onMultiSelect,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final RemoteDirectoryClient client = server.type == RemoteServerType.smb
      ? SmbClient(server: server, password: password)
      : WebDavClient(server: server, password: password);

  if (Platform.isAndroid || Platform.isIOS) {
    await showWebDavFolderBottomSheet(
      context: context,
      ref: ref,
      server: server,
      password: password,
      folder: folder,
      onOpen: onOpen,
      onMultiSelect: onMultiSelect,
    );
    return;
  }

  final selected = await AppContextMenu.show<String>(
    context: context,
    position: globalPosition,
    items: buildContextMenuPopupItems(
      context,
      _webDavFolderActionGroups(
        l10n: l10n,
        theme: theme,
        isIndexed: ref
            .read(remoteScanRootsProvider.notifier)
            .isFolderIndexed(server.id, folder.path),
        onOpen: onOpen,
        onMultiSelect: onMultiSelect,
      ),
    ),
  );

  if (!context.mounted || selected == null) return;

  if (selected == 'multi_select') {
    onMultiSelect?.call(folder.path);
    return;
  }

  await _handleWebDavFolderMenuSelection(
    selected: selected,
    context: context,
    ref: ref,
    client: client,
    server: server,
    password: password,
    folder: folder,
    onOpen: onOpen,
  );
}


Future<void> _handleWebDavFolderMenuSelection({
  required String selected,
  required BuildContext context,
  required WidgetRef ref,
  required RemoteDirectoryClient client,
  required RemoteServer server,
  required String password,
  required WebDavFile folder,
  VoidCallback? onOpen,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final audio = ref.read(audioServiceProvider);

  Future<List<MusicFile>> getAudioFiles() async {
    showToast(l10n.loadingFolderAudio);
    return await fetchWebDavFolderAudioFiles(client, server, folder.path);
  }

  switch (selected) {
    case 'play_all':
      final trackList = await getAudioFiles();
      if (trackList.isNotEmpty) {
        await audio.playPlaylist(
          trackList,
          source: PlaybackSource(
            type: PlaybackSourceType.folder,
            id: 'webdav-${server.id}-${folder.path}',
            name: folder.name,
          ),
        );
      } else {
        showToast(l10n.noAudioFilesInFolder);
      }
      break;
    case 'shuffle':
      final trackList = await getAudioFiles();
      if (trackList.isNotEmpty) {
        await audio.playPlaylist(
          List.of(trackList)..shuffle(),
          source: PlaybackSource(
            type: PlaybackSourceType.folder,
            id: 'webdav-${server.id}-${folder.path}',
            name: folder.name,
          ),
        );
      } else {
        showToast(l10n.noAudioFilesInFolder);
      }
      break;
    case 'play_next':
      final trackList = await getAudioFiles();
      if (trackList.isNotEmpty) {
        await audio.enqueueNext(trackList);
        showToast(l10n.addedToQueue);
      } else {
        showToast(l10n.noAudioFilesInFolder);
      }
      break;
    case 'add_to_queue':
      final trackList = await getAudioFiles();
      if (trackList.isNotEmpty) {
        await audio.appendToQueue(trackList);
        showToast(l10n.addedToQueue);
      } else {
        showToast(l10n.noAudioFilesInFolder);
      }
      break;
    case 'add_to_playlist':
      final trackList = await getAudioFiles();
      if (trackList.isNotEmpty && context.mounted) {
        final playlistService = ref.read(playlistServiceProvider);
        await showAddSongsToPlaylistDialog(context, playlistService, trackList);
      } else if (context.mounted) {
        showToast(l10n.noAudioFilesInFolder);
      }
      break;
    case 'download_folder':
      try {
        final audioItems =
            await fetchAllWebDavAudioFilesRecursive(client, folder.path);
        if (audioItems.isEmpty) {
          showToast(l10n.noActiveDownloads);
          return;
        }
        if (context.mounted) {
          await ref.read(remoteDownloadTasksProvider.notifier).enqueueWebDavFiles(
                server: server,
                password: password,
                files: audioItems,
              );
          showRemoteDownloadQueuedFeedback(context, ref, audioItems.length);
        }
      } catch (e) {
        showToast(l10n.failedToLoadFolder(e.toString()));
      }
      break;
    case 'add_to_media_library':
      final scanRoot = RemoteScanRoot(
        id: RemoteScanRoot.generateId(server.id, folder.path),
        serverId: server.id,
        serverType: server.type,
        serverName: server.name,
        remotePath: folder.path,
        virtualUri: RemoteScanRoot.generateVirtualUri(server, folder.path),
        addedAt: DateTime.now().millisecondsSinceEpoch,
      );
      final added =
          await ref.read(remoteScanRootsProvider.notifier).addRoot(scanRoot);
      if (!added) {
        showToast(l10n.remoteFolderAlreadyIndexed);
        break;
      }
      final currentRoots =
          ref.read(remoteScanRootsProvider).asData?.value ?? [scanRoot];
      ref.read(scannerServiceProvider).setRemoteRoots(currentRoots);
      showToast(l10n.addedToMediaLibrary);
      unawaited(
        ref.read(remoteDirectoryScannerProvider).scanRoot(
              server: server,
              password: password,
              root: scanRoot,
            ),
      );
      break;
    case 'remove_from_media_library':
      final exactRoot = ref
          .read(remoteScanRootsProvider.notifier)
          .findExactRoot(server.id, folder.path);
      if (exactRoot != null) {
        await ref.read(remoteScanRootsProvider.notifier).removeRoot(exactRoot.id);
        final currentRoots =
            ref.read(remoteScanRootsProvider).asData?.value ?? [];
        ref.read(scannerServiceProvider).setRemoteRoots(currentRoots);
        showToast(l10n.removedFromMediaLibrary);
        unawaited(
          ref
              .read(remoteDirectoryScannerProvider)
              .removeRootFromDatabase(exactRoot),
        );
      }
      break;
    case 'open':
      onOpen?.call();
      break;
    case 'copy_name':
      await Clipboard.setData(ClipboardData(text: folder.name));
      break;
    case 'copy_path':
      await Clipboard.setData(ClipboardData(text: folder.path));
      break;
  }
}

