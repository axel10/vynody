import 'dart:async';
import 'dart:convert';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';
import '../../player/metadata/metadata_database.dart';
import '../../models/music_file.dart';
import '../../player/audio/audio_riverpod.dart';
import '../../player/audio/playback_source.dart';
import '../../player/remote/remote_server_models.dart';
import '../../player/remote/remote_server_riverpod.dart';
import '../../player/remote/clients/remote_media_library_client.dart';
import '../../player/settings/settings_service.dart';
import '../../widgets/album_sections.dart';
import '../../widgets/app_top_nav_bar.dart';
import '../../widgets/draggable_remote_album_item.dart';
import '../../widgets/folder_layout_utils.dart';
import '../../widgets/remote_artwork_widget.dart';
import '../../l10n/app_localizations.dart';
import '../../player/remote/services/remote_download_service.dart';
import '../../player/remote/remote_library_navigation.dart';
import '../../utils/remote_context_menu_utils.dart';
import '../../utils/remote_download_feedback.dart';
import '../../widgets/library_selection_scope.dart';
import 'widgets/remote_library_selection_actions.dart';
import 'widgets/remote_song_selection_panel.dart';
import 'widgets/remote_library_toolbar_widgets.dart';
import '../../widgets/detail_content_scaffold.dart';
import '../../widgets/remote_page_shell.dart';

class RemoteArtistDetailPage extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final String artistId;
  final String artistName;
  final String? coverArtId;
  final int? albumCount;
  final VoidCallback? onGoBack;

  const RemoteArtistDetailPage({
    super.key,
    required this.server,
    required this.password,
    required this.artistId,
    required this.artistName,
    this.coverArtId,
    this.albumCount,
    this.onGoBack,
  });

  @override
  ConsumerState<RemoteArtistDetailPage> createState() =>
      _RemoteArtistDetailPageState();
}

class _RemoteArtistDetailPageState
    extends ConsumerState<RemoteArtistDetailPage> {
  late final ScrollController _scrollController;
  final ValueNotifier<bool> _isHeaderVisible = ValueNotifier<bool>(true);
  final ValueNotifier<double> _scrollProgress = ValueNotifier<double>(0.0);
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final isVisible = offset < 140.0;
    final progress = (offset / 100.0).clamp(0.0, 1.0);
    _scrollProgress.value = progress;
    if (isVisible != _isHeaderVisible.value) {
      _isHeaderVisible.value = isVisible;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _isHeaderVisible.dispose();
    _scrollProgress.dispose();
    super.dispose();
  }

  static double getBarHeight(BuildContext context) =>
      AppTopNavBar.getBarHeight(context);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final double barHeight = getBarHeight(context);

    return RemotePageShell(
      // 远程库已是一级 tab，外层不再 `Padding(left: railWidth)`：
      // 横屏时让位必须落在页面内部，否则整页被 Rail 压住左边缘。
      avoidRail: true,
      enableFloatingCapsule: true,
      contentBuilder: (context) => RemoteArtistDetailContent(
        server: widget.server,
        password: widget.password,
        artistId: widget.artistId,
        artistName: widget.artistName,
        coverArtId: widget.coverArtId,
        albumCount: widget.albumCount,
        scrollController: _scrollController,
        topPadding: barHeight + 8,
        onLoadingStateChanged: (isLoading, hasError) {
          if (_isLoading != isLoading || _hasError != hasError) {
            setState(() {
              _isLoading = isLoading;
              _hasError = hasError;
            });
          }
        },
      ),
      navBarBuilder: (context, isHeaderVisible, isPastTop) => AppTopNavBar(
        title: widget.artistName,
        parentTitle: l10n.artists,
        titleKey: const ValueKey('remote_artist_title'),
        isFloatingCapsule: isPastTop,
        contentMaxWidth: kFolderPageMaxWidth,
        onBack: widget.onGoBack ?? () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class RemoteArtistDetailContent extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final String artistId;
  final String artistName;
  final String? coverArtId;
  final int? albumCount;
  final ScrollController? scrollController;
  final double topPadding;
  final void Function(bool isLoading, bool hasError)? onLoadingStateChanged;

  const RemoteArtistDetailContent({
    super.key,
    required this.server,
    required this.password,
    required this.artistId,
    required this.artistName,
    this.coverArtId,
    this.albumCount,
    this.scrollController,
    this.topPadding = 0.0,
    this.onLoadingStateChanged,
  });

  @override
  ConsumerState<RemoteArtistDetailContent> createState() =>
      _RemoteArtistDetailContentState();
}

class _RemoteAlbumSectionData {
  final String id;
  final String name;
  final String artist;
  final String? coverArt;
  final int? year;
  final int? songCount;
  final int? duration;
  final List<MusicFile> songs;
  final List<Map<String, dynamic>> rawSongs;

  _RemoteAlbumSectionData({
    required this.id,
    required this.name,
    required this.artist,
    this.coverArt,
    this.year,
    this.songCount,
    this.duration,
    required this.songs,
    this.rawSongs = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'artist': artist,
    'coverArt': coverArt,
    'year': year,
    'songCount': songCount,
    'duration': duration,
    'rawSongs': rawSongs,
  };

  /// 艺术家内搜索只命中部分曲目时，用命中集合替换曲目，元信息保持不变。
  ///
  /// `songCount` 同步收缩成命中条数：竖屏网格卡片直接读它，
  /// 不改会出现「显示整张 12 首、点开只有 3 首」。
  _RemoteAlbumSectionData withSongs(List<MusicFile> songs) =>
      _RemoteAlbumSectionData(
        id: id,
        name: name,
        artist: artist,
        coverArt: coverArt,
        year: year,
        songCount: songs.length,
        duration: duration,
        songs: songs,
        rawSongs: rawSongs,
      );

  static _RemoteAlbumSectionData fromJson(
    Map<String, dynamic> json,
    RemoteMediaLibraryClient client,
  ) {
    final rawList = (json['rawSongs'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final songs = rawList.map(client.buildMusicFile).toList();
    return _RemoteAlbumSectionData(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      coverArt: json['coverArt'] as String?,
      year: json['year'] as int?,
      songCount: json['songCount'] as int? ?? songs.length,
      duration: json['duration'] as int?,
      songs: songs,
      rawSongs: rawList,
    );
  }
}

class _RemoteArtistDetailContentState
    extends ConsumerState<RemoteArtistDetailContent>
    with
        SelectionStateMixin<RemoteArtistDetailContent, String>,
        SongSelectionMixin<RemoteArtistDetailContent> {
  bool _isLoading = true;
  String? _error;
  List<_RemoteAlbumSectionData> _albumSections = [];
  List<MusicFile> _allSongs = [];
  Map<String, dynamic>? _artistInfo;
  bool _isStarred = false;
  String _resolvedArtistId = '';
  bool _isRevalidating = false;

  /// 艺术家内搜索：默认收起，点详情区顶部的放大镜展开。
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  bool _searchOpen = false;
  String _query = '';

  /// 输入防抖。首页一次会展开这位艺术家的全部专辑全集，
  /// 每个字符都重建一遍会掉帧。
  Timer? _queryDebounce;

  @override
  void initState() {
    super.initState();
    _resolvedArtistId = widget.artistId;
    _loadArtistData();
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    _queryController.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RemoteArtistDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artistId != widget.artistId ||
        oldWidget.server.id != widget.server.id ||
        oldWidget.artistName != widget.artistName) {
      // 换艺术家时别把上一位的搜索词带过来。
      _queryDebounce?.cancel();
      _queryController.clear();
      _query = '';
      _searchOpen = false;
      _resolvedArtistId = widget.artistId;
      _loadArtistData();
    }
  }

  Future<void> _loadArtistData({bool forceRefresh = false}) async {
    final targetId = widget.artistId;
    final client = RemoteMediaLibraryClient.create(
      server: widget.server,
      password: widget.password,
    );

    // 1. Try reading from SQLite cache first for instant UI (SWR)
    if (!forceRefresh && _albumSections.isEmpty) {
      try {
        final cache = await MetadataDatabase().getRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'artist_detail_$targetId',
        );
        if (cache != null && mounted) {
          final data = jsonDecode(cache.dataJson) as Map<String, dynamic>;
          final rawSections = (data['sections'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              [];
          final parsedSections = rawSections
              .map((s) => _RemoteAlbumSectionData.fromJson(s, client))
              .toList();

          final accumulatedSongs = <MusicFile>[];
          for (final sec in parsedSections) {
            accumulatedSongs.addAll(sec.songs);
          }

          if (parsedSections.isNotEmpty || accumulatedSongs.isNotEmpty) {
            setState(() {
              _albumSections = parsedSections;
              _allSongs = accumulatedSongs;
              _artistInfo = data['artistInfo'] as Map<String, dynamic>?;
              _isStarred = data['isStarred'] == true;
              _isLoading = false;
              _error = null;
            });
            widget.onLoadingStateChanged?.call(false, false);
            // Revalidate in background
            _revalidateArtistData(client);
            return;
          }
        }
      } catch (_) {}
    }

    if (!forceRefresh && _albumSections.isNotEmpty) {
      _revalidateArtistData(client);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    widget.onLoadingStateChanged?.call(true, false);

    await _fetchAndApplyArtistData(client, isBackground: false);
  }

  Future<void> _revalidateArtistData(RemoteMediaLibraryClient client) async {
    if (_isRevalidating || !mounted) return;
    _isRevalidating = true;
    try {
      await _fetchAndApplyArtistData(client, isBackground: true);
    } finally {
      _isRevalidating = false;
    }
  }

  Future<void> _fetchAndApplyArtistData(
    RemoteMediaLibraryClient client, {
    required bool isBackground,
  }) async {
    try {
      final artistMap = await client.getArtist(
        widget.artistId,
        artistName: widget.artistName,
      );
      if (artistMap == null) {
        if (!mounted || isBackground) return;
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _error = l10n.artistNotFound;
          _isLoading = false;
        });
        widget.onLoadingStateChanged?.call(false, true);
        return;
      }

      final resolvedId = (artistMap['id'] as String? ?? '').trim();
      if (resolvedId.isNotEmpty) {
        _resolvedArtistId = resolvedId;
      }

      // Fetch artist bio / info if available
      final infoTargetId =
          _resolvedArtistId.isNotEmpty ? _resolvedArtistId : widget.artistId;
      if (infoTargetId.isNotEmpty) {
        client.getArtistInfo(infoTargetId).then((info) {
          if (mounted && info != null) {
            setState(() {
              _artistInfo = info;
            });
          }
        }).catchError((_) {});
      }

      // Parse albums
      final dynamic rawAlbums = artistMap['album'];
      final List<Map<String, dynamic>> albumList = [];
      if (rawAlbums is List) {
        albumList.addAll(rawAlbums.whereType<Map<String, dynamic>>());
      } else if (rawAlbums is Map<String, dynamic>) {
        albumList.add(rawAlbums);
      }

      // If artist has songs directly (some Subsonic servers return directory format)
      final dynamic directSongs = artistMap['song'];
      final List<Map<String, dynamic>> directRawSongs = [];
      final List<MusicFile> songsFromArtist = [];
      if (directSongs is List) {
        for (final s in directSongs) {
          if (s is Map<String, dynamic>) {
            directRawSongs.add(s);
            songsFromArtist.add(
              client.buildMusicFile(s),
            );
          }
        }
      }

      // Load songs for each album
      final List<_RemoteAlbumSectionData> sections = [];
      final List<MusicFile> accumulatedSongs = [];

      if (albumList.isNotEmpty) {
        // Load details for albums concurrently
        final albumFutures = albumList.map((albumMeta) async {
          final albumId = albumMeta['id'] as String? ?? '';
          final title = albumMeta['title'] as String? ??
              albumMeta['name'] as String? ??
              '';
          final artist = albumMeta['artist'] as String? ?? widget.artistName;
          final coverArt = albumMeta['coverArt'] as String?;
          final year = albumMeta['year'] as int?;
          final songCount = albumMeta['songCount'] as int?;
          final duration = albumMeta['duration'] as int?;

          List<MusicFile> albumTracks = [];
          List<Map<String, dynamic>> rawSongData = [];
          try {
            final fullAlbum = await client.getAlbum(albumId);
            final songData = fullAlbum?['song'] as List?;
            if (songData != null) {
              for (final s in songData) {
                if (s is Map<String, dynamic>) {
                  rawSongData.add(s);
                  albumTracks.add(
                    client.buildMusicFile(s),
                  );
                }
              }
            }
          } catch (_) {}

          return _RemoteAlbumSectionData(
            id: albumId,
            name: title,
            artist: artist,
            coverArt: coverArt,
            year: year,
            songCount: songCount ?? albumTracks.length,
            duration: duration,
            songs: albumTracks,
            rawSongs: rawSongData,
          );
        }).toList();

        final loadedSections = await Future.wait(albumFutures);
        for (final sec in loadedSections) {
          sections.add(sec);
          accumulatedSongs.addAll(sec.songs);
        }
      } else if (songsFromArtist.isNotEmpty) {
        // Group songs by album if albums array wasn't provided directly
        final Map<String, List<MusicFile>> byAlbum = {};
        final Map<String, List<Map<String, dynamic>>> byAlbumRaw = {};
        for (int i = 0; i < songsFromArtist.length; i++) {
          final song = songsFromArtist[i];
          final raw = directRawSongs[i];
          final albumName = song.album ?? 'Singles';
          byAlbum.putIfAbsent(albumName, () => []).add(song);
          byAlbumRaw.putIfAbsent(albumName, () => []).add(raw);
        }
        byAlbum.forEach((albumName, sList) {
          final rawList = byAlbumRaw[albumName] ?? [];
          sections.add(
            _RemoteAlbumSectionData(
              id: widget.artistId,
              name: albumName,
              artist: widget.artistName,
              coverArt: widget.coverArtId,
              songCount: sList.length,
              songs: sList,
              rawSongs: rawList,
            ),
          );
          accumulatedSongs.addAll(sList);
        });
      }

      final effectiveId =
          _resolvedArtistId.isNotEmpty ? _resolvedArtistId : widget.artistId;
      final sessionStarred =
          ref.read(activeRemoteSessionProvider)?.navidromeStarredArtistIds;
      final isStarred = artistMap['starred'] != null ||
          artistMap['isFavorite'] == true ||
          (effectiveId.isNotEmpty &&
              sessionStarred?.contains(effectiveId) == true);

      if (!mounted) return;

      bool hasChanged = true;
      if (isBackground && _albumSections.isNotEmpty) {
        if (_allSongs.length == accumulatedSongs.length &&
            _isStarred == isStarred &&
            _albumSections.length == sections.length) {
          hasChanged = false;
          for (int i = 0; i < _allSongs.length; i++) {
            if (_allSongs[i].path != accumulatedSongs[i].path ||
                _allSongs[i].title != accumulatedSongs[i].title) {
              hasChanged = true;
              break;
            }
          }
        }
      }

      if (!isBackground || hasChanged) {
        setState(() {
          _albumSections = sections;
          _allSongs = accumulatedSongs;
          _isStarred = isStarred;
          _isLoading = false;
          _error = null;
        });
        if (!isBackground) {
          widget.onLoadingStateChanged?.call(false, false);
        }
      }

      final cachePayload = {
        'artistMap': artistMap,
        'artistInfo': _artistInfo,
        'isStarred': isStarred,
        'sections': sections.map((s) => s.toJson()).toList(),
      };
      unawaited(MetadataDatabase().saveRemoteLibraryCache(
        serverId: widget.server.id,
        category: 'artist_detail_${widget.artistId}',
        dataJson: jsonEncode(cachePayload),
        count: accumulatedSongs.length,
      ));
    } catch (e) {
      if (!mounted || isBackground) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      widget.onLoadingStateChanged?.call(false, true);
    }
  }

  /// 当前搜索词命中后的专辑分组，空词时原样返回。
  ///
  /// 命中口径是「专辑名 / 专辑艺术家 / 曲目名 / 曲目艺术家」的并集：
  /// - 命中专辑名或艺术家 → 整张专辑保留全部曲目；
  /// - 只命中某些曲目 → 该专辑只保留命中曲目，分组标题仍是专辑名。
  List<_RemoteAlbumSectionData> _visibleSections() {
    final query = _query.toLowerCase();
    if (query.isEmpty) return _albumSections;

    final result = <_RemoteAlbumSectionData>[];
    for (final section in _albumSections) {
      if (section.name.toLowerCase().contains(query) ||
          section.artist.toLowerCase().contains(query)) {
        result.add(section);
        continue;
      }
      final hits = section.songs
          .where((song) => _matchesQuery(song, query))
          .toList(growable: false);
      if (hits.isEmpty) continue;
      result.add(section.withSongs(hits));
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

  /// 当前可见分组的曲目展平，顺序与界面一致。
  List<MusicFile> _flatten(List<_RemoteAlbumSectionData> sections) => [
        for (final section in sections) ...section.songs,
      ];

  Future<void> _playAll({
    bool shuffle = false,
    List<MusicFile>? songs,
  }) async {
    final source = songs ?? _allSongs;
    final l10n = AppLocalizations.of(context)!;
    if (source.isEmpty) {
      showToast(l10n.noTracksForArtist);
      return;
    }
    final audio = ref.read(audioServiceProvider);
    final playlist = List<MusicFile>.from(source);
    if (shuffle) {
      playlist.shuffle();
    }
    await audio.playPlaylist(
      playlist,
      source: PlaybackSource(
        type: PlaybackSourceType.artist,
        id: 'remote-${widget.server.id}-${widget.artistId}',
        name: widget.artistName,
      ),
    );
    showToast(l10n.playingTracksCount(source.length));
  }

  void _openAlbumDetail(_RemoteAlbumSectionData album) {
    final l10n = AppLocalizations.of(context)!;
    final albumTitle =
        album.name.isNotEmpty ? album.name : l10n.unknownAlbum;
    RemoteLibraryNavUtils.openAlbum(
      context,
      server: widget.server,
      password: widget.password,
      albumId: album.id,
      albumName: albumTitle,
      artistName: album.artist,
      coverArtId: album.coverArt,
    );
  }

  Future<void> _playAlbumDirectly(_RemoteAlbumSectionData album) async {
    final l10n = AppLocalizations.of(context)!;
    final albumTitle =
        album.name.isNotEmpty ? album.name : l10n.unknownAlbum;
    if (album.songs.isNotEmpty) {
      final audio = ref.read(audioServiceProvider);
      await audio.playPlaylist(
        album.songs,
        source: PlaybackSource(
          type: PlaybackSourceType.album,
          id: 'remote-${widget.server.id}-${album.id}',
          name: albumTitle,
        ),
      );
    } else {
      await RemoteLibrarySelectionActions.playAlbumDirectly(
        context: context,
        ref: ref,
        server: widget.server,
        password: widget.password,
        albumId: album.id,
        albumTitle: albumTitle,
      );
    }
  }

  void _showAlbumContextMenu(
    Offset position,
    _RemoteAlbumSectionData album,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final albumTitle =
        album.name.isNotEmpty ? album.name : l10n.unknownAlbum;
    showRemoteAlbumContextMenu(
      context: context,
      globalPosition: position,
      ref: ref,
      server: widget.server,
      password: widget.password,
      albumId: album.id,
      albumTitle: albumTitle,
      artistName: album.artist,
      coverArtId: album.coverArt,
      songs: album.songs,
      onViewDetails: () => _openAlbumDetail(album),
    );
  }

  List<Widget> _buildPortraitAlbumGridSlivers({
    required BuildContext context,
    required WidgetRef ref,
    required List<_RemoteAlbumSectionData> albums,
    required double contentWidth,
    required double albumZoomScale,
  }) {
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
                  return _RemoteAlbumZoomItem(
                    server: widget.server,
                    password: widget.password,
                    album: album,
                    metrics: metrics,
                    onTap: () => _openAlbumDetail(album),
                    onPlay: () => _playAlbumDirectly(album),
                    onContextMenu: (pos) => _showAlbumContextMenu(pos, album),
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final selectedSongs = getSelectedSongs(_allSongs);

    final errorWidget = _error == null
        ? null
        : Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.errorWithMessage(_error!),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loadArtistData,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.retry),
                  ),
                ],
              ),
            ),
          );

    final visibleSections = _visibleSections();
    final visibleSongs = _flatten(visibleSections);

    // 统计跟着可见集合走，避免「显示 12 张专辑但上面写着 3 张」。
    final totalSongCount = visibleSongs.isNotEmpty
        ? visibleSongs.length
        : visibleSections.fold<int>(0, (sum, sec) => sum + (sec.songCount ?? 0));
    final totalAlbumCount =
        _query.isEmpty && widget.albumCount != null
            ? widget.albumCount!
            : visibleSections.length;
    final biography = _artistInfo?['biography'] as String?;
    final effectiveCoverArtId = widget.coverArtId ??
        _artistInfo?['coverArt'] ??
        _artistInfo?['imageUrl'] ??
        _artistInfo?['largeImageUrl'] ??
        _artistInfo?['mediumImageUrl'] ??
        _albumSections.firstOrNull?.coverArt;
    final albumZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.albumZoomScale),
    );

    return DetailContentScaffold(
      scrollController: widget.scrollController,
      topPadding: widget.topPadding,
      hasPlayingMusic: currentMusic != null,
      isSelectionMode: isSelectionMode,
      isLoading: _isLoading,
      errorWidget: errorWidget,
      onRefresh: () => _loadArtistData(forceRefresh: true),
      portraitZoomScope: LibraryZoomScope.album,
      isSearchOpen: _searchOpen,
      searchField: DetailSearchBox(
        isOpen: _searchOpen,
        child: RemoteSearchBar(
          controller: _queryController,
          focusNode: _queryFocus,
          hintText: l10n.searchInArtist,
          searchQuery: _query,
          onChanged: _onQueryChanged,
          onClear: _clearQuery,
        ),
      ),
      headerBuilder: (context, isPortrait) => _buildArtistHeader(
        theme: theme,
        l10n: l10n,
        totalAlbumCount: totalAlbumCount,
        totalSongCount: totalSongCount,
        biography: biography,
        coverArtId: effectiveCoverArtId,
        visibleSongs: visibleSongs,
      ),
      bodySliversBuilder: (context, isPortrait, contentWidth) {
        if (_albumSections.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  l10n.noAlbumsForArtist,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ];
        }
        if (visibleSections.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: DetailNoMatchView(
                message: l10n.noMatchingInArtist,
                onClear: _clearQuery,
              ),
            ),
          ];
        }
        if (isPortrait) {
          return _buildPortraitAlbumGridSlivers(
            context: context,
            ref: ref,
            albums: visibleSections,
            contentWidth: contentWidth,
            albumZoomScale: albumZoomScale,
          );
        }
        return _buildLandscapeAlbumSlivers(
          visibleSections: visibleSections,
          visibleSongs: visibleSongs,
          currentMusic: currentMusic,
          l10n: l10n,
        );
      },
      selectionPanel: RemoteSongSelectionPanel(
        panelKey: const ValueKey('remote-artist-selection-panel'),
        server: widget.server,
        password: widget.password,
        selectedSongs: selectedSongs,
        allSongs: _allSongs,
        onToggleSelectAll: () => toggleSelectAllSongs(_allSongs),
        onFetchSongs: () async => selectedSongs,
        onClearSelection: cancelSongSelection,
        onStarredChanged: (starredIds) {
          ref
              .read(activeRemoteSessionProvider.notifier)
              .updateNavidromeSongs(
                starredSongIds: {
                  ...?ref
                      .read(activeRemoteSessionProvider)
                      ?.navidromeStarredSongIds,
                  ...starredIds,
                },
              );
        },
        onDownload: () async {
          final sel = List<MusicFile>.from(selectedSongs);
          if (sel.isEmpty) return;
          await ref.read(remoteDownloadTasksProvider.notifier).enqueue(
                RemoteDownloadRequest(
                  server: widget.server,
                  password: widget.password,
                  songs: sel,
                  layout: RemoteDownloadLayout.artist,
                  collectionFolder: widget.artistName,
                ),
              );
          cancelSongSelection();
          if (!context.mounted) return;
          showRemoteDownloadQueuedFeedback(context, ref, sel.length);
        },
      ),
    );
  }

  Widget _buildArtistHeader({
    required ThemeData theme,
    required AppLocalizations l10n,
    required int totalAlbumCount,
    required int totalSongCount,
    required String? biography,
    required String? coverArtId,
    required List<MusicFile> visibleSongs,
  }) {
    final metaParts = <String>[
      l10n.albumCount(totalAlbumCount),
      if (totalSongCount > 0) l10n.songCount(totalSongCount),
    ];

    final subtitles = <DetailHeaderSubtitle>[
      DetailHeaderSubtitle(metaParts.join(' · '), maxLines: 1),
      if (biography != null && biography.trim().isNotEmpty)
        DetailHeaderSubtitle(
          biography.trim(),
          maxLines: 2,
          topSpacing: 6,
        ),
    ];

    final downloadButton = IconButton(
      tooltip: l10n.download,
      onPressed: visibleSongs.isNotEmpty
          ? () => _downloadArtistSongs(visibleSongs)
          : null,
      icon: const Icon(Icons.download_rounded, size: 21),
    );

    final starButton = IconButton(
      tooltip: l10n.btnFavorite,
      onPressed: () => _toggleStarArtist(l10n),
      icon: Icon(
        _isStarred ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: 21,
        color: _isStarred
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
    );

    return DetailHeader(
      title: widget.artistName,
      subtitles: subtitles,
      avatarBuilder: (size) => _buildArtistAvatar(size, coverArtId),
      onPlayAll: visibleSongs.isNotEmpty
          ? () => _playAll(shuffle: false, songs: visibleSongs)
          : null,
      onShufflePlay: visibleSongs.isNotEmpty
          ? () => _playAll(shuffle: true, songs: visibleSongs)
          : null,
      extraPortraitActions: [downloadButton, starButton],
      extraLandscapeActions: [downloadButton, starButton],
      searchToggle: DetailSearchToggleButton(
        isOpen: _searchOpen,
        onPressed: _toggleSearch,
      ),
    );
  }

  /// 艺术家头像（圆形 + 柔和投影），竖屏与横屏共用。
  Widget _buildArtistAvatar(double size, String? coverArtId) {
    return Container(
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
      child: ClipOval(
        child: RemoteArtworkWidget(
          server: widget.server,
          password: widget.password,
          coverArtId: coverArtId,
          size: 200,
          width: size,
          height: size,
          isArtist: true,
        ),
      ),
    );
  }

  Future<void> _downloadArtistSongs(List<MusicFile> songs) async {
    if (songs.isEmpty) return;
    await ref.read(remoteDownloadTasksProvider.notifier).enqueue(
          RemoteDownloadRequest(
            server: widget.server,
            password: widget.password,
            songs: songs,
            layout: RemoteDownloadLayout.artist,
            collectionFolder: widget.artistName,
          ),
        );
    if (!mounted) return;
    showRemoteDownloadQueuedFeedback(context, ref, songs.length);
  }

  Future<void> _toggleStarArtist(AppLocalizations l10n) async {
    final effectiveId =
        _resolvedArtistId.isNotEmpty ? _resolvedArtistId : widget.artistId;
    if (effectiveId.isEmpty) return;
    final client = RemoteMediaLibraryClient.create(
      server: widget.server,
      password: widget.password,
    );
    if (_isStarred) {
      final ok = await client.unstar(artistId: effectiveId);
      if (ok && mounted) {
        setState(() => _isStarred = false);
        final currentStarred = Set<String>.from(
          ref
                  .read(activeRemoteSessionProvider)
                  ?.navidromeStarredArtistIds ??
              {},
        );
        currentStarred.remove(effectiveId);
        ref
            .read(activeRemoteSessionProvider.notifier)
            .updateNavidromeArtists(starredArtistIds: currentStarred);
        showToast(l10n.unstarredSuccess);
      }
    } else {
      final ok = await client.star(artistId: effectiveId);
      if (ok && mounted) {
        setState(() => _isStarred = true);
        final currentStarred = Set<String>.from(
          ref
                  .read(activeRemoteSessionProvider)
                  ?.navidromeStarredArtistIds ??
              {},
        );
        currentStarred.add(effectiveId);
        ref
            .read(activeRemoteSessionProvider.notifier)
            .updateNavidromeArtists(starredArtistIds: currentStarred);
        showToast(l10n.starredSuccess);
      }
    }
  }

  List<Widget> _buildLandscapeAlbumSlivers({
    required List<_RemoteAlbumSectionData> visibleSections,
    required List<MusicFile> visibleSongs,
    required MusicFile? currentMusic,
    required AppLocalizations l10n,
  }) {
    final audio = ref.read(audioServiceProvider);
    final slivers = <Widget>[];
    var startIndex = 0;

    for (var i = 0; i < visibleSections.length; i++) {
      final sec = visibleSections[i];
      if (i > 0) {
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 36)));
      }
      if (sec.songs.isEmpty) continue;

      final albumTitle = sec.name.isNotEmpty ? sec.name : l10n.unknownAlbum;
      final repSong = sec.songs.firstWhere(
        (s) =>
            (s.artworkPath?.isNotEmpty ?? false) ||
            (s.artworkBytes?.isNotEmpty ?? false) ||
            (s.thumbnailPath?.isNotEmpty ?? false),
        orElse: () => sec.songs.first,
      );
      final totalDurationMillis =
          sec.songs.fold<int>(0, (sum, s) => sum + (s.durationMillis ?? 0));

      final albumSection = AlbumSection(
        title: albumTitle,
        songs: sec.songs,
        representativeSong: repSong,
        totalDurationMillis: totalDurationMillis,
        startIndex: startIndex,
        artist: sec.artist.isNotEmpty ? sec.artist : null,
        year: sec.year,
      );
      startIndex += sec.songs.length;

      slivers.add(
        AlbumSectionSliver(
          key: ValueKey('remote-artist-album-${sec.id}-$albumTitle'),
          section: albumSection,
          currentMusicPath: currentMusic?.path,
          showRemoteBadge: false,
          isSelectionMode: isSelectionMode,
          selectedSongPaths: selectedSongPaths,
          onOpenAlbum: () {
            RemoteLibraryNavUtils.openAlbum(
              context,
              server: widget.server,
              password: widget.password,
              albumId: sec.id,
              albumName: albumTitle,
              artistName: sec.artist,
              coverArtId: sec.coverArt,
            );
          },
          playbackSourceBuilder: (_) => PlaybackSource(
            type: PlaybackSourceType.album,
            id: 'remote-${widget.server.id}-${sec.id}',
            name: albumTitle,
          ),
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
                  source: PlaybackSource(
                    type: PlaybackSourceType.artist,
                    id: 'remote-${widget.server.id}-${widget.artistId}',
                    name: widget.artistName,
                  ),
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
          onSongSecondaryTapDown: (section, details, song) {
            if (isSelectionMode) return;
            showRemoteSongContextMenu(
              context: context,
              globalPosition: details.globalPosition,
              ref: ref,
              server: widget.server,
              password: widget.password,
              song: song,
              playlist: section.songs,
              onMultiSelect: () => enterSongSelectionMode(song.path),
              downloadLayout: RemoteDownloadLayout.artist,
              downloadCollectionFolder: widget.artistName,
              onViewAlbum: () {
                RemoteLibraryNavUtils.openAlbum(
                  context,
                  server: widget.server,
                  password: widget.password,
                  albumId: sec.id,
                  albumName: albumTitle,
                  artistName: sec.artist,
                  coverArtId: sec.coverArt,
                );
              },
            );
          },
        ),
      );
    }

    return slivers;
  }
}

typedef NavidromeArtistDetailPage = RemoteArtistDetailPage;
typedef NavidromeArtistDetailContent = RemoteArtistDetailContent;

class _RemoteAlbumZoomItem extends StatefulWidget {
  final RemoteServer server;
  final String password;
  final _RemoteAlbumSectionData album;
  final FolderZoomLayoutMetrics metrics;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final void Function(Offset position)? onContextMenu;

  const _RemoteAlbumZoomItem({
    required this.server,
    required this.password,
    required this.album,
    required this.metrics,
    required this.onTap,
    required this.onPlay,
    this.onContextMenu,
  });

  @override
  State<_RemoteAlbumZoomItem> createState() => _RemoteAlbumZoomItemState();
}

class _RemoteAlbumZoomItemState extends State<_RemoteAlbumZoomItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final metrics = widget.metrics;
    final gridMorph = metrics.gridMorph;
    final isGridTarget = metrics.isGridTarget;

    final album = widget.album;
    final albumTitle = album.name.isNotEmpty ? album.name : l10n.unknownAlbum;
    final extraInfo = album.songCount != null
        ? l10n.trackCountShort(album.songCount!)
        : (album.year != null && album.year! > 0 ? '${album.year}' : '');
    final subtitle = extraInfo.isNotEmpty
        ? '${album.artist} · $extraInfo'
        : album.artist;

    final coverRadiusValue = lerpDouble(8.0, 12.0, gridMorph)!;
    final coverRadius = BorderRadius.circular(coverRadiusValue);

    final thumbnail = RemoteArtworkWidget(
      server: widget.server,
      password: widget.password,
      coverArtId: album.coverArt,
      size: 300,
      width: double.infinity,
      height: double.infinity,
      borderRadius: coverRadius,
    );

    final cover = ZoomItemCover(
      metrics: metrics,
      isSelected: false,
      isSelectionMode: false,
      onToggleSelect: widget.onTap,
      onPlay: widget.onPlay,
      child: thumbnail,
    );

    final scaffold = ZoomItemScaffold(
      metrics: metrics,
      cover: cover,
      titleText: albumTitle,
      subtitleText: subtitle,
      titleColor: theme.colorScheme.onSurface,
      listTitleFontWeight: FontWeight.normal,
      isSelected: false,
      isSelectionMode: false,
      selectionOffset: 0.0,
      wrapHoverableCard: false,
      onTap: widget.onTap,
      onContextMenu: widget.onContextMenu,
    );

    final cardContent = MouseRegion(
      onEnter: (_) {
        if (isGridTarget && !_isHovered) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (_isHovered) setState(() => _isHovered = false);
      },
      cursor: SystemMouseCursors.click,
      child: isGridTarget ? HoverableCard(child: scaffold) : scaffold,
    );

    return DraggableRemoteAlbumItem(
      server: widget.server,
      albumId: album.id,
      title: albumTitle,
      artist: album.artist,
      songCount: album.songCount ?? album.songs.length,
      child: cardContent,
    );
  }
}

