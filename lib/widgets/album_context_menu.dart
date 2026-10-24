import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../pages/album_detail_page.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import 'album_cover.dart';
import 'app_context_menu.dart';
import 'entity_context_menu.dart';

/// 专辑菜单的唯一声明。通用骨架（播放 / 队列 / 标签 / 详情 / 多选）见
/// [EntityContextMenuSpec]，这里只写专辑自己的部分。
final EntityContextMenuSpec<AlbumSummary> albumMenuSpec =
    EntityContextMenuSpec<AlbumSummary>(
      songs: (album) => album.songs,
      selectionKey: (album) => album.id,
      title: (l10n, album) => album.title,
      subtitle: (l10n, album) => album.artist,
      cover: (context, album) => AlbumCover(album: album, size: 52),
      playbackSource: (l10n, album) => PlaybackSource(
        type: PlaybackSourceType.album,
        id: album.id,
        name: album.title,
      ),
      detailIcon: Icons.album_rounded,
      detailLabel: (l10n) => l10n.viewAlbumDetails,
      detailPageBuilder: (album) => AlbumDetailPage(album: album),
      extraPlaybackActions: (l10n, album) => [
        ContextMenuAction(
          value: 'add_to_favorites',
          label: l10n.addToFavorites,
          icon: Icons.favorite_border_rounded,
          enabled: album.songs.isNotEmpty,
        ),
      ],
      secondaryActions: (l10n, album) => [
        ContextMenuAction(
          value: 'copy_album',
          label: l10n.copyAlbumTitle,
          icon: Icons.copy_rounded,
        ),
        ContextMenuAction(
          value: 'copy_artist',
          label: l10n.copyArtistName,
          icon: Icons.mic_rounded,
        ),
      ],
      handleCustomAction: (context, ref, album, action) async {
        switch (action) {
          case 'add_to_favorites':
            final playlistService = ref.read(playlistServiceProvider);
            for (final song in album.songs) {
              await playlistService.addSongToFavorite(song);
            }
            if (context.mounted) {
              final l10n = AppLocalizations.of(context)!;
              AppSnackBar.show(
                context,
                ref,
                SnackBar(
                  content: Text('${l10n.addToFavorites} · ${album.trackCount}'),
                ),
              );
            }
            break;
          case 'copy_album':
            await Clipboard.setData(ClipboardData(text: album.title));
            break;
          case 'copy_artist':
            await Clipboard.setData(ClipboardData(text: album.artist));
            break;
        }
      },
    );

/// 在鼠标位置弹出专辑右键菜单。
Future<String?> showAlbumContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required AlbumSummary album,
  void Function(String albumId)? onMultiSelect,
  VoidCallback? onViewDetails,
}) {
  return showEntityContextMenu<AlbumSummary>(
    context: context,
    globalPosition: globalPosition,
    ref: ref,
    spec: albumMenuSpec,
    entity: album,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
  );
}

/// 长按 / 移动端用的专辑操作面板。
Future<String?> showAlbumBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required AlbumSummary album,
  void Function(String albumId)? onMultiSelect,
  VoidCallback? onViewDetails,
}) {
  return showEntityBottomSheet<AlbumSummary>(
    context: context,
    ref: ref,
    spec: albumMenuSpec,
    entity: album,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
  );
}
