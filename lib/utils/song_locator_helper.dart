import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path/path.dart' as p;
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/clients/remote_media_library_client.dart';
import 'package:vynody/player/remote/remote_library_navigation.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';

class SongHighlightNotifier extends Notifier<String?> {
  Timer? _timer;

  @override
  String? build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
    return null;
  }

  void highlight(String path, {Duration duration = const Duration(seconds: 2)}) {
    _timer?.cancel();
    state = path;
    _timer = Timer(duration, () {
      state = null;
    });
  }

  void clear() {
    _timer?.cancel();
    state = null;
  }
}

final songHighlightProvider =
    NotifierProvider<SongHighlightNotifier, String?>(SongHighlightNotifier.new);

class SongLocatorHelper {
  /// 定位是否正在进行中。
  ///
  /// 远程歌曲要先请求服务端解析专辑归属，超时最长 10s（Jellyfin 还需先鉴权），
  /// 按钮用它显示转圈；同时作为重入闸门，避免连点压出重复的专辑页。
  static final ValueNotifier<bool> isLocating = ValueNotifier<bool>(false);

  static List<MusicFolder>? findFolderHistory(
    MusicFolder root,
    String songPath,
  ) {
    List<MusicFolder>? recurse(MusicFolder folder) {
      for (final file in folder.files) {
        if (p.equals(file.path, songPath)) {
          return [folder];
        }
      }
      for (final sub in folder.subFolders) {
        final res = recurse(sub);
        if (res != null) {
          return [folder, ...res];
        }
      }
      return null;
    }

    return recurse(root);
  }

  static List<MusicFolder>? findFolderHistoryByFolderPath(
    MusicFolder root,
    String targetFolderPath,
  ) {
    List<MusicFolder>? recurse(MusicFolder folder) {
      if (ScannerPathUtils.pathsEqual(folder.path, targetFolderPath)) {
        return [folder];
      }
      for (final sub in folder.subFolders) {
        final res = recurse(sub);
        if (res != null) {
          return [folder, ...res];
        }
      }
      return null;
    }

    return recurse(root);
  }

  static Future<bool> locateCurrentPlayingSong(
    WidgetRef ref,
    BuildContext context, {
    bool showNotFoundToast = true,
  }) async {
    if (isLocating.value) return false;
    final currentMusic = ref.read(audioCurrentMusicProvider);
    if (currentMusic == null) return false;

    isLocating.value = true;
    try {
      return await _locateSong(
        ref,
        context,
        currentMusic: currentMusic,
        showNotFoundToast: showNotFoundToast,
      );
    } finally {
      isLocating.value = false;
    }
  }

  static Future<bool> _locateSong(
    WidgetRef ref,
    BuildContext context, {
    required MusicFile currentMusic,
    required bool showNotFoundToast,
  }) async {
    final l10n = AppLocalizations.of(context);
    final songPath = currentMusic.path;

    final remoteInfo = RemoteMediaResolver.parseUri(songPath);
    if (remoteInfo != null) {
      // 冷启动时服务器列表可能还没加载完，直接读 asData 会得到空表，
      // 于是把「还没读到」误判成「歌曲已不在任何库里」。
      final servers = await _loadedRemoteServers(ref);
      final server =
          servers.firstWhereOrNull((s) => s.id == remoteInfo.serverId);
      if (server == null) {
        if (showNotFoundToast && l10n != null) {
          showToast(l10n.remoteAlbumUnavailable);
        }
        return false;
      }
      final password = await ref
              .read(remoteServersProvider.notifier)
              .getPassword(server.id) ??
          '';

      if (remoteInfo.type == RemoteServerType.webdav ||
          remoteInfo.type == RemoteServerType.smb) {
        final targetDir = p.posix.dirname(remoteInfo.trackIdOrPath);
        final rootPath = normalizeRemotePath(server.customPath);
        final stack =
            ActiveRemoteSession.buildWebDavPathStack(rootPath, targetDir);
        final activeSession = ref.read(activeRemoteSessionProvider);
        if (activeSession == null || activeSession.server.id != server.id) {
          ref.read(activeRemoteSessionProvider.notifier).setSession(
                ActiveRemoteSession(
                  server: server,
                  password: password,
                  rootPath: rootPath,
                  initialPath: targetDir,
                  webDavPathStack: stack,
                  webDavHighlightedSongPath: songPath,
                ),
              );
        } else {
          ref.read(activeRemoteSessionProvider.notifier).setWebDavLocation(
                pathStack: stack,
                highlightedSongPath: songPath,
              );
        }
        ref.read(songHighlightProvider.notifier).highlight(songPath);
        return true;
      } else if (remoteInfo.type == RemoteServerType.subsonic ||
                 remoteInfo.type == RemoteServerType.jellyfin) {
        // Subsonic / Jellyfin 只有一个出口：解析曲目所属专辑，打开专辑详情页。
        // 不再先看当前位置能不能滚过去，也不再落到本地扫描目录里找。
        if (!context.mounted) return false;
        return _openAlbumForRemoteSong(
          ref,
          context,
          server: server,
          password: password,
          songPath: songPath,
          trackId: remoteInfo.trackIdOrPath,
          l10n: l10n,
          showNotFoundToast: showNotFoundToast,
        );
      }
    }

    // Local song handling
    final activeSession = ref.read(activeRemoteSessionProvider);
    if (activeSession != null) {
      ref.read(activeRemoteSessionProvider.notifier).clear();
    }

    final scanner = ref.read(scannerServiceProvider);
    List<MusicFolder>? foundHistory;

    for (final root in scanner.rootFolders) {
      foundHistory = findFolderHistory(root, songPath);
      if (foundHistory != null) {
        break;
      }
    }

    if (foundHistory == null && scanner.systemMediaFolder != null) {
      foundHistory = findFolderHistory(
        scanner.systemMediaFolder!,
        songPath,
      );
    }

    if (foundHistory == null) {
      final songMeta = await scanner.getSongMetadata(songPath);
      final isSystemMedia = songMeta != null &&
          ((songMeta.sourceFlags ?? 0) & SongSourceFlags.systemMedia) != 0;

      if (!isSystemMedia) {
        final matchingRootPath = scanner.rootPaths.firstWhereOrNull(
          (root) => ScannerPathUtils.pathContains(root, songPath),
        );
        if (matchingRootPath != null) {
          await scanner.loadRootFolderSongs(matchingRootPath);
        } else {
          for (final rootPath in scanner.rootPaths) {
            await scanner.loadRootFolderSongs(rootPath);
          }
        }
      }

      for (final root in scanner.rootFolders) {
        foundHistory = findFolderHistory(root, songPath);
        if (foundHistory != null) {
          break;
        }
      }

      if (foundHistory == null && scanner.systemMediaFolder != null) {
        foundHistory = findFolderHistory(
          scanner.systemMediaFolder!,
          songPath,
        );
      }
    }

    if (!context.mounted) return false;

    if (foundHistory != null && foundHistory.isNotEmpty) {
      final targetFolder = foundHistory.last;
      final history = foundHistory.sublist(0, foundHistory.length - 1);
      final alreadyInFolder =
          scanner.navigationCurrentFolder?.path == targetFolder.path;

      if (!alreadyInFolder) {
        scanner.setNavigationState(targetFolder, history);
      }

      ref.read(songHighlightProvider.notifier).highlight(currentMusic.path);
      return true;
    } else {
      if (showNotFoundToast && l10n != null) {
        showToast(l10n.songNotInScannedFolders);
      }
      return false;
    }
  }

  /// 同一时刻只处理一次远程定位，见 [isLocating]。

  /// 取远程服务器列表；还没加载完就等它，加载失败按空表处理。
  static Future<List<RemoteServer>> _loadedRemoteServers(WidgetRef ref) async {
    final asyncServers = ref.read(remoteServersProvider);
    if (asyncServers.hasValue) return asyncServers.requireValue;
    try {
      return await ref.read(remoteServersProvider.future);
    } catch (_) {
      return const [];
    }
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// 定位一首 Subsonic / Jellyfin 歌曲：解析它所属的专辑，打开专辑详情页并高亮该曲。
  ///
  /// 目录页、远程媒体库页、专辑详情页共用这一条路径，行为与点击位置无关。
  /// 服务端拿不到专辑归属（曲目被删除、服务器不可达、无专辑字段）时只给一条提示，
  /// 不再伪装成「不在扫描目录中」，也不再回落到本地扫描树。
  static Future<bool> _openAlbumForRemoteSong(
    WidgetRef ref,
    BuildContext context, {
    required RemoteServer server,
    required String password,
    required String songPath,
    required String trackId,
    AppLocalizations? l10n,
    bool showNotFoundToast = true,
  }) async {
    Map<String, dynamic>? songData;
    String? albumId;
    Object? failure;
    try {
      final client = RemoteMediaLibraryClient.create(
        server: server,
        password: password,
      );
      songData = await client.getSong(trackId);
      albumId = _nonEmpty(songData?['albumId'] as String?) ??
          _nonEmpty(songData?['parent'] as String?);
    } catch (error, stack) {
      // 客户端内部把异常吞成了 null，这里只做兜底记录，避免整条链路无日志。
      failure = error;
      debugPrint('[Locate] resolve remote song failed: $error\n$stack');
    }

    if (albumId == null) {
      debugPrint(
        '[Locate] album unavailable for ${server.type.name}:$trackId '
        '(songData=${songData != null}, failure=$failure)',
      );
      if (showNotFoundToast && l10n != null) {
        showToast(l10n.remoteAlbumUnavailable);
      }
      return false;
    }

    if (!context.mounted) return false;

    final albumName = _nonEmpty(songData?['album'] as String?) ?? 'Album';
    final artistName = _nonEmpty(songData?['artist'] as String?);
    final coverArtId = _nonEmpty(songData?['coverArt'] as String?);
    final activeSession = ref.read(activeRemoteSessionProvider);

    if (activeSession == null || activeSession.server.id != server.id) {
      ref.read(activeRemoteSessionProvider.notifier).setSession(
            ActiveRemoteSession(
              server: server,
              password: password,
              navidromeDetailStack: [
                NavidromeAlbumRoute(
                  albumId: albumId,
                  albumName: albumName,
                  artistName: artistName,
                  coverArtId: coverArtId,
                  highlightedSongPath: songPath,
                ),
              ],
            ),
          );
    } else {
      RemoteLibraryNavUtils.openAlbum(
        context,
        ref,
        server: server,
        password: password,
        albumId: albumId,
        albumName: albumName,
        artistName: artistName,
        coverArtId: coverArtId,
        highlightedSongPath: songPath,
      );
    }

    ref.read(songHighlightProvider.notifier).highlight(songPath);
    return true;
  }
}
