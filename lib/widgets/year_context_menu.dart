import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../pages/year_detail_page.dart';
import 'package:vynody/models/year_summary.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'app_context_menu.dart';
import 'entity_context_menu.dart';

/// 年份菜单的唯一声明。通用骨架见 [EntityContextMenuSpec]。
final EntityContextMenuSpec<YearSummary> yearMenuSpec =
    EntityContextMenuSpec<YearSummary>(
      songs: (year) => year.songs,
      selectionKey: (year) => year.queryKey,
      title: (l10n, year) => year.labelWith(l10n.unknownYear),
      subtitle: (l10n, year) =>
          '${l10n.songCount(year.songCount)} · ${l10n.albumCount(year.albumCount)}',
      cover: (context, year) => EntityMenuCover(
        songs: year.songs,
        artworkPath: year.representativeArtworkPath,
        thumbnailPath: year.representativeThumbnailPath,
        fallbackIcon: Icons.calendar_month_rounded,
      ),
      playbackSource: (l10n, year) => PlaybackSource(
        type: PlaybackSourceType.year,
        id: year.queryKey,
        name: year.labelWith(l10n.unknownYear),
      ),
      detailIcon: Icons.calendar_month_rounded,
      detailLabel: (l10n) => l10n.viewYearDetails,
      detailPageBuilder: (year) => YearDetailPage(year: year),
      secondaryActions: (l10n, year) => [
        ContextMenuAction(
          value: 'copy_year',
          label: l10n.copyYearName,
          icon: Icons.copy_rounded,
        ),
      ],
      handleCustomAction: (context, ref, year, action) async {
        if (action == 'copy_year') {
          final l10n = AppLocalizations.of(context)!;
          await Clipboard.setData(
            ClipboardData(text: year.labelWith(l10n.unknownYear)),
          );
        }
      },
    );

/// 在鼠标位置弹出发行年份右键菜单。
Future<String?> showYearContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WidgetRef ref,
  required YearSummary year,
  void Function(String yearKey)? onMultiSelect,
  VoidCallback? onViewDetails,
  bool showViewDetails = true,
}) {
  return showEntityContextMenu<YearSummary>(
    context: context,
    globalPosition: globalPosition,
    ref: ref,
    spec: yearMenuSpec,
    entity: year,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
    showViewDetails: showViewDetails,
  );
}

/// 长按 / 移动端用的发行年份操作面板。
Future<String?> showYearBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required YearSummary year,
  void Function(String yearKey)? onMultiSelect,
  VoidCallback? onViewDetails,
}) {
  return showEntityBottomSheet<YearSummary>(
    context: context,
    ref: ref,
    spec: yearMenuSpec,
    entity: year,
    onMultiSelect: onMultiSelect,
    onViewDetails: onViewDetails,
  );
}
