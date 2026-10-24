import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/album_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'album_context_menu.dart';
import 'draggable_album_item.dart';
import 'draggable_song_item.dart';
import 'library_selection_panel.dart';
import 'library_selection_scope.dart';
import 'playback_ui_tuning.dart';
import 'playing_equalizer_icon.dart';
import 'section_type_toggle.dart';
import 'song_thumbnail.dart';

/// 洞察页统一列表（最近播放 / 最多播放 / 最近添加 / 已评分共用）。
///
/// 单曲与专辑两种展示共用同一个 Widget 类型与同一套 State：
/// - 切换「单曲 / 专辑」只替换 body 的 sliver，[CustomScrollView]、[ScrollController]、
///   搜索词与搜索展开状态、多选状态全部保活，不会整页重建（旧实现是两个不同的
///   Widget 类型互相替换，切换时滚动位置与搜索词都会被清空，视觉上闪一下）。
/// - 单曲行按视口懒构建（[SliverFixedExtentList]），专辑行同样懒构建（[SliverList]），
///   避免一次性构建数百行（含每行 `SongThumbnail` 的同步 `existsSync`）。
class LibraryInsightList extends ConsumerStatefulWidget {
  const LibraryInsightList({
    super.key,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.emptyText,
    required this.selectionScope,
    this.songs = const <LibraryInsightSongEntry>[],
    this.albums = const <TimeMachineAlbumEntry>[],
    this.isLoading = false,
    this.loadError,
    this.centerAction,
    this.headerTrailing,
    this.headerAction,
    this.customFilterBar,
    this.showTimeRange = false,
    this.selectedRange = LibraryTimeRange.allTime,
    this.onRangeChanged,
    this.showRankIndex = false,
    this.songTrailing,
    this.albumTrailing,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  /// 当前展示单曲还是专辑。只影响 body 与计数文案，不影响 Widget 类型。
  final SectionItemType type;
  final String title;
  final String subtitle;
  final String emptyText;

  /// 多选作用域：四类洞察页各自独立，避免同一 IndexedStack 内互相串选。
  final LibrarySelectionScope selectionScope;

  final List<LibraryInsightSongEntry> songs;
  final List<TimeMachineAlbumEntry> albums;

  /// 首次加载中（还没有任何数据）。reload 时上游已有旧值，不应传 true。
  final bool isLoading;
  final String? loadError;

  final Widget? centerAction;
  final Widget? headerTrailing;
  final Widget? headerAction;
  final Widget? customFilterBar;
  final bool showTimeRange;
  final LibraryTimeRange selectedRange;
  final ValueChanged<LibraryTimeRange>? onRangeChanged;

  /// 是否显示「01、02…」排名序号；最近播放 / 最近添加这类非排行视图可关闭。
  final bool showRankIndex;

  final Widget Function(BuildContext, LibraryInsightSongEntry)? songTrailing;
  final Widget Function(BuildContext, TimeMachineAlbumEntry)? albumTrailing;

  final double contentTopPadding;
  final double contentLeftPadding;

  @override
  ConsumerState<LibraryInsightList> createState() => _LibraryInsightListState();
}

class _LibraryInsightListState extends ConsumerState<LibraryInsightList>
    with SelectionStateMixin<LibraryInsightList, String> {
  @override
  LibrarySelectionScope get selectionScope => widget.selectionScope;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _isSearchExpanded = false;

  /// 专辑行每次渲染都要 [TimeMachineAlbumEntry.toAlbumSummary]（含 firstWhere 与
  /// 曲目时长求和）。按 stableId 缓存，避免每帧 × 每行重算。
  final Map<String, AlbumSummary> _albumSummaryCache = <String, AlbumSummary>{};

  bool get _isAlbums => widget.type == SectionItemType.albums;

  @override
  void didUpdateWidget(covariant LibraryInsightList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.albums, widget.albums)) {
      _albumSummaryCache.clear();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<LibraryInsightSongEntry> _filterSongs(
    List<LibraryInsightSongEntry> items,
  ) {
    if (_searchQuery.isEmpty) return items;
    final q = _searchQuery.toLowerCase();
    return items.where((entry) {
      final song = entry.song;
      return song.displayName.toLowerCase().contains(q) ||
          (song.artist ?? '').toLowerCase().contains(q) ||
          (song.album ?? '').toLowerCase().contains(q);
    }).toList();
  }

  List<TimeMachineAlbumEntry> _filterAlbums(List<TimeMachineAlbumEntry> items) {
    if (_searchQuery.isEmpty) return items;
    final q = _searchQuery.toLowerCase();
    return items.where((entry) {
      return entry.album.toLowerCase().contains(q) ||
          entry.artist.toLowerCase().contains(q);
    }).toList();
  }

  AlbumSummary _summaryFor(TimeMachineAlbumEntry entry) =>
      _albumSummaryCache.putIfAbsent(entry.stableId, entry.toAlbumSummary);

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

  void _openAlbum(TimeMachineAlbumEntry entry) {
    if (entry.songs.isEmpty) return;
    final album = _summaryFor(entry);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: 'album_detail_${album.id}'),
        builder: (_) => AlbumDetailPage(album: album),
      ),
    );
  }

  /// 播放全部 / 随机播放：曲目在点击时才展开，避免每帧把几百张专辑的全部曲目
  /// `expand` 成一个大列表。
  void _playAll(
    List<LibraryInsightSongEntry> songs,
    List<TimeMachineAlbumEntry> albums, {
    bool shuffle = false,
  }) {
    final playable = _isAlbums
        ? albums.expand((entry) => entry.songs).toList()
        : [for (final entry in songs) entry.song];
    if (playable.isEmpty) return;
    if (shuffle) playable.shuffle();
    ref.read(audioServiceProvider).playPlaylist(playable);
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

  String _timeRangeLabel(AppLocalizations l10n, LibraryTimeRange range) {
    return switch (range) {
      LibraryTimeRange.allTime => l10n.allTime,
      LibraryTimeRange.last7Days => l10n.pastWeek,
      LibraryTimeRange.last30Days => l10n.pastMonth,
      LibraryTimeRange.last90Days => l10n.past90Days,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    final visibleSongs = _isAlbums
        ? const <LibraryInsightSongEntry>[]
        : _filterSongs(widget.songs);
    final visibleAlbums = _isAlbums
        ? _filterAlbums(widget.albums)
        : const <TimeMachineAlbumEntry>[];
    final visibleCount = _isAlbums ? visibleAlbums.length : visibleSongs.length;
    final sourceEmpty = _isAlbums ? widget.albums.isEmpty : widget.songs.isEmpty;

    final selectionMode = isSelectionMode;
    final visibleKeys = _isAlbums
        ? [for (final entry in visibleAlbums) entry.stableId]
        : [for (final entry in visibleSongs) entry.song.path];

    final selectedSongs = selectionMode
        ? (_isAlbums
              ? _collectSongs(
                  visibleAlbums.where((entry) => isSelected(entry.stableId)),
                )
              : [
                  for (final entry in visibleSongs)
                    if (isSelected(entry.song.path)) entry.song,
                ])
        : const <MusicFile>[];
    final allSongsInView = selectionMode
        ? (_isAlbums
              ? _collectSongs(visibleAlbums)
              : [for (final entry in visibleSongs) entry.song])
        : const <MusicFile>[];

    final countLabel = _isAlbums
        ? l10n.albumCount(visibleCount)
        : l10n.songCount(visibleCount);

    Widget currentBody = NotificationListener<ScrollNotification>(
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

                        final titleBlock = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _searchQuery.isNotEmpty ? countLabel : widget.subtitle,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        );

                        final playAllButton = IconButton(
                          tooltip: l10n.playAll,
                          icon: const Icon(Icons.play_arrow_rounded),
                          onPressed: visibleCount > 0
                              ? () => _playAll(visibleSongs, visibleAlbums)
                              : null,
                        );

                        final shufflePlayButton = IconButton(
                          tooltip: l10n.shufflePlay,
                          icon: const Icon(Icons.shuffle_rounded),
                          onPressed: visibleCount > 0
                              ? () => _playAll(visibleSongs, visibleAlbums, shuffle: true)
                              : null,
                        );

                        return Container(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, isWide ? 12 : 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              if (isWide) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: titleBlock,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 5,
                                      child: _buildSearchField(theme, l10n),
                                    ),
                                    const SizedBox(width: 12),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        playAllButton,
                                        shufflePlayButton,
                                        if (widget.headerTrailing != null) ...[
                                          const SizedBox(width: 6),
                                          widget.headerTrailing!,
                                        ],
                                        if (widget.headerAction != null) ...[
                                          const SizedBox(width: 6),
                                          widget.headerAction!,
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                if (widget.centerAction != null) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: widget.centerAction!,
                                  ),
                                ],
                              ]
                              else ...[
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    titleBlock,
                                    const SizedBox(height: 10),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      transitionBuilder: (child, animation) {
                                        return FadeTransition(opacity: animation, child: child);
                                      },
                                      child: (_isSearchExpanded || _searchQuery.isNotEmpty)
                                          ? Row(
                                              key: const ValueKey('insight_header_search_active'),
                                              children: [
                                                Expanded(child: _buildSearchField(theme, l10n)),
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  tooltip: l10n.cancel,
                                                  icon: const Icon(Icons.close_rounded),
                                                  onPressed: () {
                                                    _searchController.clear();
                                                    setState(() {
                                                      _searchQuery = '';
                                                      _isSearchExpanded = false;
                                                    });
                                                    _searchFocusNode.unfocus();
                                                  },
                                                ),
                                              ],
                                            )
                                          : Row(
                                              key: const ValueKey('insight_header_actions_normal'),
                                              children: [
                                                playAllButton,
                                                shufflePlayButton,
                                                IconButton(
                                                  tooltip: l10n.search,
                                                  icon: const Icon(Icons.search_rounded),
                                                  onPressed: () {
                                                    setState(() {
                                                      _isSearchExpanded = true;
                                                    });
                                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                                      if (mounted) {
                                                        _searchFocusNode.requestFocus();
                                                      }
                                                    });
                                                  },
                                                ),
                                                const Spacer(),
                                                if (widget.headerTrailing != null) widget.headerTrailing!,
                                                if (widget.headerAction != null) ...[
                                                  const SizedBox(width: 6),
                                                  widget.headerAction!,
                                                ],
                                              ],
                                            ),
                                    ),
                                    if (widget.centerAction != null) ...[
                                      const SizedBox(height: 12),
                                      Center(child: widget.centerAction!),
                                    ],
                                  ],
                                ),
                              ],
                              if (widget.showTimeRange) ...[
                                const SizedBox(height: 16),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: Row(
                                    children: [
                                      for (int i = 0; i < LibraryTimeRange.values.length; i++) ...[
                                        if (i > 0) const SizedBox(width: 8),
                                        ChoiceChip(
                                          label: Text(_timeRangeLabel(l10n, LibraryTimeRange.values[i])),
                                          selected: widget.selectedRange == LibraryTimeRange.values[i],
                                          onSelected: (_) => widget.onRangeChanged?.call(LibraryTimeRange.values[i]),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ] else if (widget.customFilterBar != null) ...[
                                const SizedBox(height: 16),
                                widget.customFilterBar!,
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            ..._buildBodySlivers(
              theme: theme,
              l10n: l10n,
              audio: audio,
              currentMusic: currentMusic,
              visibleSongs: visibleSongs,
              visibleAlbums: visibleAlbums,
              visibleKeys: visibleKeys,
              selectionMode: selectionMode,
              sourceEmpty: sourceEmpty,
            ),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        currentBody,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            reverseDuration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offsetAnimation = Tween<Offset>(
                begin: const Offset(0, 1.0),
                end: Offset.zero,
              ).animate(animation);
              return SlideTransition(position: offsetAnimation, child: child);
            },
            child: isSelectionMode
                ? LibrarySelectionPanel(
                    key: const ValueKey('library-insight-selection-panel'),
                    selectedSongs: selectedSongs,
                    allSongs: allSongsInView,
                    title: _isAlbums
                        ? l10n.selectedAlbumsCount(selectedCount)
                        : null,
                    onToggleSelectAll: () => toggleSelectAll(visibleKeys),
                    onCancel: cancelSelection,
                  )
                : const SizedBox.shrink(key: ValueKey('library-insight-selection-panel-hidden')),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildBodySlivers({
    required ThemeData theme,
    required AppLocalizations l10n,
    required AudioService audio,
    required MusicFile? currentMusic,
    required List<LibraryInsightSongEntry> visibleSongs,
    required List<TimeMachineAlbumEntry> visibleAlbums,
    required List<String> visibleKeys,
    required bool selectionMode,
    required bool sourceEmpty,
  }) {
    if (sourceEmpty) {
      if (widget.isLoading) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      }
      if (widget.loadError != null) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    widget.loadError!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ];
      }
      return [
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ];
    }

    final visibleCount = _isAlbums ? visibleAlbums.length : visibleSongs.length;
    if (visibleCount == 0) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.noMatchingResults,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      label: Text(l10n.clearSearch),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }

    return _isAlbums
        ? _buildAlbumSlivers(
            theme: theme,
            l10n: l10n,
            audio: audio,
            currentMusic: currentMusic,
            albums: visibleAlbums,
            visibleKeys: visibleKeys,
            selectionMode: selectionMode,
          )
        : _buildSongSlivers(
            theme: theme,
            l10n: l10n,
            audio: audio,
            currentMusic: currentMusic,
            songs: visibleSongs,
            visibleKeys: visibleKeys,
            selectionMode: selectionMode,
          );
  }

  List<Widget> _buildSongSlivers({
    required ThemeData theme,
    required AppLocalizations l10n,
    required AudioService audio,
    required MusicFile? currentMusic,
    required List<LibraryInsightSongEntry> songs,
    required List<String> visibleKeys,
    required bool selectionMode,
  }) {
    final playableSongs = [for (final entry in songs) entry.song];
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          kInsightListHorizontalInset,
          4,
          kInsightListHorizontalInset,
          MiniPlayerUiTuning.getListBottomPadding(
            context,
            hasPlayingMusic: currentMusic != null,
            isSelectionMode: selectionMode,
          ),
        ),
        sliver: SliverFixedExtentList.builder(
          itemExtent: 64.0,
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final entry = songs[index];
            final selected = isSelected(entry.song.path);
            return Align(
              key: ValueKey(entry.song.path),
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: _SongListItem(
                    entry: entry,
                    l10n: l10n,
                    audio: audio,
                    trailingBuilder: widget.songTrailing,
                    isSelectionMode: selectionMode,
                    isSelected: selected,
                    selectedPaths: selectedKeys,
                    onTap: () {
                      handleItemTap(
                        index: index,
                        itemKey: entry.song.path,
                        allKeys: visibleKeys,
                        onNormalTap: () {
                          audio.playPlaylist(
                            playableSongs,
                            initialIndex: index,
                          );
                        },
                      );
                    },
                    onLongPress: () {
                      lastAnchorIndex = index;
                      if (!selectionMode) {
                        enterSelectionMode(entry.song.path);
                      }
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _buildAlbumSlivers({
    required ThemeData theme,
    required AppLocalizations l10n,
    required AudioService audio,
    required MusicFile? currentMusic,
    required List<TimeMachineAlbumEntry> albums,
    required List<String> visibleKeys,
    required bool selectionMode,
  }) {
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          kInsightListHorizontalInset,
          4,
          kInsightListHorizontalInset,
          MiniPlayerUiTuning.getListBottomPadding(
            context,
            hasPlayingMusic: currentMusic != null,
            isSelectionMode: selectionMode,
          ),
        ),
        // 必须懒构建：最多 500 个专辑条目，`ListView(shrinkWrap: true)` 会在一帧内
        // 测量并构建全部行（含每行 SongThumbnail 的同步 IO），切换视图时整页掉帧。
        sliver: SliverList.builder(
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final entry = albums[index];
            final album = _summaryFor(entry);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kSingleColumnContentMaxWidth,
                  ),
                  child: _RankedAlbumTile(
                    index: index + 1,
                    entry: entry,
                    album: album,
                    showRankIndex: widget.showRankIndex,
                    trailingBuilder: widget.albumTrailing,
                    isSelectionMode: selectionMode,
                    isSelected: isSelected(entry.stableId),
                    onTap: () {
                      handleItemTap(
                        index: index,
                        itemKey: entry.stableId,
                        allKeys: visibleKeys,
                        onNormalTap: () => _openAlbum(entry),
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
                        onViewDetails: () => _openAlbum(entry),
                      );
                    },
                    onPlay: () {
                      if (album.songs.isNotEmpty) {
                        audio.playPlaylist(album.songs);
                      }
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }
}

/// 洞察列表卡片的水平内边距：单曲与专辑两种视图必须共用，否则切视图时
/// 卡片宽度与封面左边缘都会跳动（旧实现单曲 12/16 + sliver 12、专辑固定 10 + sliver 16）。
EdgeInsets _insightRowPadding(BuildContext context) => EdgeInsets.symmetric(
  horizontal: MediaQuery.of(context).orientation == Orientation.portrait ? 12 : 16,
  vertical: 8,
);

/// Sliver 外层的水平留白，同样两种视图共用。
const double kInsightListHorizontalInset = 12;

class _SongListItem extends ConsumerWidget {
  const _SongListItem({
    required this.entry,
    required this.l10n,
    required this.audio,
    required this.trailingBuilder,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedPaths,
    required this.onTap,
    required this.onLongPress,
  });

  final LibraryInsightSongEntry entry;
  final AppLocalizations l10n;
  final AudioService audio;
  final Widget Function(BuildContext, LibraryInsightSongEntry)? trailingBuilder;
  final bool isSelectionMode;
  final bool isSelected;
  final Iterable<String>? selectedPaths;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final song = entry.song;
    final isMissing = song.isMissing;
    final currentSong = ref.watch(audioCurrentMusicProvider);
    final isPlaying = ref.watch(audioIsPlayingProvider);
    final isCurrent = currentSong != null && currentSong.path == song.path;

    final textColor = isMissing
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
        : isCurrent
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;

    final itemWidget = RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) async {
          if (!isSelectionMode) {
            await showSongContextMenu(
              context,
              details.globalPosition,
              song: song,
              songs: [song],
              mode: SongContextMenuMode.full,
              onMultiSelect: isSelectionMode ? null : onLongPress,
              onPlayNext: () => ref.read(audioServiceProvider).enqueueNext([song]),
              onAddToQueue: () => ref.read(audioServiceProvider).appendToQueue([song]),
              onAddToPlaylist: () async {
                await showAddSongsToPlaylistDialog(
                  context,
                  ref.read(playlistServiceProvider),
                  [song],
                );
              },
            );
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: isSelectionMode && isSelected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : isCurrent
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              enableFeedback: false,
              hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: _insightRowPadding(context),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Opacity(
                            opacity: isMissing
                                ? 0.35
                                : isSelectionMode
                                    ? (isSelected ? 0.5 : 0.7)
                                    : 1.0,
                            child: SongThumbnail.fromSong(
                              song,
                              size: 44,
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isCurrent && !isMissing) ...[
                                PlayingEqualizerIcon(
                                  color: theme.colorScheme.primary,
                                  size: 16,
                                  isPlaying: isPlaying,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  song.displayName,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: textColor,
                                    fontWeight: isCurrent && !isMissing ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _songSubtitle(l10n, entry),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isMissing
                                  ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                                  : isCurrent
                                      ? theme.colorScheme.primary.withValues(alpha: 0.8)
                                      : theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (trailingBuilder != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 90),
                        child: trailingBuilder!(context, entry),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return DraggableSongItem(
      song: song,
      enabled: !isMissing,
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      selectedPaths: selectedPaths,
      child: itemWidget,
    );
  }

  String _songSubtitle(AppLocalizations l10n, LibraryInsightSongEntry entry) {
    final song = entry.song;
    final artist = isVisibleSongText(song.artist)
        ? song.artist!.trim()
        : l10n.unknownArtist;
    final album = isVisibleSongText(song.album)
        ? song.album!.trim()
        : l10n.unknownAlbum;
    final baseSubtitle = '$artist · $album';
    if ((entry.sourceFlags ?? 0) & SongSourceFlags.external != 0) {
      return '$baseSubtitle  •  [${l10n.externalSourceTag}]';
    }
    return baseSubtitle;
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
            padding: _insightRowPadding(context),
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
                  width: 44,
                  height: 44,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: isSelectionMode ? (isSelected ? 0.5 : 0.7) : 1.0,
                        child: SongThumbnail(
                          path: representative.path,
                          artworkPath: representative.artworkPath ?? entry.artworkPath,
                          thumbnailPath: representative.thumbnailPath ?? entry.thumbnailPath,
                          size: 44,
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 3),
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
