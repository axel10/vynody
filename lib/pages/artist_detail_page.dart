import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/metadata/theaudiodb_artist_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/app_log.dart';
import '../widgets/album_context_menu.dart';
import '../widgets/album_sections.dart';
import '../widgets/album_zoom_item.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/draggable_album_item.dart';
import '../widgets/folder_layout_utils.dart';
import '../widgets/folder_zoom_gesture_layer.dart';
import '../widgets/remote_media_badge.dart';
import '../widgets/mini_player_wrapper.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/library_search_field.dart';
import '../widgets/detail_page_shell.dart';
import '../widgets/library_selection_back_guard.dart';
import 'album_detail_page.dart';

class ArtistDetailPage extends StatelessWidget {
  const ArtistDetailPage({
    super.key,
    required this.artist,
    this.onGoBack,
  });

  final ArtistSummary artist;
  final VoidCallback? onGoBack;

  @override
  Widget build(BuildContext context) {
    return LibrarySelectionBackGuard(
      child: DetailPageShell(
        title: artist.name,
        titleKey: const ValueKey('album_title'),
        onGoBack: onGoBack,
        contentBuilder: (context, scrollController, topPadding) =>
            ArtistDetailContent(
          artist: artist,
          scrollController: scrollController,
          topPadding: topPadding,
        ),
      ),
    );
  }
}

class ArtistDetailContent extends ConsumerStatefulWidget {
  const ArtistDetailContent({
    super.key,
    required this.artist,
    this.showSelectionPanel = true,
    this.hasBottomPanel = false,
    this.scrollController,
    this.topPadding = 0.0,
  });

  final ArtistSummary artist;
  final bool showSelectionPanel;
  final bool hasBottomPanel;
  final ScrollController? scrollController;
  final double topPadding;

  @override
  ConsumerState<ArtistDetailContent> createState() => _ArtistDetailContentState();
}

class _ArtistDetailContentState extends ConsumerState<ArtistDetailContent>
    with
        SelectionStateMixin<ArtistDetailContent, String>,
        SongSelectionMixin<ArtistDetailContent> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.library;

  String? _cachedImagePath;
  StreamSubscription<String>? _imageUpdateSub;

  final AlbumSectionsCache _albumCache = AlbumSectionsCache();

  /// 艺术家内搜索：默认收起，点页头下方的放大镜展开。
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  bool _searchOpen = false;
  String _query = '';

  /// 输入防抖。一位艺术家可能挂着几十张专辑全集，
  /// 每敲一个字都重建一遍分组会掉帧。
  Timer? _queryDebounce;

  @override
  void initState() {
    super.initState();
    _cachedImagePath = widget.artist.cachedImagePath;
    _imageUpdateSub = TheAudioDbArtistService.instance.onArtistImageUpdated
        .listen((queryKey) {
      if (queryKey == widget.artist.queryKey && mounted) {
        _refreshImage();
      }
    });
    _fetchArtistImageIfNeeded();
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    _queryController.dispose();
    _queryFocus.dispose();
    _imageUpdateSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ArtistDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artist.queryKey != widget.artist.queryKey) {
      // 换艺术家时别把上一位的搜索词带过来。
      _queryDebounce?.cancel();
      _queryController.clear();
      _query = '';
      _searchOpen = false;
      _cachedImagePath = widget.artist.cachedImagePath;
      _fetchArtistImageIfNeeded();
    } else if (widget.artist.cachedImagePath != null &&
        widget.artist.cachedImagePath != _cachedImagePath) {
      _cachedImagePath = widget.artist.cachedImagePath;
    }
  }

  /// 当前搜索词命中后的分组，空词时原样返回。
  ///
  /// 命中口径统一走 [filterAlbumSections]：整页都是这位艺术家，
  /// 再按歌手名过滤没有意义，但口径保持一致可以少一套分支。
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

  Future<void> _refreshImage() async {
    final imagePath = await TheAudioDbArtistService.instance
        .fetchAndCacheArtistImage(widget.artist, priority: true);
    if (!mounted) return;
    if (imagePath != null &&
        imagePath.isNotEmpty &&
        imagePath != _cachedImagePath) {
      setState(() {
        _cachedImagePath = imagePath;
      });
      ref.invalidate(artistLibraryProvider);
    }
  }

  Future<void> _fetchArtistImageIfNeeded() async {
    if (_cachedImagePath != null &&
        _cachedImagePath!.isNotEmpty &&
        File(_cachedImagePath!).existsSync()) {
      return;
    }
    final imagePath = await TheAudioDbArtistService.instance
        .fetchAndCacheArtistImage(widget.artist, priority: true);
    if (!mounted) return;
    if (imagePath != null &&
        imagePath.isNotEmpty &&
        imagePath != _cachedImagePath) {
      setState(() {
        _cachedImagePath = imagePath;
      });
      ref.invalidate(artistLibraryProvider);
    }
  }

  PlaybackSource get _artistSource => PlaybackSource(
        type: PlaybackSourceType.artist,
        id: widget.artist.queryKey,
        name: widget.artist.name,
      );

  List<AlbumSummary> _buildAlbums(
    List<AlbumSection> sections,
    List<AlbumSummary>? libraryAlbums,
    String artistName,
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
          (firstSong?.albumArtist ?? firstSong?.artist ?? artistName).trim();
      final expectedId =
          '${section.title.toLowerCase()}::${effectiveArtist.toLowerCase()}';

      final matched = libraryMap[expectedId];
      if (matched != null) return matched;

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
        artist: effectiveArtist.isNotEmpty ? effectiveArtist : artistName,
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
      '[NavTrace] ArtistDetailPage _openAlbumDetail: pushing AlbumDetailPage for album="${album.title}" (id=${album.id})',
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
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    _albumCache.update(widget.artist.songs, l10n.unknownAlbum);
    final sections = _albumCache.sections;
    final displaySongs = _albumCache.allSongs;

    final visibleSections = _visibleSections(sections);
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

    final libraryAlbums = ref.watch(albumLibraryProvider).asData?.value;
    final albumZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.albumZoomScale),
    );
    final albums = _buildAlbums(
      visibleSections,
      libraryAlbums,
      widget.artist.name,
    );

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
                  // 搜索框展开时页头收紧，避免「页头间距 + 搜索框间距」叠成双份。
                  _searchOpen
                      ? (isPortrait ? 10.0 : 8.0)
                      : (isPortrait ? 30.0 : 20.0),
                ),
                child: _ArtistInfo(
                  artist: widget.artist,
                  cachedImagePath: _cachedImagePath,
                  songCountOverride: _query.isEmpty ? null : visibleSongs.length,
                  onPlayAll: () =>
                      audio.playPlaylist(visibleSongs, source: _artistSource),
                  onShufflePlay: () => audio.playPlaylist(
                    List.of(visibleSongs)..shuffle(),
                    source: _artistSource,
                  ),
                  // 与流派 / 年份详情一致：搜索开关挂在操作区行尾，
                  // 竖屏跟「播放全部 / 随机」同一行，横屏跟圆形图标同排。
                  trailingAction: _buildSearchToggle(l10n, theme),
                ),
              ),
            ),
            // 搜索框展开时在页头与专辑分组之间占一行，收起时零高度。
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  _searchOpen ? (isPortrait ? 16.0 : 12.0) : 0,
                ),
                child: _buildSearchField(l10n),
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
                  currentMusicPath: currentMusic?.path,
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
                          source: _artistSource,
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
                  hasPlayingMusic: currentMusic != null,
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

  /// 页头下方的搜索开关。展开时图标高亮，再点一次收起并清空。
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
              padding: const EdgeInsets.only(top: 8),
              child: LibrarySearchField(
                controller: _queryController,
                focusNode: _queryFocus,
                hintText: l10n.searchInArtist,
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
              l10n.noMatchingInArtist,
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
}

class _ArtistInfo extends StatelessWidget {
  const _ArtistInfo({
    required this.artist,
    this.cachedImagePath,
    required this.onPlayAll,
    required this.onShufflePlay,
    this.songCountOverride,
    this.trailingAction,
  });

  final ArtistSummary artist;
  final String? cachedImagePath;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;

  /// 操作区行尾的视图级按钮（搜索开关）。
  final Widget? trailingAction;

  /// 搜索命中时的曲目数。为 null 时用艺术家自身的总曲目数，
  /// 否则会出现「列表只剩 3 首、页头写着 120 首」。
  final int? songCountOverride;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final songCountLabel = l10n.songCount(songCountOverride ?? artist.songCount);
    final playAllLabel = l10n.playAll;
    final shufflePlayLabel = l10n.shufflePlay;

    final metaParts = <String>[
      songCountLabel,
      if ((artist.country?.trim().isNotEmpty ?? false)) artist.country!.trim(),
      if ((artist.areaName?.trim().isNotEmpty ?? false)) artist.areaName!.trim(),
      if (artist.tags.isNotEmpty) artist.tags.take(3).join(', '),
    ];

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    if (isPortrait) {
      final avatarSize = screenWidth < 360 ? 92.0 : 104.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Row 1: 艺术家头像居中占一行
          Center(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ArtistAvatar(
                diameter: avatarSize,
                imagePath: cachedImagePath ?? artist.cachedImagePath,
                imageUrl: artist.imageUrl,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Row 2: 名字占一行
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    artist.name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      fontSize: 24,
                    ),
                  ),
                ),
                RemoteMediaBadge.pillTrailing(
                  songs: artist.songs,
                  title: artist.name,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),

          // 轻量副标题展示
          if (artist.hasDistinctCanonicalName) ...[
            const SizedBox(height: 2),
            Text(
              artist.canonicalName!.trim(),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (artist.disambiguation?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 2),
            Text(
              artist.disambiguation!.trim(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (metaParts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              metaParts.join(' · '),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Row 3: 播放与随机播放操作按钮（与专辑详情页对齐：FilledButton + OutlinedButton 居中 Wrap 排列）
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onPlayAll,
                icon: const Icon(Icons.play_arrow),
                label: Text(playAllLabel),
              ),
              OutlinedButton.icon(
                onPressed: onShufflePlay,
                icon: const Icon(Icons.shuffle),
                label: Text(shufflePlayLabel),
              ),
              ?trailingAction,
            ],
          ),
        ],
      );
    }

    final avatarSize = screenWidth < 420 ? 56.0 : 72.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ArtistAvatar(
          diameter: avatarSize,
          imagePath: cachedImagePath ?? artist.cachedImagePath,
          imageUrl: artist.imageUrl,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      artist.name,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  RemoteMediaBadge.pillTrailing(
                    songs: artist.songs,
                    title: artist.name,
                  ),
                ],
              ),
              if (artist.hasDistinctCanonicalName) ...[
                const SizedBox(height: 2),
                Text(
                  artist.canonicalName!.trim(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (artist.disambiguation?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 2),
                Text(
                  artist.disambiguation!.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                metaParts.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: playAllLabel,
          onPressed: onPlayAll,
          icon: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary,
            ),
            child: Icon(
              Icons.play_arrow,
              size: 22,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: shufflePlayLabel,
          onPressed: onShufflePlay,
          icon: Icon(
            Icons.shuffle,
            size: 22,
            color: theme.colorScheme.primary,
          ),
        ),
        if (trailingAction != null) ...[
          const SizedBox(width: 4),
          trailingAction!,
        ],
      ],
    );
  }
}
