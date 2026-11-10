import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'remote_server_models.dart';
import '../../pages/remote/remote_album_detail_page.dart';
import '../../pages/remote/remote_artist_detail_page.dart';
import '../../pages/remote/remote_playlist_detail_page.dart';

/// 三级详情页的唯一入口。
///
/// 三条 `open` 以前走的是「写 `navidromeDetailStack` → 由目录页把详情页拼进
/// 自己的页面栈」这条声明式路线。三期把远程库提为一级 tab 后，这条路没了：
/// 详情页必须压在**调用点所属的那条子分类 Navigator** 上（本地库早就这么做），
/// 于是这里统一退回 `Navigator.of(context).push` —— 只靠 context 层级定位，
/// 不再需要知道自己是第几级分类。
///
/// 为什么一个 `Navigator.of` 就够：调用点全部落在某个分类的根页面或详情页内部，
/// 它们最近的祖先 Navigator 就是 `LibraryTabNavigator` 那一个。
/// * 概览页点封面 → 概览页属于远程库自己的局部 Navigator，压在概览之上，
///   返回回概览（与本地库仪表盘一致）；
/// * 专辑网格点封面 → 压在 albums 分类里，切到艺术家分类再切回来仍在专辑详情；
/// * 详情页里点艺术家 → 压在同一个分类栈里，返回逐级退回。
///
/// iOS / macOS 必须用 `CupertinoPageRoute`，否则左缘侧滑返回失效
/// （`library_page.dart` 的 `_buildSubHostRoute` 同一处理）。
class RemoteLibraryNavUtils {
  static Route<void> _route(WidgetBuilder builder) {
    if (Platform.isIOS || Platform.isMacOS) {
      return CupertinoPageRoute<void>(builder: builder);
    }
    return MaterialPageRoute<void>(builder: builder);
  }

  static void openAlbum(
    BuildContext context, {
    required RemoteServer server,
    required String password,
    required String albumId,
    required String albumName,
    String? artistName,
    String? coverArtId,
    String? highlightedSongPath,
  }) {
    Navigator.of(context).push(
      _route(
        (_) => RemoteAlbumDetailPage(
          server: server,
          password: password,
          albumId: albumId,
          albumName: albumName,
          artistName: artistName,
          coverArtId: coverArtId,
          highlightedSongPath: highlightedSongPath,
        ),
      ),
    );
  }

  static void openArtist(
    BuildContext context, {
    required RemoteServer server,
    required String password,
    required String artistId,
    required String artistName,
    String? coverArtId,
    int? albumCount,
  }) {
    Navigator.of(context).push(
      _route(
        (_) => RemoteArtistDetailPage(
          server: server,
          password: password,
          artistId: artistId,
          artistName: artistName,
          coverArtId: coverArtId,
          albumCount: albumCount,
        ),
      ),
    );
  }

  static void openPlaylist(
    BuildContext context, {
    required RemoteServer server,
    required String password,
    required String playlistId,
    required String playlistName,
    String? coverArtId,
    int? songCount,
    int? duration,
    bool isStarred = false,
    String? highlightedSongPath,
    VoidCallback? onPlaylistModified,
  }) {
    Navigator.of(context).push(
      _route(
        (_) => RemotePlaylistDetailPage(
          server: server,
          password: password,
          playlistId: playlistId,
          playlistName: playlistName,
          coverArtId: coverArtId,
          songCount: songCount,
          duration: duration,
          isStarred: isStarred,
          highlightedSongPath: highlightedSongPath,
          onPlaylistModified: onPlaylistModified,
        ),
      ),
    );
  }
}

typedef NavidromeNavUtils = RemoteLibraryNavUtils;
