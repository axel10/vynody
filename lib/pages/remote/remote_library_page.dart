import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/metadata/metadata_database.dart';
import '../../models/music_file.dart';
import '../../player/audio/audio_riverpod.dart';
import '../../player/remote/remote_server_models.dart';
import '../../player/remote/remote_server_riverpod.dart';
import '../../player/remote/clients/remote_media_library_client.dart';
import '../../player/remote/proxy/remote_media_resolver.dart';
import '../../widgets/mini_player_wrapper.dart';
import '../../l10n/app_localizations.dart';
import '../../player/remote/services/remote_download_service.dart';
import '../../widgets/library_selection_scope.dart';
import '../main_layout_riverpod.dart';
import '../../player/remote/remote_library_navigation.dart';
import '../../widgets/library_action_bar.dart';
import 'remote_download_manager_page.dart';
import 'remote_album_detail_page.dart';
import 'remote_artist_detail_page.dart';
import 'remote_playlist_detail_page.dart';
import 'remote_library_dashboard_view.dart';
import 'remote_library_sub_host_page.dart';
import 'widgets/remote_library_selection_actions.dart';
import 'widgets/remote_song_selection_panel.dart';
import 'widgets/remote_library_albums_tab.dart';
import 'widgets/remote_library_artists_tab.dart';
import 'widgets/remote_library_genres_tab.dart';
import 'widgets/remote_library_songs_tab.dart';
import 'widgets/remote_library_playlists_tab.dart';
import 'widgets/remote_library_search_tab.dart';
import '../../utils/song_locator_helper.dart';
import '../../utils/remote_library_playback.dart';
import '../../player/platform/right_queue_drawer_controller.dart';
import '../../utils/app_icons.dart';
import '../../utils/layout_constants.dart';
import '../../dialogs/sort_options_dialog.dart';

class RemoteLibraryPage extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final bool wrapWithMiniPlayer;

  const RemoteLibraryPage({
    super.key,
    required this.server,
    required this.password,
    this.wrapWithMiniPlayer = false,
  });

  @override
  ConsumerState<RemoteLibraryPage> createState() => RemoteLibraryPageState();
}

/// 公开供宿主页（`FoldersPage`）分发系统返回键。
class RemoteLibraryPageState extends ConsumerState<RemoteLibraryPage> {
  /// 概览页 / 二级分类宿主这两级路由的局部导航器。
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'remote_library',
  );

  /// 每个二级分类一条独立导航域，详情页压在自己分类里，切分类不出栈。
  late final List<GlobalKey<NavigatorState>> _tabNavigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
        6,
        (i) => GlobalKey<NavigatorState>(debugLabel: 'remote_library_tab_$i'),
      );

  late RemoteMediaLibraryClient _client;

  // Albums state
  bool _isLoadingAlbums = false;
  String _albumSortType = 'alphabeticalByName';
  bool _albumStarredOnly = false;
  List<Map<String, dynamic>> _albums = [];
  String? _albumsError;
  final TextEditingController _albumSearchController = TextEditingController();
  final FocusNode _albumSearchFocusNode = FocusNode();
  String _albumSearchQuery = '';
  final Set<String> _starredAlbumIds = {};
  List<Map<String, dynamic>> _recentPlayedAlbums = [];
  List<Map<String, dynamic>> _mostPlayedAlbums = [];

  // Artists state
  bool _isLoadingArtists = false;
  List<Map<String, dynamic>> _artists = [];
  String? _artistsError;
  String? _selectedArtistId;
  final TextEditingController _artistSearchController = TextEditingController();
  final FocusNode _artistSearchFocusNode = FocusNode();
  String _artistSearchQuery = '';
  bool _artistSortAsc = true;
  String _artistSortField = 'name'; // 'name' or 'albumCount'

  // 排序字段 + 升降序作为视图偏好存在 SettingsService（initState 读、弹窗写）。
  // 存的是「按什么排」，不是歌单顺序本身：服务端没有「歌单之间排序」的接口，
  // 也不该为此在客户端造一份持久化顺序。
  RemotePlaylistSortField _playlistSortField =
      RemotePlaylistSortField.serverOrder;
  bool _playlistSortAscending = true;
  bool _artistStarredOnly = false;
  final Set<String> _starredArtistIds = {};

  // Genres state
  bool _isLoadingGenres = false;
  List<Map<String, dynamic>> _genres = [];
  String? _genresError;

  // Songs state
  bool _isLoadingSongs = false;
  bool _isLoadingMoreSongs = false;
  bool _hasMoreSongs = true;
  int _songOffset = 0;
  List<MusicFile> _songs = [];
  final Set<String> _starredSongIds = {};
  String? _songsError;
  final TextEditingController _songSearchController = TextEditingController();
  final FocusNode _songSearchFocusNode = FocusNode();
  String _songSearchQuery = '';
  bool _songStarredOnly = false;
  String _songSortField = 'title'; // 'title', 'artist', 'album', 'duration'
  bool _songSortAsc = true;

  // Playlists state
  static const String _starredPlaylistId =
      RemoteLibrarySelectionActions.starredPlaylistId;
  bool _isLoadingPlaylists = false;
  List<Map<String, dynamic>> _playlists = [];
  String? _playlistsError;
  String? _selectedPlaylistId = _starredPlaylistId;
  final TextEditingController _playlistSearchController =
      TextEditingController();
  String _playlistSearchQuery = '';

  // Search tab state
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearching = false;
  List<MusicFile> _searchedSongs = [];
  List<Map<String, dynamic>> _searchedAlbums = [];
  List<Map<String, dynamic>> _searchedArtists = [];

  // Connection state
  String? _connectionError;
  bool _isRetrying = false;

  // Filtered 缓存（B-1）：每次 build 都会给六个 tab 传参，旧实现六份全表
  // 过滤 + 排序无条件重跑。这里用「源列表 identity + 长度 + 过滤/排序参数」
  // 组成签名，签名不变直接复用上次结果；源列表被整体替换（forceRefresh /
  // session 同步 / 加载更多）或原地 addAll（长度变）都会自动失效。
  List<MusicFile>? _cachedFilteredSongs;
  int _cachedFilteredSongsSig = 0;
  List<Map<String, dynamic>>? _cachedFilteredAlbums;
  int _cachedFilteredAlbumsSig = 0;
  List<Map<String, dynamic>>? _cachedFilteredArtists;
  int _cachedFilteredArtistsSig = 0;
  List<Map<String, dynamic>>? _cachedFilteredPlaylists;
  int _cachedFilteredPlaylistsSig = 0;

  /// 排序 / 筛选条件变更触发的再次请求：叠加轻量加载态提示
  bool _isReloadingContent = false;

  // Multi-selection state
  final Set<String> _selectedAlbumIds = {};
  final Set<String> _selectedArtistIds = {};
  final Set<String> _selectedPlaylistIds = {};
  final Set<String> _selectedSongPaths = {};

  int? _lastAlbumAnchorIndex;
  int? _lastArtistAnchorIndex;
  int? _lastPlaylistAnchorIndex;
  int? _lastSongAnchorIndex;

  bool get _isAlbumSelectionMode => _selectedAlbumIds.isNotEmpty;
  bool get _isArtistSelectionMode => _selectedArtistIds.isNotEmpty;
  bool get _isPlaylistSelectionMode => _selectedPlaylistIds.isNotEmpty;
  bool get _isSongSelectionMode => _selectedSongPaths.isNotEmpty;
  /// 搜索分类的索引（专辑 0 / 艺术家 1 / 流派 2 / 歌曲 3 / 播放列表 4 / 搜索 5）。
  static const int _kSearchTabIndex = 5;

  /// 当前二级分类索引。`null` = 停在概览页（回退到第一个分类取数）。
  int get _currentTabIndex =>
      (ref.read(remoteLibraryActiveTabIndexProvider) ?? 0).clamp(0, 5);

  bool get _isSelectionMode =>
      _isAlbumSelectionMode ||
      _isArtistSelectionMode ||
      _isPlaylistSelectionMode ||
      _isSongSelectionMode;

  void _updateSelectionScope([bool? forceActive]) {
    final active = forceActive ?? _isSelectionMode;
    if (active) {
      ref
          .read(librarySelectionScopeProvider.notifier)
          .setScope(LibrarySelectionScope.navidrome);
    } else {
      ref.read(librarySelectionScopeProvider.notifier).clear();
    }
  }

  void _cancelSelection() {
    if (_selectedAlbumIds.isNotEmpty ||
        _selectedArtistIds.isNotEmpty ||
        _selectedPlaylistIds.isNotEmpty ||
        _selectedSongPaths.isNotEmpty) {
      setState(() {
        _selectedAlbumIds.clear();
        _selectedArtistIds.clear();
        _selectedPlaylistIds.clear();
        _selectedSongPaths.clear();
        _lastAlbumAnchorIndex = null;
        _lastArtistAnchorIndex = null;
        _lastPlaylistAnchorIndex = null;
        _lastSongAnchorIndex = null;
      });
      _updateSelectionScope(false);
    }
  }

  void _setAlbumSelection(Set<String> keys) {
    setState(() {
      _selectedArtistIds.clear();
      _selectedPlaylistIds.clear();
      _selectedSongPaths.clear();
      _selectedAlbumIds
        ..clear()
        ..addAll(keys);
    });
    _updateSelectionScope();
  }

  void _setArtistSelection(Set<String> keys) {
    setState(() {
      _selectedAlbumIds.clear();
      _selectedPlaylistIds.clear();
      _selectedSongPaths.clear();
      _selectedArtistIds
        ..clear()
        ..addAll(keys);
    });
    _updateSelectionScope();
  }

  void _setPlaylistSelection(Set<String> keys) {
    setState(() {
      _selectedAlbumIds.clear();
      _selectedArtistIds.clear();
      _selectedSongPaths.clear();
      _selectedPlaylistIds
        ..clear()
        ..addAll(keys);
    });
    _updateSelectionScope();
  }

  void _setSongSelection(Set<String> keys) {
    setState(() {
      _selectedAlbumIds.clear();
      _selectedArtistIds.clear();
      _selectedPlaylistIds.clear();
      _selectedSongPaths
        ..clear()
        ..addAll(keys);
    });
    _updateSelectionScope();
  }

  void _toggleAlbumSelection(String albumId) {
    setState(() {
      _selectedArtistIds.clear();
      _selectedPlaylistIds.clear();
      _selectedSongPaths.clear();
      if (_selectedAlbumIds.contains(albumId)) {
        _selectedAlbumIds.remove(albumId);
      } else {
        _selectedAlbumIds.add(albumId);
      }
    });
    _updateSelectionScope();
  }

  void _toggleSelectAllAlbums(List<Map<String, dynamic>> filteredAlbums) {
    final allIds = filteredAlbums
        .map((a) => a['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    setState(() {
      _selectedArtistIds.clear();
      _selectedPlaylistIds.clear();
      _selectedSongPaths.clear();
      if (_selectedAlbumIds.length == allIds.length && allIds.isNotEmpty) {
        _selectedAlbumIds.clear();
      } else {
        _selectedAlbumIds.clear();
        _selectedAlbumIds.addAll(allIds);
      }
    });
    _updateSelectionScope();
  }

  void _toggleArtistSelection(String artistId) {
    setState(() {
      _selectedAlbumIds.clear();
      _selectedPlaylistIds.clear();
      _selectedSongPaths.clear();
      if (_selectedArtistIds.contains(artistId)) {
        _selectedArtistIds.remove(artistId);
      } else {
        _selectedArtistIds.add(artistId);
      }
    });
    _updateSelectionScope();
  }

  void _toggleSelectAllArtists(List<Map<String, dynamic>> filteredArtists) {
    final allIds = filteredArtists
        .map((a) => a['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    setState(() {
      _selectedAlbumIds.clear();
      _selectedPlaylistIds.clear();
      _selectedSongPaths.clear();
      if (_selectedArtistIds.length == allIds.length && allIds.isNotEmpty) {
        _selectedArtistIds.clear();
      } else {
        _selectedArtistIds.clear();
        _selectedArtistIds.addAll(allIds);
      }
    });
    _updateSelectionScope();
  }

  void _togglePlaylistSelection(String playlistId) {
    setState(() {
      _selectedAlbumIds.clear();
      _selectedArtistIds.clear();
      _selectedSongPaths.clear();
      if (_selectedPlaylistIds.contains(playlistId)) {
        _selectedPlaylistIds.remove(playlistId);
      } else {
        _selectedPlaylistIds.add(playlistId);
      }
    });
    _updateSelectionScope();
  }

  void _toggleSelectAllPlaylists(List<Map<String, dynamic>> filteredPlaylists) {
    final allIds = filteredPlaylists
        .map((p) => p['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    setState(() {
      _selectedAlbumIds.clear();
      _selectedArtistIds.clear();
      _selectedSongPaths.clear();
      if (_selectedPlaylistIds.length == allIds.length && allIds.isNotEmpty) {
        _selectedPlaylistIds.clear();
      } else {
        _selectedPlaylistIds.clear();
        _selectedPlaylistIds.addAll(allIds);
      }
    });
    _updateSelectionScope();
  }

  void _toggleSongSelection(String songPath) {
    setState(() {
      _selectedAlbumIds.clear();
      _selectedArtistIds.clear();
      _selectedPlaylistIds.clear();
      if (_selectedSongPaths.contains(songPath)) {
        _selectedSongPaths.remove(songPath);
      } else {
        _selectedSongPaths.add(songPath);
      }
    });
    _updateSelectionScope();
  }

  void _toggleSelectAllSongs(List<MusicFile> songs) {
    final allPaths = songs.map((s) => s.path).toSet();
    setState(() {
      _selectedAlbumIds.clear();
      _selectedArtistIds.clear();
      _selectedPlaylistIds.clear();
      if (_selectedSongPaths.length == allPaths.length && allPaths.isNotEmpty) {
        _selectedSongPaths.clear();
      } else {
        _selectedSongPaths.clear();
        _selectedSongPaths.addAll(allPaths);
      }
    });
    _updateSelectionScope();
  }

  /// 勾选下载的曲目批次：按「勾的是哪个栏目」分组，保证落盘结构与同一 Tab
  /// 里的单曲下载一致 ——
  /// 专辑 Tab → `专辑/曲目`；艺术家 Tab → 各 `艺术家/专辑/曲目`；
  /// 歌单 Tab → 各 `歌单/曲目`；歌曲 Tab → `专辑/曲目`；
  /// 搜索 Tab → 勾艺术家走艺术家，勾专辑 / 歌曲走专辑。
  Future<List<RemoteDownloadBatch>> _fetchSelectedDownloadBatches() {
    final songsSource = _currentTabIndex == _kSearchTabIndex ? _searchedSongs : _songs;
    return RemoteLibrarySelectionActions.fetchSelectedBatches(
      server: widget.server,
      password: widget.password,
      isAlbumSelectionMode: _isAlbumSelectionMode,
      isArtistSelectionMode: _isArtistSelectionMode,
      isPlaylistSelectionMode: _isPlaylistSelectionMode,
      isSongSelectionMode: _isSongSelectionMode,
      selectedAlbumIds: _selectedAlbumIds,
      selectedArtistIds: _selectedArtistIds,
      selectedPlaylistIds: _selectedPlaylistIds,
      selectedSongPaths: _selectedSongPaths,
      searchedSongs: songsSource,
      songs: songsSource,
      // 专辑列表项自带 songCount，多选下载时用它当加载进度的分母。
      albumSongCounts: {
        for (final album in _albums)
          if (album['id'] != null)
            album['id'].toString(): album['songCount'] is int
                ? album['songCount'] as int
                : 0,
      },
      // 每个勾选的集合都要带上自己的目录名，多个艺术家 / 歌单才不会挤进同一层。
      artistNames: {
        for (final artist in [..._artists, ..._searchedArtists])
          if (artist['id'] != null && artist['name'] != null)
            artist['id'].toString(): artist['name'] as String,
      },
      playlistNames: {
        for (final playlist in _playlists)
          if (playlist['id'] != null && playlist['name'] != null)
            playlist['id'].toString(): playlist['name'] as String,
      },
    );
  }

  Future<List<MusicFile>> _fetchSelectedSongs() async {
    final batches = await _fetchSelectedDownloadBatches();
    return [for (final batch in batches) ...batch.songs];
  }

  List<MusicFile> _getFilteredSongs() {
    final sig = Object.hash(
      identityHashCode(_songs),
      _songs.length,
      _songSearchQuery,
      _songSortField,
      _songSortAsc,
      _songStarredOnly,
      _songStarredOnly ? Object.hashAll(_starredSongIds) : 0,
    );
    final cached = _cachedFilteredSongs;
    if (cached != null && sig == _cachedFilteredSongsSig) return cached;
    final result = _computeFilteredSongs();
    _cachedFilteredSongsSig = sig;
    return _cachedFilteredSongs = result;
  }

  List<MusicFile> _computeFilteredSongs() {
    var result = _songs.where((song) {
      if (_songSearchQuery.isEmpty) return true;
      final q = _songSearchQuery.toLowerCase();
      final title = (song.title ?? song.name).toLowerCase();
      final artist = (song.artist ?? '').toLowerCase();
      final album = (song.album ?? '').toLowerCase();
      return title.contains(q) || artist.contains(q) || album.contains(q);
    }).toList();

    if (_songStarredOnly) {
      result = result.where((song) {
        final trackId = RemoteMediaResolver.extractTrackId(song) ??
            (song.id != null && song.id! > 0 ? song.id.toString() : '');
        return _starredSongIds.contains(trackId);
      }).toList();
    }

    result.sort((a, b) {
      int cmp = 0;
      switch (_songSortField) {
        case 'artist':
          cmp = (a.artist ?? '').compareTo(b.artist ?? '');
          if (cmp == 0) {
            cmp = (a.title ?? a.name).compareTo(b.title ?? b.name);
          }
          break;
        case 'album':
          cmp = (a.album ?? '').compareTo(b.album ?? '');
          if (cmp == 0) {
            cmp = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
          }
          break;
        case 'duration':
          cmp = (a.durationMillis ?? 0).compareTo(b.durationMillis ?? 0);
          break;
        case 'title':
        default:
          cmp = (a.title ?? a.name).compareTo(b.title ?? b.name);
          break;
      }
      return _songSortAsc ? cmp : -cmp;
    });

    return result;
  }

  List<Map<String, dynamic>> _getFilteredAlbums() {
    final sig = Object.hash(
      identityHashCode(_albums),
      _albums.length,
      _albumSearchQuery,
      _albumStarredOnly,
      _albumStarredOnly ? Object.hashAll(_starredAlbumIds) : 0,
    );
    final cached = _cachedFilteredAlbums;
    if (cached != null && sig == _cachedFilteredAlbumsSig) return cached;
    final result = _computeFilteredAlbums();
    _cachedFilteredAlbumsSig = sig;
    return _cachedFilteredAlbums = result;
  }

  List<Map<String, dynamic>> _computeFilteredAlbums() {
    var result = _albums.where((album) {
      if (_albumSearchQuery.isEmpty) return true;
      final q = _albumSearchQuery.toLowerCase();
      final title = (album['title'] as String? ?? album['name'] as String? ?? '')
          .toLowerCase();
      final artist = (album['artist'] as String? ?? '').toLowerCase();
      return title.contains(q) || artist.contains(q);
    }).toList();

    // 「只看收藏」和歌曲 / 艺术家一致：在已加载列表上本地过滤，
    // 不额外发请求，排序继续保持生效。
    if (_albumStarredOnly) {
      result = result
          .where((a) => _starredAlbumIds.contains(a['id']?.toString()))
          .toList();
    }
    return result;
  }

  Future<void> _fetchStarredAlbums() async {
    try {
      final starredList = await _client.getStarredAlbums();
      final ids = starredList
          .map((e) => e['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (!mounted) return;
      setState(() {
        _starredAlbumIds
          ..clear()
          ..addAll(ids);
      });
    } catch (_) {}
  }

  String _artistSortName(Map<String, dynamic> artist) =>
      (artist['name'] as String? ?? '').toLowerCase();

  List<Map<String, dynamic>> _getFilteredArtists() {
    final sig = Object.hash(
      identityHashCode(_artists),
      _artists.length,
      _artistSearchQuery,
      _artistSortField,
      _artistSortAsc,
      _artistStarredOnly,
      _artistStarredOnly ? Object.hashAll(_starredArtistIds) : 0,
    );
    final cached = _cachedFilteredArtists;
    if (cached != null && sig == _cachedFilteredArtistsSig) return cached;
    final result = _computeFilteredArtists();
    _cachedFilteredArtistsSig = sig;
    return _cachedFilteredArtists = result;
  }

  List<Map<String, dynamic>> _computeFilteredArtists() {
    var result = _artists.where((artist) {
      if (_artistSearchQuery.isEmpty) return true;
      final q = _artistSearchQuery.toLowerCase();
      final name = (artist['name'] as String? ?? '').toLowerCase();
      return name.contains(q);
    }).toList();
    if (_artistStarredOnly) {
      result =
          result.where((a) => _starredArtistIds.contains(a['id'])).toList();
    }

    result.sort((a, b) {
      int cmp;
      if (_artistSortField == 'albumCount') {
        cmp = ((a['albumCount'] as num?)?.toInt() ?? 0)
            .compareTo((b['albumCount'] as num?)?.toInt() ?? 0);
      } else {
        cmp = _artistSortName(a).compareTo(_artistSortName(b));
      }
      // 同专辑数时按名字升序兜底，保证顺序稳定
      if (cmp == 0) {
        cmp = _artistSortName(a).compareTo(_artistSortName(b));
      }
      return _artistSortAsc ? cmp : -cmp;
    });
    return result;
  }

  List<Map<String, dynamic>> _getFilteredPlaylists() {
    final session = ref.read(activeRemoteSessionProvider);
    final sig = Object.hash(
      identityHashCode(_playlists),
      _playlists.length,
      _playlistSearchQuery,
      identityHashCode(session),
      identityHashCode(session?.navidromePlaylists),
      session?.navidromePlaylists?.length,
      session?.navidromeStarredSongIds?.length,
      _starredSongIds.length,
      AppLocalizations.of(context)!.starredSongs,
    );
    final cached = _cachedFilteredPlaylists;
    if (cached != null && sig == _cachedFilteredPlaylistsSig) return cached;
    final result = _computeFilteredPlaylists();
    _cachedFilteredPlaylistsSig = sig;
    return _cachedFilteredPlaylists = result;
  }

  List<Map<String, dynamic>> _computeFilteredPlaylists() {
    final l10n = AppLocalizations.of(context)!;
    final session = ref.read(activeRemoteSessionProvider);
    final isCurrentServer =
        session != null && session.server.id == widget.server.id;

    final starredCount = isCurrentServer
        ? (session.navidromeStarredSongIds?.length ?? _starredSongIds.length)
        : _starredSongIds.length;

    final sourcePlaylists =
        (isCurrentServer && session.navidromePlaylists != null)
            ? session.navidromePlaylists!
            : _playlists;

    final allPlaylists = <Map<String, dynamic>>[
      {
        'id': _starredPlaylistId,
        'name': l10n.starredSongs,
        'songCount': starredCount,
        'duration': 0,
        'coverArt': null,
        'isStarred': true,
      },
      ...sourcePlaylists,
    ];
    return allPlaylists.where((pl) {
      if (_playlistSearchQuery.isEmpty) return true;
      final q = _playlistSearchQuery.toLowerCase();
      final name = (pl['name'] as String? ?? '').toLowerCase();
      return name.contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    // 页面可能在「深链请求」之后才被构建（切 tab 才建），`ref.listen` 只响应
    // 后续变化，首帧要自己补一次消费。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(remoteLibraryPendingDetailProvider);
      if (pending != null) _openPendingDetail(pending);
    });
    _client = RemoteMediaLibraryClient.create(
      server: widget.server,
      password: widget.password,
    );
    final session = ref.read(activeRemoteSessionProvider);
    final isSameServer =
        session != null && session.server.id == widget.server.id;
    if (isSameServer && session.navidromeSearchQuery != null) {
      _searchController.text = session.navidromeSearchQuery!;
      _searchedSongs =
          List<MusicFile>.from(session.navidromeSearchedSongs ?? const []);
      _searchedAlbums = List<Map<String, dynamic>>.from(
        session.navidromeSearchedAlbums ?? const [],
      );
      _searchedArtists = List<Map<String, dynamic>>.from(
        session.navidromeSearchedArtists ?? const [],
      );
    }
    if (isSameServer && session.navidromePlaylistSearchQuery != null) {
      _playlistSearchQuery = session.navidromePlaylistSearchQuery!;
      _playlistSearchController.text = session.navidromePlaylistSearchQuery!;
    }
    final settings = ref.read(settingsServiceProvider);
    _albumSortType = settings.navidromeAlbumSortType;
    // 「已收藏」已从排序项独立成开关：历史值归一到默认排序，
    // 否则仍会按 starred 类型向服务端请求整份收藏列表。
    if (_albumSortType == 'starred') {
      _albumSortType = 'alphabeticalByName';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(settingsServiceProvider).navidromeAlbumSortType =
            'alphabeticalByName';
      });
    }
    _artistSortField = settings.navidromeArtistSortField;
    _artistSortAsc = settings.navidromeArtistSortAscending;
    _songSortField = settings.navidromeSongSortField;
    _songSortAsc = settings.navidromeSongSortAscending;
    _playlistSortField = remotePlaylistSortFieldFromStorage(
      settings.remotePlaylistSortField,
    );
    _playlistSortAscending = settings.remotePlaylistSortAscending;
    _scheduleInitialLoads();
  }

  /// 首屏优先拉当前 tab，其余分类在首帧后错峰补齐：五路同时发请求 +
  /// 同时解析 JSON 是竖屏首屏掉帧的主因。各分类本身都有 session / 本地
  /// 缓存兜底，这里只削平并发峰值，不改变「所有分类最终都可用」的语义
  /// （搜索 tab 的多选、收藏歌单计数等仍依赖跨 tab 数据）。
  void _scheduleInitialLoads() {
    final loaders = <void Function()>[
      () {
        _loadAlbums();
      },
      () {
        _loadArtists();
      },
      () {
        _loadGenres();
      },
      () {
        _loadSongs();
      },
      () {
        _loadPlaylists();
      },
      () {
        _loadDashboardInsights();
      },
    ];
    // 首批加载哪个分类：跟随当前二级分类（深链进来时可能不是专辑）。
    final int initialIndex =
        (ref.read(remoteLibraryActiveTabIndexProvider) ?? 0).clamp(0, 5);
    final firstIndex = initialIndex < loaders.length ? initialIndex : 0;
    loaders.removeAt(firstIndex)();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        for (final loader in loaders) {
          loader();
        }
      }));
    });
  }

  @override
  void didUpdateWidget(covariant RemoteLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 一级 tab 用 GlobalKey 稳定持有 State（返回键分发要它），所以换服务器时
    // 不会自动重建 —— 必须自己把 client 与五个 loader 的数据一起换掉，
    // 否则会拿着上一台服务器的 client 继续拉，页面显示混合数据。
    if (oldWidget.server.id == widget.server.id &&
        oldWidget.password == widget.password) {
      return;
    }
    _client = RemoteMediaLibraryClient.create(
      server: widget.server,
      password: widget.password,
    );
    setState(() {
      _albums = [];
      _artists = [];
      _genres = [];
      _songs = [];
      _playlists = [];
      _recentPlayedAlbums = [];
      _mostPlayedAlbums = [];
      _starredAlbumIds.clear();
      _starredArtistIds.clear();
      _starredSongIds.clear();
      _albumsError = null;
      _artistsError = null;
      _genresError = null;
      _songsError = null;
      _connectionError = null;
      _songOffset = 0;
      _hasMoreSongs = true;
    });
    _scheduleInitialLoads();
  }

  void _beginContentReload() {
    if (!mounted || _isReloadingContent) return;
    setState(() {
      _isReloadingContent = true;
    });
  }

  void _endContentReload() {
    if (!mounted || !_isReloadingContent) return;
    setState(() {
      _isReloadingContent = false;
    });
  }

  LibrarySelectionScopeController? _selectionScopeController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectionScopeController =
        ref.read(librarySelectionScopeProvider.notifier);
  }

  @override
  void dispose() {
    if (_isSelectionMode) {
      final controller = _selectionScopeController;
      Future.microtask(() {
        controller?.clear();
      });
    }
    _albumSearchController.dispose();
    _albumSearchFocusNode.dispose();
    _artistSearchController.dispose();
    _artistSearchFocusNode.dispose();
    _songSearchController.dispose();
    _songSearchFocusNode.dispose();
    _playlistSearchController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  bool _isMapListEqual(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b, [
    String idKey = 'id',
  ]) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i][idKey]?.toString() != b[i][idKey]?.toString()) return false;
      if (a[i]['title'] != b[i]['title'] ||
          a[i]['name'] != b[i]['name'] ||
          a[i]['starred'] != b[i]['starred'] ||
          a[i]['isFavorite'] != b[i]['isFavorite'] ||
          a[i]['songCount'] != b[i]['songCount']) {
        return false;
      }
    }
    return true;
  }

  bool _isSongListEqual(List<MusicFile> a, List<MusicFile> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path ||
          a[i].title != b[i].title ||
          a[i].artist != b[i].artist) {
        return false;
      }
    }
    return true;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  bool _isRevalidatingAlbums = false;

  Future<void> _revalidateAlbums() async {
    if (_isRevalidatingAlbums || !mounted) return;
    _isRevalidatingAlbums = true;
    try {
      final list = await _client.getAlbumList(type: _albumSortType, size: 500);
      if (!mounted) return;
      if (!_isMapListEqual(_albums, list)) {
        setState(() {
          _albums = list;
        });
      }
      final session = ref.read(activeRemoteSessionProvider);
      if (session != null && session.server.id == widget.server.id) {
        ref.read(activeRemoteSessionProvider.notifier).updateNavidromeAlbums(
              list,
              sortType: _albumSortType,
            );
      }
      unawaited(MetadataDatabase().saveRemoteLibraryCache(
        serverId: widget.server.id,
        category: 'albums_$_albumSortType',
        dataJson: jsonEncode(list),
        count: list.length,
      ));
    } catch (_) {
    } finally {
      _isRevalidatingAlbums = false;
    }
  }

  /// 拉取远程流派列表（Jellyfin 走 `/Genres`，Subsonic 走 `getGenres`）。
  ///
  /// 流派数据量小、变化少，这里不做本地落盘缓存，
  /// 只在页面初始化与手动刷新时请求一次。
  Future<void> _loadGenres({bool forceRefresh = false}) async {
    if (_isLoadingGenres) return;
    setState(() {
      _isLoadingGenres = true;
      _genresError = null;
    });
    try {
      final list = await _client.getGenres();
      if (!mounted) return;
      setState(() {
        _genres = list;
        _isLoadingGenres = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _genresError = e.toString();
        _isLoadingGenres = false;
      });
    }
  }

  Future<void> _loadAlbums({bool forceRefresh = false}) async {
    final session = ref.read(activeRemoteSessionProvider);
    final isSameServer =
        session != null && session.server.id == widget.server.id;

    if (!forceRefresh &&
        isSameServer &&
        session.navidromeAlbums != null &&
        session.navidromeAlbumSortType == _albumSortType) {
      setState(() {
        _albums = session.navidromeAlbums!;
        _isLoadingAlbums = false;
        _albumsError = null;
        _connectionError = null;
      });
      _revalidateAlbums();
      return;
    }

    if (!forceRefresh && _albums.isEmpty) {
      try {
        final cache = await MetadataDatabase().getRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'albums_$_albumSortType',
        );
        if (cache != null && mounted) {
          final list = (jsonDecode(cache.dataJson) as List)
              .cast<Map<String, dynamic>>();
          if (list.isNotEmpty) {
            setState(() {
              _albums = list;
              _isLoadingAlbums = false;
              _albumsError = null;
              _connectionError = null;
            });
            _revalidateAlbums();
            return;
          }
        }
      } catch (_) {}
    }

    setState(() {
      _isLoadingAlbums = true;
      _albumsError = null;
    });
    try {
      final list = await _client.getAlbumList(type: _albumSortType, size: 500);
      if (!mounted) return;
      setState(() {
        _albums = list;
        _isLoadingAlbums = false;
        _connectionError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(activeRemoteSessionProvider.notifier).updateNavidromeAlbums(
              list,
              sortType: _albumSortType,
            );
      });
      unawaited(MetadataDatabase().saveRemoteLibraryCache(
        serverId: widget.server.id,
        category: 'albums_$_albumSortType',
        dataJson: jsonEncode(list),
        count: list.length,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _albumsError = e.toString();
        _isLoadingAlbums = false;
        if (_albums.isEmpty) {
          _connectionError = e.toString();
        }
      });
    }
  }

  bool _isRevalidatingArtists = false;

  Future<void> _revalidateArtists() async {
    if (_isRevalidatingArtists || !mounted) return;
    _isRevalidatingArtists = true;
    try {
      final list = await _client.getArtists();
      if (!mounted) return;
      final preStarred = list
          .where((a) => a['isFavorite'] == true || a['starred'] != null)
          .map((a) => a['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty);

      if (!_isMapListEqual(_artists, list)) {
        setState(() {
          _artists = list;
          _starredArtistIds.addAll(preStarred);
          if (_selectedArtistId == null && list.isNotEmpty) {
            _selectedArtistId = list.first['id'] as String?;
          }
        });
      }
      final session = ref.read(activeRemoteSessionProvider);
      if (session != null && session.server.id == widget.server.id) {
        ref.read(activeRemoteSessionProvider.notifier).updateNavidromeArtists(
              artists: list,
              selectedArtistId: _selectedArtistId,
            );
      }
      unawaited(MetadataDatabase().saveRemoteLibraryCache(
        serverId: widget.server.id,
        category: 'artists',
        dataJson: jsonEncode(list),
        count: list.length,
      ));
      _fetchStarredArtists();
    } catch (_) {
    } finally {
      _isRevalidatingArtists = false;
    }
  }

  Future<void> _loadArtists({bool forceRefresh = false}) async {
    final session = ref.read(activeRemoteSessionProvider);
    final isSameServer =
        session != null && session.server.id == widget.server.id;

    if (!forceRefresh && isSameServer && session.navidromeArtists != null) {
      setState(() {
        _artists = session.navidromeArtists!;
        _starredArtistIds
          ..clear()
          ..addAll(session.navidromeStarredArtistIds ?? {});
        _selectedArtistId = session.navidromeSelectedArtistId ??
            (_artists.isNotEmpty ? _artists.first['id'] as String? : null);
        _isLoadingArtists = false;
        _artistsError = null;
        _connectionError = null;
      });
      _revalidateArtists();
      return;
    }

    if (!forceRefresh && _artists.isEmpty) {
      try {
        final cache = await MetadataDatabase().getRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'artists',
        );
        if (cache != null && mounted) {
          final list = (jsonDecode(cache.dataJson) as List)
              .cast<Map<String, dynamic>>();
          final starredCache = await MetadataDatabase().getRemoteLibraryCache(
            serverId: widget.server.id,
            category: 'artists_starred',
          );
          final starredSet = starredCache != null
              ? (jsonDecode(starredCache.dataJson) as List).cast<String>().toSet()
              : <String>{};

          if (list.isNotEmpty) {
            setState(() {
              _artists = list;
              _starredArtistIds
                ..clear()
                ..addAll(starredSet);
              _selectedArtistId ??= list.first['id'] as String?;
              _isLoadingArtists = false;
              _artistsError = null;
              _connectionError = null;
            });
            _revalidateArtists();
            return;
          }
        }
      } catch (_) {}
    }

    setState(() {
      _isLoadingArtists = true;
      _artistsError = null;
    });
    try {
      final list = await _client.getArtists();
      if (!mounted) return;
      final preStarred = list
          .where((a) => a['isFavorite'] == true || a['starred'] != null)
          .map((a) => a['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty);
      setState(() {
        _artists = list;
        _starredArtistIds.addAll(preStarred);
        _isLoadingArtists = false;
        _connectionError = null;
        if (_selectedArtistId == null && list.isNotEmpty) {
          _selectedArtistId = list.first['id'] as String?;
        }
      });
      _fetchStarredArtists();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(activeRemoteSessionProvider.notifier).updateNavidromeArtists(
              artists: list,
              selectedArtistId: _selectedArtistId,
            );
      });
      unawaited(MetadataDatabase().saveRemoteLibraryCache(
        serverId: widget.server.id,
        category: 'artists',
        dataJson: jsonEncode(list),
        count: list.length,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _artistsError = e.toString();
        _isLoadingArtists = false;
        if (_albums.isEmpty && _artists.isEmpty) {
          _connectionError ??= e.toString();
        }
      });
    }
  }

  Future<void> _fetchStarredArtists() async {
    try {
      final starredList = await _client.getStarredArtists();
      final ids = starredList
          .map((e) => e['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (mounted) {
        setState(() {
          _starredArtistIds
            ..clear()
            ..addAll(ids);
        });
        ref.read(activeRemoteSessionProvider.notifier).updateNavidromeArtists(
              starredArtistIds: _starredArtistIds,
            );
        unawaited(MetadataDatabase().saveRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'artists_starred',
          dataJson: jsonEncode(_starredArtistIds.toList()),
        ));
      }
    } catch (_) {}
  }

  bool _isRevalidatingSongs = false;

  Future<void> _revalidateSongs() async {
    if (_isRevalidatingSongs || !mounted) return;
    _isRevalidatingSongs = true;
    try {
      final rawSongs = await _client.getSongs(
        count: 500,
        offset: 0,
      );
      if (!mounted) return;
      final newParsedSongs = <MusicFile>[];
      final newStarred = <String>{};
      for (final raw in rawSongs) {
        final song = _client.buildMusicFile(raw);
        newParsedSongs.add(song);
        if (raw['starred'] != null) {
          final id = raw['id']?.toString() ?? song.id.toString();
          newStarred.add(id);
        }
      }

      final currentFirstPage = _songs.take(newParsedSongs.length).toList();
      final songsChanged = !_isSongListEqual(currentFirstPage, newParsedSongs);
      final starredChanged = !_setEquals(_starredSongIds, newStarred);

      if (songsChanged || starredChanged) {
        setState(() {
          if (_songs.length > newParsedSongs.length) {
            _songs = [...newParsedSongs, ..._songs.skip(newParsedSongs.length)];
          } else {
            _songs = newParsedSongs;
          }
          _starredSongIds.addAll(newStarred);
        });

        ref.read(activeRemoteSessionProvider.notifier).updateNavidromeSongs(
              songs: _songs,
              starredSongIds: _starredSongIds,
              hasMore: _hasMoreSongs,
              songOffset: _songOffset,
            );
      }

      unawaited(MetadataDatabase().saveRemoteLibraryCache(
        serverId: widget.server.id,
        category: 'songs',
        dataJson: jsonEncode(rawSongs),
        count: rawSongs.length,
      ));
      unawaited(MetadataDatabase().saveRemoteLibraryCache(
        serverId: widget.server.id,
        category: 'songs_starred',
        dataJson: jsonEncode(newStarred.toList()),
      ));
      _fetchStarredSongs();
    } catch (_) {
    } finally {
      _isRevalidatingSongs = false;
    }
  }

  Future<void> _loadSongs({bool forceRefresh = false, bool loadMore = false}) async {
    final session = ref.read(activeRemoteSessionProvider);
    final isSameServer =
        session != null && session.server.id == widget.server.id;

    if (!forceRefresh && !loadMore && isSameServer && session.navidromeSongs != null) {
      setState(() {
        _songs = session.navidromeSongs!;
        _starredSongIds
          ..clear()
          ..addAll(session.navidromeStarredSongIds ?? {});
        _hasMoreSongs = session.navidromeHasMoreSongs ?? false;
        _songOffset = session.navidromeSongOffset ?? _songs.length;
        _isLoadingSongs = false;
        _songsError = null;
        _connectionError = null;
      });
      _revalidateSongs();
      return;
    }

    if (!forceRefresh && !loadMore && _songs.isEmpty) {
      try {
        final cache = await MetadataDatabase().getRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'songs',
        );
        if (cache != null && mounted) {
          final rawSongs = (jsonDecode(cache.dataJson) as List)
              .cast<Map<String, dynamic>>();
          final starredCache = await MetadataDatabase().getRemoteLibraryCache(
            serverId: widget.server.id,
            category: 'songs_starred',
          );
          final starredSet = starredCache != null
              ? (jsonDecode(starredCache.dataJson) as List).cast<String>().toSet()
              : <String>{};

          if (rawSongs.isNotEmpty) {
            final parsedSongs = <MusicFile>[];
            for (final raw in rawSongs) {
              final song = _client.buildMusicFile(raw);
              parsedSongs.add(song);
              if (raw['starred'] != null) {
                final id = raw['id']?.toString() ?? song.id.toString();
                starredSet.add(id);
              }
            }
            setState(() {
              _songs = parsedSongs;
              _starredSongIds
                ..clear()
                ..addAll(starredSet);
              _songOffset = parsedSongs.length;
              _hasMoreSongs = true;
              _isLoadingSongs = false;
              _songsError = null;
              _connectionError = null;
            });
            _revalidateSongs();
            return;
          }
        }
      } catch (_) {}
    }

    if (loadMore) {
      if (_isLoadingMoreSongs || !_hasMoreSongs) return;
      setState(() {
        _isLoadingMoreSongs = true;
      });
    } else {
      setState(() {
        _isLoadingSongs = true;
        _songsError = null;
        if (forceRefresh) {
          _songOffset = 0;
        }
      });
    }

    final targetOffset = loadMore ? _songOffset : 0;
    const pageSize = 500;

    try {
      final rawSongs = await _client.getSongs(
        count: pageSize,
        offset: targetOffset,
      );

      final newParsedSongs = <MusicFile>[];
      final newStarred = <String>{};
      for (final raw in rawSongs) {
        final song = _client.buildMusicFile(raw);
        newParsedSongs.add(song);
        if (raw['starred'] != null) {
          final id = raw['id']?.toString() ?? song.id.toString();
          newStarred.add(id);
        }
      }

      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _songs = [..._songs, ...newParsedSongs];
          _songOffset += newParsedSongs.length;
          _isLoadingMoreSongs = false;
        } else {
          _songs = newParsedSongs;
          _songOffset = newParsedSongs.length;
          _isLoadingSongs = false;
        }
        _starredSongIds.addAll(newStarred);
        _hasMoreSongs = newParsedSongs.length >= pageSize;
        _connectionError = null;
      });

      _fetchStarredSongs();

      if (!loadMore) {
        unawaited(MetadataDatabase().saveRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'songs',
          dataJson: jsonEncode(rawSongs),
          count: rawSongs.length,
        ));
        unawaited(MetadataDatabase().saveRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'songs_starred',
          dataJson: jsonEncode(_starredSongIds.toList()),
        ));
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(activeRemoteSessionProvider.notifier).updateNavidromeSongs(
              songs: _songs,
              starredSongIds: _starredSongIds,
              hasMore: _hasMoreSongs,
              songOffset: _songOffset,
            );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _songsError = e.toString();
        _isLoadingSongs = false;
        _isLoadingMoreSongs = false;
        if (_albums.isEmpty && _artists.isEmpty && _songs.isEmpty) {
          _connectionError ??= e.toString();
        }
      });
    }
  }

  Future<void> _fetchStarredSongs() async {
    try {
      final starredList = await _client.getStarredSongs();
      final ids = starredList
          .map((e) => e['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (mounted && ids.isNotEmpty) {
        setState(() {
          _starredSongIds.addAll(ids);
        });
        ref.read(activeRemoteSessionProvider.notifier).updateNavidromeSongs(
              starredSongIds: _starredSongIds,
            );
        unawaited(MetadataDatabase().saveRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'songs_starred',
          dataJson: jsonEncode(_starredSongIds.toList()),
        ));
      }
    } catch (_) {}
  }

  Future<void> _toggleSongStar(MusicFile song) async {
    final trackId = RemoteMediaResolver.extractTrackId(song) ??
        (song.id != null && song.id! > 0 ? song.id.toString() : '');
    if (trackId.isEmpty) return;

    final isCurrentlyStarred = _starredSongIds.contains(trackId);
    setState(() {
      if (isCurrentlyStarred) {
        _starredSongIds.remove(trackId);
      } else {
        _starredSongIds.add(trackId);
      }
    });

    ref.read(activeRemoteSessionProvider.notifier).updateNavidromeSongs(
          starredSongIds: _starredSongIds,
        );
    unawaited(MetadataDatabase().saveRemoteLibraryCache(
      serverId: widget.server.id,
      category: 'songs_starred',
      dataJson: jsonEncode(_starredSongIds.toList()),
    ));

    final success = isCurrentlyStarred
        ? await _client.unstar(id: trackId)
        : await _client.star(id: trackId);

    if (!success && mounted) {
      setState(() {
        if (isCurrentlyStarred) {
          _starredSongIds.add(trackId);
        } else {
          _starredSongIds.remove(trackId);
        }
      });
      ref.read(activeRemoteSessionProvider.notifier).updateNavidromeSongs(
            starredSongIds: _starredSongIds,
          );
      unawaited(MetadataDatabase().saveRemoteLibraryCache(
        serverId: widget.server.id,
        category: 'songs_starred',
        dataJson: jsonEncode(_starredSongIds.toList()),
      ));
    }
  }

  bool _isRevalidatingPlaylists = false;

  Future<void> _revalidatePlaylists() async {
    if (_isRevalidatingPlaylists || !mounted) return;
    _isRevalidatingPlaylists = true;
    try {
      final list = await _client.getPlaylists();
      if (!mounted) return;
      if (!_isPlaylistSelectionMode && !_isMapListEqual(_playlists, list)) {
        setState(() {
          _playlists = list;
        });
      }
      final session = ref.read(activeRemoteSessionProvider);
      if (session != null && session.server.id == widget.server.id) {
        ref
            .read(activeRemoteSessionProvider.notifier)
            .updateNavidromePlaylists(
              playlists: list,
              selectedPlaylistId: _selectedPlaylistId,
            );
      }
      unawaited(MetadataDatabase().saveRemoteLibraryCache(
        serverId: widget.server.id,
        category: 'playlists',
        dataJson: jsonEncode(list),
        count: list.length,
      ));
    } catch (_) {
      // Ignore background revalidation error
    } finally {
      _isRevalidatingPlaylists = false;
    }
  }

  Future<void> _loadPlaylists({bool forceRefresh = false}) async {
    final session = ref.read(activeRemoteSessionProvider);
    final isSameServer =
        session != null && session.server.id == widget.server.id;

    if (!forceRefresh && isSameServer && session.navidromePlaylists != null) {
      setState(() {
        _playlists = session.navidromePlaylists!;
        _selectedPlaylistId =
            session.navidromeSelectedPlaylistId ?? _starredPlaylistId;
        _isLoadingPlaylists = false;
        _playlistsError = null;
        _connectionError = null;
      });
      _revalidatePlaylists();
      return;
    }

    if (!forceRefresh && _playlists.isEmpty) {
      try {
        final cache = await MetadataDatabase().getRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'playlists',
        );
        if (cache != null && mounted) {
          final list = (jsonDecode(cache.dataJson) as List)
              .cast<Map<String, dynamic>>();
          if (list.isNotEmpty) {
            setState(() {
              _playlists = list;
              _selectedPlaylistId ??= _starredPlaylistId;
              _isLoadingPlaylists = false;
              _playlistsError = null;
              _connectionError = null;
            });
            _revalidatePlaylists();
            return;
          }
        }
      } catch (_) {}
    }

    setState(() {
      _isLoadingPlaylists = true;
      _playlistsError = null;
    });
    try {
      final list = await _client.getPlaylists();
      if (!mounted) return;
      setState(() {
        _playlists = list;
        _isLoadingPlaylists = false;
        _connectionError = null;
        _selectedPlaylistId ??= _starredPlaylistId;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(activeRemoteSessionProvider.notifier)
            .updateNavidromePlaylists(
              playlists: list,
              selectedPlaylistId: _selectedPlaylistId,
            );
      });
      unawaited(MetadataDatabase().saveRemoteLibraryCache(
        serverId: widget.server.id,
        category: 'playlists',
        dataJson: jsonEncode(list),
        count: list.length,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playlistsError = e.toString();
        _isLoadingPlaylists = false;
        if (_albums.isEmpty && _playlists.isEmpty) {
          _connectionError ??= e.toString();
        }
      });
    }
  }

  Future<void> _retryConnection() async {
    setState(() {
      _isRetrying = true;
      _albumsError = null;
      _artistsError = null;
      _songsError = null;
      _playlistsError = null;
    });
    await Future.wait([
      _loadAlbums(forceRefresh: true),
      _loadArtists(forceRefresh: true),
      _loadGenres(forceRefresh: true),
      _loadSongs(forceRefresh: true),
      _loadPlaylists(forceRefresh: true),
    ]);
    if (mounted) {
      setState(() {
        _isRetrying = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // 概览页 / 二级分类宿主
  // ---------------------------------------------------------------------------

  static const String _kDashboardRoute = 'remote_library_dashboard';
  static const String _kSubHostRoute = 'remote_library_sub_host';

  /// 注意传的是 [builder] 而不是已构造好的 Widget：route 内容的构建必须延迟
  /// 到每帧真正需要时，否则首帧之后的数据更新（五个 loader 陆续回来）
  /// 永远到不了页面 —— 构建一次就冻结成实例了。
  Route<void> _remoteRoute(WidgetBuilder builder, RouteSettings settings) {
    if (Platform.isIOS || Platform.isMacOS) {
      return CupertinoPageRoute<void>(
        settings: settings,
        builder: builder,
      );
    }
    return MaterialPageRoute<void>(
      settings: settings,
      builder: builder,
    );
  }

  List<Route<void>> _initialRoutes() {
    final routes = <Route<void>>[
      _remoteRoute(
        (context) => _buildDashboard(),
        const RouteSettings(name: _kDashboardRoute),
      ),
    ];
    // 分类索引是跨层信号（Rail 与概览卡片只写 provider），页面首次构建时
    // 直接用它决定要不要连同二级宿主一起入栈 —— 这就是深链的落点。
    final index = ref.read(remoteLibraryActiveTabIndexProvider);
    if (index != null && index >= 0 && index < 6) {
      routes.add(
        _remoteRoute(
          (context) => _buildSubHost(),
          const RouteSettings(name: _kSubHostRoute),
        ),
      );
    }
    return routes;
  }

  /// 进入某个二级分类。
  ///
  /// 只写 provider —— 进退栈由 build 里的 `ref.listen` 统一处理，
  /// 这样 Rail（三期）点同一个 provider 也能走同一条路径，不会出现两套入口。
  void _openTab(int index) {
    ref.read(remoteLibraryActiveTabIndexProvider.notifier).set(index);
  }

  void _closeSubHost() {
    ref.read(remoteLibraryActiveTabIndexProvider.notifier).set(null);
  }

  /// 待打开详情属于哪个分类（决定压进哪条分类 Navigator）。
  int _tabIndexForDetail(NavidromeDetailRoute route) {
    if (route is NavidromeArtistRoute) return 1;
    if (route is NavidromePlaylistRoute) return 4;
    return 0;
  }

  /// 消费一次「深链打开详情」请求。
  ///
  /// 请求方（定位当前播放、分享页）写入时页面可能还没构建，分类宿主也可能尚未
  /// 入栈，所以这里要等目标分类的 Navigator 真正就绪再压栈 —— 否则详情页会
  /// 压在还不存在的栈上，表现为「切过去只看到分类列表」。
  Future<void> _openPendingDetail(NavidromeDetailRoute route) async {
    if (!mounted) return;
    final int tab = _tabIndexForDetail(route);
    ref.read(remoteLibraryPendingDetailProvider.notifier).set(null);
    // 进二级宿主（`build` 里的 listen 负责 push 路由）。
    ref.read(remoteLibraryActiveTabIndexProvider.notifier).set(tab);

    for (int attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      final nav = _tabNavigatorKeys[tab].currentState;
      if (nav == null) continue;
      nav.push(
        _remoteRoute(
          (context) => _buildDetailPage(route),
          RouteSettings(name: 'remote_detail_${route.runtimeType}'),
        ),
      );
      return;
    }
  }

  Widget _buildDetailPage(NavidromeDetailRoute route) {
    if (route is NavidromeAlbumRoute) {
      return RemoteAlbumDetailPage(
        server: widget.server,
        password: widget.password,
        albumId: route.albumId,
        albumName: route.albumName,
        artistName: route.artistName,
        coverArtId: route.coverArtId,
        highlightedSongPath: route.highlightedSongPath,
      );
    }
    if (route is NavidromeArtistRoute) {
      return RemoteArtistDetailPage(
        server: widget.server,
        password: widget.password,
        artistId: route.artistId,
        artistName: route.artistName,
        coverArtId: route.coverArtId,
        albumCount: route.albumCount,
      );
    }
    final playlist = route as NavidromePlaylistRoute;
    return RemotePlaylistDetailPage(
      server: widget.server,
      password: widget.password,
      playlistId: playlist.playlistId,
      playlistName: playlist.playlistName,
      coverArtId: playlist.coverArtId,
      songCount: playlist.songCount,
      duration: playlist.duration,
      isStarred: playlist.isStarred,
      highlightedSongPath: playlist.highlightedSongPath,
    );
  }

  List<Map<String, dynamic>> _recentAlbums(int limit) {
    final list = List<Map<String, dynamic>>.from(_albums);
    list.sort((a, b) {
      final ca = a['created']?.toString() ?? '';
      final cb = b['created']?.toString() ?? '';
      return cb.compareTo(ca);
    });
    return list.take(limit).toList();
  }

  List<Map<String, dynamic>> _releasedAlbums(int limit) {
    final list = List<Map<String, dynamic>>.from(_albums);
    list.sort((a, b) {
      final ya = (a['year'] as num?)?.toInt() ?? 0;
      final yb = (b['year'] as num?)?.toInt() ?? 0;
      if (ya != yb) return yb.compareTo(ya);
      final ca = a['created']?.toString() ?? '';
      final cb = b['created']?.toString() ?? '';
      return cb.compareTo(ca);
    });
    final withYear =
        list.where((a) => ((a['year'] as num?)?.toInt() ?? 0) > 0).toList();
    return (withYear.isNotEmpty ? withYear : list).take(limit).toList();
  }

  Future<void> _loadDashboardInsights({bool forceRefresh = false}) async {
    try {
      final results = await Future.wait([
        _client
            .getAlbumList(type: 'recent', size: 16)
            .catchError((_) => <Map<String, dynamic>>[]),
        _client
            .getAlbumList(type: 'frequent', size: 16)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _recentPlayedAlbums = results[0];
        _mostPlayedAlbums = results[1];
      });
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    _beginContentReload();
    await Future.wait<void>([
      _loadAlbums(forceRefresh: true),
      _loadArtists(forceRefresh: true),
      _loadGenres(forceRefresh: true),
      _loadSongs(forceRefresh: true),
      _loadPlaylists(forceRefresh: true),
      _loadDashboardInsights(forceRefresh: true),
    ]);
    _endContentReload();
  }

  void _refreshTab(int index) {
    switch (index) {
      case 0:
        unawaited(_loadAlbums(forceRefresh: true));
        break;
      case 1:
        unawaited(_loadArtists(forceRefresh: true));
        break;
      case 2:
        unawaited(_loadGenres(forceRefresh: true));
        break;
      case 3:
        unawaited(_loadSongs(forceRefresh: true));
        break;
      case 4:
        unawaited(_loadPlaylists(forceRefresh: true));
        break;
      case _kSearchTabIndex:
        if (_searchController.text.isNotEmpty) {
          _onSearchChanged(_searchController.text);
        }
        break;
    }
  }

  Widget _buildDashboard() {
    final l10n = AppLocalizations.of(context)!;
    final favorites = _albums
        .where((a) => a['starred'] != null || a['isFavorite'] == true)
        .take(12)
        .toList();

    // 概览页是局部 Navigator 的根路由。为使横向流能透到左侧 Rail 栏下方，
    // 外层不加硬截断 Padding，而是将 railWidth 作为 contentLeftPadding 传给内部。
    return Builder(
      builder: (routeContext) {
        final Size size = MediaQuery.sizeOf(routeContext);
        final double railWidth = ref.watch(
          effectiveSidebarRailWidthProvider(size),
        );
        return RemoteLibraryDashboardView(
          contentTopPadding: getTitleBarTopPadding(
            routeContext,
            defaultWindowPadding: size.width > size.height ? 32.0 : 36.0,
          ),
          contentLeftPadding: railWidth,
            server: widget.server,
            password: widget.password,
            albumCount: _albums.length,
            artistCount: _artists.length,
            songCount: _songs.length,
            playlistCount: _playlists.length,
            recentAlbums: _recentAlbums(12),
            releasedAlbums: _releasedAlbums(12),
            recentPlayedAlbums: _recentPlayedAlbums,
            mostPlayedAlbums: _mostPlayedAlbums,
            playlists: _playlists.take(12).toList(),
            favoriteAlbums: favorites,
            onNavigateToTab: _openTab,
            onOpenAlbum: (albumId, albumName) =>
                RemoteLibraryNavUtils.openAlbum(
                  routeContext,
                  server: widget.server,
                  password: widget.password,
                  albumId: albumId,
                  albumName: albumName,
                ),
            onOpenPlaylist: (playlist) {
              final id = playlist['id']?.toString() ?? '';
              final name = playlist['name'] as String? ?? '';
              if (id.isEmpty) return;
              RemoteLibraryNavUtils.openPlaylist(
                routeContext,
                server: widget.server,
                password: widget.password,
                playlistId: id,
                playlistName: name,
                coverArtId: playlist['coverArt'] as String?,
                songCount: playlist['songCount'] as int?,
                duration: playlist['duration'] as int?,
                isStarred: playlist['isStarred'] == true,
                highlightedSongPath: playlist['highlightedSongPath'] as String?,
                onPlaylistModified: () => _loadPlaylists(forceRefresh: true),
              );
            },
            onDisconnect: _disconnectFromServer,
            onRefresh: _refreshAll,
            onShuffleAll: () => _playRemoteEntities(
              kind: RemoteLibraryEntityKind.album,
              entities: _getFilteredAlbums(),
              sourceSuffix: 'dashboard',
              sourceName: l10n.albums,
              shuffle: true,
            ),
          );
        },
      );
    }

  Widget _buildSubHost() {
    final l10n = AppLocalizations.of(context)!;
    return RemoteLibrarySubHostPage(
      titles: [
        l10n.albums,
        l10n.artists,
        l10n.genres,
        l10n.songs,
        l10n.playlists,
        l10n.search,
      ],
      initialIndex: ref.read(remoteLibraryActiveTabIndexProvider),
      navigatorKeys: _tabNavigatorKeys,
      onBack: _closeSubHost,
      onRefresh: _refreshTab,
      onPopBlocked: _cancelSelection,
      selectionPanel: _buildSelectionPanel(),
      tabs: [
        (context) => _buildAlbumsTab(),
        (context) => _buildArtistsTab(),
        (context) => _buildGenresTab(),
        (context) => _buildSongsTab(),
        (context) => _buildPlaylistsTab(),
        (context) => _buildSearchTab(),
      ],
    );
  }

  /// 库级动作：定位当前播放、下载管理器。
  ///
  /// 挂在各分类页头的动作行末尾 —— 原先只在二级宿主的浮动胶囊里，
  /// 页头固定后必须在列表顶部就能点到。
  List<LibraryToolbarAction> get _headerTrailingActions {
    final l10n = AppLocalizations.of(context)!;
    final activeCount = ref.watch(activeDownloadsCountProvider);
    return [
      LibraryToolbarAction(
        icon: Icons.my_location_rounded,
        label: l10n.locateCurrentSong,
        onPressed: _locateCurrentSong,
      ),
      LibraryToolbarAction(
        icon: Icons.download_rounded,
        label: l10n.downloadManager,
        showBadge: activeCount > 0,
        onPressed: () {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => const RemoteDownloadManagerPage(),
            ),
          );
        },
      ),
    ];
  }

  /// 列表底部避让（迷你播放器 / 多选面板）。
  double get _listBottomOffset {
    final hasPlayingMusic = ref.watch(
      audioCurrentMusicProvider.select((music) => music != null),
    );
    return MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: hasPlayingMusic,
      isSelectionMode: _isSelectionMode,
      selectionPanelHeight: 220.0,
    );
  }

  Widget _buildAlbumsTab() {
    return RemoteLibraryAlbumsView(
      toolbar: _buildAlbumsToolbar(),
      server: widget.server,
      password: widget.password,
      albums: _getFilteredAlbums(),
      isLoading: _isLoadingAlbums,
      error: _albumsError,
      onRefresh: () => _loadAlbums(forceRefresh: true),
      searchQuery: _albumSearchQuery,
      bottomOffset: _listBottomOffset,
      isSelectionMode: _isAlbumSelectionMode,
      selectedAlbumIds: _selectedAlbumIds,
      lastAlbumAnchorIndex: _lastAlbumAnchorIndex,
      onSetSelection: _setAlbumSelection,
      onToggleSelection: _toggleAlbumSelection,
      onUpdateAnchor: (a) => setState(() => _lastAlbumAnchorIndex = a),
      onPlayAlbumDirectly: (id, title) =>
          RemoteLibrarySelectionActions.playAlbumDirectly(
            context: context,
            ref: ref,
            server: widget.server,
            password: widget.password,
            albumId: id,
            albumTitle: title,
          ),
    );
  }

  Widget _buildArtistsTab() {
    return RemoteLibraryArtistsView(
      toolbar: _buildArtistsToolbar(),
      landscapeToolbar: _buildArtistsToolbar(compact: true),
      server: widget.server,
      password: widget.password,
      artists: _getFilteredArtists(),
      starredArtistIds: _starredArtistIds,
      selectedArtistId: _selectedArtistId,
      isLoading: _isLoadingArtists,
      error: _artistsError,
      onRefresh: () => _loadArtists(forceRefresh: true),
      searchQuery: _artistSearchQuery,
      bottomOffset: _listBottomOffset,
      isSelectionMode: _isArtistSelectionMode,
      selectedArtistIds: _selectedArtistIds,
      lastArtistAnchorIndex: _lastArtistAnchorIndex,
      onSelectArtistId: (id) {
        setState(() {
          _selectedArtistId = id;
        });
        ref
            .read(activeRemoteSessionProvider.notifier)
            .updateNavidromeArtists(selectedArtistId: id);
      },
      onSetSelection: _setArtistSelection,
      onToggleSelection: _toggleArtistSelection,
      onUpdateAnchor: (a) => setState(() => _lastArtistAnchorIndex = a),
    );
  }

  Widget _buildGenresTab() {
    return RemoteLibraryGenresView(
      title: AppLocalizations.of(context)!.genres,
      onBack: _closeSubHost,
      trailingActions: _headerTrailingActions,
      server: widget.server,
      password: widget.password,
      genres: _genres,
      isLoading: _isLoadingGenres,
      error: _genresError,
      onRefresh: () => _loadGenres(forceRefresh: true),
      bottomOffset: _listBottomOffset,
    );
  }

  Widget _buildSongsTab() {
    return RemoteLibrarySongsView(
      toolbar: _buildSongsToolbar(),
      server: widget.server,
      password: widget.password,
      songs: _getFilteredSongs(),
      totalServerSongsCount: _songs.length,
      starredSongIds: _starredSongIds,
      isLoading: _isLoadingSongs,
      isLoadingMore: _isLoadingMoreSongs,
      hasMore: _hasMoreSongs,
      error: _songsError,
      onRefresh: () => _loadSongs(forceRefresh: true),
      onLoadMore: () => _loadSongs(loadMore: true),
      searchQuery: _songSearchQuery,
      bottomOffset: _listBottomOffset,
      isSelectionMode: _isSongSelectionMode,
      selectedSongPaths: _selectedSongPaths,
      lastSongAnchorIndex: _lastSongAnchorIndex,
      onSetSelection: _setSongSelection,
      onToggleSelection: _toggleSongSelection,
      onUpdateAnchor: (a) => setState(() => _lastSongAnchorIndex = a),
      onToggleStar: _toggleSongStar,
    );
  }

  Widget _buildPlaylistsTab() {
    return RemoteLibraryPlaylistsView(
      toolbar: _buildPlaylistsToolbar(),
      server: widget.server,
      password: widget.password,
      playlists: _getFilteredPlaylists(),
      selectedPlaylistId: _selectedPlaylistId,
      isLoading: _isLoadingPlaylists,
      error: _playlistsError,
      onRefresh: () => _loadPlaylists(forceRefresh: true),
      searchQuery: _playlistSearchQuery,
      bottomOffset: _listBottomOffset,
      isSelectionMode: _isPlaylistSelectionMode,
      selectedPlaylistIds: _selectedPlaylistIds,
      lastPlaylistAnchorIndex: _lastPlaylistAnchorIndex,
      onSelectPlaylistId: (id) {
        setState(() {
          _selectedPlaylistId = id;
        });
        ref
            .read(activeRemoteSessionProvider.notifier)
            .updateNavidromePlaylists(selectedPlaylistId: id);
      },
      onSetSelection: _setPlaylistSelection,
      onToggleSelection: _togglePlaylistSelection,
      onUpdateAnchor: (a) => setState(() => _lastPlaylistAnchorIndex = a),
      sortField: _playlistSortField,
      sortAscending: _playlistSortAscending,
    );
  }

  Widget _buildSearchTab() {
    return RemoteLibrarySearchView(
      toolbar: _buildSearchToolbar(),
      server: widget.server,
      password: widget.password,
      searchController: _searchController,
      searchedSongs: _searchedSongs,
      searchedAlbums: _searchedAlbums,
      searchedArtists: _searchedArtists,
      isSearching: _isSearching,
      bottomOffset: _listBottomOffset,
      isArtistSelectionMode: _isArtistSelectionMode,
      isAlbumSelectionMode: _isAlbumSelectionMode,
      isSongSelectionMode: _isSongSelectionMode,
      selectedArtistIds: _selectedArtistIds,
      selectedAlbumIds: _selectedAlbumIds,
      selectedSongPaths: _selectedSongPaths,
      lastSongAnchorIndex: _lastSongAnchorIndex,
      onSetSongSelection: _setSongSelection,
      onToggleSongSelection: _toggleSongSelection,
      onUpdateSongAnchor: (a) => setState(() => _lastSongAnchorIndex = a),
      onToggleArtistSelection: _toggleArtistSelection,
      onToggleAlbumSelection: _toggleAlbumSelection,
    );
  }

  Widget? _buildSelectionPanel() {
    final l10n = AppLocalizations.of(context)!;

    String? panelTitle;
    VoidCallback? panelToggleSelectAll;
    bool? panelIsAllSelected;
    VoidCallback? panelDelete;
    String? panelDeleteLabel;

    if (_isAlbumSelectionMode) {
      final filteredAlbums = _currentTabIndex == _kSearchTabIndex
          ? _searchedAlbums
          : _getFilteredAlbums();
      panelTitle = l10n.selectedAlbumsCount(_selectedAlbumIds.length);
      panelToggleSelectAll = () => _toggleSelectAllAlbums(filteredAlbums);
      panelIsAllSelected =
          _selectedAlbumIds.length == filteredAlbums.length &&
          filteredAlbums.isNotEmpty;
    } else if (_isArtistSelectionMode) {
      final filteredArtists = _currentTabIndex == _kSearchTabIndex
          ? _searchedArtists
          : _getFilteredArtists();
      panelTitle = l10n.selectedArtistsCount(_selectedArtistIds.length);
      panelToggleSelectAll = () => _toggleSelectAllArtists(filteredArtists);
      panelIsAllSelected =
          _selectedArtistIds.length == filteredArtists.length &&
          filteredArtists.isNotEmpty;
    } else if (_isPlaylistSelectionMode) {
      final filteredPlaylists = _getFilteredPlaylists();
      panelTitle = l10n.selectedPlaylistsCount(_selectedPlaylistIds.length);
      panelToggleSelectAll = () => _toggleSelectAllPlaylists(filteredPlaylists);
      panelIsAllSelected =
          _selectedPlaylistIds.length == filteredPlaylists.length &&
          filteredPlaylists.isNotEmpty;
      panelDelete = () =>
          RemoteLibrarySelectionActions.handleBatchDeletePlaylists(
            server: widget.server,
            password: widget.password,
            selectedPlaylistIds: _selectedPlaylistIds,
            onClearSelection: _cancelSelection,
            onReloadPlaylists: () => _loadPlaylists(forceRefresh: true),
            context: context,
            ref: ref,
          );
      panelDeleteLabel = l10n.deletePlaylist;
    } else if (_isSongSelectionMode) {
      final songs = _currentTabIndex == _kSearchTabIndex
          ? _searchedSongs
          : _getFilteredSongs();
      panelTitle = l10n.selectedSongs(_selectedSongPaths.length);
      panelToggleSelectAll = () => _toggleSelectAllSongs(songs);
      panelIsAllSelected =
          _selectedSongPaths.length == songs.length && songs.isNotEmpty;
    }

    return AnimatedSelectionPanel(
      isVisible: _isSelectionMode,
      child: RemoteSongSelectionPanel(
        panelKey: ValueKey(
          'navidrome-library-selection-panel-$_currentTabIndex',
        ),
        actions: RemoteSelectionActions.library,
        server: widget.server,
        password: widget.password,
        selectedSongs: _isSongSelectionMode
            ? (_currentTabIndex == _kSearchTabIndex
                      ? _searchedSongs
                      : _songs)
                  .where((s) => _selectedSongPaths.contains(s.path))
                  .toList()
            : const [],
        allSongs: _isSongSelectionMode
            ? (_currentTabIndex == _kSearchTabIndex ? _searchedSongs : _songs)
            : const [],
        title: panelTitle,
        isSelectionEmpty: !_isSelectionMode,
        isAllSelected: panelIsAllSelected,
        onToggleSelectAll: panelToggleSelectAll ?? () {},
        onFetchSongs: _fetchSelectedSongs,
        onClearSelection: _cancelSelection,
        selectedAlbumIds: _isAlbumSelectionMode ? _selectedAlbumIds : null,
        selectedArtistIds: _isArtistSelectionMode ? _selectedArtistIds : null,
        onStarredChanged: (starredIds) {
          setState(() {
            _starredSongIds.addAll(starredIds);
          });
          ref
              .read(activeRemoteSessionProvider.notifier)
              .updateNavidromeSongs(starredSongIds: _starredSongIds);
        },
        onStarredArtistsChanged: (starredIds) {
          setState(() {
            _starredArtistIds.addAll(starredIds);
          });
          ref
              .read(activeRemoteSessionProvider.notifier)
              .updateNavidromeArtists(starredArtistIds: _starredArtistIds);
        },
        onDownload: () => RemoteLibrarySelectionActions.handleBatchDownload(
          context: context,
          ref: ref,
          server: widget.server,
          password: widget.password,
          onFetchBatches: _fetchSelectedDownloadBatches,
          onClearSelection: _cancelSelection,
        ),
        onDelete: panelDelete,
        deleteLabel: panelDeleteLabel,
      ),
    );
  }

  /// 系统返回键的第一站：停在二级分类就先退回概览页。
  ///
  /// 返回 false 表示已经停在概览页，交给宿主继续处理（清会话 / 退一级 tab）。
  /// 与本地库 `LibraryPageState.handleBackPressed()` 同一套分发约定。
  bool handleBackPressed() {
    // 三级详情先弹（它压在当前分类的 Navigator 上），再退二级宿主回概览。
    // 顺序与本地 `LibraryPageState.handleBackPressed()` 一致，不能反过来：
    // 直接 pop 二级宿主会连带销毁整条分类栈，用户以为只退了一层。
    final int? tabIndex = ref.read(remoteLibraryActiveTabIndexProvider);
    if (tabIndex != null && tabIndex < _tabNavigatorKeys.length) {
      final tabNav = _tabNavigatorKeys[tabIndex].currentState;
      if (tabNav != null && tabNav.canPop()) {
        tabNav.maybePop();
        return true;
      }
    }
    final nav = _navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      _closeSubHost();
      return true;
    }
    return false;
  }

  /// 断开当前媒体库。
  ///
  /// 一级 tab 没有「上一级」可退，所以这是唯一显式的退出动作：清掉会话后
  /// `MainLayout` 会把 Rail / dock 上的入口一并撤掉并切回媒体源。
  /// 断开要重新拉五个 loader，必须二次确认，避免误触。
  Future<void> _disconnectFromServer() async {
    final l10n = AppLocalizations.of(context)!;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.remoteDisconnect),
        content: Text(l10n.remoteLibraryDisconnectConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.remoteDisconnect),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(activeRemoteSessionProvider.notifier).clear();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (_isSelectionMode) {
      _cancelSelection();
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchedSongs = [];
        _searchedAlbums = [];
        _searchedArtists = [];
      });
      final activeSession = ref.read(activeRemoteSessionProvider);
      if (activeSession != null && activeSession.server.id == widget.server.id) {
        ref.read(activeRemoteSessionProvider.notifier).updateNavidromeSearch(
              query: '',
              songs: const [],
              albums: const [],
              artists: const [],
            );
      }
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final result = await _client.search(trimmed);
        final songList = result['song'] as List?;
        final albumList = result['album'] as List?;
        final artistList = result['artist'] as List?;

        final songs = <MusicFile>[];
        if (songList != null) {
          for (final s in songList) {
            if (s is Map<String, dynamic>) {
              songs.add(_client.buildMusicFile(s));
            }
          }
        }

        if (mounted) {
          final albums = (albumList ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
          final artists = (artistList ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();

          setState(() {
            _searchedSongs = songs;
            _searchedAlbums = albums;
            _searchedArtists = artists;
            _isSearching = false;
          });

          final activeSession = ref.read(activeRemoteSessionProvider);
          if (activeSession != null &&
              activeSession.server.id == widget.server.id) {
            ref.read(activeRemoteSessionProvider.notifier).updateNavidromeSearch(
                  query: query,
                  songs: songs,
                  albums: albums,
                  artists: artists,
                );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
        }
      }
    });
  }

  Future<void> _locateCurrentSong() async {
    await SongLocatorHelper.locateCurrentPlayingSong(ref, context);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ActiveRemoteSession?>(activeRemoteSessionProvider, (prev, next) {
      if (next != null && next.server.id == widget.server.id) {
        final nextStarred = next.navidromeStarredArtistIds;
        if (nextStarred != null &&
            (nextStarred.length != _starredArtistIds.length ||
                !_starredArtistIds.containsAll(nextStarred))) {
          setState(() {
            _starredArtistIds
              ..clear()
              ..addAll(nextStarred);
          });
        }
        final nextPlaylists = next.navidromePlaylists;
        if (nextPlaylists != null && nextPlaylists != _playlists) {
          setState(() {
            _playlists = nextPlaylists;
          });
        }
      }
    });

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // 二级分类的进退栈统一在这里响应：概览页卡片、Rail（三期）、
    // 深链都只写 provider，只有这一处产生导航动作。
    ref.listen<int?>(remoteLibraryActiveTabIndexProvider, (previous, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final nav = _navigatorKey.currentState;
        if (nav == null) return;
        if (next != null) {
          if (!nav.canPop()) {
            nav.push(
              _remoteRoute(
                (context) => _buildSubHost(),
                const RouteSettings(name: _kSubHostRoute),
              ),
            );
          }
        } else if (nav.canPop()) {
          nav.pop();
        }
      });
    });

    // 深链：外部写了「待打开详情」就消费一次（页面刚构建与后续请求都走这里）。
    ref.listen<NavidromeDetailRoute?>(remoteLibraryPendingDetailProvider, (
      previous,
      next,
    ) {
      if (next == null) return;
      _openPendingDetail(next);
    });

    final bool hasConnectionError = _connectionError != null &&
        _albums.isEmpty &&
        _artists.isEmpty &&
        _songs.isEmpty &&
        _playlists.isEmpty;

    Widget content;
    if (hasConnectionError) {
      content = PopScope(
        // 连接失败页挂在 IndexedStack 的一级槽位里，不能让系统返回弹掉根路由：
        // 只清会话，交给 `MainLayout` 撤栏目并切回媒体源。
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          ref.read(activeRemoteSessionProvider.notifier).clear();
        },
        child: Scaffold(
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: theme.colorScheme.surface,
            leading: IconButton(
              icon: const Icon(kAppBackIcon, size: 24),
              tooltip: l10n.close,
              onPressed: _disconnectFromServer,
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.server.name),
                Text(
                  widget.server.type == RemoteServerType.jellyfin ? 'Jellyfin' : 'Navidrome / Subsonic',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 56,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.connectionFailed,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer
                            .withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.error
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: SelectableText(
                        _connectionError!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _isRetrying ? null : _retryConnection,
                      icon: _isRetrying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      content = Navigator(
        key: _navigatorKey,
        onGenerateInitialRoutes: (navigator, initialRoute) => _initialRoutes(),
        onGenerateRoute: (settings) => _remoteRoute(
          (context) => settings.name == _kSubHostRoute
              ? _buildSubHost()
              : _buildDashboard(),
          settings,
        ),
      );
    }

    final bool isWindowMode = isWindowedEnvironment(context);

    if (isWindowMode) {
      content = Material(
        color: theme.colorScheme.surface,
        child: Column(
          children: [
            const SizedBox(height: 32),
            Expanded(child: content),
          ],
        ),
      );
    }

    if (widget.wrapWithMiniPlayer) {
      return MiniPlayerWrapper(child: content);
    }
    return content;
  }

  /// 分类 tab 的「播放全部 / 随机播放」统一下沉到这里。
  ///
  /// 各 tab 的工具栏只负责回调，条目 → 曲目的展开、进度浮层与播放来源
  /// 都在 [playRemoteLibraryEntities] 一处决定，避免四个 tab 各写一份。
  /// [entities] 传当前列出的条目（已含搜索与「只看收藏」过滤），
  /// 所以收藏筛选下播的自然只有收藏条目的曲目。
  Future<void> _playRemoteEntities({
    required RemoteLibraryEntityKind kind,
    required List<Map<String, dynamic>> entities,
    required String sourceSuffix,
    required String sourceName,
    bool shuffle = false,
  }) {
    return playRemoteLibraryEntities(
      context: context,
      ref: ref,
      server: widget.server,
      password: widget.password,
      kind: kind,
      entities: entities,
      sourceId: 'remote-${widget.server.id}-$sourceSuffix',
      sourceName: sourceName,
      shuffle: shuffle,
    );
  }

  Widget _buildAlbumsToolbar() {
    final l10n = AppLocalizations.of(context)!;
    final albums = _getFilteredAlbums();
    return RemoteLibraryAlbumsToolbar(
      title: l10n.albums,
      onBack: _closeSubHost,
      trailingActions: _headerTrailingActions,
      isJellyfin: widget.server.type == RemoteServerType.jellyfin,
      searchController: _albumSearchController,
      searchFocusNode: _albumSearchFocusNode,
      searchQuery: _albumSearchQuery,
      sortType: _albumSortType,
      starredOnly: _albumStarredOnly,
      totalCount: albums.length,
      onPlayAll: () => _playRemoteEntities(
        kind: RemoteLibraryEntityKind.album,
        entities: albums,
        sourceSuffix: 'albums',
        sourceName: l10n.albums,
      ),
      onShufflePlay: () => _playRemoteEntities(
        kind: RemoteLibraryEntityKind.album,
        entities: albums,
        sourceSuffix: 'albums',
        sourceName: l10n.albums,
        shuffle: true,
      ),
      onSearchChanged: (val) {
        setState(() {
          _albumSearchQuery = val.trim();
        });
      },
      onClearSearch: () {
        _albumSearchController.clear();
        setState(() {
          _albumSearchQuery = '';
        });
      },
      onSortTypeChanged: (newSort) async {
        if (newSort == _albumSortType) return;
        setState(() {
          _albumSortType = newSort;
          _isReloadingContent = _albums.isNotEmpty;
        });
        ref.read(settingsServiceProvider).navidromeAlbumSortType = newSort;
        await _loadAlbums(forceRefresh: true);
        _endContentReload();
      },
      onToggleStarredOnly: (selected) async {
        if (selected == _albumStarredOnly) return;
        setState(() {
          _albumStarredOnly = selected;
          if (selected) {
            // 列表项本身带 starred / isFavorite，先就地补一批收藏 id，
            // 大多数服务端下切筛选完全不发请求。
            _starredAlbumIds.addAll(
              _albums
                  .where((a) => a['starred'] != null || a['isFavorite'] == true)
                  .map((a) => a['id']?.toString() ?? '')
                  .where((id) => id.isNotEmpty),
            );
          }
        });
        // 一个都没补到，说明列表没带收藏字段，先等一次收藏集再显示；
        // 已经补到了就直接渲染，后台顺手刷新，兜住详情页里刚收藏的专辑。
        if (selected && _starredAlbumIds.isEmpty) {
          _beginContentReload();
          await _fetchStarredAlbums();
          _endContentReload();
        } else if (selected) {
          unawaited(_fetchStarredAlbums());
        }
      },
    );
  }

  Widget _buildArtistsToolbar({bool compact = false}) {
    final l10n = AppLocalizations.of(context)!;
    final artists = _getFilteredArtists();
    return RemoteLibraryArtistsToolbar(
      compact: compact,
      title: l10n.artists,
      onBack: _closeSubHost,
      trailingActions: _headerTrailingActions,
      searchController: _artistSearchController,
      searchFocusNode: _artistSearchFocusNode,
      searchQuery: _artistSearchQuery,
      starredOnly: _artistStarredOnly,
      sortAsc: _artistSortAsc,
      sortField: _artistSortField,
      totalCount: artists.length,
      onPlayAll: () => _playRemoteEntities(
        kind: RemoteLibraryEntityKind.artist,
        entities: artists,
        sourceSuffix: 'artists',
        sourceName: l10n.artists,
      ),
      onShufflePlay: () => _playRemoteEntities(
        kind: RemoteLibraryEntityKind.artist,
        entities: artists,
        sourceSuffix: 'artists',
        sourceName: l10n.artists,
        shuffle: true,
      ),
      onSearchChanged: (val) {
        setState(() {
          _artistSearchQuery = val.trim();
        });
      },
      onClearSearch: () {
        _artistSearchController.clear();
        setState(() {
          _artistSearchQuery = '';
        });
      },
      onToggleStarredOnly: (selected) async {
        setState(() {
          _artistStarredOnly = selected;
        });
        if (selected && _starredArtistIds.isEmpty) {
          _beginContentReload();
          await _fetchStarredArtists();
          _endContentReload();
        }
      },
      onSortChanged: (field, asc) {
        setState(() {
          _artistSortField = field;
          _artistSortAsc = asc;
        });
        final settings = ref.read(settingsServiceProvider);
        settings.navidromeArtistSortField = field;
        settings.navidromeArtistSortAscending = asc;
      },
    );
  }

  RemoteLibrarySongsToolbar _buildSongsToolbar() {
    final l10n = AppLocalizations.of(context)!;
    return RemoteLibrarySongsToolbar(
      title: l10n.songs,
      onBack: _closeSubHost,
      trailingActions: _headerTrailingActions,
      searchController: _songSearchController,
      searchFocusNode: _songSearchFocusNode,
      searchQuery: _songSearchQuery,
      starredOnly: _songStarredOnly,
      onSearchChanged: (val) {
        setState(() {
          _songSearchQuery = val.trim();
        });
      },
      onClearSearch: () {
        _songSearchController.clear();
        setState(() {
          _songSearchQuery = '';
        });
      },
      onToggleStarredOnly: (selected) async {
        setState(() {
          _songStarredOnly = selected;
        });
        if (selected && _starredSongIds.isEmpty) {
          _beginContentReload();
          await _fetchStarredSongs();
          _endContentReload();
        }
      },
      onSortPressed: () => _openSongsSortDialog(context),
    );
  }

  /// 歌曲排序与歌单 tab 同一套入口：单按钮点开选项弹窗。
  /// 排序只作用于展示层顺序，「字段 + 升降序」是本机视图偏好、不回写服务端。
  Future<void> _openSongsSortDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<SortResult<String>>(
      context: context,
      builder: (dialogContext) => SortOptionsDialog<String>(
        title: l10n.sort,
        currentField: _songSortField,
        sortAscending: _songSortAsc,
        options: [
          SortOptionItem(
            value: 'title',
            label: l10n.songs,
            icon: Icons.sort_by_alpha_rounded,
          ),
          SortOptionItem(
            value: 'artist',
            label: l10n.artists,
            icon: Icons.person_rounded,
          ),
          SortOptionItem(
            value: 'album',
            label: l10n.albums,
            icon: Icons.album_rounded,
          ),
          SortOptionItem(
            value: 'duration',
            label: l10n.durationLabel,
            icon: Icons.access_time_rounded,
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _songSortField = result.field;
        _songSortAsc = result.sortAscending;
      });
      final settings = ref.read(settingsServiceProvider);
      settings.navidromeSongSortField = result.field;
      settings.navidromeSongSortAscending = result.sortAscending;
    }
  }

  Future<void> _openPlaylistSortDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<SortResult<RemotePlaylistSortField>>(
      context: context,
      builder: (dialogContext) => SortOptionsDialog<RemotePlaylistSortField>(
        title: l10n.sortPlaylists,
        currentField: _playlistSortField,
        sortAscending: _playlistSortAscending,
        // 服务端原序没有升降序之分。
        ascendingToggleEnabled: (field) =>
            field != RemotePlaylistSortField.serverOrder,
        options: [
          SortOptionItem(
            value: RemotePlaylistSortField.serverOrder,
            label: l10n.sortServerOrder,
            icon: Icons.cloud_queue_rounded,
          ),
          SortOptionItem(
            value: RemotePlaylistSortField.name,
            label: l10n.playlistName,
            icon: Icons.sort_by_alpha_rounded,
          ),
          SortOptionItem(
            value: RemotePlaylistSortField.songCount,
            label: l10n.sortTrackCount,
            icon: Icons.format_list_numbered_rounded,
          ),
          SortOptionItem(
            value: RemotePlaylistSortField.duration,
            label: l10n.sortDuration,
            icon: Icons.access_time_rounded,
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _playlistSortField = result.field;
        _playlistSortAscending = result.sortAscending;
      });
      final settings = ref.read(settingsServiceProvider);
      settings.remotePlaylistSortField = result.field.name;
      settings.remotePlaylistSortAscending = result.sortAscending;
    }
  }

  Widget _buildPlaylistsToolbar() {
    final l10n = AppLocalizations.of(context)!;
    final playlists = _getFilteredPlaylists();
    return RemoteLibraryPlaylistsToolbar(
      title: l10n.playlists,
      onBack: _closeSubHost,
      trailingActions: _headerTrailingActions,
      searchController: _playlistSearchController,
      totalCount: playlists.length,
      onPlayAll: () => _playRemoteEntities(
        kind: RemoteLibraryEntityKind.playlist,
        entities: playlists,
        sourceSuffix: 'playlists',
        sourceName: l10n.playlists,
      ),
      onShufflePlay: () => _playRemoteEntities(
        kind: RemoteLibraryEntityKind.playlist,
        entities: playlists,
        sourceSuffix: 'playlists',
        sourceName: l10n.playlists,
        shuffle: true,
      ),
      onSearchChanged: (val) {
        setState(() {
          _playlistSearchQuery = val;
        });
        final activeSession = ref.read(activeRemoteSessionProvider);
        if (activeSession != null &&
            activeSession.server.id == widget.server.id) {
          ref
              .read(activeRemoteSessionProvider.notifier)
              .updateNavidromePlaylistSearchQuery(val);
        }
      },
      onClearSearch: () {
        _playlistSearchController.clear();
        setState(() {
          _playlistSearchQuery = '';
        });
        final activeSession = ref.read(activeRemoteSessionProvider);
        if (activeSession != null &&
            activeSession.server.id == widget.server.id) {
          ref
              .read(activeRemoteSessionProvider.notifier)
              .updateNavidromePlaylistSearchQuery('');
        }
      },
      onCreatePlaylist: () => showCreateNavidromePlaylistDialog(
        context: context,
        client: _client,
        onCreated: (created) async {
          await _loadPlaylists(forceRefresh: true);
          final createdId = created['id'] as String?;
          if (createdId != null && mounted) {
            setState(() {
              _selectedPlaylistId = createdId;
            });
            ref
                .read(activeRemoteSessionProvider.notifier)
                .updateNavidromePlaylists(
                  selectedPlaylistId: createdId,
                );
          }
        },
      ),
      onSortPressed: () => _openPlaylistSortDialog(context),
    );
  }

  Widget _buildSearchToolbar() {
    final l10n = AppLocalizations.of(context)!;
    return RemoteLibrarySearchToolbar(
      title: l10n.search,
      onBack: _closeSubHost,
      searchController: _searchController,
      isSearching: _isSearching,
      onSearchChanged: _onSearchChanged,
      onClearSearch: () {
        _searchController.clear();
        _onSearchChanged('');
      },
    );
  }
}

typedef NavidromeLibraryPage = RemoteLibraryPage;
