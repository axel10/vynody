import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dialogs/song_tag_edit_dialog.dart';
import '../dialogs/transcode_dialog.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'app_context_menu.dart';
import 'library_selection_scope.dart';
import 'song_thumbnail.dart';

/// 一个实体（专辑 / 艺术家 / 流派 / 年份）右键菜单的完整声明。
///
/// 四类实体的菜单骨架逐字相同——播放类动作、详情、复制、多选，差异只在取歌
/// 方式、封面、文案和少量实体特有动作。因此渲染与动作分发统一在本文件的
/// [showEntityContextMenu] / [showEntityBottomSheet] 里，各实体只保留一份 spec。
///
/// 新增一个实体（作曲家、唱片公司……）只需写一份 spec，不必再抄一遍六段结构。
class EntityContextMenuSpec<T> {
  const EntityContextMenuSpec({
    required this.songs,
    required this.selectionKey,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.playbackSource,
    required this.detailIcon,
    required this.detailLabel,
    required this.detailPageBuilder,
    this.extraPlaybackActions,
    this.secondaryActions,
    this.handleCustomAction,
  });

  /// 该实体包含的歌曲，用于播放 / 队列 / 标签 / 转码等通用动作。
  final List<MusicFile> Function(T entity) songs;

  /// 多选模式下作为选择键的稳定 id。
  final String Function(T entity) selectionKey;

  final String Function(AppLocalizations l10n, T entity) title;
  final String Function(AppLocalizations l10n, T entity) subtitle;
  final Widget Function(BuildContext context, T entity) cover;

  /// 「播放全部 / 随机播放」要写入的播放来源。
  ///
  /// 带 l10n 是因为来源名可能是本地化文案（如「未知年份」）。
  final PlaybackSource Function(AppLocalizations l10n, T entity) playbackSource;

  final IconData detailIcon;
  final String Function(AppLocalizations l10n) detailLabel;
  final Widget Function(T entity) detailPageBuilder;

  /// 插在「加入播放列表」与「编辑标签」之间的实体特有动作（如专辑的加入收藏）。
  final List<ContextMenuAction> Function(AppLocalizations l10n, T entity)?
  extraPlaybackActions;

  /// 「查看详情」与「多选」之间的实体特有动作（如各类复制项）。
  final List<ContextMenuAction> Function(AppLocalizations l10n, T entity)?
  secondaryActions;

  /// 分发通用动作之外的 value。返回的 value 没被这里处理就等于无操作。
  final Future<void> Function(
    BuildContext context,
    WidgetRef ref,
    T entity,
    String action,
  )?
  handleCustomAction;
}

/// 构建菜单动作分组。弹窗与底部面板共用同一份分组，保证两个入口永远一致。
List<List<ContextMenuAction>> buildEntityMenuActionGroups<T>(
  AppLocalizations l10n,
  EntityContextMenuSpec<T> spec,
  T entity, {
  required bool showViewDetails,
  required bool showMultiSelect,
}) {
  final songs = spec.songs(entity);
  final hasSongs = songs.isNotEmpty;
  final canEditTags =
      hasSongs && songs.any((s) => !RemoteMediaResolver.isRemoteUri(s.path));

  return [
    [
      ContextMenuAction(
        value: 'play_all',
        label: l10n.playAll,
        icon: Icons.play_arrow_rounded,
        enabled: hasSongs,
      ),
      ContextMenuAction(
        value: 'shuffle',
        label: l10n.shufflePlay,
        icon: Icons.shuffle_rounded,
        enabled: hasSongs,
      ),
      ContextMenuAction(
        value: 'play_next',
        label: l10n.playNext,
        icon: Icons.queue_play_next_rounded,
        enabled: hasSongs,
      ),
      ContextMenuAction(
        value: 'add_to_queue',
        label: l10n.addToQueue,
        icon: Icons.queue_music_rounded,
        enabled: hasSongs,
      ),
      ContextMenuAction(
        value: 'add_to_playlist',
        label: l10n.addToPlaylist,
        icon: Icons.playlist_add_rounded,
        enabled: hasSongs,
      ),
      ...?spec.extraPlaybackActions?.call(l10n, entity),
      ContextMenuAction(
        value: 'edit_tags',
        label: songs.length > 1
            ? '${l10n.batchEditSongTagsTitle} (${songs.length})'
            : l10n.editSongTagsTitle,
        icon: Icons.edit_note_rounded,
        enabled: canEditTags,
      ),
      ContextMenuAction(
        value: 'transcode',
        label: l10n.transcodeAction,
        icon: Icons.sync_rounded,
        enabled: hasSongs,
      ),
    ],
    [
      if (showViewDetails)
        ContextMenuAction(
          value: 'view_details',
          label: spec.detailLabel(l10n),
          icon: spec.detailIcon,
        ),
      ...?spec.secondaryActions?.call(l10n, entity),
      if (showMultiSelect)
        ContextMenuAction(
          value: 'multi_select',
          label: l10n.multiSelect,
          icon: Icons.checklist_rounded,
        ),
    ],
  ];
}

/// 在鼠标位置弹出实体右键菜单。
Future<String?> showEntityContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required EntityContextMenuSpec<T> spec,
  required T entity,
  void Function(String selectionKey)? onMultiSelect,
  VoidCallback? onViewDetails,
  bool showViewDetails = true,
}) async {
  final l10n = AppLocalizations.of(context)!;

  final items = buildContextMenuPopupItems(
    context,
    buildEntityMenuActionGroups(
      l10n,
      spec,
      entity,
      showViewDetails: showViewDetails,
      showMultiSelect: onMultiSelect != null,
    ),
  );

  final selected = await AppContextMenu.show<String>(
    context: context,
    position: globalPosition,
    items: items,
  );

  if (!context.mounted || selected == null) return null;

  await handleEntityMenuAction(
    selected: selected,
    context: context,
    ref: ref,
    spec: spec,
    entity: entity,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
  );

  return selected;
}

/// 长按 / 移动端用的实体操作面板。
Future<String?> showEntityBottomSheet<T>({
  required BuildContext context,
  required WidgetRef ref,
  required EntityContextMenuSpec<T> spec,
  required T entity,
  void Function(String selectionKey)? onMultiSelect,
  VoidCallback? onViewDetails,
}) async {
  final l10n = AppLocalizations.of(context)!;

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
        title: spec.title(l10n, entity),
        subtitle: spec.subtitle(l10n, entity),
        leading: spec.cover(context, entity),
      ),
      itemsBuilder: (sheetContext) => buildContextMenuSheetItems(
        sheetContext,
        buildEntityMenuActionGroups(
          l10n,
          spec,
          entity,
          showViewDetails: true,
          showMultiSelect: onMultiSelect != null,
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

  await handleEntityMenuAction(
    selected: selected,
    context: context,
    ref: ref,
    spec: spec,
    entity: entity,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
  );

  return selected;
}

/// 执行选中的菜单动作。通用动作在这里分发，其余交给 spec 的
/// [EntityContextMenuSpec.handleCustomAction]。
Future<void> handleEntityMenuAction<T>({
  required String selected,
  required BuildContext context,
  required WidgetRef ref,
  required EntityContextMenuSpec<T> spec,
  required T entity,
  void Function(String selectionKey)? onMultiSelect,
  VoidCallback? onViewDetails,
}) async {
  final audio = ref.read(audioServiceProvider);
  final playlistService = ref.read(playlistServiceProvider);
  final l10n = AppLocalizations.of(context)!;
  final songs = spec.songs(entity);

  switch (selected) {
    case 'play_all':
      await audio.playPlaylist(
        songs,
        source: spec.playbackSource(l10n, entity),
      );
      break;
    case 'shuffle':
      await audio.playPlaylist(
        List.of(songs)..shuffle(),
        source: spec.playbackSource(l10n, entity),
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
      final result = await showSongTagEditSheet(context, songs: songs);
      if (result != null && context.mounted) {
        await applySongTagEditResult(context, ref, result);
      }
      break;
    case 'transcode':
      await showTranscodeDialog(context, songs: songs);
      break;
    case 'view_details':
      if (onViewDetails != null) {
        onViewDetails();
      } else {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => spec.detailPageBuilder(entity),
          ),
        );
      }
      break;
    case 'multi_select':
      onMultiSelect?.call(spec.selectionKey(entity));
      break;
    default:
      await spec.handleCustomAction?.call(context, ref, entity, selected);
      break;
  }
}

/// 底部面板左侧的 52pt 封面：有封面走缩略图，否则回落成主题色图标块。
///
/// 流派与年份两个实体的封面貌似各自实现过一遍，实际只差回落图标，统一到这里。
class EntityMenuCover extends StatelessWidget {
  const EntityMenuCover({
    super.key,
    required this.songs,
    required this.artworkPath,
    required this.thumbnailPath,
    required this.fallbackIcon,
  });

  final List<MusicFile> songs;
  final String? artworkPath;
  final String? thumbnailPath;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCover =
        (artworkPath?.isNotEmpty ?? false) ||
        (thumbnailPath?.isNotEmpty ?? false);

    if (hasCover && songs.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SongThumbnail(
          path: songs.first.path,
          artworkPath: artworkPath,
          thumbnailPath: thumbnailPath,
          size: 52,
        ),
      );
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        fallbackIcon,
        size: 26,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
