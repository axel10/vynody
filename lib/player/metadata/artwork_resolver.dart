import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:vynody/player/metadata/thumbnail_scheduler.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_server_storage.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';

/// 统一解析返回的原始封面数据
class RawArtwork {
  final Uint8List? bytes;
  final String? filePath;
  final String? remoteUrl;

  const RawArtwork({
    this.bytes,
    this.filePath,
    this.remoteUrl,
  });

  bool get isEmpty =>
      (bytes == null || bytes!.isEmpty) &&
      (filePath == null || filePath!.isEmpty) &&
      (remoteUrl == null || remoteUrl!.isEmpty);

  bool get isNotEmpty => !isEmpty;
}

/// 统一的封面解析器
/// 负责缩略图与播放页轮播图的封面查找与缓存生成
class ArtworkResolver {
  static final LinkedHashMap<String, String> _thumbnailCache =
      LinkedHashMap<String, String>();
  static final LinkedHashMap<String, String> _remoteUrlCache =
      LinkedHashMap<String, String>();
  static final Set<String> _verifiedPaths = <String>{};

  /// 缩略图解析的全局并发闸门（同一首歌的并发请求会被合并）。
  static final _ThumbnailGate _thumbnailGate = _ThumbnailGate();

  /// 负缓存：明确解析不到封面的歌曲，短期内不再重复走整条重链路。
  ///
  /// 没有这一层时，「没有内嵌封面也没有目录封面」的专辑每次被列表回收后
  /// 重新构建都会再查一次库、再起一个 isolate 解析音频标签，然后照样返回 null。
  static final LinkedHashMap<String, _NegativeArtworkEntry> _negativeCache =
      LinkedHashMap<String, _NegativeArtworkEntry>();

  static const Duration _negativeTtl = Duration(minutes: 5);
  static const int _negativeCacheLimit = 4000;

  static void _cacheThumbnail(String path, String thumbPath) {
    _verifiedPaths.add(thumbPath);
    if (_verifiedPaths.length > 2000) {
      _verifiedPaths.clear();
    }
    _thumbnailCache[path] = thumbPath;
    if (_thumbnailCache.length > 1000) {
      _thumbnailCache.remove(_thumbnailCache.keys.first);
    }
  }

  /// 检查某首曲目当前是否命中负缓存（已确认无封面）。
  static bool isNegativeCached(
    String path, {
    String? thumbnailPath,
    String? artworkPath,
  }) {
    if (RemoteMediaResolver.isRemoteUri(path)) return false;
    final resolvedSongPath = ScannerPathUtils.resolveIosSandboxPath(path);
    final signature = '${thumbnailPath ?? ''}|${artworkPath ?? ''}';
    return _isNegativeCached(resolvedSongPath, signature);
  }

  /// 标记某个缩略图路径解码/读取失败，清除其缓存并加入负缓存，防止重复拉取损坏的图片。
  static void markThumbnailFailed(String path, String failedThumbPath) {
    final resolvedSongPath = ScannerPathUtils.resolveIosSandboxPath(path);
    final resolvedThumb =
        ScannerPathUtils.resolveIosSandboxPath(failedThumbPath);
    _verifiedPaths.remove(resolvedThumb);
    _thumbnailCache.remove(resolvedSongPath);
    final signature = '$failedThumbPath|';
    _recordNegative(resolvedSongPath, signature);
  }

  static Future<RemoteMediaResolver?> _getDefaultRemoteResolver() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storage = RemoteServerStorage(prefs: prefs);
      return RemoteMediaResolver(storage: storage);
    } catch (_) {
      return null;
    }
  }

  /// 统一的原始封面查找逻辑（真值来源）：
  /// 1. 已有本地大图路径 (artworkPath) 且文件存在
  /// 2. 音频文件内嵌封面 (MetadataHelper.decodeEmbeddedArtwork)
  /// 3. 同级目录封面 (MetadataHelper.findDirectoryCover)
  /// 4. 远程曲目封面 (RemoteMediaResolver.getArtworkBytes / getArtworkUrlFromUri)
  /// 5. Android 系统媒体库 (MetadataHelper.safeQueryArtwork)
  static Future<RawArtwork?> findRawArtwork({
    required String path,
    int? id,
    String? artworkPath,
    AudioCoreController? audioController,
    RemoteMediaResolver? remoteResolver,
    bool readBytesForFile = false,
  }) async {
    final resolvedSongPath = ScannerPathUtils.resolveIosSandboxPath(path);

    // 1. 已有本地大图路径 (artworkPath)
    if (artworkPath != null && artworkPath.isNotEmpty) {
      final resolvedArtPath =
          ScannerPathUtils.resolveIosSandboxPath(artworkPath);
      final artFile = File(resolvedArtPath);
      if (artFile.existsSync()) {
        Uint8List? fileBytes;
        if (readBytesForFile) {
          try {
            fileBytes = await artFile.readAsBytes();
          } catch (_) {}
        }
        return RawArtwork(filePath: resolvedArtPath, bytes: fileBytes);
      }
    }

    final isRemote = RemoteMediaResolver.isRemoteUri(path);

    if (!isRemote) {
      // 2. 音频内嵌封面 (decodeEmbeddedArtwork)
      try {
        final canAccess =
            await MetadataHelper.canAccessAudioFile(resolvedSongPath);
        if (canAccess) {
          final embeddedBytes =
              await MetadataHelper.decodeEmbeddedArtwork(resolvedSongPath);
          if (embeddedBytes != null && embeddedBytes.isNotEmpty) {
            return RawArtwork(bytes: embeddedBytes);
          }
        }
      } catch (e) {
        debugPrint('[ArtworkResolver] Error decoding embedded artwork: $e');
      }

      // 3. 文件夹封面 (findDirectoryCover，如 cover.jpg / folder.jpg)
      try {
        final dirCoverPath =
            MetadataHelper.findDirectoryCover(resolvedSongPath);
        if (dirCoverPath != null) {
          final dirFile = File(dirCoverPath);
          if (dirFile.existsSync()) {
            Uint8List? fileBytes;
            if (readBytesForFile) {
              try {
                fileBytes = await dirFile.readAsBytes();
              } catch (_) {}
            }
            return RawArtwork(filePath: dirCoverPath, bytes: fileBytes);
          }
        }
      } catch (e) {
        debugPrint('[ArtworkResolver] Error finding directory cover: $e');
      }

      // 4. Android 系统媒体库 (safeQueryArtwork)
      if (Platform.isAndroid && id != null) {
        try {
          final hasPermission =
              await MetadataHelper.hasAndroidAudioPermission();
          if (hasPermission) {
            final queryBytes = await MetadataHelper.safeQueryArtwork(
              id,
              size: 800,
              hasPermission: hasPermission,
            );
            if (queryBytes != null && queryBytes.isNotEmpty) {
              return RawArtwork(bytes: queryBytes);
            }
          }
        } catch (e) {
          debugPrint('[ArtworkResolver] Error querying system artwork: $e');
        }
      }
    } else {
      // 远程曲目解析
      try {
        remoteResolver ??= await _getDefaultRemoteResolver();
        if (remoteResolver != null) {
          final remoteBytes = await remoteResolver.getArtworkBytes(
            path,
            coverArtId: artworkPath,
            size: 800,
          );
          if (remoteBytes != null && remoteBytes.isNotEmpty) {
            return RawArtwork(bytes: remoteBytes);
          }

          final remoteUrl = await remoteResolver.getArtworkUrlFromUri(
            path,
            coverArtId: artworkPath,
            size: 800,
          );
          if (remoteUrl != null && remoteUrl.isNotEmpty) {
            return RawArtwork(remoteUrl: remoteUrl);
          }
        }
      } catch (e) {
        debugPrint('[ArtworkResolver] Error resolving remote artwork: $e');
      }

      // 尝试流缓存内嵌封面
      try {
        final info = RemoteMediaResolver.parseUri(path);
        if (info != null && audioController != null) {
          final rawKey = '${info.serverId}:${info.trackIdOrPath}';
          final decodedKey =
              '${info.serverId}:${Uri.decodeFull(info.trackIdOrPath)}';
          final encodedKey =
              '${info.serverId}:${Uri.encodeFull(info.trackIdOrPath)}';
          for (final key in {rawKey, decodedKey, encodedKey}) {
            final cacheFile =
                await audioController.streamCacheManager.getCacheFile(key);
            if (await cacheFile.exists() && (await cacheFile.length()) > 0) {
              final embeddedBytes =
                  await MetadataHelper.decodeEmbeddedArtwork(cacheFile.path);
              if (embeddedBytes != null && embeddedBytes.isNotEmpty) {
                return RawArtwork(bytes: embeddedBytes);
              }
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// 缩略图组件专用的封面解析流程（带并发闸门与负缓存）：
  /// 1. 内存缓存命中 / 传入的 thumbnailPath 有效时直接返回（微秒级，不进闸门）；
  /// 2. 命中负缓存直接返回 null，不再查库、不再起 isolate 解析音频标签；
  /// 3. 剩下的重活经 [_thumbnailGate] 排队执行：同一首歌的并发请求合并成一次，
  ///    并发名额由 [ThumbnailScheduler] 与扫描侧共用（本地
  ///    `clamp(cores ~/ 2, 2, 4)`，远程固定 2）；
  /// 4. 没缓存则按照统一逻辑 (findRawArtwork) 查找封面，
  ///    从原图生成缩略图缓存并保存，通知回调后展示。
  static Future<String?> resolveForThumbnail({
    required String path,
    int? id,
    String? thumbnailPath,
    String? artworkPath,
    RemoteMediaResolver? remoteResolver,
    void Function(String generatedPath)? onThumbnailGenerated,
  }) {
    final resolvedSongPath = ScannerPathUtils.resolveIosSandboxPath(path);

    // 快速路径必须留在闸门外：这两步是微秒级同步操作，一旦进队列就会被
    // 队首的重任务拖住，已经缓存过的封面反而变慢。
    final cachedThumb = _tryCachedThumbnail(resolvedSongPath, thumbnailPath);
    if (cachedThumb != null) return Future<String?>.value(cachedThumb);

    // 远程曲目的封面依赖网络，拿不到不等于「这首歌没有封面」，
    // 因此不做负缓存，否则网络恢复后仍会空白一整个 TTL。
    final useNegativeCache = !RemoteMediaResolver.isRemoteUri(path);
    final signature = '${thumbnailPath ?? ''}|${artworkPath ?? ''}';

    if (useNegativeCache && _isNegativeCached(resolvedSongPath, signature)) {
      return Future<String?>.value();
    }

    final isRemote = RemoteMediaResolver.isRemoteUri(path);
    return _thumbnailGate.run(
      '$resolvedSongPath|$signature',
      remote: isRemote,
      task: () async {
        final result = await _resolveThumbnailSlow(
          path: path,
          id: id,
          thumbnailPath: thumbnailPath,
          artworkPath: artworkPath,
          remoteResolver: remoteResolver,
          onThumbnailGenerated: onThumbnailGenerated,
        );
        if (!useNegativeCache) return result;
        if (result == null || result.isEmpty) {
          _recordNegative(resolvedSongPath, signature);
        } else {
          _negativeCache.remove(resolvedSongPath);
        }
        return result;
      },
    );
  }

  /// 同步快速路径：缩略图内存缓存命中，或传入的 thumbnailPath 文件确实存在。
  static String? _tryCachedThumbnail(
    String resolvedSongPath,
    String? thumbnailPath,
  ) {
    // 1. 检查内存缓存
    if (_thumbnailCache.containsKey(resolvedSongPath)) {
      final cached = _thumbnailCache[resolvedSongPath]!;
      if (_verifiedPaths.contains(cached) || File(cached).existsSync()) {
        _verifiedPaths.add(cached);
        return cached;
      } else {
        _thumbnailCache.remove(resolvedSongPath);
      }
    }

    // 2. 检查传入的 thumbnailPath 是否有效存在
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      final resolvedThumb =
          ScannerPathUtils.resolveIosSandboxPath(thumbnailPath);
      if (_verifiedPaths.contains(resolvedThumb) ||
          File(resolvedThumb).existsSync()) {
        _cacheThumbnail(resolvedSongPath, resolvedThumb);
        return resolvedThumb;
      }
    }
    return null;
  }

  static bool _isNegativeCached(String songPath, String signature) {
    final entry = _negativeCache[songPath];
    if (entry == null) return false;
    if (entry.signature != signature) {
      // 封面来源信息变了（例如扫描补上了 artworkPath），重新解析。
      _negativeCache.remove(songPath);
      return false;
    }
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _negativeCache.remove(songPath);
      return false;
    }
    return true;
  }

  static void _recordNegative(String songPath, String signature) {
    _negativeCache.remove(songPath);
    _negativeCache[songPath] = _NegativeArtworkEntry(
      signature: signature,
      expiresAt: DateTime.now().add(_negativeTtl),
    );
    if (_negativeCache.length > _negativeCacheLimit) {
      _negativeCache.remove(_negativeCache.keys.first);
    }
  }

  /// 重活部分：查库 → [findRawArtwork] → 生成并落盘缩略图。
  static Future<String?> _resolveThumbnailSlow({
    required String path,
    int? id,
    String? thumbnailPath,
    String? artworkPath,
    RemoteMediaResolver? remoteResolver,
    void Function(String generatedPath)? onThumbnailGenerated,
  }) async {
    final resolvedSongPath = ScannerPathUtils.resolveIosSandboxPath(path);

    // 3. 检查数据库已存在的 thumbnailPath 记录
    try {
      final db = MetadataDatabase();
      final songMeta = await db.getSongMetadata(path);
      final dbThumb = songMeta?.thumbnailPath;
      if (dbThumb != null && dbThumb.isNotEmpty) {
        final resolvedDbThumb =
            ScannerPathUtils.resolveIosSandboxPath(dbThumb);
        if (_verifiedPaths.contains(resolvedDbThumb) ||
            File(resolvedDbThumb).existsSync()) {
          _cacheThumbnail(resolvedSongPath, resolvedDbThumb);
          return resolvedDbThumb;
        }
      }
    } catch (_) {}

    // 检查远程 URL 缓存
    final remoteCacheKey = '${path}_${artworkPath ?? ''}';
    if (_remoteUrlCache.containsKey(remoteCacheKey)) {
      return _remoteUrlCache[remoteCacheKey];
    }

    // 4. 没缓存：按照统一逻辑查找原图封面
    final raw = await findRawArtwork(
      path: path,
      id: id,
      artworkPath: artworkPath,
      remoteResolver: remoteResolver,
      readBytesForFile: true,
    );

    if (raw == null || raw.isEmpty) {
      return null;
    }

    // 5. 如果原图是远程 URL，记录并返回
    if (raw.remoteUrl != null &&
        (raw.bytes == null || raw.bytes!.isEmpty) &&
        (raw.filePath == null || raw.filePath!.isEmpty)) {
      _remoteUrlCache[remoteCacheKey] = raw.remoteUrl!;
      if (_remoteUrlCache.length > 500) {
        _remoteUrlCache.remove(_remoteUrlCache.keys.first);
      }
      return raw.remoteUrl;
    }

    // 6. 从原图生成缩略图缓存并存储
    Uint8List? sourceBytes = raw.bytes;
    if ((sourceBytes == null || sourceBytes.isEmpty) && raw.filePath != null) {
      try {
        final f = File(raw.filePath!);
        if (await f.exists()) {
          sourceBytes = await f.readAsBytes();
        }
      } catch (_) {}
    }

    if (sourceBytes != null && sourceBytes.isNotEmpty) {
      try {
        final artworkInfo = await MetadataHelper.saveArtworkAndThumbnail(
          path,
          sourceBytes,
          saveLarge: false,
        );
        final newThumbPath = artworkInfo?['thumbnailPath'] as String?;
        if (newThumbPath != null && newThumbPath.isNotEmpty) {
          _cacheThumbnail(resolvedSongPath, newThumbPath);
          onThumbnailGenerated?.call(newThumbPath);
          return newThumbPath;
        }
      } catch (e) {
        debugPrint('[ArtworkResolver] Error generating thumbnail cache: $e');
      }
    }

    // 兜底：若生成缩略图失败，有原图路径则退回使用原图路径
    if (raw.filePath != null && File(raw.filePath!).existsSync()) {
      return raw.filePath;
    }

    return null;
  }

  /// 播放页封面轮播图专用的解析流程：
  /// 1. 按照统一逻辑 (findRawArtwork) 查找封面并直接提供原图（包括 bytes、filePath 或 remoteUrl）；
  /// 2. 若未找到原图，回退读取已有缩略图兜底展示。
  static Future<RawArtwork?> resolveForCarousel({
    required String path,
    int? id,
    String? artworkPath,
    String? thumbnailPath,
    AudioCoreController? audioController,
    RemoteMediaResolver? remoteResolver,
  }) async {
    // 1. 按照统一逻辑查找原图，并读出 bytes 以供轮播图与背景模糊取色使用
    final raw = await findRawArtwork(
      path: path,
      id: id,
      artworkPath: artworkPath,
      audioController: audioController,
      remoteResolver: remoteResolver,
      readBytesForFile: true,
    );

    if (raw != null && raw.isNotEmpty) {
      return raw;
    }

    // 2. 原图未找到，回退读取已有缩略图兜底展示
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      final resolvedThumb =
          ScannerPathUtils.resolveIosSandboxPath(thumbnailPath);
      final thumbFile = File(resolvedThumb);
      if (thumbFile.existsSync()) {
        try {
          final bytes = await thumbFile.readAsBytes();
          return RawArtwork(bytes: bytes, filePath: resolvedThumb);
        } catch (_) {
          return RawArtwork(filePath: resolvedThumb);
        }
      }
    }

    try {
      final db = MetadataDatabase();
      final songMeta = await db.getSongMetadata(path);
      final dbThumb = songMeta?.thumbnailPath;
      if (dbThumb != null && dbThumb.isNotEmpty) {
        final resolvedDbThumb =
            ScannerPathUtils.resolveIosSandboxPath(dbThumb);
        final thumbFile = File(resolvedDbThumb);
        if (thumbFile.existsSync()) {
          try {
            final bytes = await thumbFile.readAsBytes();
            return RawArtwork(bytes: bytes, filePath: resolvedDbThumb);
          } catch (_) {
            return RawArtwork(filePath: resolvedDbThumb);
          }
        }
      }
    } catch (_) {}

    return null;
  }
}

/// 负缓存条目：记录当时用来解析的封面来源签名，签名不一致就视为过期。
class _NegativeArtworkEntry {
  const _NegativeArtworkEntry({
    required this.signature,
    required this.expiresAt,
  });

  final String signature;
  final DateTime expiresAt;
}

/// 缩略图解析的全局并发闸门。
///
/// 列表滚动时一屏可能同时构建几十张封面，每一张都会走「查库 + 起 isolate
/// 解析音频标签 + 必要时生成缩略图并写库」这条重链路。没有闸门时它们会全部
/// 并发发起，滚动直接掉帧。扫描侧（ScannerMetadataStore）本来就限到 2 并发，
/// 这里给 UI 侧补上同样的约束，并把同一首歌的并发请求合并成一次。
/// 浏览侧的缩略图解析闸门。
///
/// 名额来自 [ThumbnailScheduler]，与扫描侧共用同一组槽位 —— 这样「扫描中浏览
/// 专辑页」不会再叠成 5 路并发。类内只保留**按路径+签名合并同一请求**的单飞逻辑，
/// 保证同一张卡被多处同时渲染时不会起两个 isolate。
class _ThumbnailGate {
  final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};

  Future<String?> run(
    String key, {
    required bool remote,
    required Future<String?> Function() task,
  }) {
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final completer = Completer<String?>();
    _inFlight[key] = completer.future;
    unawaited(_execute(key, remote, task, completer));
    return completer.future;
  }

  Future<void> _execute(
    String key,
    bool remote,
    Future<String?> Function() task,
    Completer<String?> completer,
  ) async {
    try {
      final result = await ThumbnailScheduler.instance.run(
        remote: remote,
        task: task,
      );
      if (!completer.isCompleted) completer.complete(result);
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    } finally {
      if (identical(_inFlight[key], completer.future)) {
        _inFlight.remove(key);
      }
    }
  }
}
