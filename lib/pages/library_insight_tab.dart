import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../widgets/library_insight_list.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/section_type_toggle.dart';
import '../widgets/time_range_dropdown.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';

/// 三类洞察页（最近播放 / 最多播放 / 最近添加）的统一实现。
///
/// 三者原本是三个几乎逐行相同的页面，差异只有 provider、文案、多选作用域与行尾指标。
/// 合并后切换「单曲 / 专辑」发生在同一个 [LibraryInsightList] 内：根节点类型不变，
/// 滚动位置、搜索词、多选状态都不会被销毁。
class LibraryInsightTab extends ConsumerWidget {
  const LibraryInsightTab({
    super.key,
    required this.filter,
    required this.watchSongs,
    required this.watchAlbums,
    required this.selectionScope,
    required this.title,
    this.subtitle,
    required this.emptyText,
    required this.songTrailing,
    this.albumTrailing,
    this.showRankIndex = false,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  final NotifierProvider<LibraryInsightFilterNotifier, LibraryInsightFilterState> filter;

  /// 以函数形式接收 provider，避免对外暴露 Riverpod 的 family 类型名。
  final AsyncValue<List<LibraryInsightSongEntry>> Function(
    WidgetRef ref,
    LibraryTimeRange range,
  ) watchSongs;
  final AsyncValue<List<TimeMachineAlbumEntry>> Function(
    WidgetRef ref,
    LibraryTimeRange range,
  ) watchAlbums;
  final LibrarySelectionScope selectionScope;
  final String title;
  final String? subtitle;
  final String Function(AppLocalizations l10n, LibraryTimeRange range) emptyText;
  final Widget Function(BuildContext, LibraryInsightSongEntry) songTrailing;

  /// 为空时专辑行使用默认的播放次数文案。
  final Widget Function(BuildContext, TimeMachineAlbumEntry)? albumTrailing;
  final bool showRankIndex;
  final double contentTopPadding;
  final double contentLeftPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final filterState = ref.watch(filter);
    final filterNotifier = ref.read(filter.notifier);

    final isAlbums = filterState.type == SectionItemType.albums;

    final songsAsync = watchSongs(ref, filterState.range);
    // 只在专辑视图下订阅专辑聚合并发：歌曲视图不做无谓的全量专辑索引。
    // family provider 默认非 autoDispose，切回歌曲后缓存仍在，再切回来是秒出。
    final albumsAsync = isAlbums ? watchAlbums(ref, filterState.range) : null;

    // 只有「从未产出过值」才显示整页加载态；reload 沿用旧值（provider 侧已保证
    // 上游 reload 不会返回 loading）。
    final isLoading = isAlbums
        ? (albumsAsync!.isLoading && !albumsAsync.hasValue)
        : (songsAsync.isLoading && !songsAsync.hasValue);
    final loadError = isAlbums ? albumsAsync!.error?.toString() : songsAsync.error?.toString();

    return LibraryInsightList(
      type: filterState.type,
      title: title,
      subtitle: subtitle,
      emptyText: emptyText(l10n, filterState.range),
      selectionScope: selectionScope,
      songs: isAlbums ? const <LibraryInsightSongEntry>[] : (songsAsync.value ?? const []),
      albums: albumsAsync?.value ?? const <TimeMachineAlbumEntry>[],
      isLoading: isLoading,
      loadError: loadError,
      showRankIndex: showRankIndex,
      songTrailing: songTrailing,
      albumTrailing: albumTrailing,
      centerAction: SectionTypeToggle(
        selected: filterState.type,
        onChanged: filterNotifier.setType,
        songsLabel: l10n.songs,
        albumsLabel: l10n.albums,
        fullWidth: isPortrait,
      ),
      headerTrailing: TimeRangeDropdown(
        selected: filterState.range,
        onChanged: filterNotifier.setRange,
      ),
      contentTopPadding: contentTopPadding,
      contentLeftPadding: contentLeftPadding,
    );
  }
}
