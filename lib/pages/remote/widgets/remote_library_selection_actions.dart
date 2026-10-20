import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';
import '../../../dialogs/remote_playlist_dialog.dart';
import '../../../dialogs/remote_track_load_progress_dialog.dart';
import '../../../dialogs/transcode_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/music_file.dart';
import '../../../player/audio/audio_riverpod.dart';
import '../../../player/audio/playback_source.dart';
import '../../../player/remote/clients/remote_media_library_client.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../player/remote/services/remote_download_service.dart';
import '../../../player/remote/services/remote_track_load_progress.dart';
import '../../../player/remote/remote_server_riverpod.dart';
import '../../../utils/app_snack_bar.dart';
import '../../../utils/remote_context_menu_utils.dart';
import '../../../utils/remote_download_feedback.dart';
import '../../../player/library/playlist_service.dart';
import '../../../player/remote/proxy/remote_media_resolver.dart';

class RemoteLibrarySelectionActions {
  static const String starredPlaylistId = '__navidrome_starred_songs__';

  static Future<T?> _withLoading<T>({
    required BuildContext context,
    required String message,
    required Future<T> Function() task,
    Color? indicatorColor,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Center(
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: indicatorColor != null
                          ? AlwaysStoppedAnimation<Color>(indicatorColor)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final result = await task();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return result;
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      rethrow;
    }
  }

  /// 把当前勾选拉成一串「按集合分组」的曲目批次。
  ///
  /// 分组是下载落盘层级的唯一来源：勾了几个艺术家就出几个艺术家批次，
  /// 勾了几个歌单就出几个歌单批次，每批各带自己的目录名。这样批量下载的
  /// 目录结构与「同一页面里下载单曲」完全一致，也不会把多个艺术家的同名
  /// 专辑混到一个目录里。
  static Future<List<RemoteDownloadBatch>> fetchSelectedBatches({
    required RemoteServer server,
    required String password,
    required bool isAlbumSelectionMode,
    required bool isArtistSelectionMode,
    required bool isPlaylistSelectionMode,
    required bool isSongSelectionMode,
    required Set<String> selectedAlbumIds,
    required Set<String> selectedArtistIds,
    required Set<String> selectedPlaylistIds,
    required Set<String> selectedSongPaths,
    List<MusicFile> searchedSongs = const [],
    List<MusicFile>? songs,
    Map<String, int> albumSongCounts = const {},
    Map<String, String> artistNames = const {},
    Map<String, String> playlistNames = const {},
  }) async {
    final client = RemoteMediaLibraryClient.create(
      server: server,
      password: password,
    );
    final progress = remoteTrackLoadProgress;
    final batches = <RemoteDownloadBatch>[];
    if (isAlbumSelectionMode) {
      // 专辑列表项自带 songCount，几张加起来就是分母；每拉完一张专辑再
      // 累加已加载数，这样「共 N 首、已加载 M 首」才有真实刻度。
      var expectedTotal = 0;
      for (final albumId in selectedAlbumIds) {
        expectedTotal += albumSongCounts[albumId] ?? 0;
      }
      progress.addToTotal(expectedTotal);
      for (final albumId in selectedAlbumIds) {
        progress.throwIfCancelled();
        final tracks =
            await fetchSubsonicAlbumTracks(client, server, albumId);
        if (tracks.isNotEmpty) {
          batches.add(RemoteDownloadBatch(songs: tracks));
        }
        progress.advance(tracks.length);
      }
    } else if (isArtistSelectionMode) {
      for (final artistId in selectedArtistIds) {
        progress.throwIfCancelled();
        final tracks =
            await fetchSubsonicArtistTracks(client, server, artistId);
        if (tracks.isNotEmpty) {
          batches.add(
            RemoteDownloadBatch(
              songs: tracks,
              layout: RemoteDownloadLayout.artist,
              // 目录名跟着各自勾选的艺术家走；名字缺失时下载服务会逐曲回落到
              // 专辑艺术家，不会把合辑拆散。
              collectionFolder: artistNames[artistId],
            ),
          );
        }
      }
    } else if (isPlaylistSelectionMode) {
      // 歌单列表不带曲目数，拿不到分母，但已加载数照样往上走。
      for (final playlistId in selectedPlaylistIds) {
        progress.throwIfCancelled();
        final tracks =
            await fetchSubsonicPlaylistTracks(client, server, playlistId);
        if (tracks.isNotEmpty) {
          batches.add(
            RemoteDownloadBatch(
              songs: tracks,
              layout: RemoteDownloadLayout.playlist,
              collectionFolder: playlistNames[playlistId],
            ),
          );
        }
        progress.advance(tracks.length);
      }
    } else if (isSongSelectionMode) {
      final pool = songs ?? searchedSongs;
      final selected = [
        for (final song in pool)
          if (selectedSongPaths.contains(song.path)) song,
      ];
      if (selected.isNotEmpty) {
        batches.add(RemoteDownloadBatch(songs: selected));
      }
    }
    return batches;
  }

  /// 只要曲目本身（播放、加队列、收藏、转码这些不关心目录结构的动作）。
  static Future<List<MusicFile>> fetchSelectedSongs({
    required RemoteServer server,
    required String password,
    required bool isAlbumSelectionMode,
    required bool isArtistSelectionMode,
    required bool isPlaylistSelectionMode,
    required bool isSongSelectionMode,
    required Set<String> selectedAlbumIds,
    required Set<String> selectedArtistIds,
    required Set<String> selectedPlaylistIds,
    required Set<String> selectedSongPaths,
    List<MusicFile> searchedSongs = const [],
    List<MusicFile>? songs,
    Map<String, int> albumSongCounts = const {},
  }) async {
    final batches = await fetchSelectedBatches(
      server: server,
      password: password,
      isAlbumSelectionMode: isAlbumSelectionMode,
      isArtistSelectionMode: isArtistSelectionMode,
      isPlaylistSelectionMode: isPlaylistSelectionMode,
      isSongSelectionMode: isSongSelectionMode,
      selectedAlbumIds: selectedAlbumIds,
      selectedArtistIds: selectedArtistIds,
      selectedPlaylistIds: selectedPlaylistIds,
      selectedSongPaths: selectedSongPaths,
      searchedSongs: searchedSongs,
      songs: songs,
      albumSongCounts: albumSongCounts,
    );
    return [for (final batch in batches) ...batch.songs];
  }

  static Future<void> playAlbumDirectly({
    required BuildContext context,
    required WidgetRef ref,
    required RemoteServer server,
    required String password,
    required String albumId,
    required String albumTitle,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final client = RemoteMediaLibraryClient.create(
      server: server,
      password: password,
    );
    try {
      showToast(l10n.loadingAlbumTracks);
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
        if (parsed.isNotEmpty) {
          final audio = ref.read(audioServiceProvider);
          await audio.playPlaylist(
            parsed,
            source: PlaybackSource(
              type: PlaybackSourceType.album,
              id: 'remote-${server.id}-$albumId',
              name: albumTitle,
            ),
          );
        }
      }
    } catch (e) {
      showToast(l10n.playAlbumFailed(e.toString()));
    }
  }

  static Future<void> handleBatchPlayNext({
    required BuildContext context,
    required WidgetRef ref,
    required Future<List<MusicFile>> Function() onFetchSongs,
    required VoidCallback onClearSelection,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final songs = await _withLoading(
        context: context,
        message: l10n.loadingAlbumTracks,
        task: onFetchSongs,
      );
      if (songs == null || songs.isEmpty) return;
      final audio = ref.read(audioServiceProvider);
      await audio.enqueueNext(songs);
      onClearSelection();
    } catch (e) {
      showToast(e.toString());
    }
  }

  static Future<void> handleBatchAddToQueue({
    required BuildContext context,
    required WidgetRef ref,
    required Future<List<MusicFile>> Function() onFetchSongs,
    required VoidCallback onClearSelection,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final songs = await _withLoading(
        context: context,
        message: l10n.loadingAlbumTracks,
        task: onFetchSongs,
      );
      if (songs == null || songs.isEmpty) return;
      final audio = ref.read(audioServiceProvider);
      await audio.appendToQueue(songs);
      onClearSelection();
    } catch (e) {
      showToast(e.toString());
    }
  }

  static Future<void> handleBatchAddToPlaylist({
    required BuildContext context,
    required WidgetRef ref,
    required RemoteServer server,
    required String password,
    required Future<List<MusicFile>> Function() onFetchSongs,
    required VoidCallback onClearSelection,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final isJellyfin = server.type == RemoteServerType.jellyfin;
    final brandColor = isJellyfin ? const Color(0xFF9D65C9) : Colors.orange;
    try {
      final songs = await _withLoading(
        context: context,
        message: l10n.loadingAlbumTracks,
        indicatorColor: brandColor,
        task: onFetchSongs,
      );
      if (songs == null || songs.isEmpty) return;
      if (!context.mounted) return;
      await RemoteAddToPlaylistDialog.show(
        context,
        ref: ref,
        server: server,
        password: password,
        songs: songs,
      );
      onClearSelection();
    } catch (e) {
      showToast(e.toString());
    }
  }

  static Future<void> handleBatchAddToLocalFavorites({
    required BuildContext context,
    required WidgetRef ref,
    required Future<List<MusicFile>> Function() onFetchSongs,
    required VoidCallback onClearSelection,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final songs = await _withLoading(
        context: context,
        message: l10n.loadingAlbumTracks,
        task: onFetchSongs,
      );
      if (songs == null || songs.isEmpty) return;
      final playlistService = ref.read(playlistServiceProvider);
      await playlistService.addSongsToPlaylist(
        PlaylistService.favoritePlaylistId,
        songs,
      );
      onClearSelection();
      if (context.mounted) {
        showToast(l10n.batchAddedToLocalFavorites);
      }
    } catch (e) {
      showToast(e.toString());
    }
  }

  static Future<void> handleBatchAddToCloudFavorites({
    required BuildContext context,
    required WidgetRef ref,
    required RemoteServer server,
    required String password,
    required Future<List<MusicFile>> Function() onFetchSongs,
    required VoidCallback onClearSelection,
    Set<String>? selectedAlbumIds,
    Set<String>? selectedArtistIds,
    void Function(List<String> starredTrackIds)? onStarredChanged,
    void Function(List<String> starredArtistIds)? onStarredArtistsChanged,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final isJellyfin = server.type == RemoteServerType.jellyfin;
    final brandColor = isJellyfin ? const Color(0xFF9D65C9) : Colors.orange;
    try {
      final client = RemoteMediaLibraryClient.create(
        server: server,
        password: password,
      );

      // Pre-authenticate for Jellyfin to populate session cache safely
      if (client is JellyfinMediaLibraryClient) {
        await client.client.authenticate();
        if (!context.mounted) return;
      }

      int successCount = 0;

      // 1. Album multi-selection mode
      if (selectedAlbumIds != null && selectedAlbumIds.isNotEmpty) {
        final albumIds = selectedAlbumIds.toList();
        for (final albumId in albumIds) {
          final ok = await client.star(albumId: albumId);
          if (ok) successCount++;
        }
        onClearSelection();
        if (context.mounted) {
          if (successCount > 0) {
            showToast(l10n.batchAddedToCloudFavorites);
          } else {
            showToast(l10n.starFailed);
          }
        }
        return;
      }

      // 2. Artist multi-selection mode
      if (selectedArtistIds != null && selectedArtistIds.isNotEmpty) {
        final artistIds = selectedArtistIds.toList();
        final successfulArtistIds = <String>[];
        for (final artistId in artistIds) {
          final ok = await client.star(artistId: artistId);
          if (ok) {
            successCount++;
            successfulArtistIds.add(artistId);
          }
        }
        if (successfulArtistIds.isNotEmpty) {
          onStarredArtistsChanged?.call(successfulArtistIds);
        }
        onClearSelection();
        if (context.mounted) {
          if (successCount > 0) {
            showToast(l10n.batchAddedToCloudFavorites);
          } else {
            showToast(l10n.starFailed);
          }
        }
        return;
      }

      // 3. Songs mode (songs tab, search tab, or detail pages)
      final songs = await _withLoading(
        context: context,
        message: l10n.loadingAlbumTracks,
        indicatorColor: brandColor,
        task: onFetchSongs,
      );
      if (songs == null || songs.isEmpty) return;

      final validTrackIds = <String>[];
      for (final song in songs) {
        final trackId = RemoteMediaResolver.extractTrackId(song) ??
            (song.id != null && song.id! > 0 ? song.id.toString() : '');
        if (trackId.isNotEmpty) {
          validTrackIds.add(trackId);
        }
      }

      final successfulTrackIds = <String>[];
      for (final id in validTrackIds) {
        final ok = await client.star(id: id);
        if (ok) {
          successCount++;
          successfulTrackIds.add(id);
        }
      }

      if (successfulTrackIds.isNotEmpty) {
        onStarredChanged?.call(successfulTrackIds);
      }
      onClearSelection();
      if (context.mounted) {
        if (successCount > 0) {
          showToast(l10n.batchAddedToCloudFavorites);
        } else {
          showToast(l10n.starFailed);
        }
      }
    } catch (e) {
      showToast(e.toString());
    }
  }

  static Future<void> handleBatchDownload({
    required BuildContext context,
    required WidgetRef ref,
    required RemoteServer server,
    required String password,
    required Future<List<RemoteDownloadBatch>> Function() onFetchBatches,
    required VoidCallback onClearSelection,
  }) async {
    try {
      // 勾选下载同样要先把曲目拉回来再入队，进度浮层跟着首数走。
      final batches = await runWithRemoteTrackLoadProgress<List<RemoteDownloadBatch>>(
        context: context,
        immediate: true,
        task: () async {
          final list = await onFetchBatches();
          if (list.isEmpty) return list;
          await ref.read(remoteDownloadTasksProvider.notifier).enqueue(
                RemoteDownloadRequest.grouped(
                  server: server,
                  password: password,
                  batches: list,
                ),
              );
          return list;
        },
      );
      if (batches == null || batches.isEmpty) return;
      onClearSelection();
      final count = batches.fold<int>(0, (sum, batch) => sum + batch.songs.length);
      showRemoteDownloadQueuedFeedback(context, ref, count);
    } catch (e) {
      showToast(e.toString());
    }
  }

  static Future<void> handleBatchTranscode({
    required BuildContext context,
    required Future<List<MusicFile>> Function() onFetchSongs,
    required VoidCallback onClearSelection,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final songs = await _withLoading(
        context: context,
        message: l10n.loadingAlbumTracks,
        task: onFetchSongs,
      );
      if (songs == null || songs.isEmpty) return;
      if (!context.mounted) return;
      await showTranscodeDialog(
        context,
        songs: songs,
      );
      onClearSelection();
    } catch (e) {
      showToast(e.toString());
    }
  }

  static Future<void> handleBatchDeletePlaylists({
    required RemoteServer server,
    required String password,
    required Set<String> selectedPlaylistIds,
    required VoidCallback onClearSelection,
    required VoidCallback onReloadPlaylists,
    BuildContext? context,
    WidgetRef? ref,
  }) async {
    final toDelete = selectedPlaylistIds
        .where((id) => id != starredPlaylistId && id != 'starred_songs')
        .toList();
    if (toDelete.isEmpty) return;
    final client = RemoteMediaLibraryClient.create(
      server: server,
      password: password,
    );
    int failedCount = 0;
    for (final plId in toDelete) {
      final ok = await client.deletePlaylist(plId);
      if (!ok) {
        failedCount++;
      } else if (ref != null) {
        final activeSession = ref.read(activeRemoteSessionProvider);
        if (activeSession != null && activeSession.server.id == server.id) {
          ref
              .read(activeRemoteSessionProvider.notifier)
              .removeNavidromePlaylist(plId);
        }
      }
    }
    onClearSelection();
    onReloadPlaylists();

    if (failedCount > 0 && context != null && context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      final permHint = server.type == RemoteServerType.jellyfin
          ? l10n.jellyfinMediaDeletionPermissionHint
          : '';
      AppSnackBar.show(
        context,
        ref,
        SnackBar(
          content: Text('${l10n.deletePlaylistFailed}$permHint'),
        ),
      );
    }
  }
}

typedef NavidromeSelectionActions = RemoteLibrarySelectionActions;
