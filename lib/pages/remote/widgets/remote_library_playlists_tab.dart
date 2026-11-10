import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';
import '../../../l10n/app_localizations.dart';
import '../../../player/audio/audio_riverpod.dart';
import '../../../player/remote/clients/remote_media_library_client.dart';
import '../../../player/remote/remote_library_navigation.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../player/remote/remote_server_riverpod.dart';
import '../../../utils/app_snack_bar.dart';
import 'remote_library_common_widgets.dart';
import '../../../utils/remote_context_menu_utils.dart';
import '../../../utils/selection_utils.dart';
import '../../../widgets/draggable_remote_playlist_item.dart';
import '../../../widgets/folder_layout_utils.dart';
import '../../../widgets/folder_zoom_gesture_layer.dart';
import '../../../widgets/remote_playlist_zoom_item.dart';
import 'remote_library_toolbar_widgets.dart';

class RemoteLibraryPlaylistsToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onCreatePlaylist;
  final VoidCallback onRefresh;
  final int? totalCount;

  const RemoteLibraryPlaylistsToolbar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onCreatePlaylist,
    required this.onRefresh,
    this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final searchBar = RemoteSearchBar(
      controller: searchController,
      hintText: l10n.searchPlaylists,
      searchQuery: searchController.text,
      onChanged: onSearchChanged,
      onClear: onClearSearch,
      fillColor:
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
    );

    final createButton = IconButton.filledTonal(
      style: kCompactIconButtonStyle,
      tooltip: l10n.createNewServerPlaylist,
      icon: const Icon(Icons.add_rounded, size: 18),
      onPressed: onCreatePlaylist,
    );

    final refreshButton = IconButton(
      style: kCompactIconButtonStyle,
      tooltip: l10n.refresh,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      onPressed: onRefresh,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          final isZh = Localizations.localeOf(context).languageCode == 'zh';
          final countText = totalCount != null
              ? Text(
                  isZh ? '共 $totalCount 个歌单' : '$totalCount ${l10n.playlists}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                )
              : null;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                ?countText,
                const Spacer(),
                SizedBox(
                  width: 200,
                  child: searchBar,
                ),
                const SizedBox(width: 8),
                createButton,
                const SizedBox(width: 6),
                refreshButton,
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: searchBar),
              const SizedBox(width: 8),
              createButton,
              const SizedBox(width: 6),
              refreshButton,
            ],
          ),
        );
      },
    );
  }
}

/// 远程歌单条目在网格里展示所需的派生字段。
///
/// 会话缓存优先于接口返回值：正在播的那份详情里曲目数是实时的，而列表接口
/// 返回的 `songCount` 可能落后于刚刚的增删。
class _RemotePlaylistEntry {
  const _RemotePlaylistEntry({
    required this.raw,
    required this.id,
    required this.name,
    required this.songCount,
    required this.coverArt,
    required this.isPinned,
  });

  final Map<String, dynamic> raw;
  final String id;
  final String name;
  final int songCount;
  final String? coverArt;

  /// 星标歌曲这一虚拟歌单（由外层页面插在首位，只用于样式与菜单门控）。
  final bool isPinned;
}

class RemoteLibraryPlaylistsView extends ConsumerStatefulWidget {
  static const String starredPlaylistId = '__navidrome_starred_songs__';

  final RemoteServer server;
  final String password;
  final List<Map<String, dynamic>> playlists;
  final String? selectedPlaylistId;
  final bool isLoading;
  final String? error;
  final Future<void> Function() onRefresh;
  final String searchQuery;
  final double bottomOffset;
  final bool isSelectionMode;
  final Set<String> selectedPlaylistIds;
  final int? lastPlaylistAnchorIndex;
  final ValueChanged<String?> onSelectPlaylistId;
  final void Function(Set<String> keys) onSetSelection;
  final void Function(String playlistId) onToggleSelection;
  final void Function(int? index) onUpdateAnchor;
  final Widget? toolbar;

  const RemoteLibraryPlaylistsView({
    super.key,
    required this.server,
    required this.password,
    required this.playlists,
    required this.selectedPlaylistId,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.searchQuery,
    required this.bottomOffset,
    required this.isSelectionMode,
    required this.selectedPlaylistIds,
    required this.lastPlaylistAnchorIndex,
    required this.onSelectPlaylistId,
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    this.toolbar,
  });

  @override
  ConsumerState<RemoteLibraryPlaylistsView> createState() =>
      _RemoteLibraryPlaylistsViewState();
}

class _RemoteLibraryPlaylistsViewState
    extends ConsumerState<RemoteLibraryPlaylistsView> {
  bool _isPinned(Map<String, dynamic> playlist) {
    final id = playlist['id'] as String? ?? '';
    return id == RemoteLibraryPlaylistsView.starredPlaylistId ||
        playlist['isStarred'] == true;
  }

  List<_RemotePlaylistEntry> _resolveEntries(
    List<Map<String, dynamic>> playlists,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final session = ref.watch(activeRemoteSessionProvider);
    final currentSession =
        (session != null && session.server.id == widget.server.id)
            ? session
            : null;

    return <_RemotePlaylistEntry>[
      for (final playlist in playlists)
        () {
          final id = playlist['id'] as String? ?? '';
          final isPinned = _isPinned(playlist);

          final sessionPlaylist = currentSession?.navidromePlaylists
              ?.where((p) => p['id']?.toString() == id)
              .firstOrNull;
          final cachedDetail =
              currentSession?.navidromePlaylistDetailsCache[id];

          final name = (sessionPlaylist != null &&
                  sessionPlaylist['name'] != null)
              ? (sessionPlaylist['name'] as String)
              : (playlist['name'] as String? ?? l10n.playlist);

          final int songCount;
          if (isPinned) {
            songCount = currentSession?.navidromeStarredSongIds?.length ??
                (playlist['songCount'] as int? ?? 0);
          } else if (cachedDetail != null) {
            songCount = cachedDetail.tracks.length;
          } else if (sessionPlaylist != null &&
              sessionPlaylist['songCount'] != null) {
            songCount = sessionPlaylist['songCount'] as int? ?? 0;
          } else {
            songCount = playlist['songCount'] as int? ?? 0;
          }

          return _RemotePlaylistEntry(
            raw: playlist,
            id: id,
            name: isPinned ? l10n.starredSongs : name,
            songCount: songCount,
            coverArt: playlist['coverArt'] as String?,
            isPinned: isPinned,
          );
        }(),
    ];
  }

  void _openPlaylist(_RemotePlaylistEntry entry) {
    final l10n = AppLocalizations.of(context)!;
    widget.onSelectPlaylistId(entry.id);
    RemoteLibraryNavUtils.openPlaylist(
      context,
      ref,
      server: widget.server,
      password: widget.password,
      playlistId: entry.id,
      playlistName: entry.isPinned
          ? l10n.starredSongs
          : (entry.raw['name'] as String? ?? l10n.playlist),
      coverArtId: entry.coverArt,
      songCount: entry.songCount,
      duration: entry.raw['duration'] as int?,
      isStarred: entry.raw['isStarred'] == true || entry.isPinned,
      onPlaylistModified: widget.onRefresh,
    );
  }

  void _showDeleteDialog(String name, String playlistId) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deletePlaylist),
        content: Text(l10n.confirmDeletePlaylist(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final client = RemoteMediaLibraryClient.create(
                server: widget.server,
                password: widget.password,
              );
              final ok = await client.deletePlaylist(playlistId);
              if (ok) {
                final activeSession = ref.read(activeRemoteSessionProvider);
                if (activeSession != null &&
                    activeSession.server.id == widget.server.id) {
                  ref
                      .read(activeRemoteSessionProvider.notifier)
                      .removeNavidromePlaylist(playlistId);
                }
                showToast(l10n.playlistDeleted);
                widget.onRefresh();
              } else {
                if (mounted) {
                  final permHint =
                      widget.server.type == RemoteServerType.jellyfin
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
            },
            child: Text(
              l10n.delete,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(String currentName, String playlistId) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: currentName);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renamePlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.playlistName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != currentName) {
                final client = RemoteMediaLibraryClient.create(
                  server: widget.server,
                  password: widget.password,
                );
                final ok = await client.updatePlaylist(
                  playlistId: playlistId,
                  name: newName,
                );
                if (ok) {
                  final activeSession = ref.read(activeRemoteSessionProvider);
                  if (activeSession != null &&
                      activeSession.server.id == widget.server.id) {
                    final currentPlaylists =
                        activeSession.navidromePlaylists ?? [];
                    final updatedPlaylists = currentPlaylists.map((p) {
                      if (p['id'] == playlistId) {
                        return Map<String, dynamic>.from(p)
                          ..['name'] = newName;
                      }
                      return p;
                    }).toList();
                    ref
                        .read(activeRemoteSessionProvider.notifier)
                        .updateNavidromePlaylists(playlists: updatedPlaylists);
                  }
                  widget.onRefresh();
                } else if (mounted) {
                  AppSnackBar.show(
                    context,
                    ref,
                    SnackBar(content: Text('${l10n.renamePlaylist}: failed')),
                  );
                }
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(
    _RemotePlaylistEntry entry,
    int index,
    Offset globalPosition,
  ) {
    showRemotePlaylistContextMenu(
      context: context,
      globalPosition: globalPosition,
      ref: ref,
      server: widget.server,
      password: widget.password,
      playlistId: entry.id,
      playlistName: entry.name,
      onViewDetails: () => _openPlaylist(entry),
      onRename: () => _showRenameDialog(entry.name, entry.id),
      onDelete: () => _showDeleteDialog(entry.name, entry.id),
      onMultiSelect: widget.isSelectionMode
          ? null
          : () {
              widget.onUpdateAnchor(index);
              widget.onToggleSelection(entry.id);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (widget.isLoading) {
      return RemoteLibraryLoadingView(
        server: widget.server,
        icon: Icons.queue_music_rounded,
      );
    }
    if (widget.error != null) {
      return RemoteLibraryErrorView(
        error: l10n.errorLoadingPlaylists(widget.error!),
        onRetry: widget.onRefresh,
      );
    }

    // 顺序完全用服务端返回的原序（星标虚拟歌单由外层页面插在首位）。
    // 服务端没有「歌单之间排序」的接口，所以这里不做本地排序，也不提供拖拽重排。
    final entries = _resolveEntries(widget.playlists);
    final zoomScale =
        snapFolderZoomScale(ref.watch(settingsServiceProvider).folderZoomScale);
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    final toolbarSliver = widget.toolbar != null
        ? SliverRemoteContentConstraint(
            // 与本地歌单页同宽：这一页没有单列上限，铺满内容区。
            maxWidth: kFolderPageMaxWidth,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: widget.toolbar!,
          )
        : null;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: FolderZoomGestureLayer(
        zoomGesturesEnabled: !widget.isSelectionMode,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                ?toolbarSliver,
                if (entries.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        widget.searchQuery.isEmpty
                            ? l10n.noPlaylistsFound
                            : l10n.noMatchingPlaylists,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  FolderZoomSliverBuilder(
                    zoomScale: zoomScale,
                    width: width,
                    // 本页 loading/error 是裸 view、有内容才套 RefreshIndicator，
                    // 即 ScrollView 的祖先结构会切换 —— 这种页面禁传 controller
                    // （切分支那帧会炸在 sliver 布局里，整页空白）。
                    builder: (context, metrics) {
                      final hPad = folderContentHorizontalPadding(
                        isPortrait: isPortrait,
                        gridMorph: metrics.gridMorph,
                      );

                      return SliverPadding(
                        padding: EdgeInsets.only(
                          left: hPad,
                          right: hPad,
                          top: isPortrait ? 8.0 : 16.0,
                          bottom: widget.bottomOffset,
                        ),
                        // 不可重排：服务端没有歌单之间的排序接口，直接用原始顺序。
                        sliver: SliverGrid(
                          gridDelegate: SliverAnimatedZoomGridDelegate(
                            metrics: metrics,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final entry = entries[index];
                              final isSelected = widget.selectedPlaylistIds
                                  .contains(entry.id);
                              return DraggableRemotePlaylistItem(
                                server: widget.server,
                                playlist: entry.raw,
                                songCount: entry.songCount,
                                isSelectionMode: widget.isSelectionMode,
                                isSelected: isSelected,
                                selectedPlaylistIds:
                                    widget.selectedPlaylistIds,
                                child: RemotePlaylistZoomItem(
                                  server: widget.server,
                                  password: widget.password,
                                  title: entry.name,
                                  songCount: entry.songCount,
                                  coverArtId: entry.coverArt,
                                  isPinned: entry.isPinned,
                                  metrics: metrics,
                                  index: index,
                                  isSelected: isSelected,
                                  isSelectionMode: widget.isSelectionMode,
                                  onTap: () {
                                    SelectionActionHelper.handleItemTap(
                                      index: index,
                                      itemKey: entry.id,
                                      items: entries,
                                      keySelector: (e) => e.id,
                                      isSelectionMode: widget.isSelectionMode,
                                      selectedKeys: widget.selectedPlaylistIds,
                                      lastAnchorIndex:
                                          widget.lastPlaylistAnchorIndex,
                                      onUpdateAnchor: widget.onUpdateAnchor,
                                      onSetSelection: widget.onSetSelection,
                                      onToggleSelection:
                                          widget.onToggleSelection,
                                      onNormalTap: () => _openPlaylist(entry),
                                    );
                                  },
                                  onLongPress: () {
                                    widget.onUpdateAnchor(index);
                                    widget.onToggleSelection(entry.id);
                                  },
                                  onSecondaryTapDown: entry.isPinned ||
                                          widget.isSelectionMode
                                      ? null
                                      : (details) => _showContextMenu(
                                            entry,
                                            index,
                                            details.globalPosition,
                                          ),
                                ),
                              );
                            },
                            childCount: entries.length,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> showCreateNavidromePlaylistDialog({
  required BuildContext context,
  required RemoteMediaLibraryClient client,
  required void Function(Map<String, dynamic> created) onCreated,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.createNewServerPlaylist),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.playlistName,
          hintText: l10n.enterPlaylistName,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              Navigator.pop(ctx);
              final created = await client.createPlaylist(name: name);
              if (created != null && context.mounted) {
                showToast(l10n.createdPlaylistSuccess(name));
                onCreated(created);
              }
            }
          },
          child: Text(l10n.confirm),
        ),
      ],
    ),
  );
}

typedef NavidromePlaylistsToolbar = RemoteLibraryPlaylistsToolbar;
typedef NavidromePlaylistsView = RemoteLibraryPlaylistsView;
