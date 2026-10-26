import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/music_file.dart';
import '../../player/audio/audio_riverpod.dart';
import '../../player/audio/playback_source.dart';
import '../../player/remote/clients/remote_media_library_client.dart';
import '../../player/remote/remote_library_navigation.dart';
import '../../player/remote/remote_server_models.dart';
import '../../utils/remote_context_menu_utils.dart';
import '../../widgets/album_sections.dart'
    show AlbumSection, AlbumSectionSliver, formatDurationClock;
import '../../widgets/collection_detail_header.dart';
import '../../widgets/mini_player_wrapper.dart';
import '../../widgets/remote_artwork_widget.dart';
import 'widgets/remote_library_common_widgets.dart';
import 'widgets/remote_library_toolbar_widgets.dart';

/// 远程流派详情页：竖屏时由流派列表 push 进入。
class RemoteGenreDetailPage extends ConsumerWidget {
  final RemoteServer server;
  final String password;
  final String genreId;
  final String genreName;

  const RemoteGenreDetailPage({
    super.key,
    required this.server,
    required this.password,
    required this.genreId,
    required this.genreName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPlayingMusic = ref.watch(audioCurrentMusicProvider) != null;
    final bottomOffset = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: hasPlayingMusic,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          genreName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: RemoteGenreDetailContent(
        server: server,
        password: password,
        genreId: genreId,
        genreName: genreName,
        bottomOffset: bottomOffset,
      ),
    );
  }
}

/// 拉取并展示某个流派下的内容。
///
/// 横屏分栏的右侧面板与竖屏详情页共用这一个组件，
/// 保证两种布局下的加载态 / 空态 / 播放行为完全一致。
///
/// 数据只有一条来路：把该流派名下的**全部歌曲**分页拉完，再在本地按专辑聚合。
/// 不额外查「流派下的专辑」——服务器对专辑流派和曲目流派是两套口径，
/// 混着用会出现「列了 12 张专辑、点开只有 5 张有歌」的矛盾。
/// 聚合口径下所有数字（歌曲数 / 专辑数 / 每张专辑的曲目）都出自同一份数据，
/// 天然自洽。
///
/// 布局与本地媒体库的流派页对齐：
/// - 竖屏：专辑封面网格，点专辑进详情；
/// - 横屏：一张专辑一个分组，左边封面、右边曲目列表。
class RemoteGenreDetailContent extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final String genreId;
  final String genreName;

  /// 底部额外留白（Mini 播放器 / 底栏避让）。
  final double bottomOffset;

  const RemoteGenreDetailContent({
    super.key,
    required this.server,
    required this.password,
    required this.genreId,
    required this.genreName,
    this.bottomOffset = 0,
  });

  @override
  ConsumerState<RemoteGenreDetailContent> createState() =>
      _RemoteGenreDetailContentState();
}

class _RemoteGenreDetailContentState
    extends ConsumerState<RemoteGenreDetailContent> {
  /// 单页条数。两端都支持 count/offset，Jellyfin 走 StartIndex/Limit。
  static const int _pageSize = 500;

  /// 分页保险丝：最多翻 20 页（1 万首），防止服务端 offset 不推进时死循环。
  static const int _maxPages = 20;

  late final RemoteMediaLibraryClient _client;

  bool _isLoading = true;
  String? _error;

  /// 聚合结果，专辑之间按名称升序。
  List<_GenreAlbum> _albums = const [];

  /// 流派内搜索：默认收起，点标题区行尾的放大镜展开。
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  bool _searchOpen = false;
  String _query = '';

  /// 输入防抖。一个流派上千首歌、上百个专辑分组，
  /// 每个字符都重建一遍整页分组会掉帧。
  Timer? _queryDebounce;

  @override
  void initState() {
    super.initState();
    _client = RemoteMediaLibraryClient.create(
      server: widget.server,
      password: widget.password,
    );
    _load();
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    _queryController.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RemoteGenreDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 分栏布局切换流派时复用同一个组件，需要重新拉取。
    if (oldWidget.genreId != widget.genreId ||
        oldWidget.server.id != widget.server.id) {
      // 分栏布局切换流派一般由外层的 ValueKey 触发整体重建；
      // 这里兜底同 key 复用的场景，避免上一条流派的搜索词跟过来。
      _queryDebounce?.cancel();
      _queryController.clear();
      _query = '';
      _searchOpen = false;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final raws = await _fetchAllSongs();
      if (!mounted) return;

      final albums = _groupSongsIntoAlbums(raws);
      setState(() {
        _albums = albums;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 分页拉取该流派名下的全部歌曲。
  ///
  /// 终止条件：返回空、返回条数不足一页、去重后无新增（服务端 offset 不推进）、
  /// 或触达 [_maxPages]。首屏会按实际返回条数收敛页大小——部分服务端
  /// 会把一页压得比请求的小（例如上限 100），照请求值判断会误判成末页。
  Future<List<Map<String, dynamic>>> _fetchAllSongs() async {
    final raws = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    var offset = 0;
    var pageSize = _pageSize;

    for (var page = 0; page < _maxPages; page++) {
      final batch = await _client.getSongsByGenre(
        widget.genreId,
        count: pageSize,
        offset: offset,
      );
      if (batch.isEmpty) break;
      if (page == 0) pageSize = batch.length;

      var added = 0;
      for (final raw in batch) {
        final id = (raw['id'] ?? '').toString();
        if (id.isNotEmpty && !seenIds.add(id)) continue;
        raws.add(raw);
        added++;
      }

      offset += batch.length;
      // 一点都没新增，说明服务端没按 offset 推进，再翻也是同一页。
      if (added == 0) break;
      if (batch.length < pageSize) break;
    }
    return raws;
  }

  /// 把歌曲按专辑聚合。
  ///
  /// 专辑优先用 `albumId` 分组，缺失时退化为「专辑名 + 专辑艺术家」；
  /// 专辑内按音轨号排序，专辑之间按名称升序，与本地媒体库保持一致。
  List<_GenreAlbum> _groupSongsIntoAlbums(List<Map<String, dynamic>> raws) {
    final l10n = AppLocalizations.of(context)!;
    final order = <String>[];
    final songsByKey = <String, List<MusicFile>>{};
    final metaByKey = <String, _GenreAlbum>{};

    for (final raw in raws) {
      final song = _client.buildMusicFile(raw);
      final albumId = (raw['albumId'] ?? '').toString().trim();
      final albumName = (song.album ?? '').trim();
      final artistName = (song.albumArtist ?? song.artist ?? '').trim();
      final key = albumId.isNotEmpty
          ? 'id:$albumId'
          : 'name:${albumName.toLowerCase()}::${artistName.toLowerCase()}';

      final existing = metaByKey[key];
      if (existing == null) {
        final songs = <MusicFile>[song];
        order.add(key);
        metaByKey[key] = _GenreAlbum(
          id: albumId,
          title: albumName.isNotEmpty ? albumName : l10n.unknownAlbum,
          artist: artistName.isNotEmpty ? artistName : l10n.unknownArtist,
          coverArtId:
              raw['coverArt'] is String ? raw['coverArt'] as String : null,
          songs: songs,
        );
        songsByKey[key] = songs;
      } else {
        songsByKey[key]!.add(song);
      }
    }

    for (final key in order) {
      songsByKey[key]!.sort((a, b) {
        final trackA = a.trackNumber ?? 1 << 20;
        final trackB = b.trackNumber ?? 1 << 20;
        final cmp = trackA.compareTo(trackB);
        if (cmp != 0) return cmp;
        return (a.title ?? a.name)
            .toLowerCase()
            .compareTo((b.title ?? b.name).toLowerCase());
      });
    }

    final albums = [for (final key in order) metaByKey[key]!];
    albums.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return albums;
  }

  /// 当前搜索词命中后的专辑列表，空词时原样返回。
  ///
  /// 命中口径是「专辑名 / 专辑艺术家 / 曲目名 / 曲目艺术家」的并集：
  /// - 命中专辑名或艺术家 → 整张专辑保留全部曲目；
  /// - 只命中某些曲目 → 该专辑只保留命中曲目，分组标题仍是专辑名。
  ///
  /// 只按专辑名过滤会漏掉「搜歌手」；只过滤曲目行则搜专辑名等于没过滤。
  List<_GenreAlbum> _visibleAlbums() {
    final query = _query.toLowerCase();
    if (query.isEmpty) return _albums;

    final result = <_GenreAlbum>[];
    for (final album in _albums) {
      if (album.title.toLowerCase().contains(query) ||
          album.artist.toLowerCase().contains(query)) {
        result.add(album);
        continue;
      }
      final hits = album.songs
          .where((song) => _matchesQuery(song, query))
          .toList(growable: false);
      if (hits.isEmpty) continue;
      result.add(album.withSongs(hits));
    }
    return result;
  }

  bool _matchesQuery(MusicFile song, String query) {
    if ((song.title ?? song.name).toLowerCase().contains(query)) return true;
    if ((song.artist ?? '').toLowerCase().contains(query)) return true;
    return (song.albumArtist ?? '').toLowerCase().contains(query);
  }

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

  /// 展平成一份与界面顺序一致的曲目列表，用于播放全部 / 随机。
  List<MusicFile> _flatten(List<_GenreAlbum> albums) => [
        for (final album in albums) ...album.songs,
      ];

  int _durationMillis(List<_GenreAlbum> albums) {
    var sum = 0;
    for (final album in albums) {
      sum += album.durationMillis;
    }
    return sum;
  }

  Future<void> _play(List<MusicFile> songs, {bool shuffle = false}) async {
    if (songs.isEmpty) return;
    final playlist = shuffle ? (List<MusicFile>.of(songs)..shuffle()) : songs;
    await ref.read(audioServiceProvider).playPlaylist(
          playlist,
          source: PlaybackSource(
            type: PlaybackSourceType.genre,
            id: 'remote-${widget.server.id}-${widget.genreId}',
            name: widget.genreName,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (_isLoading) {
      return RemoteLibraryLoadingView(
        server: widget.server,
        icon: Icons.style_rounded,
      );
    }
    if (_error != null) {
      return RemoteLibraryErrorView(
        error: _error!,
        onRetry: _load,
      );
    }

    // 整个流派确实没内容，沿用统一空态；「搜索没命中」是另一套文案。
    if (_albums.isEmpty) {
      return Center(
        child: Text(
          l10n.emptyList,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final visibleAlbums = _visibleAlbums();
    final visibleSongs = _flatten(visibleAlbums);

    // 三个数字全部来自同一份（过滤后的）聚合结果，任何一处都不会互相打架。
    final durationLabel = formatDurationClock(_durationMillis(visibleAlbums)) ??
        l10n.durationZero;
    final metaLine = '${l10n.songCount(visibleSongs.length)} · '
        '${l10n.albumCount(visibleAlbums.length)} · $durationLabel';

    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hPad = constraints.maxWidth >= 700 ? 24.0 : 16.0;
          final available = constraints.maxWidth - hPad * 2;

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CollectionDetailHeader(
                        title: widget.genreName,
                        metaLine: metaLine,
                        onPlayAll: () => _play(visibleSongs),
                        onShufflePlay: () =>
                            _play(visibleSongs, shuffle: true),
                        trailingAction: _buildSearchToggle(l10n, theme),
                      ),
                      _buildSearchField(l10n),
                    ],
                  ),
                ),
              ),
              if (visibleAlbums.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildNoMatch(l10n, theme),
                )
              else if (isPortrait)
                ..._buildAlbumGridSlivers(
                  context,
                  albums: visibleAlbums,
                  availableWidth: available,
                  horizontalPadding: hPad,
                )
              else
                ..._buildAlbumSectionSlivers(context, visibleAlbums),
            ],
          );
        },
      ),
    );
  }

  /// 标题区行尾的搜索开关。展开时图标高亮，再点一次收起并清空。
  Widget _buildSearchToggle(AppLocalizations l10n, ThemeData theme) {
    return IconButton(
      tooltip: _searchOpen ? l10n.closeSearch : l10n.search,
      onPressed: _toggleSearch,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        _searchOpen ? Icons.search_off_rounded : Icons.search_rounded,
        size: 22,
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
              child: RemoteSearchBar(
                controller: _queryController,
                focusNode: _queryFocus,
                hintText: l10n.searchInGenre,
                searchQuery: _query,
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
              l10n.noMatchingInGenre,
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

  /// 竖屏：专辑封面网格。
  List<Widget> _buildAlbumGridSlivers(
    BuildContext context, {
    required List<_GenreAlbum> albums,
    required double availableWidth,
    required double horizontalPadding,
  }) {
    final columns = (availableWidth / 168).floor().clamp(2, 6);
    const spacing = 14.0;
    final cellWidth = (availableWidth - spacing * (columns - 1)) / columns;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final cellHeight = cellWidth + 54 * textScale;

    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          widget.bottomOffset + 24,
        ),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 18,
            mainAxisExtent: cellHeight,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _RemoteGenreAlbumCard(
              server: widget.server,
              password: widget.password,
              album: albums[index],
              coverSize: cellWidth,
            ),
            childCount: albums.length,
          ),
        ),
      ),
    ];
  }

  /// 横屏：一张专辑一个分组，左封面 + 右曲目。
  ///
  /// 直接复用本地媒体库的 [AlbumSectionSliver]，封面尺寸档位、圆角、阴影、
  /// 内边距、分组标题与曲目行样式随之与本地流派页完全一致，不再各写一份。
  /// 曲目来自聚合时的同一份数据，不额外请求专辑接口。
  List<Widget> _buildAlbumSectionSlivers(
    BuildContext context,
    List<_GenreAlbum> albums,
  ) {
    final currentPath = ref.watch(audioCurrentMusicProvider)?.path;
    final slivers = <Widget>[];
    var startIndex = 0;

    for (var i = 0; i < albums.length; i++) {
      final album = albums[i];
      if (i > 0) {
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 36)));
      }

      final section = AlbumSection(
        title: album.title,
        songs: album.songs,
        representativeSong: album.representativeSong,
        totalDurationMillis: album.durationMillis,
        startIndex: startIndex,
        artist: album.artist.isNotEmpty ? album.artist : null,
      );
      startIndex += album.songs.length;

      slivers.add(
        AlbumSectionSliver(
          key: ValueKey('genre-album-${album.id}-${album.title}'),
          section: section,
          currentMusicPath: currentPath,
          onSongTap: (_, songIndex) =>
              _playAlbum(album, initialIndex: songIndex),
          // 远程流派页暂不支持多选，长按先留空。
          onSongLongPress: (_, _) {},
          onOpenAlbum: album.canOpen ? () => _openAlbum(context, album) : null,
          // 整页都是远程内容，封面上的云朵角标没有区分意义，去掉。
          showRemoteBadge: false,
          playbackSourceBuilder: (_) => PlaybackSource(
            type: PlaybackSourceType.genre,
            id: 'remote-${widget.server.id}-${widget.genreId}-${album.id}',
            name: album.title,
          ),
        ),
      );
    }

    slivers.add(
      SliverToBoxAdapter(
        child: SizedBox(height: widget.bottomOffset + 24),
      ),
    );
    return slivers;
  }

  void _openAlbum(BuildContext context, _GenreAlbum album) {
    if (!album.canOpen) return;
    RemoteLibraryNavUtils.openAlbum(
      context,
      ref,
      server: widget.server,
      password: widget.password,
      albumId: album.id,
      albumName: album.title,
      artistName: album.artist,
      coverArtId: album.coverArtId,
    );
  }

  /// 播放整张专辑并从 [initialIndex] 开始。
  ///
  /// 分组上的「播放全部 / 随机」由 [AlbumSectionSliver] 内部处理，
  /// 这里只服务曲目行的单曲点击。
  void _playAlbum(_GenreAlbum album, {int initialIndex = 0}) {
    if (album.songs.isEmpty) return;
    ref.read(audioServiceProvider).playPlaylist(
          album.songs,
          initialIndex: initialIndex,
          source: PlaybackSource(
            type: PlaybackSourceType.genre,
            id: 'remote-${widget.server.id}-${widget.genreId}-${album.id}',
            name: album.title,
          ),
        );
  }
}

/// 聚合出来的专辑：曲目与元信息绑在一起，避免再按 id 反查。
class _GenreAlbum {
  /// 真实专辑 id；歌曲没有 albumId 时为空串（此时不可跳转专辑详情）。
  final String id;
  final String title;
  final String artist;
  final String? coverArtId;
  final List<MusicFile> songs;

  const _GenreAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.coverArtId,
    required this.songs,
  });

  /// 流派内搜索只命中部分曲目时，用命中集合替换曲目，元信息保持不变。
  ///
  /// [representativeSong] 是 getter，会基于新曲目重新挑封面，
  /// 所以搜索不会把分组封面换成别的东西（只要原代表曲还在结果里）。
  _GenreAlbum withSongs(List<MusicFile> songs) => _GenreAlbum(
        id: id,
        title: title,
        artist: artist,
        coverArtId: coverArtId,
        songs: songs,
      );

  bool get canOpen => id.isNotEmpty;

  /// 用于取封面的代表曲目，优先选带封面的歌。
  ///
  /// 复用的 [AlbumSectionSliver] 靠 `SongThumbnail.fromSong` 取图，
  /// 远程歌曲的 `artworkPath` 是 `subsonic-cover://` / `jellyfin-cover://` 形式，
  /// 由 `RemoteMediaResolver` 解析成真实 URL。
  MusicFile get representativeSong {
    for (final song in songs) {
      final hasArtwork = (song.artworkPath?.isNotEmpty ?? false) ||
          (song.artworkBytes?.isNotEmpty ?? false) ||
          (song.thumbnailPath?.isNotEmpty ?? false);
      if (hasArtwork) return song;
    }
    return songs.first;
  }

  int get durationMillis =>
      songs.fold<int>(0, (sum, song) => sum + (song.durationMillis ?? 0));
}

/// 竖屏网格里的单个专辑卡片。
class _RemoteGenreAlbumCard extends ConsumerWidget {
  final RemoteServer server;
  final String password;
  final _GenreAlbum album;
  final double coverSize;

  const _RemoteGenreAlbumCard({
    required this.server,
    required this.password,
    required this.album,
    required this.coverSize,
  });

  void _openAlbum(BuildContext context, WidgetRef ref) {
    if (!album.canOpen) return;
    RemoteLibraryNavUtils.openAlbum(
      context,
      ref,
      server: server,
      password: password,
      albumId: album.id,
      albumName: album.title,
      artistName: album.artist,
      coverArtId: album.coverArtId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final subtitle = album.artist.isNotEmpty
        ? '${album.artist} · ${l10n.trackCountShort(album.songs.length)}'
        : l10n.trackCountShort(album.songs.length);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: album.canOpen ? () => _openAlbum(context, ref) : null,
        onSecondaryTapDown: album.canOpen
            ? (details) {
                showRemoteAlbumContextMenu(
                  context: context,
                  globalPosition: details.globalPosition,
                  ref: ref,
                  server: server,
                  password: password,
                  albumId: album.id,
                  albumTitle: album.title,
                  artistName: album.artist,
                  coverArtId: album.coverArtId,
                  onViewDetails: () => _openAlbum(context, ref),
                );
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            RemoteArtworkWidget(
              server: server,
              password: password,
              coverArtId: album.coverArtId,
              size: coverSize,
              width: coverSize,
              height: coverSize,
              borderRadius: BorderRadius.circular(10),
              fallbackIcon: Icons.album_rounded,
            ),
            const SizedBox(height: 8),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
