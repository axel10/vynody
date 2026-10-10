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
class TheAudioDbArtistService {
  TheAudioDbArtistService({
    NetworkClient? networkClient,
    MetadataDatabase? database,
  })  : _networkClient = networkClient ?? NetworkClient.instance,
        _db = database ?? MetadataDatabase();

  static final TheAudioDbArtistService instance = TheAudioDbArtistService();

  final NetworkClient _networkClient;
  final MetadataDatabase _db;

  // TheAudioDB API v1 免费测试 Key 为 123
  static const String _defaultApiKey = '123';
  static const String _baseUrl = 'https://www.theaudiodb.com/api/v1/json';

  /// 正在进行的请求去重映射
  final Map<String, Future<String?>> _inFlightFetches = <String, Future<String?>>{};

  /// 艺术家头像获取并持久化成功时的通知事件流（携带 queryKey）
  final StreamController<String> _imageUpdatedController =
      StreamController<String>.broadcast();
  Stream<String> get onArtistImageUpdated => _imageUpdatedController.stream;

  /// 网络并发限制（最多允许 2 个并发网络请求，避免被 TheAudioDB 免费接口限流）
  int _activeNetworkRequests = 0;
  static const int _maxConcurrentNetworkRequests = 2;
  static const int _maxNetworkQueueLength = 40;
  final List<Completer<void>> _networkWaitQueue = <Completer<void>>[];

  /// 记录最近网络请求失败的艺术家时间戳，避免断网或异常时高频重复重试
  final Map<String, int> _recentFailureTimestamps = <String, int>{};

  Future<bool> _acquireNetworkSlot() async {
    if (_activeNetworkRequests < _maxConcurrentNetworkRequests) {
      _activeNetworkRequests++;
      return true;
    }
    if (_networkWaitQueue.length >= _maxNetworkQueueLength) {
      return false;
    }
    final completer = Completer<void>();
    _networkWaitQueue.add(completer);
    await completer.future;
    return true;
  }

  void _releaseNetworkSlot() {
    if (_networkWaitQueue.isNotEmpty) {
      final next = _networkWaitQueue.removeAt(0);
      next.complete();
    } else {
      if (_activeNetworkRequests > 0) {
        _activeNetworkRequests--;
      }
    }
  }

  /// 清洗艺术家名称中的 feat. 等附加信息，提高 TheAudioDB 搜索命中率
  String _sanitizeArtistName(String name) {
    var sanitized = name
        .replaceAll(
          RegExp(r'\s*[\(\[](feat|ft)\.?.*?[\]\)]', caseSensitive: false),
          '',
        )
        .trim();
    return sanitized.isNotEmpty ? sanitized : name;
  }

  /// 异步查询并缓存艺术家代表图片，返回本地磁盘路径或 null
  Future<String?> fetchAndCacheArtistImage(
    ArtistSummary artist, {
    bool forceRefresh = false,
  }) async {
    final queryKey = artist.queryKey.trim();
    if (queryKey.isEmpty || artist.isUnknownArtist) {
      return null;
    }

    final inFlight = _inFlightFetches[queryKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _doFetchAndCacheArtistImage(artist, forceRefresh: forceRefresh);
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
        // 如果近期（7 天内）已查过且无数据，避免重复请求打爆 API
        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsedDays =
            (now - existingCache.updatedAtMillis) / (1000 * 60 * 60 * 24);
        if (elapsedDays < 7) {
          return null;
        }
      }

      // 检查短期失败冷却（2 分钟内网络失败不反复重试）
      final failedAt = _recentFailureTimestamps[queryKey];
      if (failedAt != null) {
        final elapsedSec =
            (DateTime.now().millisecondsSinceEpoch - failedAt) ~/ 1000;
        if (elapsedSec < 120) {
          return null;
        }
      }
    }

    final hasSlot = await _acquireNetworkSlot();
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
    // 2. 构造查询请求
    final searchName = _sanitizeArtistName(artist.name);
    if (searchName.isEmpty) return null;

    final requestUrl =
        '$_baseUrl/$_defaultApiKey/search.php?s=${Uri.encodeComponent(searchName)}';

    try {
      debugPrint('[TheAudioDB] Fetching artist image for "${artist.name}" ($searchName)...');
      final response = await _networkClient.get<dynamic>(
        requestUrl,
        options: Options(
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      if (response.statusCode != 200 || response.data is! Map<String, dynamic>) {
        debugPrint('[TheAudioDB] Unexpected response status: ${response.statusCode}');
        _recentFailureTimestamps[queryKey] = DateTime.now().millisecondsSinceEpoch;
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      final artistsList = data['artists'];
      if (artistsList is! List || artistsList.isEmpty) {
        debugPrint('[TheAudioDB] No artist found for "${artist.name}"');
        await _recordNoData(queryKey, artist.name);
        return null;
      }

      final firstArtist = artistsList.first;
      if (firstArtist is! Map<String, dynamic>) {
        await _recordNoData(queryKey, artist.name);
        return null;
      }

      final thumbUrl = firstArtist['strArtistThumb'] as String?;
      if (thumbUrl == null || thumbUrl.trim().isEmpty) {
        debugPrint('[TheAudioDB] Artist found for "${artist.name}" but strArtistThumb is empty');
        await _recordNoData(queryKey, artist.name, rawJson: jsonEncode(firstArtist));
        return null;
      }

      // 3. 下载图片保存到本地
      final downloadedPath = await _downloadAndSaveImage(queryKey, thumbUrl.trim());
      if (downloadedPath == null) {
        _recentFailureTimestamps[queryKey] = DateTime.now().millisecondsSinceEpoch;
        return null;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      // 4. 更新数据库中的 artist_image_cache 和 artist_cache
      await _db.insertOrUpdateArtistImageCache(
        ArtistImageCacheRecord(
          artistId: queryKey,
          imagePath: downloadedPath,
          sourceUrl: thumbUrl,
          updatedAtMillis: now,
        ),
      );

      await _db.insertOrUpdateArtistCache(
        ArtistCacheRecord(
          queryKey: queryKey,
          artistId: firstArtist['idArtist']?.toString(),
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
      debugPrint('[TheAudioDB] Successfully cached artist image for "${artist.name}": $downloadedPath');
      return downloadedPath;
    } catch (e, stack) {
      _recentFailureTimestamps[queryKey] = DateTime.now().millisecondsSinceEpoch;
      debugPrint('[TheAudioDB] Failed to fetch artist image for "${artist.name}": $e');
      if (kDebugMode) {
        debugPrint(stack.toString());
      }
      return null;
    }
  }

  Future<void> _recordNoData(
    String queryKey,
    String artistName, {
    String? rawJson,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insertOrUpdateArtistCache(
      ArtistCacheRecord(
        queryKey: queryKey,
        artistName: artistName,
        rawSearchJson: rawJson,
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
      final artistImagesDir = Directory(p.join(supportDir.path, 'artist_images'));
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
