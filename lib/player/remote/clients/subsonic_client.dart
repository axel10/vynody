import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import '../remote_server_models.dart';
import '../../lyrics/sources/media_server_capability_cache.dart';
import '../../lyrics/sources/media_server_lyrics_result.dart';

class SubsonicException implements Exception {
  final String message;
  final int? code;

  /// HTTP 状态码（若有）。Subsonic 的业务错误走 `code`，但「接口不存在」
  /// 这类情况是由反向代理或框架直接回 404，只能从这里看出来。
  final int? httpStatus;

  const SubsonicException(this.message, {this.code, this.httpStatus});

  /// 服务端拒绝下载（Navidrome 关闭下载时返回该码）。
  bool get isDownloadsDisabled => code == SubsonicClient.errorDownloadsDisabled;

  /// 服务端不认识该接口。
  ///
  /// OpenSubsonic 扩展端点（如 `getLyricsBySongId.view`）在未实现的实现上，
  /// 要么被框架直接回 404，要么回 code 0 + "Unknown method"。
  bool get isUnknownMethod {
    if (httpStatus == 404) return true;
    if (code != 0 && code != 30) return false;
    final lower = message.toLowerCase();
    return lower.contains('method') || lower.contains('not implemented');
  }

  /// 请求的资源不存在（Subsonic 错误码 70）。
  bool get isNotFound => code == SubsonicClient.errorNotFound;

  @override
  String toString() => message;
}

class SubsonicClient {
  static const String clientName = 'Vynody';
  static const String apiVersion = '1.16.1';

  /// Subsonic 错误码：当前用户无权执行该操作。Navidrome 关闭服务端下载时，
  /// `download.view` 返回的就是这个码（message 为 "downloads are disabled"）。
  static const int errorDownloadsDisabled = 50;

  /// Subsonic 错误码：请求的资源不存在。
  static const int errorNotFound = 70;

  final RemoteServer server;
  final String password;
  late final Dio _dio;

  SubsonicClient({
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
            headers: {'User-Agent': 'Vynody/$apiVersion'},
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

  /// Normalizes base URL (e.g. removes trailing slash and /rest).
  String get baseUrl {
    var raw = server.url.trim();
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      raw = 'http://$raw';
    }
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.endsWith('/rest')) {
      raw = raw.substring(0, raw.length - 5);
    }
    return raw;
  }

  /// Generates Subsonic authentication parameters (token + salt).
  /// Uses a deterministic salt based on server and username so generated media and cover URLs
  /// remain stable across widget builds and scrolls, enabling Flutter ImageCache and HTTP caching.
  Map<String, String> _buildAuthParams() {
    final salt = md5
        .convert(utf8.encode('vynody_${server.id}_${server.username}'))
        .toString()
        .substring(0, 12);
    final token = md5.convert(utf8.encode(password + salt)).toString();

    return {
      'u': server.username,
      't': token,
      's': salt,
      'v': apiVersion,
      'c': clientName,
      'f': 'json',
    };
  }

  /// Constructs a full endpoint URL with required query parameters.
  String buildUrl(String endpoint, [Map<String, dynamic>? query]) {
    final params = Map<String, dynamic>.from(_buildAuthParams());
    if (query != null) {
      params.addAll(query);
    }
    final queryParts = <String>[];
    for (final entry in params.entries) {
      final key = entry.key;
      final val = entry.value;
      if (val is Iterable) {
        for (final item in val) {
          queryParts.add(
            '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(item.toString())}',
          );
        }
      } else if (val != null) {
        queryParts.add(
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(val.toString())}',
        );
      }
    }
    final queryString = queryParts.join('&');
    return '$baseUrl/rest/$endpoint?$queryString';
  }

  /// Constructs stream URL for a given track id.
  String buildStreamUrl(String trackId, {int? maxBitRate}) {
    final params = <String, dynamic>{'id': trackId};
    final bitRate = maxBitRate ?? server.maxBitRate;
    if (bitRate != null && bitRate > 0) {
      params['maxBitRate'] = bitRate;
    }
    return buildUrl('stream', params);
  }

  /// 识别「HTTP 200 但内容是失败 JSON」的响应体。
  ///
  /// 二进制端点（`download.view` / `stream`）失败时不会返回 4xx，而是 200 +
  /// `subsonic-response.status == "failed"` 的 JSON；下载类调用必须先过这一道，
  /// 否则错误体会被当成音频落盘并标记完成。返回 null 表示这不是错误体
  /// （真实音频字节、空内容、正常响应）。
  static SubsonicException? parseErrorBody(String body) {
    final trimmed = body.trimLeft();
    // 音频二进制不会以 '{' 开头，先做一次零成本的形态判断。
    if (trimmed.isEmpty || trimmed.codeUnitAt(0) != 0x7B /* { */) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return null;
      final sub = decoded['subsonic-response'];
      if (sub is! Map<String, dynamic>) return null;
      if (sub['status'] != 'failed') return null;
      final error = sub['error'];
      if (error is! Map<String, dynamic>) return null;
      final message = error['message'] as String? ?? 'Subsonic request failed';
      final code = error['code'];
      return SubsonicException(message, code: code is int ? code : null);
    } catch (_) {
      return null;
    }
  }

  // 检查「刚下载完的文件」不要用这里，用 `RemotePayloadGuard.inspect`：
  // 它只读文件头（反代错误页可能几 MB）、还能识别 HTML 错误页。

  /// Constructs cover art URL for a given cover ID or track ID.
  String buildCoverArtUrl(String coverArtId, {int size = 300}) {
    return buildUrl('getCoverArt', {'id': coverArtId, 'size': size});
  }

  /// Fetches raw cover art bytes. Returns null if cover art is missing, server returns an error, or content is not an image.
  Future<Uint8List?> getCoverArtBytes(String coverArtId, {int size = 300}) async {
    try {
      final url = buildCoverArtUrl(coverArtId, size: size);
      final res = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data == null || data.isEmpty) return null;

      final contentType = res.headers.value('content-type')?.toLowerCase() ?? '';
      if (contentType.contains('json') ||
          contentType.contains('xml') ||
          contentType.contains('text') ||
          contentType.contains('html')) {
        return null;
      }

      final bytes = Uint8List.fromList(data);
      if (!_isValidImage(bytes)) {
        return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static bool _isValidImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final first = bytes[0];
    // Reject common textual responses: '{' (JSON), '<' (XML/HTML), '[' (JSON Array)
    if (first == 0x7B || first == 0x3C || first == 0x5B) return false;

    // JPEG (FF D8)
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    // PNG (89 50 4E 47)
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
    // GIF (GIF87a / GIF89a: 47 49 46)
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
    // WebP (RIFF .... WEBP)
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return true;
    }
    // BMP (BM: 42 4D)
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true;

    return false;
  }

  Future<Map<String, dynamic>> _getSubsonicData(
    String endpoint, [
    Map<String, dynamic>? params,
    CancelToken? cancelToken,
  ]) async {
    try {
      final url = buildUrl(endpoint, params);
      final response = await _dio.get<dynamic>(url, cancelToken: cancelToken);
      final data = response.data;
      if (data == null) {
        throw const SubsonicException('Empty response from server');
      }
      Map<String, dynamic>? subsonic;
      if (data is Map<String, dynamic>) {
        final sub = data['subsonic-response'];
        if (sub is Map<String, dynamic>) {
          subsonic = sub;
        }
      } else if (data is String) {
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) {
            final sub = decoded['subsonic-response'];
            if (sub is Map<String, dynamic>) {
              subsonic = sub;
            }
          }
        } catch (_) {}
      }

      if (subsonic == null) {
        throw const SubsonicException('Invalid Subsonic API response');
      }

      final status = subsonic['status'] as String?;
      if (status != 'ok') {
        final error = subsonic['error'] as Map<String, dynamic>?;
        final errorMsg =
            error?['message'] as String? ?? 'Subsonic request failed';
        final code = error?['code'] as int?;
        throw SubsonicException(errorMsg, code: code);
      }
      return subsonic;
    } on DioException catch (e) {
      if (e.response != null) {
        final respData = e.response!.data;
        if (respData is Map<String, dynamic>) {
          final subError = respData['subsonic-response']?['error'];
          if (subError is Map<String, dynamic>) {
            final msg = subError['message'] as String?;
            final code = subError['code'] as int?;
            if (msg != null && msg.isNotEmpty) {
              throw SubsonicException(msg, code: code);
            }
          }
        }
        if (e.response!.statusCode == 401) {
          throw const SubsonicException(
            '401 Unauthorized: Invalid username or password',
            httpStatus: 401,
          );
        }
        final status = e.response!.statusCode;
        final statusText = e.response!.statusMessage ?? '';
        throw SubsonicException(
          'HTTP $status $statusText'.trim(),
          httpStatus: status,
        );
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw const SubsonicException('Connection timed out');
      }
      if (e.type == DioExceptionType.connectionError) {
        final msg = e.error?.toString() ?? e.message;
        throw SubsonicException(
          msg != null && msg.isNotEmpty ? msg : 'Connection error',
        );
      }
      throw SubsonicException(e.message ?? e.toString());
    }
  }

  /// Tests the connection to the Subsonic/Navidrome server.
  Future<ConnectionTestResult> testConnection() async {
    try {
      final subsonic = await _getSubsonicData('ping.view');
      final version = subsonic['version'] as String? ?? 'Unknown';
      final serverVersion = subsonic['serverVersion'] as String?;
      final displayVer = serverVersion != null
          ? '$serverVersion (API v$version)'
          : 'API v$version';

      int? songCount;
      int? albumCount;
      try {
        final scanRes = await _getSubsonicData('getScanStatus.view');
        final scanData = scanRes['scanStatus'];
        if (scanData is Map<String, dynamic>) {
          songCount = scanData['count'] as int?;
        }
      } catch (_) {}

      // 连接已经通了：之前因网络抖动而误判的能力项不再成立，清掉重试一次。
      MediaServerCapabilityCache.instance.clear(server.id);
      return ConnectionTestResult.success(
        message: 'Connected successfully',
        serverVersion: displayVer,
        songCount: songCount,
        albumCount: albumCount,
      );
    } on SubsonicException catch (e) {
      return ConnectionTestResult.failure(e.message);
    } catch (e) {
      return ConnectionTestResult.failure('Error: $e');
    }
  }

  /// Fetches the list of artists.
  Future<List<Map<String, dynamic>>> getArtists() async {
    final subsonic = await _getSubsonicData('getArtists.view');
    final artistsRoot = subsonic['artists'];
    if (artistsRoot is Map<String, dynamic>) {
      final indexList = artistsRoot['index'] as List?;
      if (indexList != null) {
        final List<Map<String, dynamic>> allArtists = [];
        for (final index in indexList) {
          final artistList = index['artist'] as List?;
          if (artistList != null) {
            allArtists.addAll(artistList.whereType<Map<String, dynamic>>());
          }
        }
        return allArtists;
      }
    }
    return const [];
  }

  /// Fetches an artist's details including their albums and songs.
  Future<Map<String, dynamic>?> getArtist(String artistId) async {
    final subsonic = await _getSubsonicData('getArtist.view', {'id': artistId});
    final artist = subsonic['artist'];
    if (artist is Map<String, dynamic>) {
      return artist;
    }
    return null;
  }

  /// Fetches extended artist information (biography, etc.) if supported.
  Future<Map<String, dynamic>?> getArtistInfo(String artistId) async {
    try {
      final subsonic =
          await _getSubsonicData('getArtistInfo2.view', {'id': artistId});
      final info = subsonic['artistInfo2'] ?? subsonic['artistInfo'];
      if (info is Map<String, dynamic>) {
        return info;
      }
    } catch (_) {
      try {
        final subsonic =
            await _getSubsonicData('getArtistInfo.view', {'id': artistId});
        final info = subsonic['artistInfo'] ?? subsonic['artistInfo2'];
        if (info is Map<String, dynamic>) {
          return info;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Fetches album list by type (e.g. 'recent', 'newest', 'frequent', 'alphabeticalByName', 'starred', 'random').
  Future<List<Map<String, dynamic>>> getAlbumList({
    String type = 'alphabeticalByName',
    int size = 500,
    int offset = 0,
  }) async {
    final subsonic = await _getSubsonicData('getAlbumList2.view', {
      'type': type,
      'size': size,
      'offset': offset,
    });
    final albumRoot = subsonic['albumList2'] ?? subsonic['albumList'];
    final albumData = albumRoot?['album'];
    if (albumData is List) {
      return albumData.whereType<Map<String, dynamic>>().toList();
    } else if (albumData is Map<String, dynamic>) {
      return [albumData];
    }
    return const [];
  }

  /// Fetches all music genres with their song / album counts.
  ///
  /// Subsonic 的流派没有独立 ID，这里直接把流派名当作 id 使用；
  /// [getSongsByGenre] 也按流派名查询，两边保持一致。
  Future<List<Map<String, dynamic>>> getGenres() async {
    final subsonic = await _getSubsonicData('getGenres.view');
    final Object? root = subsonic['genres'];
    final Object? raw = root is Map<String, dynamic> ? root['genre'] : root;

    final List<Map<String, dynamic>> entries;
    if (raw is List) {
      entries = raw.whereType<Map<String, dynamic>>().toList();
    } else if (raw is Map<String, dynamic>) {
      entries = [raw];
    } else {
      entries = const [];
    }

    final genres = <Map<String, dynamic>>[];
    for (final entry in entries) {
      final name = (entry['value'] ?? entry['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      genres.add({
        'id': name,
        'name': name,
        'songCount': (entry['songCount'] as num?)?.toInt() ?? 0,
        'albumCount': (entry['albumCount'] as num?)?.toInt() ?? 0,
        'coverArt': null,
      });
    }
    return genres;
  }

  /// Fetches songs belonging to a genre (matched by genre name).
  Future<List<Map<String, dynamic>>> getSongsByGenre(
    String genre, {
    int count = 500,
    int offset = 0,
  }) async {
    final subsonic = await _getSubsonicData('getSongsByGenre.view', {
      'genre': genre,
      'count': count,
      'offset': offset,
    });
    final Object? root = subsonic['songsByGenre'] ?? subsonic['songs'];
    final Object? raw = root is Map<String, dynamic> ? root['song'] : root;

    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().toList();
    }
    if (raw is Map<String, dynamic>) {
      return [raw];
    }
    return const [];
  }

  /// Fetches details for an album including its songs.
  Future<Map<String, dynamic>?> getAlbum(String albumId) async {
    final subsonic = await _getSubsonicData('getAlbum.view', {'id': albumId});
    final album = subsonic['album'];
    if (album is Map<String, dynamic>) {
      return album;
    }
    return null;
  }

  /// Fetches details for a single song by ID.
  Future<Map<String, dynamic>?> getSong(String songId) async {
    try {
      final subsonic = await _getSubsonicData('getSong.view', {'id': songId});
      final song = subsonic['song'];
      if (song is Map<String, dynamic>) {
        return song;
      }
    } catch (_) {}
    return null;
  }

  /// Fetches all playlists.
  Future<List<Map<String, dynamic>>> getPlaylists() async {
    final subsonic = await _getSubsonicData('getPlaylists.view');
    final playlists = subsonic['playlists']?['playlist'] as List?;
    if (playlists != null) {
      return playlists.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  /// Fetches details for a playlist including its songs.
  Future<Map<String, dynamic>?> getPlaylist(String playlistId) async {
    final subsonic =
        await _getSubsonicData('getPlaylist.view', {'id': playlistId});
    final playlist = subsonic['playlist'];
    if (playlist is Map<String, dynamic>) {
      return playlist;
    }
    return null;
  }

  /// Fetches starred items (artists, albums, songs) using Subsonic getStarred2.view.
  Future<Map<String, dynamic>> getStarred2({String? musicFolderId}) async {
    final params = <String, dynamic>{};
    if (musicFolderId != null) params['musicFolderId'] = musicFolderId;
    try {
      final subsonic = await _getSubsonicData('getStarred2.view', params);
      final root = subsonic['starred2'] ?? subsonic['starred'];
      if (root is Map<String, dynamic>) {
        return root;
      }
    } catch (_) {
      try {
        final subsonic = await _getSubsonicData('getStarred.view', params);
        final root = subsonic['starred'] ?? subsonic['starred2'];
        if (root is Map<String, dynamic>) {
          return root;
        }
      } catch (_) {}
    }
    return const {};
  }

  /// Fetches starred songs as a list of map entries.
  Future<List<Map<String, dynamic>>> getStarredSongs() async {
    final starred = await getStarred2();
    final songs = starred['song'];
    if (songs is List) {
      return songs.whereType<Map<String, dynamic>>().toList();
    } else if (songs is Map<String, dynamic>) {
      return [songs];
    }
    return const [];
  }

  /// Fetches starred artists as a list of map entries.
  Future<List<Map<String, dynamic>>> getStarredArtists() async {
    final starred = await getStarred2();
    final artists = starred['artist'];
    if (artists is List) {
      return artists.whereType<Map<String, dynamic>>().toList();
    } else if (artists is Map<String, dynamic>) {
      return [artists];
    }
    return const [];
  }

  /// Fetches starred albums as a list of map entries.
  Future<List<Map<String, dynamic>>> getStarredAlbums() async {
    final starred = await getStarred2();
    final albums = starred['album'];
    if (albums is List) {
      return albums.whereType<Map<String, dynamic>>().toList();
    } else if (albums is Map<String, dynamic>) {
      return [albums];
    }
    return const [];
  }

  /// Searches across songs, albums, and artists.
  Future<Map<String, dynamic>> search(String query,
      {int artistCount = 20, int albumCount = 20, int songCount = 50}) async {
    final subsonic = await _getSubsonicData('search3.view', {
      'query': query,
      'artistCount': artistCount,
      'albumCount': albumCount,
      'songCount': songCount,
    });
    final searchResult = subsonic['searchResult3'];
    if (searchResult is Map<String, dynamic>) {
      return searchResult;
    }
    return const {};
  }

  /// Fetches songs (using search3 with empty query by default, optimized in Navidrome/Subsonic).
  Future<List<Map<String, dynamic>>> getSongs({
    String query = '',
    int count = 500,
    int offset = 0,
  }) async {
    try {
      final subsonic = await _getSubsonicData('search3.view', {
        'query': query,
        'artistCount': 0,
        'albumCount': 0,
        'songCount': count,
        'songOffset': offset,
      });
      final searchResult =
          subsonic['searchResult3'] ?? subsonic['searchResult2'];
      if (searchResult is Map<String, dynamic>) {
        final songs = searchResult['song'];
        if (songs is List) {
          return songs.whereType<Map<String, dynamic>>().toList();
        } else if (songs is Map<String, dynamic>) {
          return [songs];
        }
      }
    } catch (_) {
      if (offset == 0 && query.isEmpty) {
        return getRandomSongs(size: count);
      }
      rethrow;
    }
    return const [];
  }

  /// Fetches random songs from the server.
  Future<List<Map<String, dynamic>>> getRandomSongs({int size = 500}) async {
    final subsonic = await _getSubsonicData('getRandomSongs.view', {
      'size': size,
    });
    final randomSongs = subsonic['randomSongs'];
    if (randomSongs is Map<String, dynamic>) {
      final songs = randomSongs['song'];
      if (songs is List) {
        return songs.whereType<Map<String, dynamic>>().toList();
      } else if (songs is Map<String, dynamic>) {
        return [songs];
      }
    }
    return const [];
  }

  /// 拉取歌词，返回四态结论（hit / absent / unsupported / failed）。
  ///
  /// 两级策略：
  /// 1. OpenSubsonic `getLyricsBySongId`（结构化，优先带时间轴的条目）
  /// 2. 标准 `getLyrics.view`（artist + title，纯文本为主）
  ///
  /// 服务端不支持扩展接口时记入能力缓存，之后不再重复尝试；
  /// 网络 / 认证失败不记缓存，直接返回 failed 交给上层继续下一层。
  Future<MediaServerLyricsResult> fetchLyricsResult({
    String? artist,
    String? title,
    String? id,
    CancelToken? cancelToken,
  }) async {
    final capabilities = MediaServerCapabilityCache.instance;
    const capability = MediaServerCapabilityCache.subsonicLyricsBySongId;

    // 扩展端点是否因「不存在」而跳过。legacy 也查不到时要靠它区分
    // 「服务端不支持」与「服务端确实没有这首歌的歌词」。
    var extensionUnsupported = false;

    // 1. OpenSubsonic getLyricsBySongId
    if (id != null &&
        id.isNotEmpty &&
        !capabilities.isUnsupported(server.id, capability)) {
      try {
        final subsonic = await _getSubsonicData(
          'getLyricsBySongId.view',
          {'id': id},
          cancelToken,
        );
        final parsed = _parseStructuredLyrics(subsonic);
        if (parsed != null) {
          return MediaServerLyricsResult.hit(
            parsed.text,
            variant: parsed.synced ? 'structured-synced' : 'structured-plain',
            synced: parsed.synced,
          );
        }
        // 接口通了但没有内容：继续走 legacy 兜底，部分服务端只在旧接口返回。
      } on SubsonicException catch (e) {
        if (e.isUnknownMethod) {
          extensionUnsupported = true;
          capabilities.markUnsupported(server.id, capability);
          debugPrint(
            '[Subsonic] getLyricsBySongId unsupported on "${server.id}": '
            '${e.message}',
          );
        } else if (e.isNotFound) {
          return const MediaServerLyricsResult.miss(
            MediaServerLyricsStatus.absent,
            diagnostic: 'getLyricsBySongId code 70',
          );
        } else if (_isCancelled(cancelToken)) {
          return const MediaServerLyricsResult.miss(
            MediaServerLyricsStatus.failed,
            diagnostic: 'cancelled',
          );
        } else {
          // 网络 / 认证失败：不记能力缓存，也不继续发第二个请求（会双倍超时）。
          return MediaServerLyricsResult.miss(
            MediaServerLyricsStatus.failed,
            diagnostic: e.toString(),
          );
        }
      }
    }

    // 2. Standard Subsonic getLyrics.view with artist and title
    if ((artist != null && artist.isNotEmpty) ||
        (title != null && title.isNotEmpty)) {
      try {
        final params = <String, dynamic>{};
        if (artist != null) params['artist'] = artist;
        if (title != null) params['title'] = title;
        final subsonic = await _getSubsonicData(
          'getLyrics.view',
          params,
          cancelToken,
        );
        final lyrics = subsonic['lyrics'];
        if (lyrics is Map<String, dynamic>) {
          // Navidrome 的 responses.Lyrics 序列化出来是 {artist, title, value}；
          // 'content' 是部分其他 Subsonic 实现的写法，这里两者都兼容。
          final content =
              (lyrics['value'] as String?) ?? (lyrics['content'] as String?);
          if (content != null && content.trim().isNotEmpty) {
            return MediaServerLyricsResult.hit(
              content.trim(),
              variant: 'legacy',
            );
          }
        }
        return const MediaServerLyricsResult.miss(
          MediaServerLyricsStatus.absent,
          diagnostic: 'getLyrics empty',
        );
      } on SubsonicException catch (e) {
        if (e.isNotFound) {
          return const MediaServerLyricsResult.miss(
            MediaServerLyricsStatus.absent,
            diagnostic: 'getLyrics code 70',
          );
        }
        if (_isCancelled(cancelToken)) {
          return const MediaServerLyricsResult.miss(
            MediaServerLyricsStatus.failed,
            diagnostic: 'cancelled',
          );
        }
        return MediaServerLyricsResult.miss(
          MediaServerLyricsStatus.failed,
          diagnostic: e.toString(),
        );
      }
    }

    if (extensionUnsupported) {
      return const MediaServerLyricsResult.miss(
        MediaServerLyricsStatus.unsupported,
        diagnostic: 'getLyricsBySongId unsupported',
      );
    }
    return const MediaServerLyricsResult.miss(MediaServerLyricsStatus.absent);
  }

  bool _isCancelled(CancelToken? token) {
    return token?.isCancelled ?? false;
  }

  /// 解析 structuredLyrics：优先挑带 `synced` 标记的条目。
  ({String text, bool synced})? _parseStructuredLyrics(
    Map<String, dynamic> subsonic,
  ) {
    final lyricsList = subsonic['lyricsList']?['structuredLyrics'] as List?;
    if (lyricsList == null || lyricsList.isEmpty) return null;

    Map<String, dynamic>? picked;
    List? pickedLines;
    for (final entry in lyricsList) {
      if (entry is! Map<String, dynamic>) continue;
      final lineList = entry['line'] as List?;
      if (lineList == null || lineList.isEmpty) continue;
      final isSyncedEntry = entry['synced'] == true;
      if (picked == null || (isSyncedEntry && picked['synced'] != true)) {
        picked = entry;
        pickedLines = lineList;
      }
    }
    if (pickedLines == null || pickedLines.isEmpty) return null;

    // Navidrome 对无时间轴的歌词省略 start 字段，此时必须输出纯文本，
    // 否则会把整首歌拼成一堆 [00:00.00] 的「假逐行歌词」。
    final starts = pickedLines
        .whereType<Map<String, dynamic>>()
        .map((line) => line['start'] as int?)
        .toList();
    final hasAnyStart = starts.any((start) => start != null);
    final buffer = StringBuffer();
    for (final line in pickedLines) {
      if (line is! Map<String, dynamic>) continue;
      final text = line['value'] as String? ?? '';
      if (!hasAnyStart) {
        buffer.writeln(text);
        continue;
      }
      final start = line['start'] as int? ?? 0;
      final minutes = (start ~/ 60000).toString().padLeft(2, '0');
      final seconds = ((start % 60000) ~/ 1000).toString().padLeft(2, '0');
      final millis = ((start % 1000) ~/ 10).toString().padLeft(2, '0');
      buffer.writeln('[$minutes:$seconds.$millis]$text');
    }
    final content = buffer.toString();
    if (content.trim().isEmpty) return null;
    return (text: content, synced: hasAnyStart);
  }

  /// Creates a new playlist on the Subsonic server.
  Future<Map<String, dynamic>?> createPlaylist({
    required String name,
    List<String>? songIds,
  }) async {
    final params = <String, dynamic>{'name': name};
    if (songIds != null && songIds.isNotEmpty) {
      params['songId'] = songIds;
    }
    final subsonic = await _getSubsonicData('createPlaylist.view', params);
    final playlist = subsonic['playlist'];
    if (playlist is Map<String, dynamic>) {
      return playlist;
    }
    return null;
  }

  /// Updates an existing playlist on the Subsonic server (adding/removing songs).
  Future<bool> updatePlaylist({
    required String playlistId,
    List<String>? songIdsToAdd,
    List<int>? songIndexesToRemove,
    String? name,
    String? comment,
    bool? isPublic,
  }) async {
    final params = <String, dynamic>{'playlistId': playlistId};
    if (name != null) params['name'] = name;
    if (comment != null) params['comment'] = comment;
    if (isPublic != null) params['public'] = isPublic;
    if (songIdsToAdd != null && songIdsToAdd.isNotEmpty) {
      params['songIdToAdd'] = songIdsToAdd;
    }
    if (songIndexesToRemove != null && songIndexesToRemove.isNotEmpty) {
      params['songIndexToRemove'] = songIndexesToRemove;
    }
    final subsonic = await _getSubsonicData('updatePlaylist.view', params);
    final status = subsonic['status'];
    return status == 'ok';
  }

  /// Deletes a playlist on the Subsonic server.
  Future<bool> deletePlaylist(String playlistId) async {
    final subsonic =
        await _getSubsonicData('deletePlaylist.view', {'id': playlistId});
    final status = subsonic['status'];
    return status == 'ok';
  }

  /// Stars (favorites) a song, album, or artist on the Subsonic server.
  Future<bool> star({
    String? id,
    String? albumId,
    String? artistId,
  }) async {
    final params = <String, dynamic>{};
    if (id != null) params['id'] = id;
    if (albumId != null) params['albumId'] = albumId;
    if (artistId != null) params['artistId'] = artistId;
    if (params.isEmpty) return false;

    try {
      final subsonic = await _getSubsonicData('star.view', params);
      final status = subsonic['status'];
      return status == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Unstars (removes from favorites) a song, album, or artist on the Subsonic server.
  Future<bool> unstar({
    String? id,
    String? albumId,
    String? artistId,
  }) async {
    final params = <String, dynamic>{};
    if (id != null) params['id'] = id;
    if (albumId != null) params['albumId'] = albumId;
    if (artistId != null) params['artistId'] = artistId;
    if (params.isEmpty) return false;

    try {
      final subsonic = await _getSubsonicData('unstar.view', params);
      final status = subsonic['status'];
      return status == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Constructs the direct download URL for a track.
  String buildDownloadUrl(String trackId) {
    return buildUrl('download.view', {'id': trackId});
  }

  /// 读取内嵌标签专用的「原始字节」地址。
  ///
  /// 必须显式 `format=raw` 且不带 `maxBitRate`：Navidrome 只有在不转码时才用
  /// `http.ServeContent` 提供服务（支持 Range），转码流会回 `Accept-Ranges: none`，
  /// TagLib 拿到 200 全量响应后无法分片读取，只会得到一次短读。
  ///
  /// 不走 `download.view`：Navidrome 关闭服务端下载时该端点返回错误，
  /// 而 `stream` 不受这个开关影响。
  String buildRawStreamUrl(String trackId) {
    return buildUrl('stream', {'id': trackId, 'format': 'raw'});
  }
}

