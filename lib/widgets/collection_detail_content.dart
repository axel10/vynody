import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/album_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/app_log.dart';
import 'album_context_menu.dart';
import 'album_sections.dart';
import 'album_zoom_item.dart';
import 'collection_detail_header.dart';
import 'draggable_album_item.dart';
import 'folder_layout_utils.dart';
import 'folder_zoom_gesture_layer.dart';
import 'library_selection_panel.dart';
import 'library_selection_scope.dart';
import 'library_search_field.dart';
import 'mini_player_wrapper.dart';

/// 流派 / 年份等「集合型」条目的详情内容。
///
/// 顶部为 [CollectionDetailHeader]，
/// 竖屏下像艺术家详情页一样展示专辑网格；
/// 横屏下按专辑分组渲染曲目列表；
/// 分组、播放、多选与底部避让逻辑在此统一实现，各页面只负责提供数据与播放来源。
class CollectionDetailContent extends ConsumerStatefulWidget {
  const CollectionDetailContent({
    super.key,
    required this.title,
    required this.songCount,
    required this.albumCount,
    required this.totalDurationMillis,
    required this.songs,
    required this.source,
    this.showSelectionPanel = true,
    this.hasBottomPanel = false,
    this.scrollController,
    this.topPadding = 0.0,
    this.searchHintText,
    this.noMatchText,
  });

  final String title;
  final int songCount;
  final int albumCount;
  final int totalDurationMillis;

  /// 该集合下的全部歌曲（未分组），分组由内部完成并缓存。
  final List<MusicFile> songs;

  /// 播放全部、随机播放与单曲播放共用的播放来源。
  final PlaybackSource source;

  final bool showSelectionPanel;
  final bool hasBottomPanel;
  final ScrollController? scrollController;
  final double topPadding;

  /// 集合内搜索的提示文案。流派 / 年份各给各的措辞，
  /// 留空时回落到通用「搜索」。
  final String? searchHintText;

  /// 搜索无命中时的提示文案，留空时回落到通用的「未找到匹配结果」。
  final String? noMatchText;

  @override
  ConsumerState<CollectionDetailContent> createState() =>
      _CollectionDetailContentState();
}

class _CollectionDetailContentState extends ConsumerState<CollectionDetailContent>
    with
        SelectionStateMixin<CollectionDetailContent, String>,
        SongSelectionMixin<CollectionDetailContent> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.library;

  final AlbumSectionsCache _albumCache = AlbumSectionsCache();

  /// 集合内搜索：默认收起，点页头行尾的放大镜展开。
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  bool _searchOpen = false;
  String _query = '';

  /// 输入防抖。一个流派动辄上千首、上百个分组，
  /// 每敲一个字都重建一遍整页分组会掉帧。
  Timer? _queryDebounce;

  @override
  void dispose() {
    _queryDebounce?.cancel();
    _queryController.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CollectionDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 分栏布局切换流派 / 年份时复用同一个组件，别把上一条目的搜索词带过来。
    // 判定用播放来源 id 而不是歌曲列表：播放写入会让曲库快照重算，
    // 歌曲列表每次都是新实例，按它复位会把正在输入的关键词清掉。
    if (oldWidget.source.id != widget.source.id) {
      _queryDebounce?.cancel();
      _queryController.clear();
      _query = '';
      _searchOpen = false;
    }
  }

  /// 当前搜索词命中后的分组，空词时原样返回。
  ///
  /// 命中口径与分栏布局无关，统一在 [filterAlbumSections] 里实现，
  /// 本地艺术家 / 流派 / 年份与远程流派页共用同一套口径。
  List<AlbumSection> _visibleSections(List<AlbumSection> sections) =>
      filterAlbumSections(sections, _query);

  void _onQueryChanged(String value) {
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final next = value.trim();
      if (next == _query) return;
      setState(() => _query = next);
    });
  }

  void _toggleSearch() {
    final open = !_searchOpen;
    setState(() {
      _queryDebounce?.cancel();
      _searchOpen = open;
      if (!open) {
        // 收起必须连带清空，否则列表还停在旧结果上，看起来像数据丢了。
        _queryController.clear();
        _query = '';
      }
    });
    if (open) {
      // 等展开动画铺开再要焦点，避免键盘弹起和尺寸动画打架。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _queryFocus.requestFocus();
      });
    } else {
      _queryFocus.unfocus();
    }
  }

  void _clearQuery() {
    _queryDebounce?.cancel();
    _queryController.clear();
    setState(() => _query = '');
    _queryFocus.requestFocus();
  }

  int _durationOf(List<AlbumSection> sections) {
    var sum = 0;
    for (final section in sections) {
      sum += section.totalDurationMillis;
    }
    return sum;
  }

  /// 页头行尾的搜索开关。展开时图标高亮，再点一次收起并清空。
  Widget _buildSearchToggle(AppLocalizations l10n, ThemeData theme) {
    return IconButton(
      tooltip: _searchOpen ? l10n.closeSearch : l10n.search,
      onPressed: _toggleSearch,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      icon: Icon(
        _searchOpen ? Icons.search_off_rounded : Icons.search_rounded,
        size: 20,
        color: _searchOpen
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// 折叠式搜索框：收起时高度为 0，不占版面。
  Widget _buildSearchField(AppLocalizations l10n) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: _searchOpen
          ? Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LibrarySearchField(
                controller: _queryController,
                focusNode: _queryFocus,
                hintText: widget.searchHintText ?? l10n.search,
                query: _query,
                onChanged: _onQueryChanged,
                onClear: _clearQuery,
              ),
            )
          : const SizedBox(width: double.infinity, height: 0),
    );
  }

  Widget _buildNoMatch(AppLocalizations l10n, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 10),
            Text(
              widget.noMatchText ?? l10n.noMatchingResults,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _clearQuery,
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: Text(l10n.clearSearch),
            ),
          ],
        ),
      ),
    );
  }

  void _playAll(List<MusicFile> songs) {
    ref.read(audioServiceProvider).playPlaylist(songs, source: widget.source);
  }

  List<AlbumSummary> _buildAlbums(
    List<AlbumSection> sections,
    List<AlbumSummary>? libraryAlbums,
    String unknownArtistLabel,
  ) {
    final libraryMap = <String, AlbumSummary>{};
    if (libraryAlbums != null) {
      for (final album in libraryAlbums) {
        libraryMap[album.id] = album;
      }
    }

    return sections.map((section) {
      final firstSong = section.songs.firstOrNull;
      final effectiveArtist =
          (firstSong?.albumArtist ?? firstSong?.artist ?? '').trim();
      final expectedId =
          '${section.title.toLowerCase()}::${effectiveArtist.toLowerCase()}';

      final matched = libraryMap[expectedId];
      if (matched != null) return matched;

      if (libraryAlbums != null && effectiveArtist.isNotEmpty) {
        final matchedByArtist = libraryAlbums.firstWhereOrNull(
          (a) =>
              a.title.toLowerCase() == section.title.toLowerCase() &&
              (a.artist.toLowerCase() == effectiveArtist.toLowerCase() ||
                  a.songs.any((s) =>
                      (s.albumArtist ?? s.artist ?? '')
                          .trim()
                          .toLowerCase() ==
                      effectiveArtist.toLowerCase())),
        );
        if (matchedByArtist != null) return matchedByArtist;
      }

      if (libraryAlbums != null) {
        final titleMatched = libraryAlbums.firstWhereOrNull(
          (a) => a.title.toLowerCase() == section.title.toLowerCase(),
        );
        if (titleMatched != null) return titleMatched;
      }

      final albumYears = <int>{};
      for (final s in section.songs) {
        if (s.year != null && s.year! > 0) {
          albumYears.add(s.year!);
        }
      }

      return AlbumSummary(
        id: expectedId,
        title: section.title,
        artist: effectiveArtist.isNotEmpty ? effectiveArtist : unknownArtistLabel,
        songs: section.songs,
        representativeSong: section.representativeSong,
        totalDurationMillis: section.totalDurationMillis,
        minYear: albumYears.isEmpty ? null : albumYears.reduce(math.min),
        maxYear: albumYears.isEmpty ? null : albumYears.reduce(math.max),
      );
    }).toList();
  }

  void _openAlbumDetail(AlbumSummary album) {
    AppLog.log(
      '[NavTrace] CollectionDetailContent _openAlbumDetail: pushing AlbumDetailPage for album="${album.title}" (id=${album.id})',
      mirrorToConsole: true,
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: '/album_detail/${Uri.encodeComponent(album.id)}',
        ),
        builder: (_) => AlbumDetailPage(album: album),
      ),
    );
  }

  List<Widget> _buildPortraitAlbumGridSlivers({
    required BuildContext context,
    required WidgetRef ref,
    required List<AlbumSummary> albums,
    required double contentWidth,
    required double albumZoomScale,
  }) {
    final audio = ref.read(audioServiceProvider);

    return [
      FolderZoomSliverBuilder(
        zoomScale: snapFolderZoomScale(albumZoomScale),
        width: contentWidth,
        builder: (context, metrics) {
          final hPad = folderContentHorizontalPadding(
            isPortrait: true,
            gridMorph: metrics.gridMorph,
          );

          return SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            sliver: SliverGrid(
              gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final album = albums[index];
                  return DraggableAlbumItem(
                    album: album,
                    enabled: true,
                    child: AlbumZoomItem(
                      album: album,
                      metrics: metrics,
                      isSelected: false,
                      isSelectionMode: false,
                      enableHero: true,
                      onTap: () => _openAlbumDetail(album),
                      onSecondaryTapDown: (details) {
                        showAlbumContextMenu(
                          context: context,
                          globalPosition: details.globalPosition,
                          ref: ref,
                          album: album,
                        );
                      },
                      onPlay: () => audio.playPlaylist(
                        album.songs,
                        source: PlaybackSource(
                          type: PlaybackSourceType.album,
                          id: album.id,
                          name: album.title,
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);
    final currentMusicPath = ref.watch(audioCurrentMusicProvider)?.path;

    _albumCache.update(widget.songs, l10n.unknownAlbum);
    final sections = _albumCache.sections;
    final displaySongs = _albumCache.allSongs;

    final visibleSections = _visibleSections(sections);
    // 空词时直接用缓存里的扁平列表，不必每次重建。
    final visibleSongs = identical(visibleSections, sections)
        ? displaySongs
        : [
            for (final section in visibleSections) ...section.songs,
          ];

    final selectedSongs = isSelectionMode
        ? getSelectedSongs(visibleSongs)
        : const <MusicFile>[];

    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final horizontalPadding = isPortrait ? 20.0 : 28.0;

    // 统计跟着可见集合走，避免「列表只剩 3 首、页头还写着整张流派 120 首」。
    final durationLabel = _query.isEmpty
        ? (formatDurationClock(widget.totalDurationMillis) ?? l10n.durationZero)
        : (formatDurationClock(_durationOf(visibleSections)) ??
            l10n.durationZero);
    final songCountLabel = _query.isEmpty ? widget.songCount : visibleSongs.length;
    final albumCountLabel =
        _query.isEmpty ? widget.albumCount : visibleSections.length;

    final libraryAlbums = ref.watch(albumLibraryProvider).asData?.value;
    final albumZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.albumZoomScale),
    );
    final albums = _buildAlbums(visibleSections, libraryAlbums, l10n.unknownArtist);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.min(constraints.maxWidth, kFolderPageMaxWidth);

        final scrollView = CustomScrollView(
          controller: widget.scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  widget.topPadding > 0 ? widget.topPadding + 12 : 24,
                  horizontalPadding,
                  isPortrait ? 24.0 : 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CollectionDetailHeader(
                      title: widget.title,
                      metaLine: '${l10n.songCount(songCountLabel)} · '
                          '${l10n.albumCount(albumCountLabel)} · $durationLabel',
                      onPlayAll: () => _playAll(visibleSongs),
                      onShufflePlay: () =>
                          _playAll(List<MusicFile>.of(visibleSongs)..shuffle()),
                      trailingAction: _buildSearchToggle(l10n, theme),
                    ),
                    _buildSearchField(l10n),
                  ],
                ),
              ),
            ),
            if (sections.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(l10n.emptyList, style: theme.textTheme.titleMedium),
                ),
              )
            else if (visibleSections.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildNoMatch(l10n, theme),
              )
            else if (isPortrait)
              ..._buildPortraitAlbumGridSlivers(
                context: context,
                ref: ref,
                albums: albums,
                contentWidth: contentWidth,
                albumZoomScale: albumZoomScale,
              )
            else
              for (int i = 0; i < visibleSections.length; i++) ...[
                if (i > 0) const SliverToBoxAdapter(child: SizedBox(height: 36)),
                AlbumSectionSliver(
                  section: visibleSections[i],
                  currentMusicPath: currentMusicPath,
                  onSongTap: (section, songIndex) {
                    final song = section.songs[songIndex];
                    final globalIndex = section.startIndex + songIndex;
                    handleSongTap(
                      index: globalIndex,
                      songPath: song.path,
                      allSongs: visibleSongs,
                      onNormalTap: () {
                        audio.playPlaylist(
                          visibleSongs,
                          initialIndex: globalIndex,
                          source: widget.source,
                        );
                      },
                    );
                  },
                  onSongLongPress: (section, song) {
                    final songIndex = section.songs.indexOf(song);
                    if (songIndex != -1) {
                      lastAnchorIndex = section.startIndex + songIndex;
                    }
                    if (!isSelectionMode) {
                      enterSongSelectionMode(song.path);
                    }
                  },
                  isSelectionMode: isSelectionMode,
                  selectedSongPaths: selectedSongPaths,
                  onOpenAlbum: i < albums.length
                      ? () => _openAlbumDetail(albums[i])
                      : null,
                ),
              ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: MiniPlayerUiTuning.getListBottomPadding(
                  context,
                  hasPlayingMusic: currentMusicPath != null,
                  isSelectionMode: widget.hasBottomPanel ||
                      (!isPortrait && isSelectionMode && widget.showSelectionPanel),
                  selectionPanelHeight: 220.0,
                ),
              ),
            ),
          ],
        );

        final scrollContent = isPortrait
            ? FolderZoomGestureLayer(
                scope: LibraryZoomScope.album,
                child: scrollView,
              )
            : scrollView;

        return Stack(
          children: [
            scrollContent,
            AnimatedSelectionPanel(
              isVisible: !isPortrait && isSelectionMode && widget.showSelectionPanel,
              child: LibrarySelectionPanel(
                key: const ValueKey('library-selection-panel'),
                selectedSongs: selectedSongs,
                allSongs: visibleSongs,
                onToggleSelectAll: () => toggleSelectAllSongs(visibleSongs),
                onCancel: cancelSongSelection,
              ),
            ),
          ],
        );
      },
    );
  }
}
