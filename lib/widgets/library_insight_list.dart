import 'dart:math' as math;

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
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'album_context_menu.dart';
import 'album_zoom_item.dart';
import 'draggable_album_item.dart';
import 'draggable_song_item.dart';
import 'folder_layout_utils.dart';
import 'folder_zoom_gesture_layer.dart';
import 'library_selection_panel.dart';
import 'library_selection_scope.dart';
import 'library_zoom_popover.dart';
import 'playback_ui_tuning.dart';
import 'section_type_toggle.dart';
import 'song_zoom_item.dart';

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
    this.subtitle,
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
  final String? subtitle;
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

    final currentScope = _isAlbums ? LibraryZoomScope.album : LibraryZoomScope.song;
    final zoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.zoomScaleFor(currentScope)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final availableWidth = constraints.maxWidth - widget.contentLeftPadding;
        final contentWidth = math.min(availableWidth, kFolderPageMaxWidth);

        final subtitleText =
            _searchQuery.isNotEmpty ? countLabel : widget.subtitle;

        final largeTitleBlock = Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            if (subtitleText != null && subtitleText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  subtitleText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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

        final zoomButton = LibraryZoomButton(scope: currentScope);

        final headerSliver = SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, headerConstraints) {
                final isWide = headerConstraints.maxWidth >= 600;

                return Container(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, isWide ? 8 : 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isWide) ...[
                        Row(
                          children: [
                            largeTitleBlock,
                            const SizedBox(width: 16),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 280),
                                  child: _buildSearchField(theme, l10n),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
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
                                const SizedBox(width: 6),
                                zoomButton,
                              ],
                            ),
                          ],
                        ),
                        if (widget.centerAction != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: widget.centerAction!,
                          ),
                        ],
                      ] else ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            largeTitleBlock,
                            const SizedBox(height: 8),
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
                                        const Spacer(),
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
                                        if (widget.headerTrailing != null) widget.headerTrailing!,
                                        if (widget.headerAction != null) ...[
                                          const SizedBox(width: 6),
                                          widget.headerAction!,
                                        ],
                                        const SizedBox(width: 6),
                                        zoomButton,
                                      ],
                                    ),
                            ),
                            if (widget.centerAction != null) ...[
                              const SizedBox(height: 8),
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
        );

        final mainContent = Padding(
          padding: EdgeInsets.only(left: widget.contentLeftPadding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kFolderPageMaxWidth),
              child: FolderZoomGestureLayer(
                scope: currentScope,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    if (widget.contentTopPadding > 0)
                      SliverToBoxAdapter(
                        child: SizedBox(height: widget.contentTopPadding),
                      ),
                    headerSliver,
                    ..._buildBodySlivers(
                      context: context,
                      theme: theme,
                      l10n: l10n,
                      audio: audio,
                      currentMusic: currentMusic,
                      visibleSongs: visibleSongs,
                      visibleAlbums: visibleAlbums,
                      visibleKeys: visibleKeys,
                      selectionMode: selectionMode,
                      sourceEmpty: sourceEmpty,
                      zoomScale: zoomScale,
                      contentWidth: contentWidth,
                      isPortrait: isPortrait,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null &&
                    _searchFocusNode.hasFocus) {
                  _searchFocusNode.unfocus();
                }
                return false;
              },
              child: mainContent,
            ),
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
      },
    );
  }

  List<Widget> _buildBodySlivers({
    required BuildContext context,
    required ThemeData theme,
    required AppLocalizations l10n,
    required AudioService audio,
    required MusicFile? currentMusic,
    required List<LibraryInsightSongEntry> visibleSongs,
    required List<TimeMachineAlbumEntry> visibleAlbums,
    required List<String> visibleKeys,
    required bool selectionMode,
    required bool sourceEmpty,
    required double zoomScale,
    required double contentWidth,
    required bool isPortrait,
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
        ];
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
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
      ];
    }

    final visibleCount = _isAlbums ? visibleAlbums.length : visibleSongs.length;
    if (visibleCount == 0) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
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
      ];
    }

    return _isAlbums
        ? _buildAlbumSlivers(
            context: context,
            theme: theme,
            l10n: l10n,
            audio: audio,
            currentMusic: currentMusic,
            albums: visibleAlbums,
            visibleKeys: visibleKeys,
            selectionMode: selectionMode,
            zoomScale: zoomScale,
            contentWidth: contentWidth,
            isPortrait: isPortrait,
          )
        : _buildSongSlivers(
            context: context,
            theme: theme,
            l10n: l10n,
            audio: audio,
            currentMusic: currentMusic,
            songs: visibleSongs,
            visibleKeys: visibleKeys,
            selectionMode: selectionMode,
            zoomScale: zoomScale,
            contentWidth: contentWidth,
            isPortrait: isPortrait,
          );
  }

  List<Widget> _buildSongSlivers({
    required BuildContext context,
    required ThemeData theme,
    required AppLocalizations l10n,
    required AudioService audio,
    required MusicFile? currentMusic,
    required List<LibraryInsightSongEntry> songs,
    required List<String> visibleKeys,
    required bool selectionMode,
    required double zoomScale,
    required double contentWidth,
    required bool isPortrait,
  }) {
    final playableSongs = [for (final entry in songs) entry.song];
    final bottomPadding = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
      isSelectionMode: selectionMode,
    );

    return [
      FolderZoomSliverBuilder(
        zoomScale: snapFolderZoomScale(zoomScale),
        width: contentWidth,
        builder: (context, metrics) {
          final hPad = folderContentHorizontalPadding(
            isPortrait: isPortrait,
            gridMorph: metrics.gridMorph,
          );

          return SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 4, hPad, bottomPadding),
            sliver: SliverGrid(
              gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = songs[index];
                  final song = entry.song;
                  final isCurrent = currentMusic?.path == song.path;
                  final isAudioPlaying = ref.watch(audioIsPlayingProvider);
                  final isSelected = this.isSelected(song.path);

                  final trailing = widget.songTrailing != null
                      ? widget.songTrailing!(context, entry)
                      : null;

                  return DraggableSongItem(
                    song: song,
                    enabled: !selectionMode,
                    child: SongZoomItem(
                      key: ValueKey(song.path),
                      song: song,
                      metrics: metrics,
                      isCurrent: isCurrent,
                      isPlaying: isAudioPlaying,
                      isSelected: isSelected,
                      isSelectionMode: selectionMode,
                      selectedPaths: selectedKeys,
                      trailing: trailing,
                      trailingWidth: trailing != null ? 140.0 : null,
                      onTap: () {
                        handleItemTap(
                          index: index,
                          itemKey: song.path,
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
                        if (selectionMode) {
                          toggleSelection(song.path);
                        } else {
                          enterSelectionMode(song.path);
                        }
                      },
                      onSecondaryTapDown: (details) {
                        if (!selectionMode) {
                          showSongContextMenu(
                            context,
                            details.globalPosition,
                            song: song,
                            songs: [song],
                            mode: SongContextMenuMode.full,
                            onMultiSelect: () => enterSelectionMode(song.path),
                          );
                        }
                      },
                      onMorePressed: (btnContext) {
                        final renderBox =
                            btnContext.findRenderObject() as RenderBox?;
                        final position = renderBox != null
                            ? renderBox.localToGlobal(Offset.zero) +
                                Offset(renderBox.size.width / 2,
                                    renderBox.size.height / 2)
                            : Offset.zero;
                        showSongContextMenu(
                          context,
                          position,
                          song: song,
                          songs: [song],
                          mode: SongContextMenuMode.full,
                          onMultiSelect: () => enterSelectionMode(song.path),
                        );
                      },
                    ),
                  );
                },
                childCount: songs.length,
              ),
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _buildAlbumSlivers({
    required BuildContext context,
    required ThemeData theme,
    required AppLocalizations l10n,
    required AudioService audio,
    required MusicFile? currentMusic,
    required List<TimeMachineAlbumEntry> albums,
    required List<String> visibleKeys,
    required bool selectionMode,
    required double zoomScale,
    required double contentWidth,
    required bool isPortrait,
  }) {
    final bottomPadding = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
      isSelectionMode: selectionMode,
    );

    return [
      FolderZoomSliverBuilder(
        zoomScale: snapFolderZoomScale(zoomScale),
        width: contentWidth,
        builder: (context, metrics) {
          final hPad = folderContentHorizontalPadding(
            isPortrait: isPortrait,
            gridMorph: metrics.gridMorph,
          );

          return SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 4, hPad, bottomPadding),
            sliver: SliverGrid(
              gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = albums[index];
                  final album = _summaryFor(entry);
                  final isSelected = this.isSelected(entry.stableId);

                  Widget? trailing = widget.albumTrailing != null
                      ? widget.albumTrailing!(context, entry)
                      : Text(
                          l10n.playCountLabel(entry.totalPlayCount),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );

                  final subtitleText = entry.artist.isNotEmpty
                      ? '${entry.artist} • ${l10n.songCount(entry.songs.length)}'
                      : l10n.songCount(entry.songs.length);

                  Widget? titlePrefix;
                  if (widget.showRankIndex) {
                    final rankNum = index + 1;
                    final isTop3 = rankNum <= 3;
                    titlePrefix = Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        rankNum.toString().padLeft(2, '0'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isTop3
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                        ),
                      ),
                    );
                  }

                  return DraggableAlbumItem(
                    album: album,
                    enabled: !selectionMode,
                    child: AlbumZoomItem(
                      album: album,
                      metrics: metrics,
                      isSelected: isSelected,
                      isSelectionMode: selectionMode,
                      enableHero: false,
                      subtitleText: subtitleText,
                      titlePrefix: titlePrefix,
                      trailing: trailing,
                      trailingWidth: 140.0,
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
                  );
                },
                childCount: albums.length,
              ),
            ),
          );
        },
      ),
    ];
  }
}

