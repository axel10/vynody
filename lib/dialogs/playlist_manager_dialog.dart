import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../player/audio/audio_riverpod.dart';
import '../player/library/playlist_service.dart';

import '../utils/app_snack_bar.dart';
import '../utils/file_selector_helper.dart';
import '../utils/playlist_name.dart';
import '../utils/selection_utils.dart';
import '../widgets/app_bottom_sheet.dart';
import 'sort_options_dialog.dart';

/// 统一的播放列表选择与管理弹窗
/// 兼具快速切换当前歌单、新建歌单、排序、重命名、单项/批量删除、导入导出等完整功能。
class PlaylistManagerDialog extends ConsumerStatefulWidget {
  /// 是否强制以 BottomSheet 形式展示（为 null 时由 [AppAdaptiveSheet] 根据屏幕宽度和横竖屏自适应）
  final bool? asBottomSheet;

  const PlaylistManagerDialog({
    super.key,
    this.asBottomSheet,
  });

  static Future<void> show(BuildContext context) {
    return showAppAdaptiveModal<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => const PlaylistManagerDialog(),
    );
  }

  @override
  ConsumerState<PlaylistManagerDialog> createState() =>
      _PlaylistManagerDialogState();
}

class _PlaylistManagerDialogState
    extends ConsumerState<PlaylistManagerDialog> {
  bool _isSelectionMode = false;
  final Set<String> _selectedPlaylistIds = {};
  int? _lastAnchorIndex;

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool _isFavoritePlaylist(Playlist playlist) {
    return playlist.id == PlaylistService.favoritePlaylistId;
  }

  Future<void> _showSortDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.read(settingsServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);

    final result = await showDialog<SortResult<PlaylistSortField>>(
      context: context,
      builder: (dialogContext) => SortOptionsDialog<PlaylistSortField>(
        title: l10n.sortPlaylists,
        currentField: settings.playlistSortField,
        sortAscending: settings.playlistSortAscending,
        options: [
          SortOptionItem(
            value: PlaylistSortField.updatedAt,
            label: l10n.sortRecentlyUpdated,
            icon: Icons.update_rounded,
          ),
          SortOptionItem(
            value: PlaylistSortField.name,
            label: l10n.playlistName,
            icon: Icons.sort_by_alpha_rounded,
          ),
          SortOptionItem(
            value: PlaylistSortField.trackCount,
            label: l10n.sortTrackCount,
            icon: Icons.numbers_rounded,
          ),
          SortOptionItem(
            value: PlaylistSortField.createdAt,
            label: l10n.sortRecentlyCreated,
            icon: Icons.calendar_today_rounded,
          ),
        ],
      ),
    );

    if (result != null) {
      settings.playlistSortField = result.field;
      settings.playlistSortAscending = result.sortAscending;
      await playlistService.sortPlaylists(
        field: result.field,
        ascending: result.sortAscending,
      );
    }
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.createPlaylist),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.playlistName,
              hintText: AppLocalizations.of(context)!.enterPlaylistName,
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
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final playlistService = ref.read(playlistServiceProvider);
                  if (playlistService.playlistExists(name)) {
                    setDialogState(() {
                      errorText = AppLocalizations.of(
                        context,
                      )!.playlistNameExists;
                    });
                    return;
                  }
                  await playlistService.createPlaylist(name);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                }
              },
              child: Text(AppLocalizations.of(context)!.createPlaylist),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenamePlaylistDialog(BuildContext context, Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.renamePlaylist),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.playlistName,
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
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            TextButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final playlistService = ref.read(playlistServiceProvider);
                  if (playlistService.playlistExists(
                    name,
                    excludeId: playlist.id,
                  )) {
                    setDialogState(() {
                      errorText = AppLocalizations.of(
                        context,
                      )!.playlistNameExists;
                    });
                    return;
                  }
                  playlistService.renamePlaylist(playlist.id, name);
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(AppLocalizations.of(context)!.confirm),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeletePlaylistDialog(BuildContext context, Playlist playlist) {
    if (_isFavoritePlaylist(playlist)) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deletePlaylist),
        content: Text(l10n.confirmDeletePlaylist(playlist.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () {
              ref.read(playlistServiceProvider).deletePlaylist(playlist.id);
              Navigator.pop(dialogContext);
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _importM3uPlaylist(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final filePaths = await FileSelectorHelper.pickFiles(
        extensions: ['m3u', 'm3u8'],
        label: 'M3U Playlist',
      );
      if (filePaths == null || filePaths.isEmpty || !context.mounted) return;

      final playlistService = ref.read(playlistServiceProvider);
      final scannerRoots = ref.read(scannerServiceProvider).rootPaths;
      final imported = await playlistService.importPlaylistsFromM3u(
        filePaths,
        rootPaths: scannerRoots,
      );

      if (!context.mounted) return;
      if (imported.isNotEmpty) {
        final last = imported.last;
        AppSnackBar.show(
          context,
          ref,
          SnackBar(
            content: Text(
              l10n.importPlaylistSuccess(last.name, last.songs.length),
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        ref,
        SnackBar(
          content: Text(l10n.importPlaylistFailed(e.toString())),
        ),
      );
    }
  }

  Future<void> _exportPlaylistAsM3u(
    BuildContext context,
    Playlist playlist,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (playlist.songs.isEmpty) {
      AppSnackBar.show(
        context,
        ref,
        SnackBar(
          content: Text(l10n.noSongsInPlaylist),
        ),
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
          SnackBar(
            content: Text(l10n.exportPlaylistSuccess),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        ref,
        SnackBar(
          content: Text(l10n.exportPlaylistFailed(e.toString())),
        ),
      );
    }
  }

  void _showPlaylistOptions(BuildContext context, Playlist playlist) {
    final l10n = AppLocalizations.of(context)!;
    final isFav = _isFavoritePlaylist(playlist);

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (bottomSheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: Text(l10n.exportPlaylistAsM3u),
              onTap: () {
                Navigator.pop(bottomSheetContext);
                _exportPlaylistAsM3u(context, playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.rename),
              enabled: !isFav,
              onTap: () {
                if (isFav) return;
                Navigator.pop(bottomSheetContext);
                _showRenamePlaylistDialog(context, playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.delete),
              enabled: !isFav,
              onTap: () {
                if (isFav) return;
                Navigator.pop(bottomSheetContext);
                _showDeletePlaylistDialog(context, playlist);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBatchDeleteConfirmDialog(
    BuildContext context,
    Set<String> playlistIds,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final count = playlistIds.length;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deletePlaylists),
        content: Text(l10n.confirmDeletePlaylists(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final idsToDelete = Set<String>.from(playlistIds);
              await ref
                  .read(playlistServiceProvider)
                  .deletePlaylists(idsToDelete);
              if (mounted && context.mounted) {
                setState(() {
                  _selectedPlaylistIds.clear();
                  _isSelectionMode = false;
                });
                AppSnackBar.show(
                  context,
                  ref,
                  SnackBar(
                    content: Text(l10n.playlistsDeleted(count)),
                  ),
                );
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final playlistService = ref.watch(playlistServiceProvider);
    final playlists = playlistService.playlists;
    final currentPlaylist = playlistService.currentPlaylist;

    final deletablePlaylists =
        playlists.where((p) => !_isFavoritePlaylist(p)).toList();
    final isAllSelected = deletablePlaylists.isNotEmpty &&
        _selectedPlaylistIds.length >= deletablePlaylists.length;

    final isDialog = widget.asBottomSheet != null
        ? !widget.asBottomSheet!
        : AppAdaptiveSheetScope.isDialogMode(context);

    return AppAdaptiveSheet(
      asDialog: widget.asBottomSheet != null ? !widget.asBottomSheet! : null,
      dialogMaxWidth: 500,
      sheetMaxWidth: 680,
      landscapeMaxWidth: 860,
      dialogHeight: 640,
      expandHeight: true,
      padding: EdgeInsets.zero,
      showCloseButton: !_isSelectionMode && isDialog,
      headerPadding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      titleWidget: !_isSelectionMode
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.queue_music_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.playlist,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${playlists.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: l10n.cancel,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedPlaylistIds.clear();
                    });
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.selectedPlaylistsCount(_selectedPlaylistIds.length),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
      headerTrailing: !_isSelectionMode
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.createNewPlaylist,
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => _showCreatePlaylistDialog(context),
                ),
                IconButton(
                  tooltip: l10n.sort,
                  icon: const Icon(Icons.sort_rounded),
                  onPressed: () => _showSortDialog(context),
                ),
                if (deletablePlaylists.isNotEmpty)
                  IconButton(
                    tooltip: l10n.batchDelete,
                    icon: const Icon(Icons.checklist_rounded),
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = true;
                      });
                    },
                  ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (deletablePlaylists.isNotEmpty)
                  IconButton(
                    tooltip: isAllSelected ? l10n.deselectAll : l10n.selectAll,
                    icon: Icon(
                      isAllSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                    ),
                    onPressed: () {
                      setState(() {
                        if (isAllSelected) {
                          _selectedPlaylistIds.clear();
                        } else {
                          _selectedPlaylistIds.addAll(
                            deletablePlaylists.map((p) => p.id),
                          );
                        }
                      });
                    },
                  ),
                IconButton(
                  tooltip: l10n.delete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: _selectedPlaylistIds.isNotEmpty
                        ? Colors.redAccent
                        : null,
                  ),
                  onPressed: _selectedPlaylistIds.isNotEmpty
                      ? () => _showBatchDeleteConfirmDialog(
                            context,
                            _selectedPlaylistIds,
                          )
                      : null,
                ),
              ],
            ),
      child: Column(
        children: [
          const Divider(height: 1),
          if (!_isSelectionMode) ...[
            // 快捷导入条
            InkWell(
              onTap: () => _importM3uPlaylist(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.file_download_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.importPlaylist,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: theme.colorScheme.primary.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
          ],
          // 歌单列表（支持拖拽重排与点击切换）
          Expanded(
            child: _isSelectionMode
                ? ListView.builder(
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final isFav = _isFavoritePlaylist(playlist);
                      final isSelected =
                          _selectedPlaylistIds.contains(playlist.id);

                      if (isFav) {
                        return ListTile(
                          enabled: false,
                          leading: const Icon(
                            Icons.favorite_rounded,
                            color: Colors.grey,
                          ),
                          title: Text(
                            localizedPlaylistName(context, playlist),
                            style: TextStyle(color: theme.disabledColor),
                          ),
                          subtitle: Text(
                            '${l10n.songCount(playlist.songs.length)} · ${_formatDate(playlist.updatedAt)}',
                            style: TextStyle(color: theme.disabledColor),
                          ),
                        );
                      }

                      return ListTile(
                        selected: isSelected,
                        leading: Checkbox(
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedPlaylistIds.add(playlist.id);
                              } else {
                                _selectedPlaylistIds.remove(playlist.id);
                              }
                            });
                          },
                        ),
                        title: Text(localizedPlaylistName(context, playlist)),
                        subtitle: Text(
                          '${l10n.songCount(playlist.songs.length)} · ${_formatDate(playlist.updatedAt)}',
                        ),
                        onTap: () {
                          SelectionActionHelper.handleItemTap(
                            index: index,
                            itemKey: playlist.id,
                            items: playlists,
                            keySelector: (p) => p.id,
                            isSelectionMode: true,
                            selectedKeys: _selectedPlaylistIds,
                            lastAnchorIndex: _lastAnchorIndex,
                            onUpdateAnchor: (a) =>
                                setState(() => _lastAnchorIndex = a),
                            onSetSelection: (keys) => setState(() {
                              _selectedPlaylistIds
                                ..clear()
                                ..addAll(
                                  keys.where(
                                    (id) =>
                                        deletablePlaylists.any((p) => p.id == id),
                                  ),
                                );
                            }),
                            onToggleSelection: (key) => setState(() {
                              if (_selectedPlaylistIds.contains(key)) {
                                _selectedPlaylistIds.remove(key);
                              } else {
                                _selectedPlaylistIds.add(key);
                              }
                            }),
                          );
                        },
                      );
                    },
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: playlists.length,
                    onReorder: (oldIndex, newIndex) {
                      ref.read(settingsServiceProvider).playlistSortField =
                          PlaylistSortField.custom;
                      ref
                          .read(playlistServiceProvider)
                          .reorderPlaylist(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final isFav = _isFavoritePlaylist(playlist);
                      final isCurrent = playlist.id == currentPlaylist?.id;

                      return ListTile(
                        key: ValueKey(playlist.id),
                        tileColor: isCurrent
                            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: isFav
                            ? Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.favorite_rounded,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                              )
                            : Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? theme.colorScheme.primaryContainer
                                      : theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.playlist_play_rounded,
                                  color: isCurrent
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                  size: 24,
                                ),
                              ),
                        title: Text(
                          localizedPlaylistName(context, playlist),
                          style: TextStyle(
                            fontWeight:
                                isCurrent ? FontWeight.bold : FontWeight.w500,
                            color: isCurrent
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${l10n.songCount(playlist.songs.length)} · ${_formatDate(playlist.updatedAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.more,
                              icon: const Icon(Icons.more_vert_rounded),
                              onPressed: () => _showPlaylistOptions(context, playlist),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: theme.colorScheme.outline.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          SelectionActionHelper.handleItemTap(
                            index: index,
                            itemKey: playlist.id,
                            items: playlists,
                            keySelector: (p) => p.id,
                            isSelectionMode: _isSelectionMode,
                            selectedKeys: _selectedPlaylistIds,
                            lastAnchorIndex: _lastAnchorIndex,
                            onUpdateAnchor: (a) =>
                                setState(() => _lastAnchorIndex = a),
                            onSetSelection: (keys) => setState(() {
                              _isSelectionMode = true;
                              _selectedPlaylistIds
                                ..clear()
                                ..addAll(
                                  keys.where(
                                    (id) =>
                                        deletablePlaylists.any((p) => p.id == id),
                                  ),
                                );
                            }),
                            onToggleSelection: (key) => setState(() {
                              if (isFav) return;
                              _isSelectionMode = true;
                              if (_selectedPlaylistIds.contains(key)) {
                                _selectedPlaylistIds.remove(key);
                              } else {
                                _selectedPlaylistIds.add(key);
                              }
                            }),
                            onEnterSelectionMode: () =>
                                setState(() => _isSelectionMode = true),
                            onNormalTap: () {
                              playlistService.setCurrentPlaylist(playlist.id);
                              Navigator.pop(context);
                            },
                          );
                        },
                        onLongPress: isFav
                            ? null
                            : () {
                                setState(() {
                                  _lastAnchorIndex = index;
                                  _isSelectionMode = true;
                                  _selectedPlaylistIds.add(playlist.id);
                                });
                              },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
