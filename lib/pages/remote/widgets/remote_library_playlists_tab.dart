import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';
import '../../../l10n/app_localizations.dart';
import '../../../player/remote/clients/remote_media_library_client.dart';
import '../../../player/remote/remote_library_navigation.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../player/remote/remote_server_riverpod.dart';
import '../../../utils/app_snack_bar.dart';
import 'remote_library_common_widgets.dart';
import '../../../utils/remote_context_menu_utils.dart';
import '../../../utils/selection_utils.dart';
import '../../../widgets/draggable_remote_playlist_item.dart';
import '../../../widgets/remote_artwork_widget.dart';
import '../remote_playlist_detail_page.dart';
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

class RemoteLibraryPlaylistsView extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (isLoading) {
      return RemoteLibraryLoadingView(
        server: server,
        icon: Icons.queue_music_rounded,
      );
    }
    if (error != null) {
      return RemoteLibraryErrorView(
        error: l10n.errorLoadingPlaylists(error!),
        onRetry: onRefresh,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape =
            constraints.maxWidth >= 750 && playlists.isNotEmpty;

        final selectedPlaylist = playlists
                .where((pl) => pl['id'] == selectedPlaylistId)
                .firstOrNull ??
            (playlists.isNotEmpty ? playlists.first : const <String, dynamic>{});

        if (isLandscape) {
          return _LandscapePlaylistsSplitView(
            server: server,
            password: password,
            playlists: playlists,
            selectedPlaylist: selectedPlaylist,
            onRefresh: onRefresh,
            bottomOffset: bottomOffset,
            isSelectionMode: isSelectionMode,
            selectedPlaylistIds: selectedPlaylistIds,
            lastPlaylistAnchorIndex: lastPlaylistAnchorIndex,
            onSelectPlaylistId: onSelectPlaylistId,
            onSetSelection: onSetSelection,
            onToggleSelection: onToggleSelection,
            onUpdateAnchor: onUpdateAnchor,
            toolbar: toolbar,
            maxWidth: constraints.maxWidth,
          );
        }

        final toolbarSliver = toolbar != null
            ? SliverRemoteContentConstraint(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: toolbar!,
              )
            : null;

        // Portrait: Vertical List of Playlist Cards
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                ?toolbarSliver,
                if (playlists.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        searchQuery.isEmpty
                            ? l10n.noPlaylistsFound
                            : l10n.noMatchingPlaylists,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, bottomOffset),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final pl = playlists[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: RemoteLibraryPlaylistItem(
                              server: server,
                              password: password,
                              playlist: pl,
                              index: index,
                              allPlaylists: playlists,
                              isSelected: false,
                              isMultiSelected: selectedPlaylistIds
                                  .contains(pl['id'] as String? ?? ''),
                              isSelectionMode: isSelectionMode,
                              selectedPlaylistIds: selectedPlaylistIds,
                              lastPlaylistAnchorIndex: lastPlaylistAnchorIndex,
                              onSetSelection: onSetSelection,
                              onToggleSelection: onToggleSelection,
                              onUpdateAnchor: onUpdateAnchor,
                              onRefreshPlaylists: onRefresh,
                              onTap: () {
                                RemoteLibraryNavUtils.openPlaylist(
                                  context,
                                  ref,
                                  server: server,
                                  password: password,
                                  playlistId: pl['id'] as String? ?? '',
                                  playlistName:
                                      pl['name'] as String? ?? l10n.playlist,
                                  coverArtId: pl['coverArt'] as String?,
                                  songCount: pl['songCount'] as int?,
                                  duration: pl['duration'] as int?,
                                  isStarred: pl['isStarred'] == true ||
                                      pl['id'] == starredPlaylistId,
                                  onPlaylistModified: onRefresh,
                                );
                              },
                            ),
                          );
                        },
                        childCount: playlists.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
      },
    );
  }
}

class RemoteLibraryPlaylistItem extends ConsumerWidget {
  static const String starredPlaylistId = '__navidrome_starred_songs__';

  final RemoteServer server;
  final String password;
  final Map<String, dynamic> playlist;
  final int index;
  final List<Map<String, dynamic>> allPlaylists;
  final bool isSelected;
  final bool isMultiSelected;
  final bool isSelectionMode;
  final Set<String> selectedPlaylistIds;
  final int? lastPlaylistAnchorIndex;
  final void Function(Set<String> keys) onSetSelection;
  final void Function(String playlistId) onToggleSelection;
  final void Function(int? index) onUpdateAnchor;
  final VoidCallback onRefreshPlaylists;
  final VoidCallback onTap;

  const RemoteLibraryPlaylistItem({
    super.key,
    required this.server,
    required this.password,
    required this.playlist,
    required this.index,
    required this.allPlaylists,
    required this.isSelected,
    required this.isMultiSelected,
    required this.isSelectionMode,
    required this.selectedPlaylistIds,
    required this.lastPlaylistAnchorIndex,
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    required this.onRefreshPlaylists,
    required this.onTap,
  });

  void _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    String name,
    String playlistId,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
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
                server: server,
                password: password,
              );
              final ok = await client.deletePlaylist(playlistId);
              if (ok) {
                final activeSession = ref.read(activeRemoteSessionProvider);
                if (activeSession != null &&
                    activeSession.server.id == server.id) {
                  ref
                      .read(activeRemoteSessionProvider.notifier)
                      .removeNavidromePlaylist(playlistId);
                }
                showToast(l10n.playlistDeleted);
                onRefreshPlaylists();
              } else {
                if (context.mounted) {
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
            },
            child: Text(l10n.delete,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    String currentName,
    String playlistId,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renamePlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.playlistName,
          ),
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
                  server: server,
                  password: password,
                );
                final ok = await client.updatePlaylist(
                  playlistId: playlistId,
                  name: newName,
                );
                if (ok) {
                  final activeSession = ref.read(activeRemoteSessionProvider);
                  if (activeSession != null &&
                      activeSession.server.id == server.id) {
                    final currentPlaylists =
                        activeSession.navidromePlaylists ?? [];
                    final updatedPlaylists = currentPlaylists.map((p) {
                      if (p['id'] == playlistId) {
                        return Map<String, dynamic>.from(p)..['name'] = newName;
                      }
                      return p;
                    }).toList();
                    ref
                        .read(activeRemoteSessionProvider.notifier)
                        .updateNavidromePlaylists(
                          playlists: updatedPlaylists,
                        );
                  }
                  onRefreshPlaylists();
                } else if (context.mounted) {
                  AppSnackBar.show(
                    context,
                    ref,
                    SnackBar(
                      content: Text('${l10n.renamePlaylist}: failed'),
                    ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final playlistId = playlist['id'] as String? ?? '';
    final isStarredItem =
        playlist['isStarred'] == true || playlistId == starredPlaylistId;

    final session = ref.watch(activeRemoteSessionProvider);
    final isCurrentServer = session != null && session.server.id == server.id;

    final cachedDetail = isCurrentServer
        ? session.navidromePlaylistDetailsCache[playlistId]
        : null;

    final sessionPlaylist = isCurrentServer
        ? session.navidromePlaylists
            ?.where((p) => p['id']?.toString() == playlistId)
            .firstOrNull
        : null;

    final name = (sessionPlaylist != null && sessionPlaylist['name'] != null)
        ? (sessionPlaylist['name'] as String)
        : (playlist['name'] as String? ?? l10n.playlist);

    final songCount = isStarredItem
        ? (session?.navidromeStarredSongIds?.length ??
            (playlist['songCount'] as int? ?? 0))
        : (cachedDetail != null
            ? cachedDetail.tracks.length
            : (sessionPlaylist != null && sessionPlaylist['songCount'] != null
                ? (sessionPlaylist['songCount'] as int? ?? 0)
                : (playlist['songCount'] as int? ?? 0)));

    final durationSec = (sessionPlaylist != null &&
            sessionPlaylist['duration'] != null)
        ? (sessionPlaylist['duration'] as int? ?? 0)
        : (playlist['duration'] as int? ?? 0);
    final durationMin = durationSec ~/ 60;
    final coverArt = playlist['coverArt'] as String?;

    final backgroundColor = isSelectionMode && isMultiSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
        : (isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35));

    final itemWidget = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: isStarredItem || isSelectionMode
          ? null
          : (details) {
              showRemotePlaylistContextMenu(
                context: context,
                globalPosition: details.globalPosition,
                ref: ref,
                server: server,
                password: password,
                playlistId: playlistId,
                playlistName: name,
                onViewDetails: onTap,
                onRename: () =>
                    _showRenameDialog(context, ref, name, playlistId),
                onDelete: () =>
                    _showDeleteDialog(context, ref, name, playlistId),
              );
            },
      onLongPressStart: (details) {
        onUpdateAnchor(index);
        onToggleSelection(playlistId);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            SelectionActionHelper.handleItemTap(
              index: index,
              itemKey: playlistId,
              items: allPlaylists,
              keySelector: (p) => p['id'] as String? ?? '',
              isSelectionMode: isSelectionMode,
              selectedKeys: selectedPlaylistIds,
              lastAnchorIndex: lastPlaylistAnchorIndex,
              onUpdateAnchor: onUpdateAnchor,
              onSetSelection: onSetSelection,
              onToggleSelection: onToggleSelection,
              onNormalTap: onTap,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isSelectionMode && isMultiSelected) || isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.5)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: (isSelectionMode && isMultiSelected) || isSelected
                    ? 1.5
                    : 0.8,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: coverArt != null && coverArt.isNotEmpty
                      ? RemoteArtworkWidget(
                          server: server,
                          password: password,
                          coverArtId: coverArt,
                          size: 44,
                        )
                      : Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isStarredItem
                                ? Colors.redAccent.withValues(alpha: 0.15)
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isStarredItem
                                ? Icons.favorite_rounded
                                : Icons.playlist_play_rounded,
                            color: isStarredItem
                                ? Colors.redAccent
                                : theme.colorScheme.primary,
                            size: 24,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isStarredItem ? l10n.starredSongs : name,
                        style: TextStyle(
                          fontWeight: (isSelectionMode &&
                                      isMultiSelected) ||
                                  isSelected
                              ? FontWeight.bold
                              : FontWeight.w600,
                          fontSize: 13,
                          color: (isSelectionMode &&
                                      isMultiSelected) ||
                                  isSelected
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${l10n.trackCountShort(songCount)} • $durationMin min',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelectionMode)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isMultiSelected,
                      onChanged: (_) {
                        onToggleSelection(playlistId);
                      },
                    ),
                  )
                else if (!isStarredItem)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    tooltip: l10n.more,
                    onPressed: () {
                      final box = context.findRenderObject() as RenderBox?;
                      final pos = box != null
                          ? box.localToGlobal(
                              Offset(box.size.width / 2, box.size.height / 2))
                          : Offset.zero;
                      showRemotePlaylistContextMenu(
                        context: context,
                        globalPosition: pos,
                        ref: ref,
                        server: server,
                        password: password,
                        playlistId: playlistId,
                        playlistName: name,
                        onViewDetails: onTap,
                        onRename: () =>
                            _showRenameDialog(context, ref, name, playlistId),
                        onDelete: () =>
                            _showDeleteDialog(context, ref, name, playlistId),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return DraggableRemotePlaylistItem(
      server: server,
      playlist: playlist,
      songCount: songCount,
      isSelectionMode: isSelectionMode,
      isSelected: isMultiSelected,
      selectedPlaylistIds: selectedPlaylistIds,
      allPlaylists: allPlaylists,
      child: itemWidget,
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

class _LandscapePlaylistsSplitView extends StatefulWidget {
  final RemoteServer server;
  final String password;
  final List<Map<String, dynamic>> playlists;
  final Map<String, dynamic> selectedPlaylist;
  final Future<void> Function() onRefresh;
  final double bottomOffset;
  final bool isSelectionMode;
  final Set<String> selectedPlaylistIds;
  final int? lastPlaylistAnchorIndex;
  final ValueChanged<String?> onSelectPlaylistId;
  final void Function(Set<String> keys) onSetSelection;
  final void Function(String playlistId) onToggleSelection;
  final void Function(int? index) onUpdateAnchor;
  final Widget? toolbar;
  final double maxWidth;

  const _LandscapePlaylistsSplitView({
    required this.server,
    required this.password,
    required this.playlists,
    required this.selectedPlaylist,
    required this.onRefresh,
    required this.bottomOffset,
    required this.isSelectionMode,
    required this.selectedPlaylistIds,
    required this.lastPlaylistAnchorIndex,
    required this.onSelectPlaylistId,
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    this.toolbar,
    required this.maxWidth,
  });

  @override
  State<_LandscapePlaylistsSplitView> createState() =>
      _LandscapePlaylistsSplitViewState();
}

class _LandscapePlaylistsSplitViewState
    extends State<_LandscapePlaylistsSplitView> {
  late final ScrollController _leftScrollController;

  @override
  void initState() {
    super.initState();
    _leftScrollController = ScrollController();
  }

  @override
  void dispose() {
    _leftScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final selectedPlaylist = widget.selectedPlaylist;

    return NotificationListener<ScrollNotification>(
      onNotification: (_) => true,
      child: Column(
        children: [
          if (widget.toolbar != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: widget.toolbar!,
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: Playlist List Pane
                SizedBox(
                  width: widget.maxWidth >= 1100 ? 360 : 300,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                    ),
                    child: PrimaryScrollController.none(
                      child: RefreshIndicator(
                        onRefresh: widget.onRefresh,
                        child: Scrollbar(
                          controller: _leftScrollController,
                          child: ListView.builder(
                            controller: _leftScrollController,
                            primary: false,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              12,
                              6,
                              12,
                              widget.bottomOffset,
                            ),
                            itemCount: widget.playlists.length,
                            itemBuilder: (context, index) {
                              final pl = widget.playlists[index];
                              final isSelected =
                                  pl['id'] == selectedPlaylist['id'];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: RemoteLibraryPlaylistItem(
                                  server: widget.server,
                                  password: widget.password,
                                  playlist: pl,
                                  index: index,
                                  allPlaylists: widget.playlists,
                                  isSelected: isSelected,
                                  isMultiSelected: widget.selectedPlaylistIds
                                      .contains(pl['id'] as String? ?? ''),
                                  isSelectionMode: widget.isSelectionMode,
                                  selectedPlaylistIds:
                                      widget.selectedPlaylistIds,
                                  lastPlaylistAnchorIndex:
                                      widget.lastPlaylistAnchorIndex,
                                  onSetSelection: widget.onSetSelection,
                                  onToggleSelection: widget.onToggleSelection,
                                  onUpdateAnchor: widget.onUpdateAnchor,
                                  onRefreshPlaylists: widget.onRefresh,
                                  onTap: () {
                                    final id = pl['id'] as String?;
                                    widget.onSelectPlaylistId(id);
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Right: Playlist Detail Pane
                Expanded(
                  child: PrimaryScrollController.none(
                    child: selectedPlaylist.isNotEmpty
                        ? NavidromePlaylistDetailContent(
                            key: ValueKey(selectedPlaylist['id']),
                            server: widget.server,
                            password: widget.password,
                            playlistId:
                                selectedPlaylist['id'] as String? ?? '',
                            playlistName:
                                selectedPlaylist['name'] as String? ??
                                    l10n.playlist,
                            coverArtId:
                                selectedPlaylist['coverArt'] as String?,
                            songCount:
                                selectedPlaylist['songCount'] as int?,
                            duration:
                                selectedPlaylist['duration'] as int?,
                            isStarred: selectedPlaylist['isStarred'] ==
                                    true ||
                                selectedPlaylist['id'] ==
                                    RemoteLibraryPlaylistsView.starredPlaylistId,
                            onPlaylistModified: widget.onRefresh,
                            onDeleted: () {
                              widget.onRefresh();
                              widget.onSelectPlaylistId(null);
                            },
                          )
                        : Center(child: Text(l10n.noPlaylistSelected)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef NavidromePlaylistsToolbar = RemoteLibraryPlaylistsToolbar;
typedef NavidromePlaylistsView = RemoteLibraryPlaylistsView;
typedef NavidromePlaylistItem = RemoteLibraryPlaylistItem;

