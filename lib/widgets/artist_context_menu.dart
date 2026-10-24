import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/artist_detail_page.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'artist_avatar.dart';
import 'app_context_menu.dart';
import 'entity_context_menu.dart';

/// 艺术家菜单的唯一声明。通用骨架见 [EntityContextMenuSpec]。
final EntityContextMenuSpec<ArtistSummary> artistMenuSpec =
    EntityContextMenuSpec<ArtistSummary>(
      songs: (artist) => artist.songs,
      selectionKey: (artist) => artist.queryKey,
      title: (l10n, artist) => artist.name,
      subtitle: (l10n, artist) {
        final parts = <String>[l10n.songCount(artist.songCount)];
        final country = artist.country?.trim() ?? '';
        if (country.isNotEmpty) parts.add(country);
        final disambiguation = artist.disambiguation?.trim() ?? '';
        if (disambiguation.isNotEmpty) parts.add(disambiguation);
        return parts.join(' · ');
      },
      cover: (context, artist) => ArtistAvatar(
        diameter: 52,
        imagePath: artist.cachedImagePath,
        imageUrl: artist.imageUrl,
      ),
      playbackSource: (l10n, artist) => PlaybackSource(
        type: PlaybackSourceType.artist,
        id: artist.queryKey,
        name: artist.name,
      ),
      detailIcon: Icons.mic_rounded,
      detailLabel: (l10n) => l10n.viewArtistDetails,
      detailPageBuilder: (artist) => ArtistDetailPage(artist: artist),
      secondaryActions: (l10n, artist) => [
        ContextMenuAction(
          value: 'copy_artist',
          label: l10n.copyArtistName,
          icon: Icons.copy_rounded,
        ),
      ],
      handleCustomAction: (context, ref, artist, action) async {
        if (action == 'copy_artist') {
          await Clipboard.setData(ClipboardData(text: artist.name));
        }
      },
    );

/// 在鼠标位置弹出艺术家右键菜单。
Future<String?> showArtistContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required ArtistSummary artist,
  void Function(String artistKey)? onMultiSelect,
  VoidCallback? onViewDetails,
  bool showViewDetails = true,
}) {
  return showEntityContextMenu<ArtistSummary>(
    context: context,
    globalPosition: globalPosition,
    ref: ref,
    spec: artistMenuSpec,
    entity: artist,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
    showViewDetails: showViewDetails,
  );
}

/// 长按 / 移动端用的艺术家操作面板。
Future<String?> showArtistBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ArtistSummary artist,
  void Function(String artistKey)? onMultiSelect,
  VoidCallback? onViewDetails,
}) {
  return showEntityBottomSheet<ArtistSummary>(
    context: context,
    ref: ref,
    spec: artistMenuSpec,
    entity: artist,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
  );
}
