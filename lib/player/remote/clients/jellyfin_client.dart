import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../remote_server_models.dart';

class JellyfinException implements Exception {
  final String message;
  final int? code;
  const JellyfinException(this.message, {this.code});

  @override
  String toString() => message;
}

class JellyfinSession {
  final String token;
  final String userId;
  final String? serverId;
  final String? serverVersion;

  const JellyfinSession({
    required this.token,
    required this.userId,
    this.serverId,
    this.serverVersion,
  });
}

class JellyfinClient {
  static const String clientName = 'Vynody';
  static const String appVersion = '1.0.0';

  /// In-memory cache for session tokens per serverId
  static final Map<String, JellyfinSession> _sessionCache = {};

  final RemoteServer server;
  final String password;
  late final Dio _dio;

  JellyfinClient({
    required this.server,
    required this.password,
    Dio? customDio,
  }) {
    _dio = customDio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 10),
            headers: {
              'User-Agent': 'Vynody/$appVersion',
              'Accept': 'application/json',
            },
          ),
        );

    if (server.ignoreSsl && customDio == null) {
      final adapter = _dio.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      }
    }
  }

  /// Normalizes base URL (ensures http/https, strips trailing slashes).
  String get baseUrl {
    var raw = server.url.trim();
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      raw = 'http://$raw';
    }
    return raw.replaceAll(RegExp(r'/+$'), '');
  }

  String get _authHeaderValue {
    final devId = 'vynody-${server.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
    return 'MediaBrowser Client="$clientName", Device="Desktop", DeviceId="$devId", Version="$appVersion"';
  }

  Map<String, String> _authHeaders([String? token]) {
    final effectiveToken = token ?? _sessionCache[server.id]?.token;
    final authValue = effectiveToken != null && effectiveToken.isNotEmpty
        ? '$_authHeaderValue, Token="$effectiveToken"'
        : _authHeaderValue;
    return {
      'Authorization': authValue,
      'X-Emby-Authorization': authValue,
      if (effectiveToken != null && effectiveToken.isNotEmpty) ...{
        'X-Emby-Token': effectiveToken,
        'X-MediaBrowser-Token': effectiveToken,
      },
    };
  }

  JellyfinSession? get currentSession => _sessionCache[server.id];

  /// Authenticates with the Jellyfin server and returns session info.
  Future<JellyfinSession> authenticate({bool forceRefresh = false}) async {
    if (!forceRefresh && _sessionCache.containsKey(server.id)) {
      return _sessionCache[server.id]!;
    }

    try {
      final authUrl = '$baseUrl/Users/AuthenticateByName';
      final response = await _dio.post<dynamic>(
        authUrl,
        data: {
          'Username': server.username.trim(),
          'Pw': password,
        },
        options: Options(
          headers: {
            ..._authHeaders(),
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        final token = data['AccessToken'] as String? ?? '';
        final user = data['User'] as Map<String, dynamic>?;
        final userId = user?['Id'] as String? ?? '';
        final serverId = data['ServerId'] as String?;

        if (token.isEmpty || userId.isEmpty) {
          throw const JellyfinException('Invalid authentication response from Jellyfin server');
        }

        final session = JellyfinSession(
          token: token,
          userId: userId,
          serverId: serverId,
        );
        _sessionCache[server.id] = session;
        return session;
      } else {
        throw const JellyfinException('Unexpected response from Jellyfin server');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final code = e.response!.statusCode;
        if (code == 401) {
          throw const JellyfinException('Invalid username or password', code: 401);
        }
        throw JellyfinException('HTTP $code: ${e.response!.statusMessage}', code: code);
      }
      throw JellyfinException(e.message ?? 'Failed to connect to Jellyfin server');
    }
  }

  /// Performs an authenticated GET request.
  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? query]) async {
    JellyfinSession session;
    try {
      session = await authenticate();
    } catch (_) {
      session = await authenticate(forceRefresh: true);
    }

    try {
      final response = await _dio.get<dynamic>(
        '$baseUrl$path',
        queryParameters: query,
        options: Options(
          headers: _authHeaders(session.token),
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      } else if (data is List) {
        return {'Items': data, 'TotalRecordCount': data.length};
      }
      return const {};
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // Retry once with refreshed authentication
        session = await authenticate(forceRefresh: true);
        final retryRes = await _dio.get<dynamic>(
          '$baseUrl$path',
          queryParameters: query,
          options: Options(
            headers: _authHeaders(session.token),
          ),
        );
        if (retryRes.data is Map<String, dynamic>) {
          return retryRes.data as Map<String, dynamic>;
        }
        return const {};
      }
      throw JellyfinException(e.message ?? e.toString(), code: e.response?.statusCode);
    }
  }

  /// Tests the connection to the Jellyfin server.
  Future<ConnectionTestResult> testConnection() async {
    try {
      // 1. Check server public info
      String serverVer = 'Jellyfin';
      try {
        final infoRes = await _dio.get<dynamic>(
          '$baseUrl/System/Info/Public',
          options: Options(
            headers: _authHeaders(),
          ),
        );
        if (infoRes.data is Map<String, dynamic>) {
          final data = infoRes.data as Map<String, dynamic>;
          final v = data['Version'] as String?;
          final name = data['ServerName'] as String?;
          if (v != null) {
            serverVer = name != null ? '$name ($v)' : 'v$v';
          }
        }
      } catch (_) {}

      // 2. Authenticate
      final session = await authenticate(forceRefresh: true);

      // 3. Count songs and albums
      int? songCount;
      int? albumCount;
      try {
        final songsRes = await _get(
          '/Users/${session.userId}/Items',
          {
            'IncludeItemTypes': 'Audio',
            'Recursive': true,
            'Limit': 0,
          },
        );
        songCount = songsRes['TotalRecordCount'] as int?;

        final albumsRes = await _get(
          '/Users/${session.userId}/Items',
          {
            'IncludeItemTypes': 'MusicAlbum',
            'Recursive': true,
            'Limit': 0,
          },
        );
        albumCount = albumsRes['TotalRecordCount'] as int?;
      } catch (_) {}

      return ConnectionTestResult.success(
        message: 'Connected successfully',
        serverVersion: serverVer,
        songCount: songCount,
        albumCount: albumCount,
      );
    } on JellyfinException catch (e) {
      return ConnectionTestResult.failure(e.message);
    } catch (e) {
      return ConnectionTestResult.failure('Error: $e');
    }
  }

  /// Builds stream URL for a given track id.
  String buildStreamUrl(String trackId, {int? maxBitRate}) {
    final token = _sessionCache[server.id]?.token ?? '';
    final bitRate = maxBitRate ?? server.maxBitRate;
    if (bitRate != null && bitRate > 0) {
      final bps = bitRate * 1000;
      return '$baseUrl/Audio/$trackId/stream?static=false&maxStreamingBitrate=$bps&api_key=$token';
    }
    return '$baseUrl/Audio/$trackId/stream?static=true&api_key=$token';
  }

  /// Builds cover art URL for a given item id.
  String buildCoverArtUrl(String itemId, {int size = 300}) {
    final token = _sessionCache[server.id]?.token ?? '';
    final tokenParam = token.isNotEmpty ? '&api_key=$token' : '';
    return '$baseUrl/Items/$itemId/Images/Primary?maxWidth=$size&maxHeight=$size&quality=90$tokenParam';
  }

  /// Fetches raw cover art bytes for a given item id.
  Future<Uint8List?> getCoverArtBytes(String itemId, {int size = 300}) async {
    try {
      final url = buildCoverArtUrl(itemId, size: size);
      final res = await _dio.get<List<int>>(
        url,
        options: Options(
          headers: _authHeaders(),
          responseType: ResponseType.bytes,
        ),
      );
      final data = res.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  /// Normalizes Jellyfin item to Subsonic-compatible song JSON.
  static Map<String, dynamic> normalizeSongItem(Map<String, dynamic> item) {
    final id = item['Id'] as String? ?? '';
    final name = item['Name'] as String? ?? '';
    final artistsList = item['Artists'] as List?;
    final artistName = artistsList != null && artistsList.isNotEmpty
        ? artistsList.join(', ')
        : (item['AlbumArtist'] as String? ?? '');
    final albumName = item['Album'] as String? ?? '';
    final albumId = item['AlbumId'] as String? ?? '';
    final trackNum = item['IndexNumber'] as int?;
    final discNum = item['ParentIndexNumber'] as int?;
    final year = item['ProductionYear'] as int?;
    final ticks = item['RunTimeTicks'] as num? ?? 0;
    final durationSec = (ticks / 10000000).round();
    final container = item['Container'] as String? ?? 'mp3';
    final isStarred = item['UserData']?['IsFavorite'] == true;

    return {
      'id': id,
      'title': name,
      'name': name,
      'artist': artistName,
      'album': albumName,
      'albumId': albumId,
      'track': trackNum,
      'discNumber': discNum,
      'year': year,
      'duration': durationSec,
      'coverArt': albumId.isNotEmpty ? albumId : id,
      'suffix': container,
      'starred': isStarred ? DateTime.now().toIso8601String() : null,
      'isFavorite': isStarred,
    };
  }

  /// Normalizes Jellyfin item to Subsonic-compatible album JSON.
  static Map<String, dynamic> normalizeAlbumItem(Map<String, dynamic> item) {
    final id = item['Id'] as String? ?? '';
    final name = item['Name'] as String? ?? '';
    final artistName = item['AlbumArtist'] as String? ??
        ((item['Artists'] as List?)?.join(', ') ?? '');
    final year = item['ProductionYear'] as int?;
    final songCount = item['ChildCount'] as int? ?? item['SongCount'] as int? ?? 0;
    final ticks = item['RunTimeTicks'] as num? ?? 0;
    final durationSec = (ticks / 10000000).round();
    final isStarred = item['UserData']?['IsFavorite'] == true;

    return {
      'id': id,
      'name': name,
      'title': name,
      'artist': artistName,
      'year': year,
      'songCount': songCount,
      'duration': durationSec,
      'coverArt': id,
      'starred': isStarred ? DateTime.now().toIso8601String() : null,
      'isFavorite': isStarred,
    };
  }

  /// Normalizes Jellyfin artist to Subsonic-compatible artist JSON.
  static Map<String, dynamic> normalizeArtistItem(Map<String, dynamic> item) {
    final id = item['Id'] as String? ?? '';
    final name = item['Name'] as String? ?? '';
    final albumCount = item['AlbumCount'] as int? ?? item['ChildCount'] as int? ?? 0;
    final songCount = item['SongCount'] as int? ?? 0;
    final isStarred = item['UserData']?['IsFavorite'] == true;

    return {
      'id': id,
      'name': name,
      'albumCount': albumCount,
      'songCount': songCount,
      'coverArt': id,
      'starred': isStarred ? DateTime.now().toIso8601String() : null,
      'isFavorite': isStarred,
    };
  }

  /// Fetches artists list.
  Future<List<Map<String, dynamic>>> getArtists() async {
    final session = await authenticate();
    final res = await _get(
      '/Artists',
      {
        'userId': session.userId,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Recursive': true,
        'Fields': 'ItemCounts',
      },
    );

    final items = res['Items'] as List? ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(normalizeArtistItem)
        .toList();
  }

  /// Fetches albums list with pagination and sorting.
  Future<List<Map<String, dynamic>>> getAlbumList({
    String type = 'alphabeticalByName',
    int size = 500,
    int offset = 0,
  }) async {
    final session = await authenticate();
    String sortBy = 'SortName';
    String sortOrder = 'Ascending';
    Map<String, dynamic> extra = {};

    switch (type) {
      case 'newest':
      case 'recent':
        sortBy = 'DateCreated';
        sortOrder = 'Descending';
        break;
      case 'frequent':
        sortBy = 'PlayCount';
        sortOrder = 'Descending';
        break;
      case 'starred':
        extra['Filters'] = 'IsFavorite';
        sortBy = 'SortName';
        break;
      case 'random':
        sortBy = 'Random';
        break;
      case 'alphabeticalByName':
      default:
        sortBy = 'SortName';
        sortOrder = 'Ascending';
        break;
    }

    final query = {
      'IncludeItemTypes': 'MusicAlbum',
      'Recursive': true,
      'StartIndex': offset,
      'Limit': size,
      'SortBy': sortBy,
      'SortOrder': sortOrder,
      'Fields': 'ChildCount,ItemCounts',
      ...extra,
    };

    final res = await _get('/Users/${session.userId}/Items', query);
    final items = res['Items'] as List? ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(normalizeAlbumItem)
        .toList();
  }

  /// Fetches details for an album including its songs.
  Future<Map<String, dynamic>?> getAlbum(String albumId) async {
    final session = await authenticate();

    // 1. Fetch album item info
    Map<String, dynamic>? albumInfo;
    try {
      albumInfo = await _get(
        '/Users/${session.userId}/Items/$albumId',
        {'Fields': 'ChildCount,ItemCounts'},
      );
    } catch (_) {}

    // 2. Fetch tracks belonging to this album
    final tracksRes = await _get(
      '/Users/${session.userId}/Items',
      {
        'ParentId': albumId,
        'IncludeItemTypes': 'Audio',
        'SortBy': 'ParentIndexNumber,IndexNumber,SortName',
        'SortOrder': 'Ascending',
      },
    );

    final rawTracks = tracksRes['Items'] as List? ?? [];
    final normalizedTracks = rawTracks
        .whereType<Map<String, dynamic>>()
        .map(normalizeSongItem)
        .toList();

    final result = albumInfo != null ? normalizeAlbumItem(albumInfo) : <String, dynamic>{'id': albumId};
    result['song'] = normalizedTracks;
    if (normalizedTracks.isNotEmpty) {
      result['songCount'] = normalizedTracks.length;
    }
    return result;
  }

  /// Fetches artist details including their albums and songs.
  Future<Map<String, dynamic>?> getArtist(String artistId) async {
    final session = await authenticate();

    // 1. Fetch artist albums
    final albumsRes = await _get(
      '/Users/${session.userId}/Items',
      {
        'ArtistIds': artistId,
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': true,
        'SortBy': 'ProductionYear,SortName',
        'SortOrder': 'Descending',
        'Fields': 'ChildCount,ItemCounts',
      },
    );
    final rawAlbums = albumsRes['Items'] as List? ?? [];
    final normalizedAlbums = rawAlbums
        .whereType<Map<String, dynamic>>()
        .map(normalizeAlbumItem)
        .toList();

    // 2. Fetch artist songs
    final songsRes = await _get(
      '/Users/${session.userId}/Items',
      {
        'ArtistIds': artistId,
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': 200,
      },
    );
    final rawSongs = songsRes['Items'] as List? ?? [];
    final normalizedSongs = rawSongs
        .whereType<Map<String, dynamic>>()
        .map(normalizeSongItem)
        .toList();

    return {
      'id': artistId,
      'album': normalizedAlbums,
      'song': normalizedSongs,
    };
  }

  /// Fetches artist info / biography.
  Future<Map<String, dynamic>?> getArtistInfo(String artistId) async {
    try {
      final session = await authenticate();
      final item = await _get('/Users/${session.userId}/Items/$artistId');
      final overview = item['Overview'] as String? ?? '';
      return {
        'biography': overview,
        'musicBrainzId': (item['ProviderIds'] as Map?)?['MusicBrainzArtist'] as String?,
      };
    } catch (_) {
      return null;
    }
  }

  /// Fetches a single song by ID.
  Future<Map<String, dynamic>?> getSong(String songId) async {
    try {
      final session = await authenticate();
      final item = await _get('/Users/${session.userId}/Items/$songId');
      return normalizeSongItem(item);
    } catch (_) {
      return null;
    }
  }

  /// Fetches songs list with search, pagination, and sorting.
  Future<List<Map<String, dynamic>>> getSongs({
    String query = '',
    int count = 500,
    int offset = 0,
    String? sortBy,
    bool sortAsc = true,
  }) async {
    final session = await authenticate();
    final params = <String, dynamic>{
      'IncludeItemTypes': 'Audio',
      'Recursive': true,
      'StartIndex': offset,
      'Limit': count,
      'SortBy': sortBy ?? 'SortName',
      'SortOrder': sortAsc ? 'Ascending' : 'Descending',
    };
    if (query.trim().isNotEmpty) {
      params['SearchTerm'] = query.trim();
    }

    final res = await _get('/Users/${session.userId}/Items', params);
    final items = res['Items'] as List? ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(normalizeSongItem)
        .toList();
  }

  /// Fetches all playlists.
  Future<List<Map<String, dynamic>>> getPlaylists() async {
    final session = await authenticate();
    final res = await _get(
      '/Users/${session.userId}/Items',
      {
        'IncludeItemTypes': 'Playlist',
        'Recursive': true,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Fields': 'ItemCounts,ChildCount,CumulativeRunTimeTicks,PrimaryImageAspectRatio',
      },
    );

    final items = res['Items'] as List? ?? [];
    return items.whereType<Map<String, dynamic>>().map((item) {
      final id = item['Id'] as String? ?? '';
      final name = item['Name'] as String? ?? '';
      final songCount = item['ChildCount'] as int? ?? item['SongCount'] as int? ?? 0;
      final ticks = item['RunTimeTicks'] as num? ?? 0;
      return {
        'id': id,
        'name': name,
        'songCount': songCount,
        'duration': (ticks / 10000000).round(),
        'coverArt': id,
      };
    }).toList();
  }

  /// Fetches playlist details including songs.
  Future<Map<String, dynamic>?> getPlaylist(String playlistId) async {
    final session = await authenticate();
    final res = await _get(
      '/Playlists/$playlistId/Items',
      {
        'userId': session.userId,
      },
    );

    final items = res['Items'] as List? ?? [];
    final tracks = items
        .whereType<Map<String, dynamic>>()
        .map(normalizeSongItem)
        .toList();

    return {
      'id': playlistId,
      'entry': tracks,
      'song': tracks,
    };
  }

  /// Star / favorite or unstar an item.
  Future<bool> setFavorite(String itemId, bool isFavorite) async {
    final session = await authenticate();
    try {
      if (isFavorite) {
        await _dio.post<dynamic>(
          '$baseUrl/Users/${session.userId}/FavoriteItems/$itemId',
          options: Options(
            headers: _authHeaders(session.token),
          ),
        );
      } else {
        await _dio.delete<dynamic>(
          '$baseUrl/Users/${session.userId}/FavoriteItems/$itemId',
          options: Options(
            headers: _authHeaders(session.token),
          ),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stars (favorites) a song, album, or artist.
  Future<bool> star({
    String? id,
    String? albumId,
    String? artistId,
  }) async {
    final targetId = id ?? albumId ?? artistId;
    if (targetId == null) return false;
    return setFavorite(targetId, true);
  }

  /// Unstars (removes from favorites) a song, album, or artist.
  Future<bool> unstar({
    String? id,
    String? albumId,
    String? artistId,
  }) async {
    final targetId = id ?? albumId ?? artistId;
    if (targetId == null) return false;
    return setFavorite(targetId, false);
  }

  /// Fetches starred / favorite songs.
  Future<List<Map<String, dynamic>>> getStarredSongs() async {
    final session = await authenticate();
    final res = await _get(
      '/Users/${session.userId}/Items',
      {
        'IncludeItemTypes': 'Audio',
        'Filters': 'IsFavorite',
        'Recursive': true,
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
      },
    );

    final items = res['Items'] as List? ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(normalizeSongItem)
        .toList();
  }

  /// Fetches starred / favorite artists.
  Future<List<Map<String, dynamic>>> getStarredArtists() async {
    final session = await authenticate();
    final res = await _get(
      '/Artists',
      {
        'userId': session.userId,
        'Filters': 'IsFavorite',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Recursive': true,
        'Fields': 'ItemCounts',
      },
    );

    final items = res['Items'] as List? ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(normalizeArtistItem)
        .toList();
  }

  /// Creates a playlist on the Jellyfin server.
  Future<Map<String, dynamic>?> createPlaylist({
    required String name,
    List<String>? songIds,
  }) async {
    final session = await authenticate();
    try {
      final res = await _dio.post<dynamic>(
        '$baseUrl/Playlists',
        data: {
          'Name': name,
          'Ids': songIds ?? [],
          'UserId': session.userId,
          'MediaType': 'Audio',
        },
        options: Options(
          headers: {
            ..._authHeaders(session.token),
            'Content-Type': 'application/json',
          },
        ),
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        final createdId = (data['Id'] ?? data['id'])?.toString() ?? '';
        return {
          'id': createdId,
          'name': name,
        };
      }
    } catch (e) {
      debugPrint('Error creating Jellyfin playlist: $e');
    }
    return null;
  }

  /// Updates a playlist on the Jellyfin server (renaming, adding items).
  Future<bool> updatePlaylist({
    required String playlistId,
    String? name,
    List<String>? songIdsToAdd,
    List<int>? songIndexesToRemove,
  }) async {
    final session = await authenticate();
    try {
      if (name != null && name.isNotEmpty) {
        await _dio.post<dynamic>(
          '$baseUrl/Items/$playlistId',
          data: {'Name': name, 'Id': playlistId},
          options: Options(
            headers: _authHeaders(session.token),
          ),
        );
      }
      if (songIdsToAdd != null && songIdsToAdd.isNotEmpty) {
        await _dio.post<dynamic>(
          '$baseUrl/Playlists/$playlistId/Items',
          data: {},
          queryParameters: {
            'ids': songIdsToAdd.join(','),
            'userId': session.userId,
          },
          options: Options(
            headers: _authHeaders(session.token),
          ),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error updating Jellyfin playlist: $e');
      return false;
    }
  }

  /// Deletes a playlist on the Jellyfin server.
  Future<bool> deletePlaylist(String playlistId) async {
    final session = await authenticate();
    try {
      await _dio.delete<dynamic>(
        '$baseUrl/Items/$playlistId',
        options: Options(
          headers: _authHeaders(session.token),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Searches songs, albums, and artists.
  Future<Map<String, dynamic>> search(
    String query, {
    int artistCount = 20,
    int albumCount = 20,
    int songCount = 50,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return {
        'song': <Map<String, dynamic>>[],
        'album': <Map<String, dynamic>>[],
        'artist': <Map<String, dynamic>>[],
      };
    }

    final session = await authenticate();

    final results = await Future.wait([
      _get(
        '/Artists',
        {
          'userId': session.userId,
          'SearchTerm': trimmed,
          'Limit': artistCount,
          'Fields': 'ItemCounts',
        },
      ).catchError((_) => <String, dynamic>{}),
      _get(
        '/Users/${session.userId}/Items',
        {
          'SearchTerm': trimmed,
          'IncludeItemTypes': 'MusicAlbum',
          'Recursive': true,
          'Limit': albumCount,
          'Fields': 'ChildCount,ItemCounts',
        },
      ).catchError((_) => <String, dynamic>{}),
      _get(
        '/Users/${session.userId}/Items',
        {
          'SearchTerm': trimmed,
          'IncludeItemTypes': 'Audio',
          'Recursive': true,
          'Limit': songCount,
        },
      ).catchError((_) => <String, dynamic>{}),
    ]);

    final artistItems = results[0]['Items'] as List? ?? [];
    final albumItems = results[1]['Items'] as List? ?? [];
    final songItems = results[2]['Items'] as List? ?? [];

    final artists = artistItems
        .whereType<Map<String, dynamic>>()
        .map(normalizeArtistItem)
        .toList();
    final albums = albumItems
        .whereType<Map<String, dynamic>>()
        .map(normalizeAlbumItem)
        .toList();
    final songs = songItems
        .whereType<Map<String, dynamic>>()
        .map(normalizeSongItem)
        .toList();

    return {
      'song': songs,
      'album': albums,
      'artist': artists,
    };
  }

  /// Fetches lyrics for a given track id (supports Jellyfin 10.9+ /Audio/{id}/Lyrics).
  Future<String?> getLyrics(String trackId) async {
    final session = await authenticate();
    try {
      final res = await _dio.get<dynamic>(
        '$baseUrl/Audio/$trackId/Lyrics',
        options: Options(
          headers: _authHeaders(session.token),
        ),
      );
      final data = res.data;
      if (data is String && data.trim().isNotEmpty) {
        return data;
      } else if (data is Map<String, dynamic>) {
        // Jellyfin lyrics structure (Lyrics / Lyrics.Lyrics / Lyrics.Lines)
        final lyricsObj = data['Lyrics'];
        if (lyricsObj is String && lyricsObj.trim().isNotEmpty) {
          return lyricsObj;
        }
        final lines = (data['Lyrics'] is Map ? data['Lyrics']['Lines'] : data['Lines']) as List?;
        if (lines != null && lines.isNotEmpty) {
          final sb = StringBuffer();
          for (final line in lines) {
            if (line is Map<String, dynamic>) {
              final startTicks = line['Start'] as num? ?? 0;
              final text = line['Text'] as String? ?? '';
              final totalMillis = (startTicks / 10000).round();
              final minutes = (totalMillis ~/ 60000).toString().padLeft(2, '0');
              final seconds = ((totalMillis % 60000) ~/ 1000).toString().padLeft(2, '0');
              final millis = ((totalMillis % 1000) ~/ 10).toString().padLeft(2, '0');
              sb.writeln('[$minutes:$seconds.$millis]$text');
            }
          }
          final lrc = sb.toString().trim();
          if (lrc.isNotEmpty) return lrc;
        }
      }
    } catch (_) {}
    return null;
  }
}
