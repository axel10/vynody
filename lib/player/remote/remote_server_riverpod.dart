import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'remote_server_models.dart';
import 'remote_server_storage.dart';
import '../../models/music_file.dart';
import 'clients/subsonic_client.dart';
import 'clients/webdav_client.dart';
import 'clients/smb_client.dart';
import 'clients/jellyfin_client.dart';
import 'services/remote_directory_scanner.dart';
import '../metadata/metadata_database.dart';

final remoteServerStorageProvider = FutureProvider<RemoteServerStorage>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return RemoteServerStorage(prefs: prefs);
});

class RemoteServersNotifier extends AsyncNotifier<List<RemoteServer>> {
  @override
  Future<List<RemoteServer>> build() async {
    final storage = await ref.watch(remoteServerStorageProvider.future);
    return storage.loadServers();
  }

  Future<void> addServer(RemoteServer server, String password) async {
    final storage = await ref.read(remoteServerStorageProvider.future);
    await storage.savePassword(server.id, password);

    final currentList = state.asData?.value ?? [];
    final updatedList = [...currentList.where((s) => s.id != server.id), server];
    await storage.saveServers(updatedList);
    state = AsyncData(updatedList);
  }

  Future<void> updateServer(RemoteServer server, {String? newPassword}) async {
    final storage = await ref.read(remoteServerStorageProvider.future);
    if (newPassword != null && newPassword.isNotEmpty) {
      await storage.savePassword(server.id, newPassword);
    }

    final currentList = state.asData?.value ?? [];
    final updatedList = currentList.map((s) => s.id == server.id ? server : s).toList();
    await storage.saveServers(updatedList);
    state = AsyncData(updatedList);
  }

  Future<void> deleteServer(String serverId) => deleteServers(<String>[serverId]);

  /// 批量删除：只更新一次 state，避免逐个删时列表反复重建。
  Future<void> deleteServers(Iterable<String> serverIds) async {
    final ids = serverIds.toSet();
    if (ids.isEmpty) return;
    final storage = await ref.read(remoteServerStorageProvider.future);
    for (final id in ids) {
      await storage.deleteServer(id);
      try {
        await ref
            .read(remoteDirectoryScannerProvider)
            .removeServerFromDatabase(id);
      } catch (_) {}

      final activeSession = ref.read(activeRemoteSessionProvider);
      if (activeSession?.server.id == id) {
        ref.read(activeRemoteSessionProvider.notifier).clear();
      }
    }

    final currentList = state.asData?.value ?? [];
    state = AsyncData(currentList.where((s) => !ids.contains(s.id)).toList());
  }

  Future<void> reorderServers(List<RemoteServer> reorderedServers) async {
    final storage = await ref.read(remoteServerStorageProvider.future);
    await storage.saveServers(reorderedServers);
    state = AsyncData(reorderedServers);
  }

  Future<String?> getPassword(String serverId) async {
    final storage = await ref.read(remoteServerStorageProvider.future);
    return storage.getPassword(serverId);
  }

  Future<ConnectionTestResult> testConnection(RemoteServer server, String password) async {
    if (server.type == RemoteServerType.subsonic) {
      final client = SubsonicClient(server: server, password: password);
      return client.testConnection();
    } else if (server.type == RemoteServerType.smb) {
      final client = SmbClient(server: server, password: password);
      return client.testConnection();
    } else if (server.type == RemoteServerType.jellyfin) {
      final client = JellyfinClient(server: server, password: password);
      return client.testConnection();
    } else {
      final client = WebDavClient(server: server, password: password);
      return client.testConnection();
    }
  }
}

final remoteServersProvider =
    AsyncNotifierProvider<RemoteServersNotifier, List<RemoteServer>>(() {
  return RemoteServersNotifier();
});

sealed class NavidromeDetailRoute {
  const NavidromeDetailRoute();
}

class NavidromeAlbumRoute extends NavidromeDetailRoute {
  final String albumId;
  final String albumName;
  final String? coverArtId;
  final String? artistName;
  final String? highlightedSongPath;

  const NavidromeAlbumRoute({
    required this.albumId,
    required this.albumName,
    this.coverArtId,
    this.artistName,
    this.highlightedSongPath,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavidromeAlbumRoute &&
          runtimeType == other.runtimeType &&
          albumId == other.albumId;

  @override
  int get hashCode => albumId.hashCode;
}

class NavidromeArtistRoute extends NavidromeDetailRoute {
  final String artistId;
  final String artistName;
  final String? coverArtId;
  final int? albumCount;

  const NavidromeArtistRoute({
    required this.artistId,
    required this.artistName,
    this.coverArtId,
    this.albumCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavidromeArtistRoute &&
          runtimeType == other.runtimeType &&
          artistId == other.artistId &&
          artistName == other.artistName;

  @override
  int get hashCode => Object.hash(artistId, artistName);
}

class NavidromePlaylistRoute extends NavidromeDetailRoute {
  final String playlistId;
  final String playlistName;
  final String? coverArtId;
  final int? songCount;
  final int? duration;
  final bool isStarred;
  final String? highlightedSongPath;

  const NavidromePlaylistRoute({
    required this.playlistId,
    required this.playlistName,
    this.coverArtId,
    this.songCount,
    this.duration,
    this.isStarred = false,
    this.highlightedSongPath,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavidromePlaylistRoute &&
          runtimeType == other.runtimeType &&
          playlistId == other.playlistId;

  @override
  int get hashCode => playlistId.hashCode;
}

class NavidromePlaylistCache {
  final Map<String, dynamic> playlistData;
  final List<MusicFile> tracks;
  final Set<String> starredSongIds;

  const NavidromePlaylistCache({
    required this.playlistData,
    required this.tracks,
    required this.starredSongIds,
  });
}

class ActiveRemoteSession {
  final RemoteServer server;
  final String password;
  final String? initialPath;
  final String? rootPath;
  final int? initialTabIndex;
  final Map<String, List<WebDavFile>> webDavDirectoryCache;
  final Map<String, SongMetadata> webDavMetadataCache;
  final List<String> webDavPathStack;

  // Navidrome / Subsonic cached states
  final List<Map<String, dynamic>>? navidromeAlbums;
  final String? navidromeAlbumSortType;
  final List<Map<String, dynamic>>? navidromeArtists;
  final Set<String>? navidromeStarredArtistIds;
  final String? navidromeSelectedArtistId;
  final List<Map<String, dynamic>>? navidromePlaylists;
  final String? navidromeSelectedPlaylistId;
  final String? navidromePlaylistSearchQuery;
  final Map<String, NavidromePlaylistCache> navidromePlaylistDetailsCache;
  final String? navidromeSearchQuery;
  final List<MusicFile>? navidromeSearchedSongs;
  final List<Map<String, dynamic>>? navidromeSearchedAlbums;
  final List<Map<String, dynamic>>? navidromeSearchedArtists;
  final List<MusicFile>? navidromeSongs;
  final Set<String>? navidromeStarredSongIds;
  final bool? navidromeHasMoreSongs;
  final int? navidromeSongOffset;
  final List<NavidromeDetailRoute> navidromeDetailStack;
  final String? webDavHighlightedSongPath;

  const ActiveRemoteSession({
    required this.server,
    required this.password,
    this.initialPath,
    this.rootPath,
    this.initialTabIndex,
    this.webDavDirectoryCache = const {},
    this.webDavMetadataCache = const {},
    this.webDavPathStack = const [],
    this.navidromeAlbums,
    this.navidromeAlbumSortType,
    this.navidromeArtists,
    this.navidromeStarredArtistIds,
    this.navidromeSelectedArtistId,
    this.navidromePlaylists,
    this.navidromeSelectedPlaylistId,
    this.navidromePlaylistSearchQuery,
    this.navidromePlaylistDetailsCache = const {},
    this.navidromeSearchQuery,
    this.navidromeSearchedSongs,
    this.navidromeSearchedAlbums,
    this.navidromeSearchedArtists,
    this.navidromeSongs,
    this.navidromeStarredSongIds,
    this.navidromeHasMoreSongs,
    this.navidromeSongOffset,
    this.navidromeDetailStack = const [],
    this.webDavHighlightedSongPath,
  });

  static List<String> buildWebDavPathStack(
    String rootPath,
    String targetDir,
  ) {
    final cleanRoot = normalizeRemotePath(rootPath);
    final cleanTarget = normalizeRemotePath(targetDir);

    if (cleanTarget.isEmpty ||
        cleanTarget == cleanRoot ||
        cleanTarget == '/') {
      return const [];
    }

    var relative = cleanTarget;
    if (cleanRoot != '/' && relative.startsWith(cleanRoot)) {
      relative = relative.substring(cleanRoot.length);
    }

    final segments = relative
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .toList();

    if (segments.isEmpty) return const [];

    final stack = <String>[];
    for (int i = 0; i < segments.length; i++) {
      final sub = segments.sublist(0, i + 1).join('/');
      if (cleanRoot == '/' || cleanRoot.isEmpty) {
        stack.add('/$sub');
      } else {
        stack.add('$cleanRoot/$sub');
      }
    }
    return stack;
  }

  ActiveRemoteSession copyWith({
    RemoteServer? server,
    String? password,
    String? initialPath,
    String? rootPath,
    int? initialTabIndex,
    Map<String, List<WebDavFile>>? webDavDirectoryCache,
    Map<String, SongMetadata>? webDavMetadataCache,
    List<String>? webDavPathStack,
    List<Map<String, dynamic>>? navidromeAlbums,
    String? navidromeAlbumSortType,
    List<Map<String, dynamic>>? navidromeArtists,
    Set<String>? navidromeStarredArtistIds,
    String? navidromeSelectedArtistId,
    List<Map<String, dynamic>>? navidromePlaylists,
    String? navidromeSelectedPlaylistId,
    bool clearSelectedPlaylistId = false,
    String? navidromePlaylistSearchQuery,
    Map<String, NavidromePlaylistCache>? navidromePlaylistDetailsCache,
    String? navidromeSearchQuery,
    List<MusicFile>? navidromeSearchedSongs,
    List<Map<String, dynamic>>? navidromeSearchedAlbums,
    List<Map<String, dynamic>>? navidromeSearchedArtists,
    List<MusicFile>? navidromeSongs,
    Set<String>? navidromeStarredSongIds,
    bool? navidromeHasMoreSongs,
    int? navidromeSongOffset,
    List<NavidromeDetailRoute>? navidromeDetailStack,
    String? webDavHighlightedSongPath,
  }) {
    return ActiveRemoteSession(
      server: server ?? this.server,
      password: password ?? this.password,
      initialPath: initialPath ?? this.initialPath,
      rootPath: rootPath ?? this.rootPath,
      initialTabIndex: initialTabIndex ?? this.initialTabIndex,
      webDavDirectoryCache: webDavDirectoryCache ?? this.webDavDirectoryCache,
      webDavMetadataCache: webDavMetadataCache ?? this.webDavMetadataCache,
      webDavPathStack: webDavPathStack ?? this.webDavPathStack,
      navidromeAlbums: navidromeAlbums ?? this.navidromeAlbums,
      navidromeAlbumSortType:
          navidromeAlbumSortType ?? this.navidromeAlbumSortType,
      navidromeArtists: navidromeArtists ?? this.navidromeArtists,
      navidromeStarredArtistIds:
          navidromeStarredArtistIds ?? this.navidromeStarredArtistIds,
      navidromeSelectedArtistId:
          navidromeSelectedArtistId ?? this.navidromeSelectedArtistId,
      navidromePlaylists: navidromePlaylists ?? this.navidromePlaylists,
      navidromeSelectedPlaylistId: clearSelectedPlaylistId
          ? null
          : (navidromeSelectedPlaylistId ?? this.navidromeSelectedPlaylistId),
      navidromePlaylistSearchQuery:
          navidromePlaylistSearchQuery ?? this.navidromePlaylistSearchQuery,
      navidromePlaylistDetailsCache:
          navidromePlaylistDetailsCache ?? this.navidromePlaylistDetailsCache,
      navidromeSearchQuery: navidromeSearchQuery ?? this.navidromeSearchQuery,
      navidromeSearchedSongs:
          navidromeSearchedSongs ?? this.navidromeSearchedSongs,
      navidromeSearchedAlbums:
          navidromeSearchedAlbums ?? this.navidromeSearchedAlbums,
      navidromeSearchedArtists:
          navidromeSearchedArtists ?? this.navidromeSearchedArtists,
      navidromeSongs: navidromeSongs ?? this.navidromeSongs,
      navidromeStarredSongIds:
          navidromeStarredSongIds ?? this.navidromeStarredSongIds,
      navidromeHasMoreSongs:
          navidromeHasMoreSongs ?? this.navidromeHasMoreSongs,
      navidromeSongOffset: navidromeSongOffset ?? this.navidromeSongOffset,
      navidromeDetailStack: navidromeDetailStack ?? this.navidromeDetailStack,
      webDavHighlightedSongPath:
          webDavHighlightedSongPath ?? this.webDavHighlightedSongPath,
    );
  }
}

class ActiveRemoteSessionNotifier extends Notifier<ActiveRemoteSession?> {
  @override
  ActiveRemoteSession? build() => null;

  void setSession(ActiveRemoteSession? session) {
    state = session;
  }

  void updateInitialPath(String? path) {
    if (state != null) {
      state = state!.copyWith(initialPath: path);
    }
  }

  void updateWebDavState({
    required String currentPath,
    String? rootPath,
    List<WebDavFile>? items,
    Map<String, SongMetadata>? metadataMap,
  }) {
    if (state != null) {
      final newDirCache =
          Map<String, List<WebDavFile>>.from(state!.webDavDirectoryCache);
      if (items != null) {
        newDirCache[currentPath] = items;
      }
      final newMetaCache =
          Map<String, SongMetadata>.from(state!.webDavMetadataCache);
      if (metadataMap != null) {
        newMetaCache.addAll(metadataMap);
      }
      state = state!.copyWith(
        initialPath: currentPath,
        rootPath: rootPath ?? state!.rootPath,
        webDavDirectoryCache: newDirCache,
        webDavMetadataCache: newMetaCache,
      );
    }
  }

  void updateInitialTabIndex(int? index) {
    if (state != null) {
      state = state!.copyWith(initialTabIndex: index);
    }
  }

  void updateNavidromeAlbums(
    List<Map<String, dynamic>> albums, {
    String? sortType,
  }) {
    if (state != null) {
      state = state!.copyWith(
        navidromeAlbums: albums,
        navidromeAlbumSortType: sortType ?? state!.navidromeAlbumSortType,
      );
    }
  }

  void updateNavidromeArtists({
    List<Map<String, dynamic>>? artists,
    Set<String>? starredArtistIds,
    String? selectedArtistId,
  }) {
    if (state != null) {
      state = state!.copyWith(
        navidromeArtists: artists ?? state!.navidromeArtists,
        navidromeStarredArtistIds:
            starredArtistIds ?? state!.navidromeStarredArtistIds,
        navidromeSelectedArtistId:
            selectedArtistId ?? state!.navidromeSelectedArtistId,
      );
    }
  }

  void updateNavidromePlaylists({
    List<Map<String, dynamic>>? playlists,
    String? selectedPlaylistId,
  }) {
    if (state != null) {
      state = state!.copyWith(
        navidromePlaylists: playlists ?? state!.navidromePlaylists,
        navidromeSelectedPlaylistId:
            selectedPlaylistId ?? state!.navidromeSelectedPlaylistId,
      );
    }
  }

  void updateNavidromePlaylistSearchQuery(String query) {
    if (state != null) {
      state = state!.copyWith(navidromePlaylistSearchQuery: query);
    }
  }

  void updateNavidromePlaylistDetail({
    required String playlistId,
    required Map<String, dynamic> playlistData,
    required List<MusicFile> tracks,
    required Set<String> starredSongIds,
  }) {
    if (state != null) {
      final newCache = Map<String, NavidromePlaylistCache>.from(
        state!.navidromePlaylistDetailsCache,
      );
      newCache[playlistId] = NavidromePlaylistCache(
        playlistData: playlistData,
        tracks: tracks,
        starredSongIds: starredSongIds,
      );
      List<Map<String, dynamic>>? newPlaylists = state!.navidromePlaylists;
      if (newPlaylists != null) {
        newPlaylists = newPlaylists.map((p) {
          if (p['id']?.toString() == playlistId.toString()) {
            final updated = Map<String, dynamic>.from(p);
            updated['songCount'] = tracks.length;
            if (playlistData['name'] != null) {
              updated['name'] = playlistData['name'];
            }
            if (playlistData['duration'] != null) {
              updated['duration'] = playlistData['duration'];
            }
            return updated;
          }
          return p;
        }).toList();
      }
      state = state!.copyWith(
        navidromePlaylistDetailsCache: newCache,
        navidromePlaylists: newPlaylists,
      );
    }
  }

  void addNavidromePlaylist(Map<String, dynamic> playlist) {
    if (state != null) {
      final current = state!.navidromePlaylists ?? [];
      final playlistId = playlist['id']?.toString();
      final exists = current.any((p) => p['id']?.toString() == playlistId);
      final newPlaylists = exists
          ? current
              .map((p) => p['id']?.toString() == playlistId ? playlist : p)
              .toList()
          : [playlist, ...current];
      state = state!.copyWith(navidromePlaylists: newPlaylists);
    }
  }

  void updateNavidromePlaylistSummary(
    String playlistId, {
    String? name,
    int? songCount,
    int? songCountDelta,
    int? duration,
  }) {
    if (state != null && state!.navidromePlaylists != null) {
      final updated = state!.navidromePlaylists!.map((p) {
        if (p['id']?.toString() == playlistId) {
          final map = Map<String, dynamic>.from(p);
          if (name != null) map['name'] = name;
          if (songCount != null) {
            map['songCount'] = songCount;
          } else if (songCountDelta != null) {
            final currentCount = (map['songCount'] as num?)?.toInt() ?? 0;
            map['songCount'] = (currentCount + songCountDelta).clamp(0, 999999);
          }
          if (duration != null) map['duration'] = duration;
          return map;
        }
        return p;
      }).toList();
      state = state!.copyWith(navidromePlaylists: updated);
    }
  }

  void removeNavidromePlaylistDetail(String playlistId) {
    if (state != null) {
      final newCache = Map<String, NavidromePlaylistCache>.from(
        state!.navidromePlaylistDetailsCache,
      );
      newCache.remove(playlistId);
      state = state!.copyWith(navidromePlaylistDetailsCache: newCache);
    }
  }

  void invalidateNavidromePlaylistDetail(String playlistId) {
    removeNavidromePlaylistDetail(playlistId);
  }

  void removeNavidromePlaylist(String playlistId) {
    if (state != null) {
      final newPlaylists = state!.navidromePlaylists
          ?.where((p) => p['id'] != playlistId)
          .toList();
      final newCache = Map<String, NavidromePlaylistCache>.from(
        state!.navidromePlaylistDetailsCache,
      );
      newCache.remove(playlistId);
      state = state!.copyWith(
        navidromePlaylists: newPlaylists,
        navidromePlaylistDetailsCache: newCache,
        clearSelectedPlaylistId:
            state!.navidromeSelectedPlaylistId == playlistId,
      );
    }
  }

  void updateNavidromeSearch({
    required String query,
    required List<MusicFile> songs,
    required List<Map<String, dynamic>> albums,
    required List<Map<String, dynamic>> artists,
  }) {
    if (state != null) {
      state = state!.copyWith(
        navidromeSearchQuery: query,
        navidromeSearchedSongs: songs,
        navidromeSearchedAlbums: albums,
        navidromeSearchedArtists: artists,
      );
    }
  }

  void updateNavidromeSongs({
    List<MusicFile>? songs,
    Set<String>? starredSongIds,
    bool? hasMore,
    int? songOffset,
  }) {
    if (state != null) {
      state = state!.copyWith(
        navidromeSongs: songs ?? state!.navidromeSongs,
        navidromeStarredSongIds:
            starredSongIds ?? state!.navidromeStarredSongIds,
        navidromeHasMoreSongs: hasMore ?? state!.navidromeHasMoreSongs,
        navidromeSongOffset: songOffset ?? state!.navidromeSongOffset,
      );
    }
  }

  void pushNavidromeDetail(NavidromeDetailRoute route) {
    if (state != null) {
      state = state!.copyWith(
        navidromeDetailStack: [...state!.navidromeDetailStack, route],
      );
    }
  }

  void popNavidromeDetail() {
    if (state != null && state!.navidromeDetailStack.isNotEmpty) {
      final newStack =
          List<NavidromeDetailRoute>.from(state!.navidromeDetailStack)
            ..removeLast();
      state = state!.copyWith(navidromeDetailStack: newStack);
    }
  }

  void pushWebDavPath(String path) {
    if (state != null) {
      state = state!.copyWith(
        webDavPathStack: [...state!.webDavPathStack, path],
      );
    }
  }

  void popWebDavPath() {
    if (state != null && state!.webDavPathStack.isNotEmpty) {
      final newStack = List<String>.from(state!.webDavPathStack)..removeLast();
      state = state!.copyWith(webDavPathStack: newStack);
    }
  }

  void setWebDavPathStack(List<String> stack) {
    if (state != null) {
      state = state!.copyWith(webDavPathStack: stack);
    }
  }

  void setWebDavLocation({
    required List<String> pathStack,
    String? highlightedSongPath,
  }) {
    if (state != null) {
      state = state!.copyWith(
        webDavPathStack: pathStack,
        webDavHighlightedSongPath: highlightedSongPath,
      );
    }
  }

  void clearWebDavHighlightedSongPath() {
    if (state != null && state!.webDavHighlightedSongPath != null) {
      state = state!.copyWith(webDavHighlightedSongPath: null);
    }
  }

  void clear() {
    state = null;
  }
}

final activeRemoteSessionProvider =
    NotifierProvider<ActiveRemoteSessionNotifier, ActiveRemoteSession?>(
      ActiveRemoteSessionNotifier.new,
    );
