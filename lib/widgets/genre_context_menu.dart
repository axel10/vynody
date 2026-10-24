import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/genre_detail_page.dart';
import 'package:vynody/models/genre_summary.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'app_context_menu.dart';
import 'entity_context_menu.dart';

/// 流派菜单的唯一声明。通用骨架见 [EntityContextMenuSpec]。
final EntityContextMenuSpec<GenreSummary> genreMenuSpec =
    EntityContextMenuSpec<GenreSummary>(
      songs: (genre) => genre.songs,
      selectionKey: (genre) => genre.queryKey,
      title: (l10n, genre) => genre.name,
      subtitle: (l10n, genre) =>
          '${l10n.songCount(genre.songCount)} · ${l10n.albumCount(genre.albumCount)}',
      cover: (context, genre) => EntityMenuCover(
        songs: genre.songs,
        artworkPath: genre.representativeArtworkPath,
        thumbnailPath: genre.representativeThumbnailPath,
        fallbackIcon: Icons.style_rounded,
      ),
      playbackSource: (l10n, genre) => PlaybackSource(
        type: PlaybackSourceType.genre,
        id: genre.queryKey,
        name: genre.name,
      ),
      detailIcon: Icons.style_rounded,
      detailLabel: (l10n) => l10n.viewGenreDetails,
      detailPageBuilder: (genre) => GenreDetailPage(genre: genre),
      secondaryActions: (l10n, genre) => [
        ContextMenuAction(
          value: 'copy_genre',
          label: l10n.copyGenreName,
          icon: Icons.copy_rounded,
        ),
      ],
      handleCustomAction: (context, ref, genre, action) async {
        if (action == 'copy_genre') {
          await Clipboard.setData(ClipboardData(text: genre.name));
        }
      },
    );

/// 在鼠标位置弹出流派右键菜单。
Future<String?> showGenreContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required GenreSummary genre,
  void Function(String genreKey)? onMultiSelect,
  VoidCallback? onViewDetails,
  bool showViewDetails = true,
}) {
  return showEntityContextMenu<GenreSummary>(
    context: context,
    globalPosition: globalPosition,
    ref: ref,
    spec: genreMenuSpec,
    entity: genre,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
    showViewDetails: showViewDetails,
  );
}

/// 长按 / 移动端用的流派操作面板。
Future<String?> showGenreBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required GenreSummary genre,
  void Function(String genreKey)? onMultiSelect,
  VoidCallback? onViewDetails,
}) {
  return showEntityBottomSheet<GenreSummary>(
    context: context,
    ref: ref,
    spec: genreMenuSpec,
    entity: genre,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
  );
}
