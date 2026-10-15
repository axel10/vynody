import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
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

  /// 缩略图组件专用的封面解析流程：
  /// 1. 查找是否有缩略图缓存，若有直接返回缩略图路径；
  /// 2. 没缓存则按照统一逻辑 (findRawArtwork) 查找封面；
  /// 3. 从原图生成缩略图缓存并保存，通知回调后展示。
  static Future<String?> resolveForThumbnail({
    required String path,
    int? id,
    String? thumbnailPath,
    String? artworkPath,
    RemoteMediaResolver? remoteResolver,
    void Function(String generatedPath)? onThumbnailGenerated,
  }) async {
    final resolvedSongPath = ScannerPathUtils.resolveIosSandboxPath(path);

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
