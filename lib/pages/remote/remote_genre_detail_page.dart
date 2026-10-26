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
import '../../widgets/album_sections.dart' show formatDurationClock;
import '../../widgets/collection_detail_header.dart';
import '../../widgets/mini_player_wrapper.dart';
import '../../widgets/remote_artwork_widget.dart';
import 'widgets/remote_library_common_widgets.dart';

/// 远程流派详情页：竖屏时由流派列表 push 进入。
class RemoteGenreDetailPage extends ConsumerWidget {
  final RemoteServer server;
  final String password;
  final String genreId;
  final String genreName;

  /// 流派列表里服务器给出的统计，用于让详情页与左栏数字一致。
  final int? songCount;
  final int? albumCount;

  const RemoteGenreDetailPage({
    super.key,
    required this.server,
    required this.password,
    required this.genreId,
    required this.genreName,
    this.songCount,
    this.albumCount,
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
        songCount: songCount,
        albumCount: albumCount,
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
/// 布局与本地媒体库的流派页对齐：
/// - 竖屏：专辑封面网格，点专辑进详情；
/// - 横屏：一张专辑一个分组，左边封面、右边曲目列表。
///
/// 专辑列表来自服务器（Jellyfin `/Items?IncludeItemTypes=MusicAlbum&GenreIds=`
/// / Subsonic `getAlbumList2?type=byGenre`），不能由流派歌曲聚合——服务器统计的
/// 「专辑数」按专辑实体的流派计算，而曲目的流派标签可能整张缺失，两者会打架。
class RemoteGenreDetailContent extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final String genreId;
  final String genreName;

  /// 列表页已经拿到的统计值；传了就优先用它显示，避免与左栏数字不一致。
  final int? songCount;
  final int? albumCount;

  /// 底部额外留白（Mini 播放器 / 底栏避让）。
  final double bottomOffset;

  const RemoteGenreDetailContent({
    super.key,
    required this.server,
    required this.password,
    required this.genreId,
    required this.genreName,
    this.songCount,
    this.albumCount,
    this.bottomOffset = 0,
  });

  @override
  ConsumerState<RemoteGenreDetailContent> createState() =>
      _RemoteGenreDetailContentState();
}

class _RemoteGenreDetailContentState
    extends ConsumerState<RemoteGenreDetailContent> {
  late final RemoteMediaLibraryClient _client;

  bool _isLoading = true;
  String? _error;

  /// 专辑（服务器返回的归一化 map：id/name/title/artist/songCount/coverArt/year）。
  List<Map<String, dynamic>> _albums = const [];

  /// 流派下的歌曲，仅用于「播放全部 / 随机播放」与总时长。
  List<MusicFile> _songs = const [];

  /// 横屏分组视图中各专辑的曲目缓存，避免来回滚动重复请求。
  final Map<String, List<MusicFile>> _trackCache = {};

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
  void didUpdateWidget(covariant RemoteGenreDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 分栏布局切换流派时复用同一个组件，需要重新拉取。
    if (oldWidget.genreId != widget.genreId ||
        oldWidget.server.id != widget.server.id) {
      _trackCache.clear();
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        _client.getAlbumsByGenre(
          genreId: widget.genreId,
          genreName: widget.genreName,
          count: 500,
        ),
        _client.getSongsByGenre(widget.genreId, count: 500),
      ]);
      if (!mounted) return;

      final songRaws = results[1];
      final songs = songRaws.map(_client.buildMusicFile).toList(growable: false);
      var albums = results[0];

      // 兜底：个别服务端不认 byGenre（返回空）时，退回按歌曲聚合，
      // 至少保证流派能点开看到专辑，而不是空白页。
      if (albums.isEmpty && songRaws.isNotEmpty) {
        final l10n = AppLocalizations.of(context)!;
        albums = _groupSongsIntoAlbums(
          songRaws,
          unknownAlbum: l10n.unknownAlbum,
          unknownArtist: l10n.unknownArtist,
        );
      }

      setState(() {
        _albums = albums;
        _songs = songs;
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

  /// 兜底聚合：把歌曲按专辑归并成与 [getAlbumsByGenre] 相同形状的 map。
  ///
  /// 专辑优先用 `albumId` 分组，缺失时退化为「专辑名 + 专辑艺术家」；
  /// 专辑内按音轨号排序，专辑之间按名称升序，与本地媒体库保持一致。
  List<Map<String, dynamic>> _groupSongsIntoAlbums(
    List<Map<String, dynamic>> raws, {
    required String unknownAlbum,
    required String unknownArtist,
  }) {
    final groups = <String, Map<String, dynamic>>{};
    final groupedSongs = <String, List<MusicFile>>{};

    for (final raw in raws) {
      final song = _client.buildMusicFile(raw);
      final albumId = (raw['albumId'] ?? raw['AlbumId'] ?? '').toString();
      final albumName = (song.album ?? '').trim();
      final artistName = (song.albumArtist ?? song.artist ?? '').trim();
      final key = albumId.isNotEmpty
          ? 'id:$albumId'
          : 'name:${albumName.toLowerCase()}::${artistName.toLowerCase()}';

      final existing = groups[key];
      if (existing == null) {
        groups[key] = {
          'id': albumId.isNotEmpty ? albumId : key,
          'name': albumName.isNotEmpty ? albumName : unknownAlbum,
          'title': albumName.isNotEmpty ? albumName : unknownAlbum,
          'artist': artistName.isNotEmpty ? artistName : unknownArtist,
          'coverArt': raw['coverArt'] is String ? raw['coverArt'] : null,
          'year': song.year,
        };
        groupedSongs[key] = <MusicFile>[song];
      } else {
        groupedSongs[key]!.add(song);
      }
    }

    for (final entry in groupedSongs.entries) {
      entry.value.sort((a, b) {
        final trackA = a.trackNumber ?? 1 << 20;
        final trackB = b.trackNumber ?? 1 << 20;
        final cmp = trackA.compareTo(trackB);
        if (cmp != 0) return cmp;
        return (a.title ?? a.name)
            .toLowerCase()
            .compareTo((b.title ?? b.name).toLowerCase());
      });
      groups[entry.key]!['songCount'] = entry.value.length;
      _trackCache[groups[entry.key]!['id'] as String] = entry.value;
    }

    final albums = groups.values.toList();
    albums.sort(
      (a, b) => (a['title'] as String? ?? '')
          .toLowerCase()
          .compareTo((b['title'] as String? ?? '').toLowerCase()),
    );
    return albums;
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

    // 优先用列表页的服务器统计，保证和左栏的「N 首 · M 张专辑」完全一致；
    // 单独进入（无统计）时才退回本地计数。
    final songCount = widget.songCount ?? _songs.length;
    final albumCount = widget.albumCount ?? _albums.length;
    final durationLabel =
        formatDurationClock(_totalDurationMillis) ?? l10n.durationZero;
    final metaLine =
        '${l10n.songCount(songCount)} · ${l10n.albumCount(albumCount)} · $durationLabel';

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
                  padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 18),
                  child: CollectionDetailHeader(
                    title: widget.genreName,
                    metaLine: metaLine,
                    onPlayAll: () => _play(_songs),
                    onShufflePlay: () => _play(_songs, shuffle: true),
                  ),
                ),
              ),
              if (isPortrait)
                ..._buildAlbumGridSlivers(
                  context,
                  availableWidth: available,
                  horizontalPadding: hPad,
                )
              else
                ..._buildAlbumSectionSlivers(
                  context,
                  availableWidth: available,
                  horizontalPadding: hPad,
                  coverSize: available >= 760 ? 170 : 132,
                ),
            ],
          );
        },
      ),
    );
  }

  /// 竖屏：专辑封面网格。
  List<Widget> _buildAlbumGridSlivers(
    BuildContext context, {
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
              album: _albums[index],
              coverSize: cellWidth,
            ),
            childCount: _albums.length,
          ),
        ),
      ),
    ];
  }

  /// 横屏：一张专辑一个分组，左封面 + 右曲目（与本地流派页横屏一致）。
  List<Widget> _buildAlbumSectionSlivers(
    BuildContext context, {
    required double availableWidth,
    required double horizontalPadding,
    required double coverSize,
  }) {
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          widget.bottomOffset + 24,
        ),
        sliver: SliverList.builder(
          itemCount: _albums.length,
          itemBuilder: (context, index) {
            final album = _albums[index];
            final albumId = album['id'] as String? ?? '';
            return Padding(
              padding: EdgeInsets.only(bottom: index == _albums.length - 1 ? 0 : 36),
              child: _RemoteGenreAlbumSection(
                key: ValueKey('genre-album-$albumId'),
                client: _client,
                server: widget.server,
                password: widget.password,
                album: album,
                genreId: widget.genreId,
                genreName: widget.genreName,
                coverSize: coverSize,
                cachedSongs: _trackCache[albumId],
                onSongsLoaded: (songs) {
                  if (songs.isNotEmpty) _trackCache[albumId] = songs;
                },
              ),
            );
          },
        ),
      ),
    ];
  }

  int get _totalDurationMillis {
    var sum = 0;
    for (final song in _songs) {
      sum += song.durationMillis ?? 0;
    }
    return sum;
  }
}

/// 竖屏网格里的单个专辑卡片。
class _RemoteGenreAlbumCard extends ConsumerWidget {
  final RemoteServer server;
  final String password;
  final Map<String, dynamic> album;
  final double coverSize;

  const _RemoteGenreAlbumCard({
    required this.server,
    required this.password,
    required this.album,
    required this.coverSize,
  });

  String get _id => album['id'] as String? ?? '';
  String get _title =>
      album['title'] as String? ?? album['name'] as String? ?? '';
  String get _artist => album['artist'] as String? ?? '';
  String? get _coverArtId => album['coverArt'] as String?;

  void _openAlbum(BuildContext context, WidgetRef ref) {
    RemoteLibraryNavUtils.openAlbum(
      context,
      ref,
      server: server,
      password: password,
      albumId: _id,
      albumName: _title,
      artistName: _artist,
      coverArtId: _coverArtId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final title = _title.isNotEmpty ? _title : l10n.unknownAlbum;
    final artist = _artist.isNotEmpty ? _artist : l10n.unknownArtist;
    final songCount = (album['songCount'] as num?)?.toInt() ?? 0;
    final subtitle = songCount > 0
        ? '$artist · ${l10n.trackCountShort(songCount)}'
        : artist;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openAlbum(context, ref),
        onSecondaryTapDown: (details) {
          showRemoteAlbumContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            ref: ref,
            server: server,
            password: password,
            albumId: _id,
            albumTitle: title,
            artistName: artist,
            coverArtId: _coverArtId,
            onViewDetails: () => _openAlbum(context, ref),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            RemoteArtworkWidget(
              server: server,
              password: password,
              coverArtId: _coverArtId,
              size: coverSize,
              width: coverSize,
              height: coverSize,
              borderRadius: BorderRadius.circular(10),
              fallbackIcon: Icons.album_rounded,
            ),
            const SizedBox(height: 8),
            Text(
              title,
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

/// 横屏分组：左封面 + 右曲目列表，曲目按需向服务器拉取（带缓存）。
class _RemoteGenreAlbumSection extends ConsumerStatefulWidget {
  final RemoteMediaLibraryClient client;
  final RemoteServer server;
  final String password;
  final Map<String, dynamic> album;
  final String genreId;
  final String genreName;
  final double coverSize;
  final List<MusicFile>? cachedSongs;
  final void Function(List<MusicFile> songs) onSongsLoaded;

  const _RemoteGenreAlbumSection({
    super.key,
    required this.client,
    required this.server,
    required this.password,
    required this.album,
    required this.genreId,
    required this.genreName,
    required this.coverSize,
    required this.cachedSongs,
    required this.onSongsLoaded,
  });

  @override
  ConsumerState<_RemoteGenreAlbumSection> createState() =>
      _RemoteGenreAlbumSectionState();
}

class _RemoteGenreAlbumSectionState
    extends ConsumerState<_RemoteGenreAlbumSection> {
  bool _isLoading = false;
  String? _error;
  List<MusicFile> _songs = const [];

  String get _albumId => widget.album['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    final cached = widget.cachedSongs;
    if (cached != null) {
      _songs = cached;
    } else {
      _loadTracks();
    }
  }

  Future<void> _loadTracks() async {
    if (_albumId.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final raws = await widget.client.getAlbumSongs(_albumId);
      final songs =
          raws.map(widget.client.buildMusicFile).toList(growable: false);
      widget.onSongsLoaded(songs);
      if (!mounted) return;
      setState(() {
        _songs = songs;
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

  void _playFrom(int index, {bool shuffle = false}) {
    if (_songs.isEmpty) return;
    final playlist =
        shuffle ? (List<MusicFile>.of(_songs)..shuffle()) : _songs;
    ref.read(audioServiceProvider).playPlaylist(
          playlist,
          initialIndex: shuffle ? 0 : index,
          source: PlaybackSource(
            type: PlaybackSourceType.genre,
            id: 'remote-${widget.server.id}-${widget.genreId}-$_albumId',
            name: (widget.album['title'] as String?) ?? widget.genreName,
          ),
        );
  }

  void _openAlbum() {
    RemoteLibraryNavUtils.openAlbum(
      context,
      ref,
      server: widget.server,
      password: widget.password,
      albumId: _albumId,
      albumName: widget.album['title'] as String? ??
          widget.album['name'] as String? ??
          '',
      artistName: widget.album['artist'] as String?,
      coverArtId: widget.album['coverArt'] as String?,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final currentPath = ref.watch(audioCurrentMusicProvider)?.path;

    final title = (widget.album['title'] as String?)?.isNotEmpty == true
        ? widget.album['title'] as String
        : ((widget.album['name'] as String?)?.isNotEmpty == true
            ? widget.album['name'] as String
            : l10n.unknownAlbum);
    final artist = (widget.album['artist'] as String?)?.isNotEmpty == true
        ? widget.album['artist'] as String
        : l10n.unknownArtist;
    final serverSongCount = (widget.album['songCount'] as num?)?.toInt() ?? 0;
    final shownSongCount =
        _songs.isNotEmpty ? _songs.length : serverSongCount;
    final durationLabel = _songs.isEmpty
        ? null
        : formatDurationClock(
            _songs.fold<int>(0, (sum, s) => sum + (s.durationMillis ?? 0)),
          );
    final subtitle = [
      l10n.songCount(shownSongCount),
      ?durationLabel,
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _openAlbum,
          child: RemoteArtworkWidget(
            server: widget.server,
            password: widget.password,
            coverArtId: widget.album['coverArt'] as String?,
            size: widget.coverSize,
            width: widget.coverSize,
            height: widget.coverSize,
            borderRadius: BorderRadius.circular(10),
            fallbackIcon: Icons.album_rounded,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _openAlbum,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$artist · $subtitle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.playAll,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    onPressed:
                        _songs.isEmpty ? null : () => _playFrom(0),
                  ),
                  IconButton(
                    tooltip: l10n.shuffle,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    onPressed: _songs.isEmpty
                        ? null
                        : () => _playFrom(0, shuffle: true),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextButton(
                    onPressed: _loadTracks,
                    child: Text(l10n.retry),
                  ),
                )
              else if (_songs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    l10n.emptyList,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (int i = 0; i < _songs.length; i++)
                  _RemoteGenreSongRow(
                    song: _songs[i],
                    index: i,
                    isCurrent:
                        currentPath != null && currentPath == _songs[i].path,
                    onTap: () => _playFrom(i),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 横屏分组内的单首曲目。
class _RemoteGenreSongRow extends StatelessWidget {
  final MusicFile song;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;

  const _RemoteGenreSongRow({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = song.title ?? song.name;
    final artist = song.artist;

    return Material(
      color: isCurrent
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${index + 1}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: isCurrent ? FontWeight.bold : null,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.w500,
                        color: isCurrent ? theme.colorScheme.primary : null,
                      ),
                    ),
                    if (artist != null && artist.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatDurationClock(song.durationMillis) ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
