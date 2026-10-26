import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
import '../../widgets/album_detail_widgets.dart';
import '../../widgets/draggable_remote_album_item.dart';
import '../../widgets/folder_layout_utils.dart';
import '../../widgets/folder_zoom_gesture_layer.dart';
import '../../widgets/hoverable_card.dart';
import '../../widgets/remote_artwork_widget.dart';
import '../../widgets/mini_player_wrapper.dart';
import '../../widgets/playing_equalizer_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../dialogs/remote_track_load_progress_dialog.dart';
import '../../player/remote/services/remote_download_service.dart';
import '../../player/remote/remote_library_navigation.dart';
import '../../utils/remote_context_menu_utils.dart';
import '../../utils/remote_download_feedback.dart';
import '../../widgets/library_selection_panel.dart';
import '../../widgets/library_selection_scope.dart';
import 'remote_download_manager_page.dart';
import 'widgets/remote_library_selection_actions.dart';
import 'widgets/remote_library_toolbar_widgets.dart';
import '../../widgets/auto_hide_header.dart';

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
      AlbumDetailNavBar.getBarHeight(context);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final double barHeight = getBarHeight(context);

    return AutoHideHeaderScope(
      builder: (context, isHeaderVisible) {
        final Widget content = Scaffold(
          body: Stack(
            children: [
              RemoteArtistDetailContent(
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
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AutoHideHeader(
                  isVisible: isHeaderVisible,
                  child: AlbumDetailNavBar(
                    title: widget.artistName,
                    scrollProgress: (_isLoading || _hasError)
                        ? const AlwaysStoppedAnimation(1.0)
                        : _scrollProgress,
                    isCoverVisible: (_isLoading || _hasError)
                        ? const AlwaysStoppedAnimation(false)
                        : _isHeaderVisible,
                    onGoBack: widget.onGoBack ?? () => Navigator.of(context).maybePop(),
                    actions: [
                      IconButton(
                        icon: Badge(
                          isLabelVisible: ref.watch(activeDownloadsCountProvider) > 0,
                          label: Text('${ref.watch(activeDownloadsCountProvider)}'),
                          child: const Icon(Icons.download_rounded, size: 20),
                        ),
                        tooltip: l10n.downloadManager,
                        onPressed: () {
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (_) => const RemoteDownloadManagerPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        return MiniPlayerWrapper(child: content);
      },
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
      ref,
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
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final bottomOffset = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
      isSelectionMode: !isPortrait && isSelectionMode,
      selectionPanelHeight: 220.0,
    );
    final selectedSongs = getSelectedSongs(_allSongs);

    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }

    if (_error != null) {
      return Center(
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
    }

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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final albumZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.albumZoomScale),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth =
            math.min(constraints.maxWidth, kFolderPageMaxWidth);

        final scrollView = CustomScrollView(
          controller: widget.scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // Artist Header (Styled similarly to local ArtistDetailContent)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isPortrait ? 20 : 28,
                  widget.topPadding > 0 ? widget.topPadding + 12 : 24,
                  isPortrait ? 20 : 28,
                  isPortrait ? 30.0 : 20.0,
                ),
                    child: isPortrait
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Row 1: 艺术家头像居中占一行
                                    Center(
                                      child: _buildArtistAvatar(
                                        screenWidth < 360 ? 92.0 : 104.0,
                                        effectiveCoverArtId,
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // Row 2: 名字占一行
                                    Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              widget.artistName,
                                              textAlign: TextAlign.center,
                                              style: theme.textTheme
                                                  .headlineMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.5,
                                                fontSize: 24,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 22,
                                            color: theme
                                                .colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.7),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // 轻量副标题展示
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        l10n.albumCount(totalAlbumCount),
                                        if (totalSongCount > 0)
                                          l10n.songCount(totalSongCount),
                                      ].join(' · '),
                                      textAlign: TextAlign.center,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (biography != null &&
                                        biography.trim().isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        biography.trim(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 18),

                                    // Row 3: 按钮占一行（通栏并排两个胶囊按钮 + 下载/收藏圆形快捷按钮），
                                    // 搜索开关贴在这行右端；左侧留等宽占位，保证按钮组仍然居中。
                                    Row(
                                      children: [
                                        // 与右侧搜索开关等宽（34），保证按钮组整体仍然居中。
                                        const SizedBox(width: 34),
                                        Expanded(
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            minWidth: 124,
                                            maxWidth: 160,
                                          ),
                                          child: SizedBox(
                                            height: 44,
                                            child: FilledButton.icon(
                                              onPressed: visibleSongs.isNotEmpty
                                                  ? () => _playAll(
                                                        shuffle: false,
                                                        songs: visibleSongs,
                                                      )
                                                  : null,
                                              icon: const Icon(Icons.play_arrow_rounded,
                                                  size: 20),
                                              label: Text(
                                                l10n.playAll,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              style: FilledButton.styleFrom(
                                                shape: const StadiumBorder(),
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 18),
                                                fixedSize:
                                                    const Size.fromHeight(44),
                                                minimumSize:
                                                    const Size.fromHeight(44),
                                                elevation: 0,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        IconButton.filledTonal(
                                          onPressed: visibleSongs.isNotEmpty
                                              ? () => _playAll(
                                                    shuffle: true,
                                                    songs: visibleSongs,
                                                  )
                                              : null,
                                          tooltip: l10n.shufflePlay,
                                          style: IconButton.styleFrom(
                                            foregroundColor:
                                                theme.colorScheme.onSecondaryContainer,
                                            backgroundColor: theme.colorScheme
                                                .surfaceContainerHighest,
                                            fixedSize: const Size(44, 44),
                                            padding: EdgeInsets.zero,
                                            shape: const CircleBorder(),
                                          ),
                                          icon: const Icon(Icons.shuffle_rounded,
                                              size: 20),
                                        ),
                                        if (visibleSongs.isNotEmpty) ...[
                                          const SizedBox(width: 10),
                                          IconButton.filledTonal(
                                            onPressed: () async {
                                              // null = 用户在进度浮层里取消了。
                                              final queued =
                                                  await runWithRemoteTrackLoadProgress<
                                                      bool>(
                                                context: context,
                                                immediate: true,
                                                task: () async {
                                                  await ref
                                                      .read(
                                                          remoteDownloadTasksProvider
                                                              .notifier)
                                                      .enqueue(
                                                        RemoteDownloadRequest(
                                                          server:
                                                              widget.server,
                                                          password: widget
                                                              .password,
                                                          songs: visibleSongs,
                                                          layout:
                                                              RemoteDownloadLayout
                                                                  .artist,
                                                          collectionFolder: widget
                                                              .artistName,
                                                        ),
                                                      );
                                                  return true;
                                                },
                                              );
                                              if (queued != true || !context.mounted) return;
                                              showRemoteDownloadQueuedFeedback(
                                                context,
                                                ref,
                                                visibleSongs.length,
                                              );
                                            },
                                            tooltip: l10n.download,
                                            style: IconButton.styleFrom(
                                              foregroundColor:
                                                  theme.colorScheme.primary,
                                              backgroundColor: theme.colorScheme
                                                  .surfaceContainerHighest,
                                              fixedSize: const Size(44, 44),
                                              padding: EdgeInsets.zero,
                                              shape: const CircleBorder(),
                                            ),
                                            icon: const Icon(
                                                Icons.download_rounded,
                                                size: 20),
                                          ),
                                        ],
                                        const SizedBox(width: 10),
                                        IconButton.filledTonal(
                                          onPressed: () async {
                                            final effectiveId =
                                                _resolvedArtistId.isNotEmpty
                                                    ? _resolvedArtistId
                                                    : widget.artistId;
                                            if (effectiveId.isEmpty) return;
                                            final client =
                                                RemoteMediaLibraryClient.create(
                                              server: widget.server,
                                              password: widget.password,
                                            );
                                            if (_isStarred) {
                                              final ok = await client.unstar(
                                                  artistId: effectiveId);
                                              if (ok && mounted) {
                                                setState(
                                                    () => _isStarred = false);
                                                final currentStarred =
                                                    Set<String>.from(ref
                                                            .read(
                                                                activeRemoteSessionProvider)
                                                            ?.navidromeStarredArtistIds ??
                                                        {});
                                                currentStarred
                                                    .remove(effectiveId);
                                                ref
                                                    .read(
                                                        activeRemoteSessionProvider
                                                            .notifier)
                                                    .updateNavidromeArtists(
                                                      starredArtistIds:
                                                          currentStarred,
                                                    );
                                                showToast(
                                                    l10n.unstarredSuccess);
                                              }
                                            } else {
                                              final ok = await client.star(
                                                  artistId: effectiveId);
                                              if (ok && mounted) {
                                                setState(
                                                    () => _isStarred = true);
                                                final currentStarred =
                                                    Set<String>.from(ref
                                                            .read(
                                                                activeRemoteSessionProvider)
                                                            ?.navidromeStarredArtistIds ??
                                                        {});
                                                currentStarred.add(effectiveId);
                                                ref
                                                    .read(
                                                        activeRemoteSessionProvider
                                                            .notifier)
                                                    .updateNavidromeArtists(
                                                      starredArtistIds:
                                                          currentStarred,
                                                    );
                                                showToast(l10n.starredSuccess);
                                              }
                                            }
                                          },
                                          tooltip: l10n.btnFavorite,
                                          style: IconButton.styleFrom(
                                            foregroundColor: _isStarred
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme
                                                    .onSurfaceVariant,
                                            backgroundColor: theme.colorScheme
                                                .surfaceContainerHighest,
                                            fixedSize: const Size(44, 44),
                                            padding: EdgeInsets.zero,
                                            shape: const CircleBorder(),
                                          ),
                                          icon: Icon(
                                            _isStarred
                                                ? Icons.favorite_rounded
                                                : Icons.favorite_border_rounded,
                                            size: 20,
                                          ),
                                        ),
                                            ],
                                          ),
                                        ),
                                        _buildSearchToggle(l10n, theme),
                                      ],
                                    ),
                                  ],
                                )
                              : _buildLandscapeHeader(
                                  theme,
                                  l10n,
                                  totalAlbumCount,
                                  totalSongCount,
                                  biography,
                                  effectiveCoverArtId,
                                  visibleSongs,
                                ),
                  ),
                ),

                // 艺术家内搜索：开关在页头操作行右端，展开后搜索框在页头下方占一行。
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isPortrait ? 20 : 28,
                      0,
                      isPortrait ? 20 : 28,
                      10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSearchField(l10n),
                      ],
                    ),
                  ),
                ),

                if (_albumSections.isEmpty)
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
                    albums: visibleSections,
                    contentWidth: contentWidth,
                    albumZoomScale: albumZoomScale,
                  )
                else ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  for (int i = 0; i < visibleSections.length; i++) ...[
                    if (i > 0) const SliverToBoxAdapter(child: SizedBox(height: 28)),
                    _buildAlbumSection(theme, visibleSections[i], currentMusic),
                  ],
                ],
                SliverToBoxAdapter(child: SizedBox(height: bottomOffset)),
              ],
            );

        final refreshView = RefreshIndicator(
          onRefresh: () => _loadArtistData(forceRefresh: true),
          child: scrollView,
        );

        final scrollContent = isPortrait
            ? FolderZoomGestureLayer(
                scope: LibraryZoomScope.album,
                child: refreshView,
              )
            : refreshView;

        return Stack(
          children: [
            Positioned.fill(child: scrollContent),
            AnimatedSelectionPanel(
              isVisible: !isPortrait && isSelectionMode,
              child: LibrarySelectionPanel(
                key: const ValueKey('remote-artist-selection-panel'),
                selectedSongs: selectedSongs,
                allSongs: _allSongs,
                onToggleSelectAll: () => toggleSelectAllSongs(_allSongs),
                onCancel: cancelSongSelection,
                onAddToFavorites: () =>
                    RemoteLibrarySelectionActions.handleBatchAddToLocalFavorites(
                  context: context,
                  ref: ref,
                  onFetchSongs: () async => selectedSongs,
                  onClearSelection: cancelSongSelection,
                ),
                onAddToCloudFavorites: () =>
                    RemoteLibrarySelectionActions.handleBatchAddToCloudFavorites(
                  context: context,
                  ref: ref,
                  server: widget.server,
                  password: widget.password,
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
                ),
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
            ),
          ],
        );
      },
    );
  }

  /// 页头操作行右端的搜索开关。展开时图标高亮，再点一次收起并清空。
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
              child: RemoteSearchBar(
                controller: _queryController,
                focusNode: _queryFocus,
                hintText: l10n.searchInArtist,
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
          size: size,
          width: size,
          height: size,
          isArtist: true,
        ),
      ),
    );
  }

  /// 横屏页头：头像与文字信息左右并排，操作按钮独占一行。
  Widget _buildLandscapeHeader(
    ThemeData theme,
    AppLocalizations l10n,
    int totalAlbumCount,
    int totalSongCount,
    String? biography,
    String? coverArtId,
    List<MusicFile> songs,
  ) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildArtistAvatar(screenWidth < 480 ? 64.0 : 80.0, coverArtId),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.artistLabel.toUpperCase(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.artistName,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(label: l10n.albumCount(totalAlbumCount)),
                      if (totalSongCount > 0)
                        _InfoChip(label: l10n.songCount(totalSongCount)),
                    ],
                  ),
                  if (biography != null && biography.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      biography.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // 操作按钮与搜索开关同一行：搜索贴在这行的右端，既不额外占一行，
        // 也不会孤零零悬在页头右下方。按钮换行时搜索跟随第一行顶部对齐。
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
            FilledButton.icon(
              onPressed: songs.isNotEmpty
                  ? () => _playAll(shuffle: false, songs: songs)
                  : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(l10n.playAll),
            ),
            OutlinedButton.icon(
              onPressed: songs.isNotEmpty
                  ? () => _playAll(shuffle: true, songs: songs)
                  : null,
              icon: const Icon(Icons.shuffle_rounded, size: 18),
              label: Text(l10n.shufflePlay),
            ),
            OutlinedButton.icon(
              onPressed: songs.isNotEmpty
                  ? () async {
                      await ref
                          .read(remoteDownloadTasksProvider.notifier)
                          .enqueue(
                            RemoteDownloadRequest(
                              server: widget.server,
                              password: widget.password,
                              songs: songs,
                              layout: RemoteDownloadLayout.artist,
                              collectionFolder: widget.artistName,
                            ),
                          );
                      if (!mounted) return;
                      showRemoteDownloadQueuedFeedback(
                        context,
                        ref,
                        songs.length,
                      );
                    }
                  : null,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(l10n.download),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final effectiveId = _resolvedArtistId.isNotEmpty
                    ? _resolvedArtistId
                    : widget.artistId;
                if (effectiveId.isEmpty) return;
                final client = RemoteMediaLibraryClient.create(
                  server: widget.server,
                  password: widget.password,
                );
                if (_isStarred) {
                  final ok = await client.unstar(artistId: effectiveId);
                  if (ok && mounted) {
                    setState(() => _isStarred = false);
                    final currentStarred = Set<String>.from(ref
                            .read(activeRemoteSessionProvider)
                            ?.navidromeStarredArtistIds ??
                        {});
                    currentStarred.remove(effectiveId);
                    ref
                        .read(activeRemoteSessionProvider.notifier)
                        .updateNavidromeArtists(
                          starredArtistIds: currentStarred,
                        );
                    showToast(l10n.unstarredSuccess);
                  }
                } else {
                  final ok = await client.star(artistId: effectiveId);
                  if (ok && mounted) {
                    setState(() => _isStarred = true);
                    final currentStarred = Set<String>.from(ref
                            .read(activeRemoteSessionProvider)
                            ?.navidromeStarredArtistIds ??
                        {});
                    currentStarred.add(effectiveId);
                    ref
                        .read(activeRemoteSessionProvider.notifier)
                        .updateNavidromeArtists(
                          starredArtistIds: currentStarred,
                        );
                    showToast(l10n.starredSuccess);
                  }
                }
              },
              icon: Icon(
                _isStarred
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 18,
                color: _isStarred ? theme.colorScheme.primary : null,
              ),
              label: Text(
                l10n.btnFavorite,
                style: TextStyle(
                  color: _isStarred ? theme.colorScheme.primary : null,
                ),
              ),
            ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              // 搜索按钮 34 高、按钮 44 高，下移 5 让两者视觉中线对齐。
              padding: const EdgeInsets.only(top: 5),
              child: _buildSearchToggle(l10n, theme),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlbumSection(
    ThemeData theme,
    _RemoteAlbumSectionData section,
    MusicFile? currentMusic,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final albumTitle = section.name.isNotEmpty ? section.name : l10n.unknownAlbum;
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isPortrait ? 20.0 : 28.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              // Section Header
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) {
                  showRemoteAlbumContextMenu(
                    context: context,
                    globalPosition: details.globalPosition,
                    ref: ref,
                    server: widget.server,
                    password: widget.password,
                    albumId: section.id,
                    albumTitle: albumTitle,
                    artistName: section.artist,
                    coverArtId: section.coverArt,
                    songs: section.songs,
                    onViewDetails: () {
                      RemoteLibraryNavUtils.openAlbum(
                        context,
                        ref,
                        server: widget.server,
                        password: widget.password,
                        albumId: section.id,
                        albumName: albumTitle,
                        artistName: section.artist,
                        coverArtId: section.coverArt,
                      );
                    },
                  );
                },
                onLongPressStart: (details) {
                  showRemoteAlbumContextMenu(
                    context: context,
                    globalPosition: details.globalPosition,
                    ref: ref,
                    server: widget.server,
                    password: widget.password,
                    albumId: section.id,
                    albumTitle: albumTitle,
                    artistName: section.artist,
                    coverArtId: section.coverArt,
                    songs: section.songs,
                    onViewDetails: () {
                      RemoteLibraryNavUtils.openAlbum(
                        context,
                        ref,
                        server: widget.server,
                        password: widget.password,
                        albumId: section.id,
                        albumName: albumTitle,
                        artistName: section.artist,
                        coverArtId: section.coverArt,
                      );
                    },
                  );
                },
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    RemoteLibraryNavUtils.openAlbum(
                      context,
                      ref,
                      server: widget.server,
                      password: widget.password,
                      albumId: section.id,
                      albumName: albumTitle,
                      artistName: section.artist,
                      coverArtId: section.coverArt,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 6.0,
                    ),
                    child: Row(
                      children: [
                        RemoteArtworkWidget(
                          server: widget.server,
                          password: widget.password,
                          coverArtId: section.coverArt,
                          size: 52,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                albumTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  if (section.year != null && section.year! > 0)
                                    '${section.year}',
                                  l10n.trackCountShort(section.songs.length),
                                ].join(' • '),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.playAlbum,
                          icon: Icon(
                            Icons.play_circle_filled_rounded,
                            size: 32,
                            color: theme.colorScheme.primary,
                          ),
                          onPressed: section.songs.isNotEmpty
                              ? () async {
                                  final audio = ref.read(audioServiceProvider);
                                  await audio.playPlaylist(
                                    section.songs,
                                    source: PlaybackSource(
                                      type: PlaybackSourceType.album,
                                      id: 'remote-${widget.server.id}-${section.id}',
                                      name: albumTitle,
                                    ),
                                  );
                                }
                              : null,
                        ),
                        IconButton(
                          tooltip: l10n.shuffleAlbum,
                          icon: const Icon(Icons.shuffle_rounded, size: 20),
                          onPressed: section.songs.isNotEmpty
                              ? () async {
                                  final audio = ref.read(audioServiceProvider);
                                  await audio.playPlaylist(
                                    List.of(section.songs)..shuffle(),
                                    source: PlaybackSource(
                                      type: PlaybackSourceType.album,
                                      id: 'remote-${widget.server.id}-${section.id}',
                                      name: albumTitle,
                                    ),
                                  );
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Track items
              for (int j = 0; j < section.songs.length; j++) ...[
                _buildSongItem(
                  theme,
                  section.songs[j],
                  // 搜索只留下部分曲目时，用真实音轨号，别把「第 5 首」显示成「第 1 首」。
                  _query.isEmpty
                      ? j + 1
                      : (section.songs[j].trackNumber ?? j + 1),
                  section.songs,
                  j,
                  currentMusic,
                  albumSection: section,
                  showTopDivider: j > 0,
                ),
              ],
            ],
          ),
        ),
      );
    }

  Widget _buildSongItem(
    ThemeData theme,
    MusicFile song,
    int trackNum,
    List<MusicFile> playlist,
    int initialIndex,
    MusicFile? currentMusic, {
    _RemoteAlbumSectionData? albumSection,
    bool showTopDivider = false,
  }) {
    final isPlaying = currentMusic?.path == song.path;
    final isAudioPlaying = ref.watch(audioIsPlayingProvider);
    final isSelected = isSongSelected(song.path);
    final trackLabel = '$trackNum'.padLeft(2, '0');
    final durationLabel = song.durationMillis != null && song.durationMillis! > 0
        ? _formatDuration(song.durationMillis!)
        : null;
    final isTileSelected = isSelectionMode ? isSelected : isPlaying;

    void openContextMenu(Offset position) {
      showRemoteSongContextMenu(
        context: context,
        globalPosition: position,
        ref: ref,
        server: widget.server,
        password: widget.password,
        song: song,
        playlist: playlist,
        onMultiSelect: () => enterSongSelectionMode(song.path),
        downloadLayout: RemoteDownloadLayout.artist,
        downloadCollectionFolder: widget.artistName,
        onViewAlbum: albumSection != null
            ? () {
                RemoteLibraryNavUtils.openAlbum(
                  context,
                  ref,
                  server: widget.server,
                  password: widget.password,
                  albumId: albumSection.id,
                  albumName: albumSection.name,
                  artistName: albumSection.artist,
                  coverArtId: albumSection.coverArt,
                );
              }
            : null,
      );
    }

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTopDivider && !isTileSelected)
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 48,
              endIndent: 8,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) {
              if (!isSelectionMode) {
                openContextMenu(details.globalPosition);
              }
            },
            onLongPressStart: (details) {
              lastAnchorIndex = initialIndex;
              if (!isSelectionMode) {
                enterSongSelectionMode(song.path);
              } else {
                toggleSongSelection(song.path);
              }
            },
            child: Material(
              color: isTileSelected
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  handleSongTap(
                    index: initialIndex,
                    songPath: song.path,
                    allSongs: playlist,
                    onNormalTap: () async {
                      final audio = ref.read(audioServiceProvider);
                      await audio.playPlaylist(
                        playlist,
                        initialIndex: initialIndex,
                        source: PlaybackSource(
                          type: PlaybackSourceType.artist,
                          id: 'remote-${widget.server.id}-${widget.artistId}',
                          name: widget.artistName,
                        ),
                      );
                    },
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Center(
                          child: isSelectionMode
                              ? Checkbox(
                                  value: isSelected,
                                  onChanged: (_) =>
                                      toggleSongSelection(song.path),
                                )
                              : (isPlaying
                                  ? PlayingEqualizerIcon(
                                      color: theme.colorScheme.primary,
                                      size: 16,
                                      isPlaying: isAudioPlaying,
                                    )
                                  : Text(
                                      trackLabel,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          song.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: isPlaying ? theme.colorScheme.primary : null,
                            fontWeight: isPlaying ? FontWeight.w700 : null,
                          ),
                        ),
                      ),
                      if (durationLabel != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          durationLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (!isSelectionMode) ...[
                        const SizedBox(width: 4),
                        Builder(
                          builder: (btnContext) => IconButton(
                            icon: const Icon(Icons.more_vert_rounded, size: 18),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () {
                              final renderBox = btnContext.findRenderObject() as RenderBox?;
                              final offset = renderBox != null
                                  ? renderBox.localToGlobal(Offset.zero)
                                  : Offset.zero;
                              openContextMenu(offset);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int millis) {
    final dur = Duration(milliseconds: millis);
    final m = dur.inMinutes;
    final s = dur.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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

