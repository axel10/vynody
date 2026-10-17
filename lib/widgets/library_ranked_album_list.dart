import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/album_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'album_context_menu.dart';
import 'draggable_album_item.dart';
import 'library_selection_panel.dart';
import 'library_selection_scope.dart';
import 'playback_ui_tuning.dart';
import 'song_thumbnail.dart';

class LibraryRankedAlbumList extends ConsumerStatefulWidget {
  const LibraryRankedAlbumList({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
    this.selectedRange = LibraryTimeRange.allTime,
    this.onRangeChanged,
    this.showTimeRange = false,
    this.centerAction,
    this.headerTrailing,
    this.headerAction,
    required this.emptyText,
    this.showRankIndex = true,
    this.trailingBuilder,
    this.selectionScope = LibrarySelectionScope.album,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  final String title;
  final String subtitle;
  final List<TimeMachineAlbumEntry> items;
  final LibraryTimeRange selectedRange;
  final ValueChanged<LibraryTimeRange>? onRangeChanged;
  final bool showTimeRange;
  final Widget? centerAction;
  final Widget? headerTrailing;
  final Widget? headerAction;
  final String emptyText;

  /// 是否显示「01、02…」排名序号；最近播放 / 最近添加这类非排行视图可关闭。
  final bool showRankIndex;

  /// 自定义右侧指标，默认显示专辑总播放次数。
  final Widget Function(BuildContext context, TimeMachineAlbumEntry entry)? trailingBuilder;

  /// 多选作用域。默认专辑 Tab；最近播放/最多播放/最近添加各自传入独立作用域，
  /// 避免同一 IndexedStack 内的页面互相串选。
  final LibrarySelectionScope selectionScope;
  final double contentTopPadding;
  final double contentLeftPadding;

  @override
  ConsumerState<LibraryRankedAlbumList> createState() => _LibraryRankedAlbumListState();
}

class _LibraryRankedAlbumListState extends ConsumerState<LibraryRankedAlbumList>
    with SelectionStateMixin<LibraryRankedAlbumList, String> {
  @override
  LibrarySelectionScope get selectionScope => widget.selectionScope;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _isSearchExpanded = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<TimeMachineAlbumEntry> _filterItems(List<TimeMachineAlbumEntry> items) {
    if (_searchQuery.isEmpty) return items;
    final q = _searchQuery.toLowerCase();
    return items.where((entry) {
      final title = entry.album.toLowerCase();
      final artist = entry.artist.toLowerCase();
      return title.contains(q) || artist.contains(q);
    }).toList();
  }

  Widget _buildSearchField(ThemeData theme, AppLocalizations l10n) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: (val) {
        setState(() {
          _searchQuery = val.trim();
        });
      },
      decoration: InputDecoration(
        hintText: l10n.search,
        hintStyle: TextStyle(
          color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.6),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
        ),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: l10n.clearSearch,
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
              )
            : null,
        filled: true,
        fillColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      style: TextStyle(
        color: theme.colorScheme.onSecondaryContainer,
        fontSize: 14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    final filteredItems = _filterItems(widget.items);
    final playAllSongs = filteredItems.expand((e) => e.songs).toList();
    final selectionMode = isSelectionMode;
    final visibleKeys = [for (final entry in filteredItems) entry.stableId];
    final selectedSongs = selectionMode
        ? _collectSongs(
            filteredItems.where((entry) => isSelected(entry.stableId)),
          )
        : const <MusicFile>[];
    final allSongsInView = selectionMode
        ? _collectSongs(filteredItems)
        : const <MusicFile>[];

    void openAlbum(TimeMachineAlbumEntry entry) {
      if (entry.songs.isEmpty) return;
      final album = entry.toAlbumSummary();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: 'album_detail_${album.id}'),
          builder: (_) => AlbumDetailPage(album: album),
        ),
      );
    }

    final content = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null &&
            _searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        }
        return false;
      },
      child: Padding(
        padding: EdgeInsets.only(left: widget.contentLeftPadding),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (widget.contentTopPadding > 0)
              SliverToBoxAdapter(
                child: SizedBox(height: widget.contentTopPadding),
              ),
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 600;
                        return Container(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, isWide ? 12 : 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isWide)
                                if (widget.centerAction != null || widget.headerTrailing != null) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.title,
                                              style: theme.textTheme.headlineSmall?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _searchQuery.isNotEmpty
                                                  ? l10n.albumCount(filteredItems.length)
                                                  : widget.subtitle,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (widget.centerAction != null)
                                        widget.centerAction!,
                                      Expanded(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            if (widget.headerTrailing != null) widget.headerTrailing!,
                                            if (widget.headerAction != null) ...[
                                              const SizedBox(width: 8),
                                              widget.headerAction!,
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildSearchField(theme, l10n),
                                      ),
                                      if (playAllSongs.isNotEmpty) ...[
                                        const SizedBox(width: 16),
                                        FilledButton.icon(
                                          onPressed: () => audio.playPlaylist(playAllSongs),
                                          icon: const Icon(Icons.play_arrow_rounded),
                                          label: Text(l10n.playAll),
                                        ),
                                        const SizedBox(width: 12),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            final shuffled = List.of(playAllSongs)..shuffle();
                                            audio.playPlaylist(shuffled);
                                          },
                                          icon: const Icon(Icons.shuffle_rounded),
                                          label: Text(l10n.shufflePlay),
                                        ),
                                      ],
                                    ],
                                  ),
                                ] else
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.title,
                                              style: theme.textTheme.headlineSmall?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _searchQuery.isNotEmpty
                                                  ? l10n.albumCount(filteredItems.length)
                                                  : widget.subtitle,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 4,
                                        child: _buildSearchField(theme, l10n),
                                      ),
                                      const SizedBox(width: 16),
                                      if (playAllSongs.isNotEmpty) ...[
                                        FilledButton.icon(
                                          onPressed: () => audio.playPlaylist(playAllSongs),
                                          icon: const Icon(Icons.play_arrow_rounded),
                                          label: Text(l10n.playAll),
                                        ),
                                        const SizedBox(width: 12),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            final shuffled = List.of(playAllSongs)..shuffle();
                                            audio.playPlaylist(shuffled);
                                          },
                                          icon: const Icon(Icons.shuffle_rounded),
                                          label: Text(l10n.shufflePlay),
                                        ),
                                      ],
                                      if (widget.headerAction != null) ...[
                                        const SizedBox(width: 8),
                                        widget.headerAction!,
                                      ],
                                    ],
                                  )
                              else
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                widget.title,
                                                style: theme.textTheme.headlineSmall?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _searchQuery.isNotEmpty
                                                    ? l10n.albumCount(filteredItems.length)
                                                    : widget.subtitle,
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  color: theme.colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (widget.headerTrailing != null) ...[
                                          widget.headerTrailing!,
                                          const SizedBox(width: 6),
                                        ],
                                        if (widget.headerAction != null) ...[
                                          widget.headerAction!,
                                          const SizedBox(width: 4),
                                        ],
                                        IconButton(
                                          icon: Icon(
                                            _isSearchExpanded || _searchQuery.isNotEmpty
                                                ? Icons.search_off_rounded
                                                : Icons.search_rounded,
                                          ),
                                          tooltip: l10n.search,
                                          onPressed: () {
                                            setState(() {
                                              _isSearchExpanded = !_isSearchExpanded;
                                              if (_isSearchExpanded) {
                                                _searchFocusNode.requestFocus();
                                              } else {
                                                _searchController.clear();
                                                _searchQuery = '';
                                                _searchFocusNode.unfocus();
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    if (widget.centerAction != null) ...[
                                      const SizedBox(height: 12),
                                      Center(child: widget.centerAction!),
                                    ],
                                    AnimatedCrossFade(
                                      firstChild: const SizedBox.shrink(),
                                      secondChild: Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: _buildSearchField(theme, l10n),
                                      ),
                                      crossFadeState: (_isSearchExpanded || _searchQuery.isNotEmpty)
                                          ? CrossFadeState.showSecond
                                          : CrossFadeState.showFirst,
                                      duration: const Duration(milliseconds: 200),
                                    ),
                                    if (playAllSongs.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: FilledButton.icon(
                                              onPressed: () => audio.playPlaylist(playAllSongs),
                                              icon: const Icon(Icons.play_arrow_rounded),
                                              label: Text(l10n.playAll),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () {
                                                final shuffled = List.of(playAllSongs)..shuffle();
                                                audio.playPlaylist(shuffled);
                                              },
                                              icon: const Icon(Icons.shuffle_rounded),
                                              label: Text(l10n.shufflePlay),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (filteredItems.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.emptyText,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MiniPlayerUiTuning.getListBottomPadding(
                    context,
                    hasPlayingMusic: currentMusic != null,
                    isSelectionMode: selectionMode,
                  ),
                ),
                sliver: SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final entry = filteredItems[index];
                          final album = entry.toAlbumSummary();
                          return _RankedAlbumTile(
                            index: index + 1,
                            entry: entry,
                            album: album,
                            showRankIndex: widget.showRankIndex,
                            trailingBuilder: widget.trailingBuilder,
                            isSelectionMode: selectionMode,
                            isSelected: isSelected(entry.stableId),
                            onTap: () {
                              handleItemTap(
                                index: index,
                                itemKey: entry.stableId,
                                allKeys: visibleKeys,
                                onNormalTap: () => openAlbum(entry),
                              );
                            },
                            onLongPress: () {
                              lastAnchorIndex = index;
                              if (selectionMode) {
                                toggleSelection(entry.stableId);
                              } else {
                                enterSelectionMode(entry.stableId);
                              }
                            },
                            onSecondaryTapDown: (details) {
                              if (selectionMode) return;
                              showAlbumContextMenu(
                                context: context,
                                globalPosition: details.globalPosition,
                                ref: ref,
                                album: album,
                                onMultiSelect: (id) => enterSelectionMode(id),
                                onViewDetails: () => openAlbum(entry),
                              );
                            },
                            onPlay: () {
                              if (album.songs.isNotEmpty) {
                                audio.playPlaylist(album.songs);
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        content,
        AnimatedSelectionPanel(
          isVisible: selectionMode,
          child: LibrarySelectionPanel(
            key: const ValueKey('ranked-album-selection-panel'),
            selectedSongs: selectedSongs,
            allSongs: allSongsInView,
            title: l10n.selectedAlbumsCount(selectedCount),
            onToggleSelectAll: () => toggleSelectAll(visibleKeys),
            onCancel: cancelSelection,
          ),
        ),
      ],
    );
  }

  /// 收集专辑条目下的全部曲目并去重（多选面板按歌曲维度操作）。
  List<MusicFile> _collectSongs(Iterable<TimeMachineAlbumEntry> entries) {
    final seenPaths = <String>{};
    final songs = <MusicFile>[];
    for (final entry in entries) {
      for (final song in entry.songs) {
        if (seenPaths.add(song.path)) songs.add(song);
      }
    }
    return songs;
  }
}

class _RankedAlbumTile extends StatelessWidget {
  const _RankedAlbumTile({
    required this.index,
    required this.entry,
    required this.album,
    required this.onTap,
    required this.onPlay,
    required this.onLongPress,
    required this.onSecondaryTapDown,
    this.showRankIndex = true,
    this.trailingBuilder,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  final int index;
  final TimeMachineAlbumEntry entry;
  final AlbumSummary album;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onLongPress;
  final void Function(TapDownDetails details) onSecondaryTapDown;
  final bool showRankIndex;
  final Widget Function(BuildContext context, TimeMachineAlbumEntry entry)? trailingBuilder;
  final bool isSelectionMode;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isTop3 = index <= 3;
    final representative = album.representativeSong;

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isSelectionMode && isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                if (showRankIndex) ...[
                  SizedBox(
                    width: 28,
                    child: Text(
                      index.toString().padLeft(2, '0'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isTop3
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: isSelectionMode ? (isSelected ? 0.5 : 0.7) : 1.0,
                        child: SongThumbnail(
                          path: representative.path,
                          artworkPath: representative.artworkPath ?? entry.artworkPath,
                          thumbnailPath: representative.thumbnailPath ?? entry.thumbnailPath,
                          size: 48,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      if (isSelectionMode)
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: isSelected,
                                onChanged: (_) => onTap(),
                                fillColor: WidgetStateProperty.all(Colors.white),
                                checkColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.artist.isNotEmpty
                            ? '${entry.artist} • ${l10n.songCount(entry.songs.length)}'
                            : l10n.songCount(entry.songs.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (trailingBuilder != null) ...[
                  trailingBuilder!(context, entry),
                  const SizedBox(width: 4),
                ] else ...[
                  Text(
                    l10n.playCountLabel(entry.totalPlayCount),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                IconButton(
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 24),
                  tooltip: l10n.play,
                  onPressed: onPlay,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return DraggableAlbumItem(
      album: album,
      enabled: !isSelectionMode,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: onSecondaryTapDown,
        child: tile,
      ),
    );
  }
}
