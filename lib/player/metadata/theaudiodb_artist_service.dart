import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/utils/network_client.dart';

/// TheAudioDB 艺术家元数据与代表图片查询服务
///
/// 采用 MusicBrainz MBID 解析 + TheAudioDB 查询的双重策略：
/// 1. 优先通过 MusicBrainz 查询艺人的 MBID（充分利用 MusicBrainz 的全球多语言别名与模糊匹配，如支持搜“周杰伦”匹配“Jay Chou”）；
/// 2. 拿到 MBID 后，直接调 TheAudioDB 的 `artist-mb.php` 接口精准获取艺人详情及代表图片；
/// 3. 若 MusicBrainz 未命中或无有效 MBID，回退到 TheAudioDB 的 `search.php` 原始名称搜索。
class TheAudioDbArtistService {
  TheAudioDbArtistService({
    NetworkClient? networkClient,
    MetadataDatabase? database,
    String? theAudioDbBaseUrl,
    String? musicBrainzBaseUrl,
    Duration? musicBrainzRateLimitDelay,
  })  : _networkClient = networkClient ?? NetworkClient.instance,
        _db = database ?? MetadataDatabase(),
        _baseUrl = theAudioDbBaseUrl ?? 'https://www.theaudiodb.com/api/v1/json',
        _musicBrainzBaseUrl =
            musicBrainzBaseUrl ?? 'https://musicbrainz.org/ws/2',
        _musicBrainzRateLimitDelay =
            musicBrainzRateLimitDelay ?? const Duration(milliseconds: 1000);

  static final TheAudioDbArtistService instance = TheAudioDbArtistService();

  final NetworkClient _networkClient;
  final MetadataDatabase _db;
  final String _baseUrl;
  final String _musicBrainzBaseUrl;
  final Duration _musicBrainzRateLimitDelay;

  // TheAudioDB API v1 免费测试 Key 为 123
  static const String _defaultApiKey = '123';

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// 已解析出的 MBID 内存缓存 (queryKey -> mbid)
  final Map<String, String> _resolvedMbids = <String, String>{};

  /// MusicBrainz 限流时间戳（公共非认证接口限制 1次/秒）
  static DateTime _lastMusicBrainzRequestAt =
      DateTime.fromMillisecondsSinceEpoch(0);

  /// 正在进行的请求去重映射
  final Map<String, Future<String?>> _inFlightFetches =
      <String, Future<String?>>{};

  /// 艺术家头像获取并持久化成功时的通知事件流（携带 queryKey）
  final StreamController<String> _imageUpdatedController =
      StreamController<String>.broadcast();
  Stream<String> get onArtistImageUpdated => _imageUpdatedController.stream;

  /// 网络并发限制（最多允许 2 个并发网络请求，避免被 TheAudioDB 免费接口限流）
  int _activeNetworkRequests = 0;
  static const int _maxConcurrentNetworkRequests = 2;
  static const int _maxNetworkQueueLength = 40;
  final List<_PendingNetworkSlot> _networkWaitQueue = <_PendingNetworkSlot>[];

  /// 记录最近网络请求失败的艺术家时间戳，避免断网或异常时高频重复重试
  final Map<String, int> _recentFailureTimestamps = <String, int>{};

  Future<bool> _acquireNetworkSlot(String queryKey, {bool priority = false}) async {
    if (_activeNetworkRequests < _maxConcurrentNetworkRequests) {
      _activeNetworkRequests++;
      return true;
    }
    if (!priority && _networkWaitQueue.length >= _maxNetworkQueueLength) {
      return false;
    }
    final completer = Completer<void>();
    final slot = _PendingNetworkSlot(
      completer: completer,
      queryKey: queryKey,
      isPriority: priority,
    );
    if (priority) {
      // 插队：优先分配下一个可用槽位（若前面已有其他 priority 请求，则追加在所有 priority 之后、普通请求之前）
      final insertIndex =
          _networkWaitQueue.lastIndexWhere((item) => item.isPriority) + 1;
      _networkWaitQueue.insert(insertIndex, slot);
    } else {
      _networkWaitQueue.add(slot);
    }
    await completer.future;
    return true;
  }

  void _releaseNetworkSlot() {
    if (_networkWaitQueue.isNotEmpty) {
      final next = _networkWaitQueue.removeAt(0);
      next.completer.complete();
    } else {
      if (_activeNetworkRequests > 0) {
        _activeNetworkRequests--;
      }
    }
  }

  /// 清洗艺术家名称中的 feat. 等附加信息，提高搜索命中率
  String _sanitizeArtistName(String name) {
    var sanitized = name
        .replaceAll(
          RegExp(r'\s*[\(\[](feat|ft)\.?.*?[\]\)]', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\s+(feat|ft)\.?\s+.*$', caseSensitive: false),
          '',
        )
        .trim();
    return sanitized.isNotEmpty ? sanitized : name;
  }

  /// 转义 Lucene 查询保留字符
  String _escapeLucene(String value) {
    const specialChars = r'+-!(){}[]^"~*?:\/&|';
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      if (specialChars.contains(char)) {
        buffer.write(r'\');
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  Future<void> _rateLimitMusicBrainz() async {
    if (_musicBrainzRateLimitDelay == Duration.zero) return;
    final now = DateTime.now();
    final elapsed = now.difference(_lastMusicBrainzRequestAt);
    if (elapsed < _musicBrainzRateLimitDelay) {
      await Future.delayed(_musicBrainzRateLimitDelay - elapsed);
    }
    _lastMusicBrainzRequestAt = DateTime.now();
  }

  /// 异步查询并缓存艺术家代表图片，返回本地磁盘路径或 null。
  /// [priority] 为 true 时表示高优先级请求（例如进入详情页），可插队至等待队列前列，并跳过短期失败冷却。
  Future<String?> fetchAndCacheArtistImage(
    ArtistSummary artist, {
    bool forceRefresh = false,
    bool priority = false,
  }) async {
    final queryKey = artist.queryKey.trim();
    if (queryKey.isEmpty || artist.isUnknownArtist) {
      return null;
    }

    final inFlight = _inFlightFetches[queryKey];
    if (inFlight != null) {
      if (priority) {
        // 如果该任务已经在等待队列中排队，立即将其提至队列最前列插队
        final queueIndex = _networkWaitQueue.indexWhere(
          (item) => item.queryKey == queryKey,
        );
        if (queueIndex > 0) {
          final slot = _networkWaitQueue.removeAt(queueIndex);
          slot.isPriority = true;
          final insertIndex =
              _networkWaitQueue.lastIndexWhere((item) => item.isPriority) + 1;
          _networkWaitQueue.insert(insertIndex, slot);
        }
      }
      return inFlight;
    }

    final future = _doFetchAndCacheArtistImage(
      artist,
      forceRefresh: forceRefresh,
      priority: priority,
    );
    _inFlightFetches[queryKey] = future;

    try {
      return await future;
    } finally {
      _inFlightFetches.remove(queryKey);
    }
  }

  Future<String?> _doFetchAndCacheArtistImage(
    ArtistSummary artist, {
    bool forceRefresh = false,
    bool priority = false,
  }) async {
    final queryKey = artist.queryKey.trim();

    // 1. 如果已有本地缓存图片且文件存在，直接返回
    if (!forceRefresh) {
      if (artist.cachedImagePath != null &&
          artist.cachedImagePath!.isNotEmpty &&
          File(artist.cachedImagePath!).existsSync()) {
        return artist.cachedImagePath;
      }

      final existingImage = await _db.getArtistImageCache(queryKey);
      if (existingImage != null &&
          existingImage.imagePath.isNotEmpty &&
          File(existingImage.imagePath).existsSync()) {
        return existingImage.imagePath;
      }

      final existingCache = await _db.getArtistCache(queryKey);
      if (existingCache != null && existingCache.noData) {
        // 如果该记录已被新流程查询过确认无数据（带有 mbid_queried 标识），且在 7 天内，跳过避免刷爆
        // 若是旧版本未走 MBID 查询遗留的 noData 记录，则允许尝试走新的 MBID 流程
        final isModernNoData = existingCache.rawSearchJson != null &&
            existingCache.rawSearchJson!.contains('"mbid_queried":true');
        if (isModernNoData) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final elapsedDays =
              (now - existingCache.updatedAtMillis) / (1000 * 60 * 60 * 24);
          if (elapsedDays < 7) {
            return null;
          }
        }
      }

      // 检查短期失败冷却（2 分钟内网络失败不反复重试；但若是 priority 插队请求，允许跳过冷却重试）
      if (!priority) {
        final failedAt = _recentFailureTimestamps[queryKey];
        if (failedAt != null) {
          final elapsedSec =
              (DateTime.now().millisecondsSinceEpoch - failedAt) ~/ 1000;
          if (elapsedSec < 120) {
            return null;
          }
        }
      }
    }

    final hasSlot = await _acquireNetworkSlot(queryKey, priority: priority);
    if (!hasSlot) {
      return null;
    }

    try {
      return await _fetchFromNetworkAndSave(artist, queryKey);
    } finally {
      _releaseNetworkSlot();
    }
  }

  Future<String?> _fetchFromNetworkAndSave(
    ArtistSummary artist,
    String queryKey,
  ) async {
    final searchName = _sanitizeArtistName(artist.name);
    if (searchName.isEmpty) return null;

    try {
      // 1. 获取 MBID：优先看 artist.artistId 是否为 UUID，其次看内存缓存，再次调 MusicBrainz 查询
      String? mbid;
      if (artist.artistId != null &&
          _uuidRegex.hasMatch(artist.artistId!.trim())) {
        mbid = artist.artistId!.trim();
      } else {
        mbid = _resolvedMbids[queryKey];
      }

      if (mbid == null || mbid.isEmpty) {
        mbid = await _resolveMbidFromMusicBrainz(searchName);
        if (mbid != null && mbid.isNotEmpty) {
          _resolvedMbids[queryKey] = mbid;
        }
      }

      Map<String, dynamic>? firstArtist;

      // 2. 如果存在 MBID，优先走 TheAudioDB artist-mb.php 查询
      if (mbid != null && mbid.isNotEmpty) {
        firstArtist = await _fetchArtistFromTheAudioDbByMbid(mbid, artist.name);
      }

      // 3. 若 MBID 未查到或未命中，回退走名称搜索 search.php
      firstArtist ??=
          await _fetchArtistFromTheAudioDbByName(searchName, artist.name);

      if (firstArtist == null) {
        debugPrint('[TheAudioDB] No artist found for "${artist.name}"');
        await _recordNoData(queryKey, artist.name);
        return null;
      }

      final thumbUrl = firstArtist['strArtistThumb'] as String?;
      if (thumbUrl == null || thumbUrl.trim().isEmpty) {
        debugPrint(
          '[TheAudioDB] Artist found for "${artist.name}" but strArtistThumb is empty',
        );
        await _recordNoData(
          queryKey,
          artist.name,
          rawJson: jsonEncode(firstArtist),
        );
        return null;
      }

      // 4. 下载图片保存到本地
      final downloadedPath =
          await _downloadAndSaveImage(queryKey, thumbUrl.trim());
      if (downloadedPath == null) {
        _recentFailureTimestamps[queryKey] =
            DateTime.now().millisecondsSinceEpoch;
        return null;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      // 5. 更新数据库中的 artist_image_cache 和 artist_cache
      await _db.insertOrUpdateArtistImageCache(
        ArtistImageCacheRecord(
          artistId: queryKey,
          imagePath: downloadedPath,
          sourceUrl: thumbUrl,
          updatedAtMillis: now,
        ),
      );

      final theAudioDbId = firstArtist['idArtist']?.toString();
      await _db.insertOrUpdateArtistCache(
        ArtistCacheRecord(
          queryKey: queryKey,
          artistId: theAudioDbId ?? mbid,
          artistName: firstArtist['strArtist']?.toString() ?? artist.name,
          imageUrl: thumbUrl,
          thumbnailUrl: thumbUrl,
          rawSearchJson: jsonEncode(firstArtist),
          noData: false,
          imageFetchCompleted: true,
          updatedAtMillis: now,
        ),
      );

      _recentFailureTimestamps.remove(queryKey);
      _imageUpdatedController.add(queryKey);
      debugPrint(
        '[TheAudioDB] Successfully cached artist image for "${artist.name}": $downloadedPath',
      );
      return downloadedPath;
    } catch (e, stack) {
      _recentFailureTimestamps[queryKey] =
          DateTime.now().millisecondsSinceEpoch;
      debugPrint('[TheAudioDB] Failed to fetch artist image for "${artist.name}": $e');
      if (kDebugMode) {
        debugPrint(stack.toString());
      }
      return null;
    }
  }

  /// 通过 MusicBrainz 检索艺人并提取 MBID
  Future<String?> _resolveMbidFromMusicBrainz(String artistName) async {
    final trimmed = artistName.trim();
    if (trimmed.isEmpty) return null;

    final escaped = _escapeLucene(trimmed);
    // 优先尝试带引号短语检索，以获取最高匹配度
    final phraseQuery = '"$escaped"';
    final result = await _executeMusicBrainzArtistQuery(phraseQuery, trimmed);
    if (result != null) return result;

    // 如果短语匹配未命中且包含空格或符号，尝试宽松检索
    if (trimmed.contains(' ') ||
        RegExp(r'[^a-zA-Z0-9\u4e00-\u9fa5]').hasMatch(trimmed)) {
      return await _executeMusicBrainzArtistQuery(escaped, trimmed);
    }

    return null;
  }

  Future<String?> _executeMusicBrainzArtistQuery(
    String query,
    String debugArtistName,
  ) async {
    final url =
        '$_musicBrainzBaseUrl/artist/?query=${Uri.encodeComponent(query)}&fmt=json&limit=3';

    try {
      await _rateLimitMusicBrainz();
      debugPrint(
        '[TheAudioDB] Resolving MBID from MusicBrainz for "$debugArtistName" (query: $query)...',
      );
      final response = await _networkClient.get<dynamic>(
        url,
        options: Options(
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'Vynody/1.0 (zgmf300@outlook.com)',
          },
        ),
      );

      if (response.statusCode != 200 ||
          response.data is! Map<String, dynamic>) {
        debugPrint(
          '[TheAudioDB] MusicBrainz query returned ${response.statusCode}',
        );
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      final artists = data['artists'];
      if (artists is! List || artists.isEmpty) {
        debugPrint(
          '[TheAudioDB] MusicBrainz found no artists for "$debugArtistName"',
        );
        return null;
      }

      for (final item in artists) {
        if (item is Map<String, dynamic>) {
          final id = item['id'] as String?;
          final score = int.tryParse(item['score']?.toString() ?? '') ?? 0;
          if (id != null && _uuidRegex.hasMatch(id) && score >= 70) {
            debugPrint(
              '[TheAudioDB] MusicBrainz resolved MBID $id (score $score) for "$debugArtistName"',
            );
            return id;
          }
        }
      }

      // 如果没有 >= 70 分但首个结果是有效 UUID
      final first = artists.first;
      if (first is Map<String, dynamic>) {
        final id = first['id'] as String?;
        if (id != null && _uuidRegex.hasMatch(id)) {
          debugPrint(
            '[TheAudioDB] MusicBrainz fallback MBID $id for "$debugArtistName"',
          );
          return id;
        }
      }

      return null;
    } catch (e) {
      debugPrint(
        '[TheAudioDB] MusicBrainz query failed for "$debugArtistName": $e',
      );
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchArtistFromTheAudioDbByMbid(
    String mbid,
    String debugArtistName,
  ) async {
    final requestUrl =
        '$_baseUrl/$_defaultApiKey/artist-mb.php?i=${Uri.encodeComponent(mbid)}';

    try {
      debugPrint(
        '[TheAudioDB] Fetching artist image by MBID $mbid for "$debugArtistName"...',
      );
      final response = await _networkClient.get<dynamic>(
        requestUrl,
        options: Options(
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      if (response.statusCode != 200 ||
          response.data is! Map<String, dynamic>) {
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      final artistsList = data['artists'];
      if (artistsList is! List || artistsList.isEmpty) {
        return null;
      }

      final firstArtist = artistsList.first;
      if (firstArtist is Map<String, dynamic>) {
        return firstArtist;
      }
      return null;
    } catch (e) {
      debugPrint('[TheAudioDB] Fetch by MBID $mbid failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchArtistFromTheAudioDbByName(
    String searchName,
    String debugArtistName,
  ) async {
    final requestUrl =
        '$_baseUrl/$_defaultApiKey/search.php?s=${Uri.encodeComponent(searchName)}';

    try {
      debugPrint(
        '[TheAudioDB] Fetching artist image by name "$searchName" for "$debugArtistName"...',
      );
      final response = await _networkClient.get<dynamic>(
        requestUrl,
        options: Options(
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      if (response.statusCode != 200 ||
          response.data is! Map<String, dynamic>) {
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      final artistsList = data['artists'];
      if (artistsList is! List || artistsList.isEmpty) {
        return null;
      }

      final firstArtist = artistsList.first;
      if (firstArtist is Map<String, dynamic>) {
        return firstArtist;
      }
      return null;
    } catch (e) {
      debugPrint('[TheAudioDB] Fetch by name "$searchName" failed: $e');
      return null;
    }
  }

  Future<void> _recordNoData(
    String queryKey,
    String artistName, {
    String? rawJson,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = rawJson ?? jsonEncode({'mbid_queried': true});
    await _db.insertOrUpdateArtistCache(
      ArtistCacheRecord(
        queryKey: queryKey,
        artistName: artistName,
        rawSearchJson: payload,
        noData: true,
        imageFetchCompleted: true,
        updatedAtMillis: now,
      ),
    );
  }

  Future<String?> _downloadAndSaveImage(String queryKey, String url) async {
    try {
      final response = await _networkClient.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        return null;
      }

      final supportDir = await getApplicationSupportDirectory();
      final artistImagesDir =
          Directory(p.join(supportDir.path, 'artist_images'));
      if (!await artistImagesDir.exists()) {
        await artistImagesDir.create(recursive: true);
      }

      final hash = md5.convert(utf8.encode(queryKey.toLowerCase())).toString();
      final uri = Uri.tryParse(url);
      final rawExt = uri != null ? p.extension(uri.path) : '';
      final ext = (rawExt.isNotEmpty && rawExt.length <= 5) ? rawExt : '.jpg';
      final file = File(p.join(artistImagesDir.path, '$hash$ext'));

      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[TheAudioDB] Error downloading artist image from $url: $e');
      return null;
    }
  }
}

class _PendingNetworkSlot {
  final Completer<void> completer;
  final String queryKey;
  bool isPriority;

  _PendingNetworkSlot({
    required this.completer,
    required this.queryKey,
    this.isPriority = false,
  });
}
