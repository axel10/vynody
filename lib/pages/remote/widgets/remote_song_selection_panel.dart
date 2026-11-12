import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/music_file.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../widgets/library_selection_panel.dart';
import 'remote_library_selection_actions.dart';

/// 远程批量操作里可以由面板统一接管的动作。
///
/// 各页面只声明「要哪些」，回调由 [RemoteSongSelectionPanel] 按
/// [RemoteLibrarySelectionActions] 里已有的实现统一装配 —— 此前每个页面都在
/// 复读同一份 `handleBatchXxx(... onClearSelection: ..., ...)` 参数组合。
enum RemoteSelectionAction {
  playNext,
  addToQueue,
  addToPlaylist,
  addToLocalFavorites,
  addToCloudFavorites,
  transcode,
}

/// 常用动作集合。
abstract final class RemoteSelectionActions {
  /// 媒体库分类页：全套。
  static const Set<RemoteSelectionAction> library = {
    RemoteSelectionAction.playNext,
    RemoteSelectionAction.addToQueue,
    RemoteSelectionAction.addToPlaylist,
    RemoteSelectionAction.addToLocalFavorites,
    RemoteSelectionAction.addToCloudFavorites,
    RemoteSelectionAction.transcode,
  };

  /// 详情页（专辑 / 艺术家 / 歌单）：只有收藏与下载/转码这类对曲目本体无副作用
  /// 的动作。队列与歌单操作在详情页里语义含糊（「把这张专辑的歌加入队列」与顶部的
  /// 播放全部按钮重复），不放进来。
  static const Set<RemoteSelectionAction> detail = {
    RemoteSelectionAction.addToLocalFavorites,
    RemoteSelectionAction.addToCloudFavorites,
  };
}

/// 远程媒体库的批量操作面板。
///
/// 把 `LibrarySelectionPanel` 的构造与 `RemoteLibrarySelectionActions` 的调用
/// 收成一处，各页面只提供数据与少量覆盖项（删除、下载）。
///
/// 下载**不**由本组件接管：专辑 / 歌单 / 媒体库分类页的落盘层级不同
/// （`RemoteDownloadLayout` 与 `collectionFolder`），由调用方通过 [onDownload]
/// 自行入队，以免把「按页面定层级」这条不变量藏进共享组件里。
class RemoteSongSelectionPanel extends ConsumerWidget {
  const RemoteSongSelectionPanel({
    super.key,
    required this.server,
    required this.password,
    required this.selectedSongs,
    required this.allSongs,
    required this.onFetchSongs,
    required this.onClearSelection,
    this.actions = RemoteSelectionActions.detail,
    this.panelKey,
    this.title,
    this.isSelectionEmpty,
    this.isAllSelected,
    this.onToggleSelectAll,
    this.hideSongProperties = false,
    this.selectedAlbumIds,
    this.selectedArtistIds,
    this.onStarredChanged,
    this.onStarredArtistsChanged,
    this.onDelete,
    this.deleteLabel,
    this.onDownload,
  });

  final RemoteServer server;
  final String password;

  final List<MusicFile> selectedSongs;

  /// 当前列表里的全部曲目，供「全选」判断使用。
  final List<MusicFile> allSongs;

  /// 把选中项展开成可播放曲目。媒体库分类页在多选专辑/艺术家时需要现拉曲目，
  /// 详情页直接返回 [selectedSongs] 即可。
  final Future<List<MusicFile>> Function() onFetchSongs;

  final VoidCallback onClearSelection;

  final Set<RemoteSelectionAction> actions;

  /// 透传给内部 `LibrarySelectionPanel` 的 key。
  ///
  /// 媒体库主页面板随 tab 切换复用同一个位置，靠 key 让 `AnimatedSwitcher`
  /// 认出是另一份面板而不是原地改内容。
  final Key? panelKey;

  final String? title;
  final bool? isSelectionEmpty;
  final bool? isAllSelected;
  final VoidCallback? onToggleSelectAll;
  final bool hideSongProperties;

  final Set<String>? selectedAlbumIds;
  final Set<String>? selectedArtistIds;
  final void Function(List<String> starredTrackIds)? onStarredChanged;
  final void Function(List<String> starredArtistIds)? onStarredArtistsChanged;

  final VoidCallback? onDelete;
  final String? deleteLabel;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool Function(Object?) has = actions.contains;

    return LibrarySelectionPanel(
      key: panelKey,
      selectedSongs: selectedSongs,
      allSongs: allSongs,
      title: title,
      isSelectionEmpty: isSelectionEmpty,
      isAllSelected: isAllSelected,
      onToggleSelectAll: onToggleSelectAll,
      onCancel: onClearSelection,
      hideSongProperties: hideSongProperties,
      onPlayNext: has(RemoteSelectionAction.playNext)
          ? () => RemoteLibrarySelectionActions.handleBatchPlayNext(
              context: context,
              ref: ref,
              onFetchSongs: onFetchSongs,
              onClearSelection: onClearSelection,
            )
          : null,
      onAddToQueue: has(RemoteSelectionAction.addToQueue)
          ? () => RemoteLibrarySelectionActions.handleBatchAddToQueue(
              context: context,
              ref: ref,
              onFetchSongs: onFetchSongs,
              onClearSelection: onClearSelection,
            )
          : null,
      onAddToPlaylist: has(RemoteSelectionAction.addToPlaylist)
          ? () => RemoteLibrarySelectionActions.handleBatchAddToPlaylist(
              context: context,
              ref: ref,
              server: server,
              password: password,
              onFetchSongs: onFetchSongs,
              onClearSelection: onClearSelection,
            )
          : null,
      onAddToFavorites: has(RemoteSelectionAction.addToLocalFavorites)
          ? () => RemoteLibrarySelectionActions.handleBatchAddToLocalFavorites(
              context: context,
              ref: ref,
              onFetchSongs: onFetchSongs,
              onClearSelection: onClearSelection,
            )
          : null,
      onAddToCloudFavorites: has(RemoteSelectionAction.addToCloudFavorites)
          ? () => RemoteLibrarySelectionActions.handleBatchAddToCloudFavorites(
              context: context,
              ref: ref,
              server: server,
              password: password,
              selectedAlbumIds: selectedAlbumIds,
              selectedArtistIds: selectedArtistIds,
              // 面板手里的曲目就是「直接勾中的那些」：集合类条目（专辑 /
              // 艺术家）展开出来的歌不该被逐首再收藏一遍。
              directSongs: selectedSongs,
              onFetchSongs: onFetchSongs,
              onClearSelection: onClearSelection,
              onStarredChanged: onStarredChanged,
              onStarredArtistsChanged: onStarredArtistsChanged,
            )
          : null,
      onTranscode: has(RemoteSelectionAction.transcode)
          ? () => RemoteLibrarySelectionActions.handleBatchTranscode(
              context: context,
              onFetchSongs: onFetchSongs,
              onClearSelection: onClearSelection,
            )
          : null,
      onDownload: onDownload,
      onDelete: onDelete,
      deleteLabel: deleteLabel,
    );
  }
}
