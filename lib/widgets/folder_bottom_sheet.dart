import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import '../widgets/library_selection_scope.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import 'package:vynody/dialogs/song_tag_edit_dialog.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import '../dialogs/transcode_dialog.dart';
import 'app_context_menu.dart';

/// Shows context menu (at mouse position) for a local folder.
Future<String?> showFolderContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required MusicFolder folder,
  required bool isRoot,
  void Function(String folderPath)? onMultiSelect,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final scanner = ref.read(scannerServiceProvider);
  final songs = await scanner.getSongsForFolder(folder);
  if (!context.mounted) return null;

  final canOpenLocation =
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
      folder.path.trim().isNotEmpty &&
      folder.path != 'system';

  final canEditTags = songs.isNotEmpty &&
      songs.any((s) => !RemoteMediaResolver.isRemoteUri(s.path));

  final selectLabel = l10n.selectFolders;
  final removeLabel = l10n.removeDirectory;

  final items = <PopupMenuEntry<String>>[
    buildContextMenuItem<String>(
      value: 'play_all',
      label: l10n.playAll,
      icon: Icons.play_arrow_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'shuffle',
      label: l10n.shufflePlay,
      icon: Icons.shuffle_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'play_next',
      label: l10n.playNext,
      icon: Icons.queue_play_next_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'add_to_queue',
      label: l10n.addToQueue,
      icon: Icons.queue_music_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'add_to_playlist',
      label: l10n.addToPlaylist,
      icon: Icons.playlist_add_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'edit_tags',
      label: songs.length > 1
          ? '${l10n.batchEditSongTagsTitle} (${songs.length})'
          : l10n.editSongTagsTitle,
      icon: Icons.edit_note_rounded,
      enabled: canEditTags,
      context: context,
    ),
    buildContextMenuItem<String>(
      value: 'transcode',
      label: l10n.transcodeAction,
      icon: Icons.sync_rounded,
      enabled: songs.isNotEmpty,
      context: context,
    ),
    if (canOpenLocation)
      buildContextMenuItem<String>(
        value: 'open_folder_location',
        label: l10n.openFolderLocation,
        icon: Icons.folder_open_rounded,
        context: context,
      ),
    // 多选入口与歌曲行对齐：子目录同样提供，根目录额外的「移除」才需要 isRoot。
    // 调用方没给 onMultiSelect 时（如无选择态的入口）不显示。
    if (isRoot || onMultiSelect != null) const PopupMenuDivider(),
    if (onMultiSelect != null)
      buildContextMenuItem<String>(
        value: 'multi_select',
        label: isRoot ? selectLabel : l10n.multiSelect,
        icon: Icons.checklist_rounded,
        context: context,
      ),
    if (isRoot)
      buildContextMenuItem<String>(
        value: 'remove_root',
        label: removeLabel,
        icon: Icons.delete_rounded,
        iconColor: theme.colorScheme.error,
        context: context,
      ),
  ];

  final selected = await AppContextMenu.show<String>(
    context: context,
    position: globalPosition,
    items: items,
  );

  if (!context.mounted || selected == null) return null;

  await _handleFolderMenuAction(
    selected: selected,
    context: context,
    ref: ref,
    folder: folder,
    songs: songs,
    isRoot: isRoot,
    onMultiSelect: onMultiSelect,
  );

  return selected;
}

/// Shows bottom sheet (typically on long press or mobile) for a local folder.
Future<String?> showFolderBottomSheet(
  BuildContext context,
  WidgetRef ref,
  MusicFolder folder, {
  required bool isRoot,
  void Function(String folderPath)? onMultiSelect,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final scanner = ref.read(scannerServiceProvider);
  final songs = await scanner.getSongsForFolder(folder);
  if (!context.mounted) return null;

  final canOpenLocation =
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
      folder.path.trim().isNotEmpty &&
      folder.path != 'system';

  final canEditTags = songs.isNotEmpty &&
      songs.any((s) => !RemoteMediaResolver.isRemoteUri(s.path));

  final selectLabel = l10n.selectFolders;
  final removeLabel = l10n.removeDirectory;

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
        // 子目录的面包屑已经显示路径，只有根目录需要额外标注位置。
        subtitle: isRoot && folder.path.isNotEmpty ? folder.path : null,
        leading: ActionSheetSquareIcon(
          icon: isRoot ? Icons.folder_shared : Icons.folder_rounded,
          color: Colors.amber,
        ),
      ),
      // 形参与外层 context 同名：条目行必须用面板自己的 context 关闭自己。
      itemsBuilder: (context) => [
        _buildFolderBottomSheetItem(
          context: context,
          value: 'play_all',
          label: l10n.playAll,
          icon: Icons.play_arrow_rounded,
          enabled: songs.isNotEmpty,
        ),
        _buildFolderBottomSheetItem(
          context: context,
          value: 'shuffle',
          label: l10n.shufflePlay,
          icon: Icons.shuffle_rounded,
          enabled: songs.isNotEmpty,
        ),
        _buildFolderBottomSheetItem(
          context: context,
          value: 'play_next',
          label: l10n.playNext,
          icon: Icons.queue_play_next_rounded,
          enabled: songs.isNotEmpty,
        ),
        _buildFolderBottomSheetItem(
          context: context,
          value: 'add_to_queue',
          label: l10n.addToQueue,
          icon: Icons.queue_music_rounded,
          enabled: songs.isNotEmpty,
        ),
        _buildFolderBottomSheetItem(
          context: context,
          value: 'add_to_playlist',
          label: l10n.addToPlaylist,
          icon: Icons.playlist_add_rounded,
          enabled: songs.isNotEmpty,
        ),
        _buildFolderBottomSheetItem(
          context: context,
          value: 'edit_tags',
          label: songs.length > 1
              ? '${l10n.batchEditSongTagsTitle} (${songs.length})'
              : l10n.editSongTagsTitle,
          icon: Icons.edit_note_rounded,
          enabled: canEditTags,
        ),
        _buildFolderBottomSheetItem(
          context: context,
          value: 'transcode',
          label: l10n.transcodeAction,
          icon: Icons.sync_rounded,
          enabled: songs.isNotEmpty,
        ),
        if (canOpenLocation)
          _buildFolderBottomSheetItem(
            context: context,
            value: 'open_folder_location',
            label: l10n.openFolderLocation,
            icon: Icons.folder_open_rounded,
          ),
        if (onMultiSelect != null)
          _buildFolderBottomSheetItem(
            context: context,
            value: 'multi_select',
            label: isRoot ? selectLabel : l10n.multiSelect,
            icon: Icons.checklist_rounded,
          ),
        if (isRoot)
          _buildFolderBottomSheetItem(
            context: context,
            value: 'remove_root',
            label: removeLabel,
            icon: Icons.delete_rounded,
            iconColor: theme.colorScheme.error,
          ),
      ],
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

  await _handleFolderMenuAction(
    selected: selected,
    context: context,
    ref: ref,
    folder: folder,
    songs: songs,
    isRoot: isRoot,
    onMultiSelect: onMultiSelect,
  );

  return selected;
}

Future<void> _handleFolderMenuAction({
  required String selected,
  required BuildContext context,
  required WidgetRef ref,
  required MusicFolder folder,
  required List<MusicFile> songs,
  required bool isRoot,
  void Function(String folderPath)? onMultiSelect,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final audio = ref.read(audioServiceProvider);
  final playlistService = ref.read(playlistServiceProvider);
  final scanner = ref.read(scannerServiceProvider);
  final removeLabel = l10n.removeDirectory;

  switch (selected) {
    case 'play_all':
      await audio.playPlaylist(
        songs,
        source: PlaybackSource(
          type: PlaybackSourceType.folder,
          id: folder.path,
          name: folder.name,
        ),
      );
      break;
    case 'shuffle':
      await audio.playPlaylist(
        List.of(songs)..shuffle(),
        source: PlaybackSource(
          type: PlaybackSourceType.folder,
          id: folder.path,
          name: folder.name,
        ),
      );
      break;
    case 'play_next':
      await audio.enqueueNext(songs);
      break;
    case 'add_to_queue':
      await audio.appendToQueue(songs);
      break;
    case 'add_to_playlist':
      await showAddSongsToPlaylistDialog(context, playlistService, songs);
      break;
    case 'edit_tags':
      final result = await showSongTagEditSheet(
        context,
        songs: songs,
      );
      if (result != null && context.mounted) {
        await applySongTagEditResult(context, ref, result);
      }
      break;
    case 'transcode':
      await showTranscodeDialog(context, songs: songs);
      break;
    case 'open_folder_location':
      await openFolderLocation(folder.path);
      break;
    case 'multi_select':
      // 根目录多选归根列表作用域，子目录多选归目录详情作用域。
      // 全部写 folderRoot 会让详情页的勾选读不到状态，表现为「点了没反应」。
      ref
          .read(librarySelectionScopeProvider.notifier)
          .setScope(
            isRoot
                ? LibrarySelectionScope.folderRoot
                : LibrarySelectionScope.folder,
          );
      onMultiSelect?.call(folder.path);
      break;
    case 'remove_root':
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(removeLabel),
          content: Text(
            l10n.removeRootDirectoryConfirmation(folder.name),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (confirm == true && context.mounted) {
        await scanner.removeRootPath(folder.path);
        if (context.mounted) {
          AppSnackBar.show(
            context,
            ref,
            SnackBar(content: Text(l10n.foldersDeleted(1))),
          );
        }
      }
      break;
  }
}

/// 文件夹面板的行。渲染统一交给 [buildContextMenuSheetItem]，这里只保留调用点
/// 熟悉的参数名。
Widget _buildFolderBottomSheetItem({
  required BuildContext context,
  required String value,
  required String label,
  required IconData icon,
  bool enabled = true,
  Color? iconColor,
}) {
  return buildContextMenuSheetItem(
    context,
    ContextMenuAction(
      value: value,
      label: label,
      icon: icon,
      enabled: enabled,
      accentColor: iconColor,
    ),
  );
}
