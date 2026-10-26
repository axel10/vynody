import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, RootIsolateToken, BackgroundIsolateBinaryMessenger;
import 'package:audio_core/audio_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/player/metadata/artwork_constants.dart';
import 'package:flutter_taglib/flutter_taglib.dart' as taglib;
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/utils/app_log.dart' as app_log;
import 'package:on_audio_query/on_audio_query.dart';

Future<Map<String, dynamic>?> _buildArtworkFiles({
  required String songPath,
  required Uint8List data,
  required String supportDirPath,
  required bool saveLarge,
  int thumbnailSize = vynodyArtworkThumbnailSize,
}) async {
  try {
    await AudioCoreController.ensureRustLibInitialized();
    final result = await generateTrackArtwork(
      path: songPath,
      artworkBytes: data,
      cacheRootPath: supportDirPath,
      saveLargeArtwork: saveLarge,
      thumbnailSize: thumbnailSize,
      meshStylePreset: MeshStylePreset.stable.index,
      hueCohesion: 0.0,
      paletteBlurRadius: 5.0,
      meshMuddyPenaltyMultiplier: 1.0,
      meshPopulationStrength: 1.0,
      meshContrastStrength: 1.0,
      meshHarmonyStrength: 1.0,
      meshVibrancyStrength: 1.0,
    );
    return {
      'artworkPath': result.artworkPath,
      'thumbnailPath': result.thumbnailPath,
      'width': result.artworkWidth,
      'height': result.artworkHeight,
      'themeColorsBlob': result.themeColorsBlob,
    };
  } catch (e) {
    debugPrint('Error building artwork files via Rust: $e');
    return null;
  }
}

/// Supported file extensions for writing metadata
const Set<String> writableMetadataExtensions = {
  '.mp3',
  '.m4a',
  '.mp4',
  '.flac',
  '.wav',
};

/// Unsupported file extensions (OGG, Opus, etc.)
const Set<String> unsupportedMetadataExtensions = {'.ogg', '.opus'};

/// Checks if a file extension supports writing metadata
bool isMetadataWritable(String filePath) {
  final ext = p.extension(filePath).toLowerCase();
  return writableMetadataExtensions.contains(ext);
}

/// Result of saving metadata to file
class SaveMetadataResult {
  final bool success;
  final String? error;
  final int unsupportedCount;
  final int savedCount;
  final List<String> unsupportedFiles;

  SaveMetadataResult({
    required this.success,
    this.error,
    this.unsupportedCount = 0,
    this.savedCount = 0,
    this.unsupportedFiles = const [],
  });
}

class MetadataHelper {
  /// Stores the last error message during metadata saving.
  static String? lastWriteError;

  /// Cached Android SDK version. Unlikely to change during app runtime.
  static int? _cachedAndroidSdkInt;

  /// Cached Android audio permission result.
  static bool? _cachedAndroidAudioPermission;
  static DateTime? _permissionCacheTimestamp;
  static const Duration _permissionCacheTtl = Duration(seconds: 30);

  /// Invalidate cached permission status (e.g. when app resumes or user grants permission)
  static void invalidatePermissionCache() {
    _cachedAndroidAudioPermission = null;
    _permissionCacheTimestamp = null;
  }

  /// 统一检查 Android 音频媒体权限（带内存缓存与自动失效机制，避免启动遍历时成千上万次 IPC 通信）
  static Future<bool> hasAndroidAudioPermission({bool forceRefresh = false}) async {
    if (!Platform.isAndroid) return true;
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedAndroidAudioPermission != null &&
        _permissionCacheTimestamp != null &&
        now.difference(_permissionCacheTimestamp!) < _permissionCacheTtl) {
      return _cachedAndroidAudioPermission!;
    }
    try {
      _cachedAndroidSdkInt ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      final bool granted;
      if (_cachedAndroidSdkInt! >= 33) {
        granted = await Permission.audio.isGranted;
      } else {
        granted = await Permission.storage.isGranted;
      }
      _cachedAndroidAudioPermission = granted;
      _permissionCacheTimestamp = now;
      return granted;
    } catch (e) {
      debugPrint('[MetadataHelper] hasAndroidAudioPermission check failed: $e');
      return false;
    }
  }

  /// 统一检查当前环境是否有权访问指定的音频文件。
  ///
  /// - 非 Android 平台直接返回 true；
  /// - 远程 URL（如 subsonic://, webdav://, http://, https://）或 content:// 协议直接返回 true；
  /// - Android 平台下，应用私有目录（如 /data/...）直接返回 true；
  /// - Android 外部存储下，若拥有媒体库权限则返回 true；
  /// - 若无媒体库权限，则检查该路径是否处于已授权的 SAF 目录树中；
  /// - 若两者皆无，则返回 false，避免未授权直接访问文件系统导致崩溃或多余报错。
  static Future<bool> canAccessAudioFile(
    String filePath, {
    bool? hasPermission,
  }) async {
    if (!Platform.isAndroid) return true;
    final resolved = ScannerPathUtils.resolveIosSandboxPath(filePath);
    final trimmed = resolved.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('subsonic://') ||
        trimmed.startsWith('webdav://') ||
        trimmed.startsWith('jellyfin://') ||
        trimmed.startsWith('smb://')) {
      return true;
    }
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('content://')) {
      return true;
    }

    try {
      final isExternal =
          trimmed.startsWith('/storage/') || trimmed.startsWith('/sdcard/');
      if (!isExternal) {
        return true;
      }

      final permitted = hasPermission ?? await hasAndroidAudioPermission();
      if (permitted) return true;

      final mapping = await AndroidSafStorageHelper.findBestMapping(trimmed);
      return mapping != null;
    } catch (e) {
      debugPrint('[MetadataHelper] canAccessAudioFile check failed for $filePath: $e');
      return false;
    }
  }

  /// 将音频路径转换为底层最适合读取的路径。
  /// 若处于 Android 平台且无媒体库权限，自动通过已持久化的 SAF 映射转换为 content:// URI，
  /// 避免底层 C++ 盲目使用 fopen 尝试打开物理路径而触发 fileRef is null 报错及回退。
  static Future<String> resolveReadTargetPath(String filePath) async {
    final resolvedPath = ScannerPathUtils.resolveIosSandboxPath(filePath);
    if (!Platform.isAndroid ||
        resolvedPath.startsWith('content://') ||
        resolvedPath.startsWith('http://') ||
        resolvedPath.startsWith('https://') ||
        resolvedPath.startsWith('subsonic://') ||
        resolvedPath.startsWith('webdav://') ||
        resolvedPath.startsWith('jellyfin://') ||
        resolvedPath.startsWith('smb://')) {
      return resolvedPath;
    }
    final isExternal =
        resolvedPath.startsWith('/storage/') || resolvedPath.startsWith('/sdcard/');
    if (!isExternal) {
      return resolvedPath;
    }
    try {
      final permitted = await hasAndroidAudioPermission();
      if (permitted) return resolvedPath;

      final mappings = await AndroidSafStorageHelper.getMappings();
      final safUri =
          AndroidSafStorageHelper.resolvePhysicalPathToSafUri(resolvedPath, mappings);
      return safUri ?? resolvedPath;
    } catch (_) {
      return resolvedPath;
    }
  }

  /// 安全查询系统媒体库封面，内部统一校验权限并捕获异常，未授权时静默返回 null
  static Future<Uint8List?> safeQueryArtwork(
    int songId, {
    int size = 800,
    bool? hasPermission,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final permitted = hasPermission ?? await hasAndroidAudioPermission();
      if (!permitted) return null;
      return await OnAudioQuery().queryArtwork(
        songId,
        ArtworkType.AUDIO,
        size: size,
      );
    } catch (e) {
      debugPrint('[MetadataHelper] safeQueryArtwork failed for $songId: $e');
      return null;
    }
  }

  static String _resolveText(String? value, String fallback) {
    if (value == null) return fallback;
    return value.trim();
  }

  static Future<bool> _writeSelectionMetadataToFile({
    required String filePath,
    required SongMetadata metadata,
    Uint8List? artworkBytes,
    String? lyrics,
    List<TrackMetadataPicture>? pictures,
    String? fallbackMediaUri,
    bool clearTrackNumber = false,
    bool writeYear = false,
    bool clearYear = false,
    bool clearGenres = false,
  }) async {
    lastWriteError = null;
    if (!isMetadataWritable(filePath)) {
      lastWriteError = 'File format is not supported for writing metadata';
      debugPrint('[MetadataHelper] $lastWriteError');
      return false;
    }

    final controller = AudioCoreController();
    if (!controller.isInitialized) {
      try {
        await controller.initialize();
      } catch (e) {
        debugPrint('Failed to initialize audio core for metadata write: $e');
        lastWriteError = 'Failed to initialize audio core: $e';
      }
    }

    final isArtworkCleared = artworkBytes != null && artworkBytes.isEmpty;
    final update = TrackMetadataUpdate(
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      albumArtist: metadata.albumArtist ?? '',
      trackNumber: metadata.trackNumber,
      genres: metadata.genres ?? const <String>[],
      // Only touch the YEAR/DATE tags when the caller explicitly changed the
      // year, otherwise writing a year would strip an existing DATE tag.
      year: writeYear ? metadata.year : null,
      lyrics: lyrics,
      clearArtwork: isArtworkCleared,
      clearTrackNumber: clearTrackNumber,
      clearGenres: clearGenres,
      clearYear: writeYear && clearYear,
      pictures:
          pictures ??
          (artworkBytes == null || artworkBytes.isEmpty
              ? const <TrackMetadataPicture>[]
              : <TrackMetadataPicture>[
                   TrackMetadataPicture(
                     bytes: artworkBytes,
                     mimeType: 'image/jpeg',
                     pictureType: 'Front Cover',
                   ),
                 ]),
    );

    try {
      final results = await controller.updateMetadataBatch([
        TrackMetadataWriteRequest(
          path: filePath,
          metadata: update,
          fallbackMediaUri: fallbackMediaUri,
        ),
      ]);
      final success = results.isNotEmpty && results.first;
      if (!success) {
        lastWriteError = taglib.TagLibFile.lastError ?? 'Native updateMetadataBatch operation returned false';
        debugPrint('[MetadataHelper] Save failed: $lastWriteError');
      }
      return success;
    } catch (e) {
      debugPrint('Failed to write selection metadata to file $filePath: $e');
      lastWriteError = e.toString();
      return false;
    }
  }

  static Future<(SongMetadata, Uint8List?)?> saveSelectedSongMetadata({
    required String filePath,
    required String title,
    required String artist,
    required String album,
    String? albumArtist,
    int? duration,
    int? trackNumber,
    bool clearTrackNumber = false,
    List<String>? genres,
    bool clearGenres = false,
    int? year,
    bool clearYear = false,
    Uint8List? artworkBytes,
    String? artworkPath,
    String? thumbnailPath,
    int? artworkWidth,
    int? artworkHeight,
    SongMetadata? existingMetadata,
    bool writeToFile = true,
    String? fallbackMediaUri,
  }) async {
    try {
      final db = MetadataDatabase();
      final dbRecord = await db.getSongMetadata(filePath);
      final existing = dbRecord ?? existingMetadata;
      final now = DateTime.now().millisecondsSinceEpoch;

      var resolvedArtworkPath = artworkPath ?? existing?.artworkPath;
      var resolvedThumbnailPath = thumbnailPath ?? existing?.thumbnailPath;
      var resolvedArtworkWidth = artworkWidth ?? existing?.artworkWidth;
      var resolvedArtworkHeight = artworkHeight ?? existing?.artworkHeight;
      Uint8List? themeColorsBlob = existing?.themeColorsBlob;

      final isArtworkCleared = artworkBytes != null && artworkBytes.isEmpty;

      if (isArtworkCleared) {
        if (existing?.artworkPath != null && existing!.artworkPath!.isNotEmpty) {
          final oldArtworkFile = File(existing.artworkPath!);
          if (oldArtworkFile.existsSync()) {
            try {
              oldArtworkFile.deleteSync();
            } catch (e) {
              debugPrint('Error deleting old artwork file: $e');
            }
          }
        }
        if (existing?.thumbnailPath != null && existing!.thumbnailPath!.isNotEmpty) {
          final oldThumbnailFile = File(existing.thumbnailPath!);
          if (oldThumbnailFile.existsSync()) {
            try {
              oldThumbnailFile.deleteSync();
            } catch (e) {
              debugPrint('Error deleting old thumbnail file: $e');
            }
          }
        }
        resolvedArtworkPath = null;
        resolvedThumbnailPath = null;
        resolvedArtworkWidth = null;
        resolvedArtworkHeight = null;
        themeColorsBlob = null;
      }

      final needsArtworkSave =
          artworkBytes != null &&
          artworkBytes.isNotEmpty &&
          artworkPath == null &&
          thumbnailPath == null &&
          artworkWidth == null &&
          artworkHeight == null;

       if (needsArtworkSave) {
        if (existing?.artworkPath != null && existing!.artworkPath!.isNotEmpty) {
          final oldArtworkFile = File(existing.artworkPath!);
          if (oldArtworkFile.existsSync()) {
            try {
              oldArtworkFile.deleteSync();
            } catch (e) {
              debugPrint('Error deleting old artwork file: $e');
            }
          }
        }

        final supportDir = await getApplicationSupportDirectory();
        final artworkInfo = await _buildArtworkFiles(
          songPath: filePath,
          data: artworkBytes,
          supportDirPath: supportDir.path,
          saveLarge: !writeToFile,
        );

        if (artworkInfo != null) {
          resolvedArtworkPath = artworkInfo['artworkPath'] as String?;
          resolvedThumbnailPath = artworkInfo['thumbnailPath'] as String?;
          resolvedArtworkWidth = artworkInfo['width'] as int?;
          resolvedArtworkHeight = artworkInfo['height'] as int?;
          themeColorsBlob = artworkInfo['themeColorsBlob'] as Uint8List?;
        } else {
          debugPrint('Failed to save artwork for selected metadata $filePath');
        }
      }


      int? resolvedSourceFlags = existing?.sourceFlags;
      try {
        final prefs = await SharedPreferences.getInstance();
        final roots = prefs.getStringList('root_paths') ?? [];
        bool isInsideRoot = false;
        for (final root in roots) {
          if (ScannerPathUtils.pathContains(root, filePath)) {
            isInsideRoot = true;
            break;
          }
        }
        if (isInsideRoot) {
          if (resolvedSourceFlags == null) {
            resolvedSourceFlags = SongSourceFlags.rootScan;
          } else {
            resolvedSourceFlags = (resolvedSourceFlags & ~SongSourceFlags.external) | SongSourceFlags.rootScan;
          }
        } else if (resolvedSourceFlags == null) {
          resolvedSourceFlags = SongSourceFlags.external;
        }
      } catch (_) {
        resolvedSourceFlags ??= SongSourceFlags.external;
      }

      final base =
          existing ??
          SongMetadata(
            path: filePath,
            title: p.basenameWithoutExtension(filePath),
            album: 'Unknown Album',
            artist: 'Unknown Artist',
            sourceFlags: resolvedSourceFlags,
          );

      var updated = base.copyWith(
        title: _resolveText(title, base.title),
        artist: _resolveText(artist, base.artist),
        albumArtist: albumArtist == null
            ? base.albumArtist
            : (albumArtist.trim().isEmpty ? null : albumArtist.trim()),
        album: _resolveText(album, base.album),
        duration: duration ?? base.duration,
        trackNumber: clearTrackNumber ? null : (trackNumber ?? base.trackNumber),
        artworkPath: resolvedArtworkPath,
        thumbnailPath: resolvedThumbnailPath,
        artworkWidth: resolvedArtworkWidth,
        artworkHeight: resolvedArtworkHeight,
        themeColorsBlob: themeColorsBlob,
        lastModifiedTime: now,
        metadataTextScanned: now,
        metadataImgScanned: artworkBytes != null
            ? now
            : base.metadataImgScanned,
        createdAt: base.createdAt ??
            (File(filePath).existsSync()
                ? File(filePath).lastModifiedSync().millisecondsSinceEpoch
                : now),
        genres: clearGenres
            ? null
            : (genres == null
                ? base.genres
                : (genres.isEmpty ? null : List<String>.from(genres))),
        year: clearYear ? null : (year ?? base.year),
        isAppModified: true,
        sourceFlags: resolvedSourceFlags,
      );

      final yearChanged =
          clearYear || (year != null && year != base.year);

      if (writeToFile) {
        final fileUpdated = await _writeSelectionMetadataToFile(
          filePath: filePath,
          metadata: updated,
          artworkBytes: artworkBytes,
          fallbackMediaUri: fallbackMediaUri,
          clearTrackNumber: clearTrackNumber,
          writeYear: yearChanged,
          clearYear: clearYear,
          clearGenres: clearGenres,
        );

        if (!fileUpdated) {
          return null;
        }

        final mtime = File(filePath).lastModifiedSync().millisecondsSinceEpoch;
        updated = updated.copyWith(
          lastModifiedTime: mtime,
          createdAt: mtime,
          isAppModified: false,
        );
      }

      await db.insertOrUpdateSong(updated);
      return (updated, artworkBytes);
    } catch (e) {
      debugPrint('Error saving selected metadata for $filePath: $e');
      return null;
    }
  }

  /// Writes current database metadata and cached artwork of the song back to the physical audio file,
  /// and resets the `isModified` flag in the database.
  static Future<bool> saveDatabaseMetadataToFile(String filePath, {String? fallbackMediaUri}) async {
    try {
      final db = MetadataDatabase();
      final metadata = await db.getSongMetadata(filePath);
      if (metadata == null) {
        debugPrint('[MetadataHelper] Cannot save to file: No database metadata found for $filePath');
        return false;
      }

      Uint8List? artworkBytes;
      if (metadata.artworkPath != null && metadata.artworkPath!.isNotEmpty) {
        final artworkFile = File(metadata.artworkPath!);
        if (await artworkFile.exists()) {
          artworkBytes = await artworkFile.readAsBytes();
        }
      }

      // If we don't have artworkBytes locally but we have a thumbnail, we can fall back to the thumbnail
      if (artworkBytes == null && metadata.thumbnailPath != null && metadata.thumbnailPath!.isNotEmpty) {
        final thumbnailFile = File(metadata.thumbnailPath!);
        if (await thumbnailFile.exists()) {
          artworkBytes = await thumbnailFile.readAsBytes();
        }
      }

      final success = await _writeSelectionMetadataToFile(
        filePath: filePath,
        metadata: metadata,
        artworkBytes: artworkBytes,
        fallbackMediaUri: fallbackMediaUri,
      );

      if (success) {
        final mtime = File(filePath).lastModifiedSync().millisecondsSinceEpoch;
        var updated = metadata.copyWith(
          lastModifiedTime: mtime,
          createdAt: mtime,
          isAppModified: false,
        );

        if (metadata.artworkPath != null && metadata.artworkPath!.isNotEmpty) {
          final artworkFile = File(metadata.artworkPath!);
          if (await artworkFile.exists()) {
            try {
              await artworkFile.delete();
              updated = updated.copyWith(artworkPath: null);
            } catch (e) {
              debugPrint('[MetadataHelper] Error deleting old artwork file: $e');
            }
          }
        }

        await db.insertOrUpdateSong(updated);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[MetadataHelper] Error saving database metadata to file for $filePath: $e');
      return false;
    }
  }

  static const Set<String> validCoverExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
    '.gif',
  };

  static final Map<String, String?> _globalDirCoverCache = {};

  /// Searches for cover.xxx (case-insensitive) in the same directory as songPath
  static String? findDirectoryCover(
    String songPath, {
    Map<String, String?>? dirCache,
  }) {
    final resolvedSongPath = ScannerPathUtils.resolveIosSandboxPath(songPath);
    final dirPath = p.dirname(resolvedSongPath);
    if (dirCache != null && dirCache.containsKey(dirPath)) {
      return dirCache[dirPath];
    }
    if (_globalDirCoverCache.containsKey(dirPath)) {
      final cachedResult = _globalDirCoverCache[dirPath];
      if (dirCache != null) {
        dirCache[dirPath] = cachedResult;
      }
      return cachedResult;
    }

    String? result;
    try {
      // 1. Fast path: test common candidate file names directly to avoid expensive directory listing
      const candidateNames = [
        'cover.jpg',
        'cover.png',
        'cover.jpeg',
        'cover.webp',
        'folder.jpg',
        'folder.png',
      ];
      for (final name in candidateNames) {
        final file = File(p.join(dirPath, name));
        if (file.existsSync()) {
          result = file.path;
          break;
        }
      }

      // 2. Fallback: list directory to check for case-insensitive matches or other supported extensions
      if (result == null) {
        final dir = Directory(dirPath);
        if (dir.existsSync()) {
          final entries = dir.listSync(followLinks: false);
          for (final entry in entries) {
            if (entry is File) {
              final baseName =
                  p.basenameWithoutExtension(entry.path).toLowerCase();
              final ext = p.extension(entry.path).toLowerCase();
              if ((baseName == 'cover' || baseName == 'folder') &&
                  validCoverExtensions.contains(ext)) {
                result = entry.path;
                break;
              }
            }
          }
        }
      }
    } catch (_) {
      // 在 Android 分区存储下，无媒体库权限时直接访问外部目录可能会失败，静默忽略
    }

    _globalDirCoverCache[dirPath] = result;
    if (dirCache != null) {
      dirCache[dirPath] = result;
    }
    return result;
  }

  /// 深度解析音频文件的元数据和封面信息
  ///
  /// 该方法耗时较长，通常在后台线程（Isolate）中执行，结果会存入数据库以便下次秒开。
  static Future<(SongMetadata, Uint8List?)?> processMetadata(
    String filePath, {
    int? songId,
    bool generateThumbnail = true,
    bool forceRefresh = false,
    int? sourceFlags,
    Map<String, String?>? dirCache,
  }) async {
    if (filePath.startsWith('subsonic://') ||
        filePath.startsWith('webdav://') ||
        filePath.startsWith('jellyfin://') ||
        filePath.startsWith('smb://')) {
      return null;
    }
    if (!await canAccessAudioFile(filePath)) {
      debugPrint('processMetadata skipped, cannot access file: $filePath');
      return null;
    }

    final file = File(filePath);
    final isExternalAndroid = Platform.isAndroid &&
        (filePath.startsWith('/storage/') || filePath.startsWith('/sdcard/'));
    final hasPerm = isExternalAndroid ? await hasAndroidAudioPermission() : true;

    // 仅在拥有直接文件系统访问权限时执行 File.exists 检查，
    // 避免在 Android 仅有 SAF 权限时被原生 stat() 误判为文件不存在
    if (!isExternalAndroid || hasPerm) {
      try {
        if (!await file.exists()) {
          debugPrint('processMetadata skipped, file missing: $filePath');
          return null;
        }
      } catch (_) {}
    }

    int lastModified = 0;
    try {
      lastModified = (await file.lastModified()).millisecondsSinceEpoch;
    } catch (_) {}

    final db = MetadataDatabase();

    // 1. 如果数据库已有记录且已被修改尚未保存，或者修改时间相同，直接返回
    final existing = await db.getSongMetadata(filePath);
    if (!forceRefresh && existing != null && existing.isModified) {
      return (existing, null);
    }
    if (!forceRefresh &&
        existing != null &&
        existing.lastModifiedTime == lastModified &&
        _isMetadataComplete(existing)) {
      final hasArtwork =
          (existing.artworkPath?.isNotEmpty ?? false) ||
          (existing.thumbnailPath?.isNotEmpty ?? false);
      final hasImageScanned = existing.metadataImgScanned == lastModified;
      final dirCover = findDirectoryCover(filePath, dirCache: dirCache);
      final hasDirCover = dirCover != null;
      if (!generateThumbnail || hasArtwork || (hasImageScanned && !hasDirCover)) {
        return (existing, null);
      }
    }

    try {
      Uint8List? artworkData;
      String? title;
      String? album;
      String? artist;
      String? albumArtist;
      int? duration;
      int? trackNumber;
      int? bitrate;
      int? sampleRate;
      int? channels;
      int? bitDepth;
      String? format;
      String? codec;
      int? fileRating;
      int? year;
      List<String>? genres;
      bool? hasArtwork;
      // 标签解析是否整体失败。封面字段的取舍依赖它：读取失败时必须保留
      // 库内已有封面路径，不能因为「这次没读到」就当成「文件确实没有封面」。
      bool tagReadFailed = false;

      try {
        final targetPath = await resolveReadTargetPath(filePath);
        // 2. 在 Isolate 中读取文件标签；只有需要缩略图时才取封面字节
        final metadata = await compute(
          generateThumbnail
              ? _readMetadataWithImageIsolateEntryPoint
              : _readMetadataIsolateEntryPoint,
          <String, dynamic>{
            'path': targetPath,
            'token': RootIsolateToken.instance,
          },
        );
        title = metadata.title;
        album = metadata.album;
        artist = metadata.artist;
        albumArtist = metadata.albumArtist;
        duration = metadata.duration?.inMilliseconds;
        trackNumber = metadata.trackNumber;
        bitrate = metadata.bitrate;
        sampleRate = metadata.sampleRate;
        channels = metadata.channels;
        bitDepth = metadata.bitDepth;
        format = metadata.format;
        codec = metadata.codec;
        fileRating = metadata.rating;
        year = metadata.year;
        genres = metadata.genres;
        hasArtwork = metadata.hasArtwork;
        artworkData = metadata.pictures.isNotEmpty
            ? metadata.pictures.first.bytes
            : null;
      } catch (e) {
        tagReadFailed = true;
        debugPrint('TagLib read error for $filePath: $e');
      }

      String? artworkPath;
      String? thumbnailPath;
      int? artworkWidth;
      int? artworkHeight;
      Uint8List? themeColorsBlob;

      if (artworkData != null && generateThumbnail) {
        // 3. 处理封面图：保存原始大图并生成缩略图
        // Windows 下仅生成缩略图，不存大图
        final artworkInfo = await saveArtworkAndThumbnail(
          filePath,
          artworkData,
          saveLarge: false,
        );

        artworkPath = artworkInfo?['artworkPath'] as String?;
        thumbnailPath = artworkInfo?['thumbnailPath'] as String?;
        artworkWidth = artworkInfo?['width'] as int?;
        artworkHeight = artworkInfo?['height'] as int?;
        themeColorsBlob = artworkInfo?['themeColorsBlob'] as Uint8List?;
      } else if (generateThumbnail) {
        final coverPath = findDirectoryCover(filePath, dirCache: dirCache);
        if (coverPath != null) {
          try {
            final coverBytes = await File(coverPath).readAsBytes();
            if (coverBytes.isNotEmpty) {
              final artworkInfo = await saveArtworkAndThumbnail(
                filePath,
                coverBytes,
                saveLarge: false,
              );

              artworkPath = artworkInfo?['artworkPath'] as String?;
              thumbnailPath = artworkInfo?['thumbnailPath'] as String?;
              artworkWidth = artworkInfo?['width'] as int?;
              artworkHeight = artworkInfo?['height'] as int?;
              themeColorsBlob = artworkInfo?['themeColorsBlob'] as Uint8List?;
            }
          } catch (e) {
            debugPrint('Failed to process directory cover $coverPath: $e');
          }
        } else if (Platform.isAndroid && songId != null) {
          try {
            final queryBytes = await safeQueryArtwork(
              songId,
              size: 800,
            );
            if (queryBytes != null && queryBytes.isNotEmpty) {
              final artworkInfo = await saveArtworkAndThumbnail(
                filePath,
                queryBytes,
                saveLarge: false,
              );

              artworkPath = artworkInfo?['artworkPath'] as String?;
              thumbnailPath = artworkInfo?['thumbnailPath'] as String?;
              artworkWidth = artworkInfo?['width'] as int?;
              artworkHeight = artworkInfo?['height'] as int?;
              themeColorsBlob = artworkInfo?['themeColorsBlob'] as Uint8List?;
            }
          } catch (e) {
            debugPrint('Failed to fetch system artwork via safeQueryArtwork for $songId: $e');
          }
        }
      }

      // 如果是更新现有记录，保留原有的 createdAt；否则使用当前时间
      int? resolvedSourceFlags = sourceFlags ?? existing?.sourceFlags;
      try {
        final prefs = await SharedPreferences.getInstance();
        final roots = prefs.getStringList('root_paths') ?? [];
        bool isInsideRoot = false;
        for (final root in roots) {
          if (ScannerPathUtils.pathContains(root, filePath)) {
            isInsideRoot = true;
            break;
          }
        }
        if (isInsideRoot) {
          if (resolvedSourceFlags == null) {
            resolvedSourceFlags = SongSourceFlags.rootScan;
          } else {
            resolvedSourceFlags = (resolvedSourceFlags & ~SongSourceFlags.external) | SongSourceFlags.rootScan;
          }
        } else if (resolvedSourceFlags == null) {
          resolvedSourceFlags = SongSourceFlags.external;
        }
      } catch (_) {
        resolvedSourceFlags ??= SongSourceFlags.external;
      }

      final bool readFailed = title == null &&
          artist == null &&
          album == null &&
          duration == null;
      final int? textScannedTime =
          readFailed ? existing?.metadataTextScanned : lastModified;

      // 【整行写入的安全基底】
      // insertOrUpdateSong → _songCompanion 把 SongMetadata 的每一列都写成
      // Value(...)，没有 Value.absent()，所以「构造时没写的字段」等于
      // 「主动把该列清成 NULL」。历史上这里用 new SongMetadata(...) 逐个字段填，
      // 漏了 genres / hasArtwork / waveformBlob / deletedAt 等列，于是每次
      // 重读标签都会把它们洗掉（流派页整专辑消失就是这么来的）。
      // 改成以库内记录为基底 copyWith：没写的列一律保持旧值，以后新增字段
      // 即使忘了在这里处理，最坏结果也只是「沿用旧值」，不会静默清空。
      final base =
          existing ??
          SongMetadata(
            path: filePath,
            title: p.basenameWithoutExtension(filePath),
            album: 'Unknown Album',
            artist: 'Unknown Artist',
          );

      // 封面相关字段：只有本次「确实探测过封面」才采用探测结果。
      // generateThumbnail 为 false 或标签解析整体抛异常、且也没找到目录封面时，
      // 一律沿用旧值，避免一次读取失败就把库里已有的封面路径清空。
      final bool artworkProbed =
          generateThumbnail &&
          (!tagReadFailed || artworkPath != null || thumbnailPath != null);

      final song = base.copyWith(
        path: filePath,
        title: title ?? base.title,
        album: album ?? base.album,
        artist: artist ?? base.artist,
        albumArtist: albumArtist ?? base.albumArtist,
        duration: duration ?? base.duration,
        artworkPath: artworkProbed ? artworkPath : base.artworkPath,
        thumbnailPath: artworkProbed ? thumbnailPath : base.thumbnailPath,
        artworkWidth: artworkProbed ? artworkWidth : base.artworkWidth,
        artworkHeight: artworkProbed ? artworkHeight : base.artworkHeight,
        // 主题色是派生数据，重新生成要解码图片再做量化，代价较高；
        // 只有本次真的产出新色才覆盖，避免无谓丢色。
        themeColorsBlob: themeColorsBlob ?? base.themeColorsBlob,
        trackNumber: trackNumber ?? base.trackNumber,
        lastModifiedTime: lastModified,
        metadataTextScanned: textScannedTime,
        metadataImgScanned: generateThumbnail
            ? (readFailed ? base.metadataImgScanned : lastModified)
            : base.metadataImgScanned,
        createdAt: base.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        sourceFlags: resolvedSourceFlags,
        bitrate: bitrate ?? base.bitrate,
        sampleRate: sampleRate ?? base.sampleRate,
        channels: channels ?? base.channels,
        bitDepth: bitDepth ?? base.bitDepth,
        format: format ?? base.format,
        codec: codec ?? base.codec,
        fileRating: fileRating ?? base.fileRating,
        year: year ?? base.year,
        // 流派：标签里读不到时保留库内旧值，宁可留旧也不写空。
        genres: (genres != null && genres.isNotEmpty) ? genres : base.genres,
        hasArtwork: hasArtwork ?? base.hasArtwork,
        // id / mediaId / isAppModified / waveformBlob / deletedAt 有意不覆盖：
        // 它们不是「读文件能得到的列」，必须原样保留。
      );

      // 5. 将解析结果存入数据库
      await db.insertOrUpdateSong(song);
      return (song, artworkData);
    } catch (e) {
      debugPrint('Error processing metadata for $filePath: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> saveArtworkAndThumbnail(
    String songPath,
    Uint8List data, {
    bool saveLarge = false,
    int thumbnailSize = vynodyArtworkThumbnailSize,
  }) async {
    try {
      final md5Hex = await calculateMd5(bytes: data);
      final db = MetadataDatabase();
      final cached = await db.getArtworkCache(md5Hex);
      if (cached != null) {
        final hasThumb = cached.thumbnailPath != null && File(cached.thumbnailPath!).existsSync();
        final hasArt = cached.artworkPath != null && File(cached.artworkPath!).existsSync();
        if (hasThumb && (!saveLarge || hasArt)) {
          return {
            'artworkPath': cached.artworkPath,
            'thumbnailPath': cached.thumbnailPath,
            'width': cached.artworkWidth,
            'height': cached.artworkHeight,
            'themeColorsBlob': cached.themeColorsBlob,
          };
        }
      }

      final supportDir = await getApplicationSupportDirectory();
      final artworkInfo = await _buildArtworkFiles(
        songPath: songPath,
        data: data,
        supportDirPath: supportDir.path,
        saveLarge: saveLarge,
        thumbnailSize: thumbnailSize,
      );

      if (artworkInfo != null) {
        final record = ArtworkCacheRecord(
          md5: md5Hex,
          artworkPath: artworkInfo['artworkPath'] as String?,
          thumbnailPath: artworkInfo['thumbnailPath'] as String?,
          artworkWidth: artworkInfo['width'] as int?,
          artworkHeight: artworkInfo['height'] as int?,
          themeColorsBlob: artworkInfo['themeColorsBlob'] as Uint8List?,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        );
        await db.insertOrUpdateArtworkCache(record);
      }

      return artworkInfo;
    } catch (e) {
      debugPrint('Error saving artwork: $e');
      return null;
    }
  }

  static Future<void> clearThumbnails() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final thumbnailsDir = Directory(p.join(supportDir.path, 'thumbnails'));
      if (await thumbnailsDir.exists()) {
        await thumbnailsDir.delete(recursive: true);
        await thumbnailsDir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing thumbnails: $e');
    }
  }

  /// 从文件直接读取原始标签，不请求网络，不存入数据库
  static Future<SongMetadata?> readMetadataFromFile(String filePath) async {
    if (filePath.startsWith('subsonic://') ||
        filePath.startsWith('webdav://') ||
        filePath.startsWith('jellyfin://') ||
        filePath.startsWith('smb://')) {
      return null;
    }
    if (!await canAccessAudioFile(filePath)) {
      return null;
    }
    try {
      final targetPath = await resolveReadTargetPath(filePath);
      final metadata = await compute(_readMetadataIsolateEntryPoint, <String, dynamic>{
        'path': targetPath,
        'token': RootIsolateToken.instance,
      });
      final (format, codec) = resolveFormatAndCodec(
        path: filePath,
        rawFormat: metadata.format,
      );

      return SongMetadata(
        path: filePath,
        title: metadata.title ?? p.basenameWithoutExtension(filePath),
        album: metadata.album ?? 'Unknown Album',
        artist: metadata.artist ?? 'Unknown Artist',
        albumArtist: metadata.albumArtist,
        duration: metadata.duration?.inMilliseconds,
        trackNumber: metadata.trackNumber,
        hasArtwork: metadata.hasArtwork,
        bitrate: metadata.bitrate,
        sampleRate: metadata.sampleRate,
        channels: metadata.channels,
        bitDepth: metadata.bitDepth,
        format: format,
        codec: codec,
        year: metadata.year,
        genres: metadata.genres,
      );
    } catch (e) {
      debugPrint('Error reading metadata from file $filePath: $e');
      return null;
    }
  }

  /// Loads metadata for playback use.
  ///
  /// This first tries the database cache. If no record exists, it falls back to
  /// reading the audio file itself, then persists the parsed metadata back into
  /// the database through [processMetadata].
  ///
  /// The returned artwork bytes are only populated when the fallback file parse
  /// Reads metadata and embedded artwork from a locally cached file for a remote song URI,
  /// saves the metadata into the database (keyed by [remoteUri]), and returns the metadata.
  static Future<(SongMetadata, Uint8List?)?> processRemoteCachedMetadata(
    String remoteUri,
    String cachedFilePath, {
    bool generateThumbnail = true,
  }) async {
    final file = File(cachedFilePath);
    if (!await file.exists()) {
      return null;
    }
    final db = MetadataDatabase();
    final existing = await db.getSongMetadata(remoteUri);

    try {
      Uint8List? artworkData;
      String? title;
      String? album;
      String? artist;
      int? duration;
      int? trackNumber;

      try {
        final metadata = await compute(
          generateThumbnail
              ? _readMetadataWithImageIsolateEntryPoint
              : _readMetadataIsolateEntryPoint,
          <String, dynamic>{
            'path': cachedFilePath,
            'token': RootIsolateToken.instance,
          },
        );
        title = metadata.title;
        album = metadata.album;
        artist = metadata.artist;
        duration = metadata.duration?.inMilliseconds;
        trackNumber = metadata.trackNumber;
        artworkData = metadata.pictures.isNotEmpty
            ? metadata.pictures.first.bytes
            : null;
      } catch (e) {
        debugPrint('TagLib read error for remote cache $cachedFilePath ($remoteUri): $e');
      }

      String? artworkPath = existing?.artworkPath;
      String? thumbnailPath = existing?.thumbnailPath;
      int? artworkWidth = existing?.artworkWidth;
      int? artworkHeight = existing?.artworkHeight;
      Uint8List? themeColorsBlob = existing?.themeColorsBlob;

      if (artworkData != null && artworkData.isNotEmpty && generateThumbnail) {
        final artworkInfo = await saveArtworkAndThumbnail(
          remoteUri,
          artworkData,
          saveLarge: false,
        );
        if (artworkInfo != null) {
          artworkPath = artworkInfo['artworkPath'] as String?;
          thumbnailPath = artworkInfo['thumbnailPath'] as String?;
          artworkWidth = artworkInfo['width'] as int?;
          artworkHeight = artworkInfo['height'] as int?;
          themeColorsBlob = artworkInfo['themeColorsBlob'] as Uint8List?;
        }
      }

      final resolvedTitle = (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : (existing?.title ?? p.basenameWithoutExtension(remoteUri));
      final resolvedArtist = (artist != null && artist.trim().isNotEmpty)
          ? artist.trim()
          : (existing?.artist ?? 'Unknown Artist');
      final resolvedAlbum = (album != null && album.trim().isNotEmpty)
          ? album.trim()
          : (existing?.album ?? 'Unknown Album');

      // 与 processMetadata 同一条原则：以库内记录为基底 copyWith，
      // 让「没写的列」保持旧值，而不是被整行写入清成 NULL。
      final base =
          existing ??
          SongMetadata(
            path: remoteUri,
            title: p.basenameWithoutExtension(remoteUri),
            album: 'Unknown Album',
            artist: 'Unknown Artist',
          );
      final now = DateTime.now().millisecondsSinceEpoch;

      final song = base.copyWith(
        path: remoteUri,
        title: resolvedTitle,
        album: resolvedAlbum,
        artist: resolvedArtist,
        duration: duration ?? base.duration,
        artworkPath: artworkPath,
        thumbnailPath: thumbnailPath,
        artworkWidth: artworkWidth,
        artworkHeight: artworkHeight,
        trackNumber: trackNumber ?? base.trackNumber,
        themeColorsBlob: themeColorsBlob,
        lastModifiedTime: now,
        metadataImgScanned: now,
        metadataTextScanned: now,
        createdAt: base.createdAt ?? now,
      );

      await db.insertOrUpdateSong(song);
      return (song, artworkData);
    } catch (e) {
      debugPrint('Error processing remote cached metadata for $remoteUri: $e');
      return null;
    }
  }

  /// Loads metadata for the playback pipeline.
  ///
  /// This is optimized for quick playback startup: if the metadata is already
  /// cached in the database, it returns immediately with that metadata (and null
  /// for artwork bytes, which can be hydrated asynchronously). If not cached, it
  /// does a quick scan to extract basic metadata and embedded artwork bytes.
  ///
  /// Returns a tuple of `(SongMetadata, Uint8List?)` where the second element
  /// is non-null only if a fresh scan (not a DB cache hit)
  /// was needed and the file contained embedded artwork.
  static bool _isMetadataComplete(SongMetadata metadata) {
    if (metadata.isModified) {
      return true;
    }
    final hasTitle = metadata.title.trim().isNotEmpty &&
        metadata.title.trim().toLowerCase() != 'unknown';
    final hasArtist = metadata.artist.trim().isNotEmpty &&
        metadata.artist.trim().toLowerCase() != 'unknown' &&
        metadata.artist.trim().toLowerCase() != 'unknown artist';
    final hasAlbum = metadata.album.trim().isNotEmpty &&
        metadata.album.trim().toLowerCase() != 'unknown' &&
        metadata.album.trim().toLowerCase() != 'unknown album';
    final hasDuration = metadata.duration != null && metadata.duration! > 0;
    return hasTitle && (hasArtist || hasAlbum) && hasDuration;
  }

  static Future<(SongMetadata, Uint8List?)?> loadMetadataForPlayback(
    String filePath, {
    bool generateThumbnail = false,
    bool forceRefresh = false,
  }) async {
    final db = MetadataDatabase();
    final cached = await db.getSongMetadata(filePath);
    if (!forceRefresh && cached != null && _isMetadataComplete(cached)) {
      return (cached, null);
    }
    if (filePath.startsWith('subsonic://') ||
        filePath.startsWith('webdav://') ||
        filePath.startsWith('jellyfin://') ||
        filePath.startsWith('smb://')) {
      if (cached != null) {
        return (cached, null);
      }
      return null;
    }

    return processMetadata(
      filePath,
      generateThumbnail: generateThumbnail,
      sourceFlags: SongSourceFlags.external,
      forceRefresh: forceRefresh,
    );
  }

  /// 解码文件内嵌封面，分辨率限制在 [maxWidth] * [maxHeight]
  static Future<Uint8List?> decodeEmbeddedArtwork(String filePath) async {
    if (filePath.startsWith('subsonic://') ||
        filePath.startsWith('webdav://') ||
        filePath.startsWith('jellyfin://') ||
        filePath.startsWith('smb://')) {
      return null;
    }
    if (!await canAccessAudioFile(filePath)) {
      return null;
    }
    try {
      final targetPath = await resolveReadTargetPath(filePath);
      final metadata = await compute(_readMetadataWithImageIsolateEntryPoint, <String, dynamic>{
        'path': targetPath,
        'token': RootIsolateToken.instance,
      });
      if (metadata.pictures.isEmpty) return null;

      return metadata.pictures.first.bytes;
    } catch (e) {
      debugPrint('Error decoding embedded artwork for $filePath: $e');
      return null;
    }
  }

  /// 探测文件内是否存在内嵌封面，不生成任何缓存文件。
  static Future<bool> hasEmbeddedArtwork(String filePath) async {
    if (filePath.startsWith('subsonic://') ||
        filePath.startsWith('webdav://') ||
        filePath.startsWith('jellyfin://') ||
        filePath.startsWith('smb://')) {
      return false;
    }
    if (!await canAccessAudioFile(filePath)) {
      return false;
    }
    try {
      final targetPath = await resolveReadTargetPath(filePath);
      final metadata = await compute(_readMetadataIsolateEntryPoint, <String, dynamic>{
        'path': targetPath,
        'token': RootIsolateToken.instance,
      });
      return metadata.hasArtwork;
    } catch (_) {
      // Probe-only API: tagless or slightly malformed files should behave like
      // "no artwork" here instead of polluting logs.
      return false;
    }
  }

  static String? _extractAlbumArtist(taglib.TagLibFile tagFile) {
    try {
      final props = tagFile.properties;
      final val = props[taglib.TagProperties.albumArtist]?.firstOrNull ??
          props['ALBUM ARTIST']?.firstOrNull ??
          props['ALBUM_ARTIST']?.firstOrNull;
      final trimmed = val?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    } catch (_) {}
    return null;
  }

  /// 把标签里的流派原始文本切成列表。
  ///
  /// 允许的分隔符与批量扫描路径保持一致，避免单文件读取与批量读取
  /// 对同一份标签给出不同的流派分组。
  static List<String>? parseGenreTag(String? rawGenre) {
    final raw = rawGenre?.trim();
    if (raw == null || raw.isEmpty) return null;
    final genres = raw
        .split(RegExp(r'[;,/、\\|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return genres.isEmpty ? null : genres;
  }

  static Never _throwTagLibNotSupported() {
    final probeError = taglib.TagLibFile.lastSupportProbeError;
    if (probeError != null) {
      throw UnsupportedError('TagLib is not supported: $probeError');
    }
    throw UnsupportedError('TagLib is not supported.');
  }

  static TagLibMetadata readMetadataIsolate(String path) {
    if (!taglib.TagLibFile.isSupported) {
      _throwTagLibNotSupported();
    }
    final tagFile = taglib.TagLibFile.open(path);
    if (tagFile == null) {
      throw Exception('Failed to open file via TagLib.');
    }
    try {
      final title = tagFile.title;
      final artist = tagFile.artist;
      final album = tagFile.album;
      final albumArtist = _extractAlbumArtist(tagFile);
      final duration = tagFile.duration;
      final trackNumber = tagFile.track;
      final hasArtwork = tagFile.hasCover;
      final bitrate = tagFile.bitrate > 0 ? tagFile.bitrate * 1000 : null;
      final sampleRate = tagFile.sampleRate > 0 ? tagFile.sampleRate : null;
      final channels = tagFile.channels > 0 ? tagFile.channels : null;
      final bitDepth = tagFile.bitDepth;
      final format = tagFile.format;
      final rating = tagFile.rating > 0 ? tagFile.rating.clamp(1, 5) : null;

      return TagLibMetadata(
        title: title.isNotEmpty ? title : null,
        album: album.isNotEmpty ? album : null,
        artist: artist.isNotEmpty ? artist : null,
        albumArtist: albumArtist,
        duration: duration.inMilliseconds > 0 ? duration : null,
        trackNumber: trackNumber > 0 ? trackNumber : null,
        hasArtwork: hasArtwork,
        pictures: const [],
        bitrate: bitrate,
        sampleRate: sampleRate,
        channels: channels,
        bitDepth: bitDepth,
        format: format,
        rating: rating,
        genres: parseGenreTag(tagFile.genre),
      );
    } finally {
      tagFile.close();
    }
  }

  static TagLibMetadata readMetadataWithImageIsolate(String path) {
    if (!taglib.TagLibFile.isSupported) {
      _throwTagLibNotSupported();
    }
    final tagFile = taglib.TagLibFile.open(path);
    if (tagFile == null) {
      throw Exception('Failed to open file via TagLib.');
    }
    try {
      final title = tagFile.title;
      final artist = tagFile.artist;
      final album = tagFile.album;
      final albumArtist = _extractAlbumArtist(tagFile);
      final duration = tagFile.duration;
      final trackNumber = tagFile.track;
      final hasArtwork = tagFile.hasCover;
      final pictures = tagFile.pictures;
      final bitrate = tagFile.bitrate > 0 ? tagFile.bitrate * 1000 : null;
      final sampleRate = tagFile.sampleRate > 0 ? tagFile.sampleRate : null;
      final channels = tagFile.channels > 0 ? tagFile.channels : null;
      final bitDepth = tagFile.bitDepth;
      final format = tagFile.format;
      final rating = tagFile.rating > 0 ? tagFile.rating.clamp(1, 5) : null;

      return TagLibMetadata(
        title: title.isNotEmpty ? title : null,
        album: album.isNotEmpty ? album : null,
        artist: artist.isNotEmpty ? artist : null,
        albumArtist: albumArtist,
        duration: duration.inMilliseconds > 0 ? duration : null,
        trackNumber: trackNumber > 0 ? trackNumber : null,
        hasArtwork: hasArtwork,
        pictures: pictures,
        bitrate: bitrate,
        sampleRate: sampleRate,
        channels: channels,
        bitDepth: bitDepth,
        format: format,
        rating: rating,
        genres: parseGenreTag(tagFile.genre),
      );
    } finally {
      tagFile.close();
    }
  }

  static Future<TagLibMetadata> _readMetadataIsolateEntryPoint(
    Map<String, dynamic> args,
  ) async {
    final path = args['path'] as String;
    final token = args['token'] as RootIsolateToken?;

    if (Platform.isAndroid && token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }

    if (!taglib.TagLibFile.isSupported) {
      _throwTagLibNotSupported();
    }
    final tagFile = await taglib.TagLibFile.openAsync(path);
    if (tagFile == null) {
      throw Exception('Failed to open file via TagLib.');
    }
    try {
      final title = tagFile.title;
      final artist = tagFile.artist;
      final album = tagFile.album;
      final albumArtist = _extractAlbumArtist(tagFile);
      final duration = tagFile.duration;
      final trackNumber = tagFile.track;
      final hasArtwork = tagFile.hasCover;
      final bitrate = tagFile.bitrate > 0 ? tagFile.bitrate * 1000 : null;
      final sampleRate = tagFile.sampleRate > 0 ? tagFile.sampleRate : null;
      final channels = tagFile.channels > 0 ? tagFile.channels : null;
      final bitDepth = tagFile.bitDepth;
      final (format, codec) = resolveFormatAndCodec(path: path, rawFormat: tagFile.format);
      final rating = tagFile.rating > 0 ? tagFile.rating.clamp(1, 5) : null;
      final year = tagFile.year > 0 ? tagFile.year : null;

      return TagLibMetadata(
        title: title.isNotEmpty ? title : null,
        album: album.isNotEmpty ? album : null,
        artist: artist.isNotEmpty ? artist : null,
        albumArtist: albumArtist,
        duration: duration.inMilliseconds > 0 ? duration : null,
        trackNumber: trackNumber > 0 ? trackNumber : null,
        hasArtwork: hasArtwork,
        pictures: const [],
        bitrate: bitrate,
        sampleRate: sampleRate,
        channels: channels,
        bitDepth: bitDepth,
        format: format,
        codec: codec,
        rating: rating,
        year: year,
        genres: parseGenreTag(tagFile.genre),
      );
    } finally {
      tagFile.close();
    }
  }

  static Future<TagLibMetadata> _readMetadataWithImageIsolateEntryPoint(
    Map<String, dynamic> args,
  ) async {
    final path = args['path'] as String;
    final token = args['token'] as RootIsolateToken?;

    if (Platform.isAndroid && token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }

    if (!taglib.TagLibFile.isSupported) {
      _throwTagLibNotSupported();
    }
    final tagFile = await taglib.TagLibFile.openAsync(path);
    if (tagFile == null) {
      throw Exception('Failed to open file via TagLib.');
    }
    try {
      final title = tagFile.title;
      final artist = tagFile.artist;
      final album = tagFile.album;
      final albumArtist = _extractAlbumArtist(tagFile);
      final duration = tagFile.duration;
      final trackNumber = tagFile.track;
      final hasArtwork = tagFile.hasCover;
      final pictures = tagFile.pictures;
      final bitrate = tagFile.bitrate > 0 ? tagFile.bitrate * 1000 : null;
      final sampleRate = tagFile.sampleRate > 0 ? tagFile.sampleRate : null;
      final channels = tagFile.channels > 0 ? tagFile.channels : null;
      final bitDepth = tagFile.bitDepth;
      final (format, codec) = resolveFormatAndCodec(path: path, rawFormat: tagFile.format);
      final rating = tagFile.rating > 0 ? tagFile.rating.clamp(1, 5) : null;
      final year = tagFile.year > 0 ? tagFile.year : null;

      return TagLibMetadata(
        title: title.isNotEmpty ? title : null,
        album: album.isNotEmpty ? album : null,
        artist: artist.isNotEmpty ? artist : null,
        albumArtist: albumArtist,
        duration: duration.inMilliseconds > 0 ? duration : null,
        trackNumber: trackNumber > 0 ? trackNumber : null,
        hasArtwork: hasArtwork,
        pictures: pictures,
        bitrate: bitrate,
        sampleRate: sampleRate,
        channels: channels,
        bitDepth: bitDepth,
        format: format,
        codec: codec,
        rating: rating,
        year: year,
        genres: parseGenreTag(tagFile.genre),
      );
    } finally {
      tagFile.close();
    }
  }

  /// Resolves normalized audio format and codec from file path and optional raw TagLib format string.
  static (String? format, String? codec) resolveFormatAndCodec({
    required String path,
    String? rawFormat,
  }) {
    var ext = p.extension(path).replaceAll('.', '').toLowerCase();
    if (ext.contains('?')) ext = ext.split('?').first;
    String? format = rawFormat?.trim().isNotEmpty == true ? rawFormat!.trim() : null;
    if (format == null || format.isEmpty) {
      if (ext != 'cache' && ext != 'tmp' && ext.isNotEmpty) {
        format = (ext == 'mpeg') ? 'mp3' : (ext == 'mp4' ? 'm4a' : ext);
      }
    }
    String? codec;
    if (format != null) {
      final fLower = format.toLowerCase();
      if (fLower == 'mp3' || fLower == 'mpeg') {
        codec = 'mp3';
      } else if (fLower == 'm4a' || fLower == 'mp4') {
        codec = 'aac';
      } else {
        codec = format;
      }
    }
    return (format, codec);
  }

  static Future<List<ScannedFileMetadata>> readMetadataBatch(
    List<String> filePaths, {
    bool getImage = false,
    int? isolateCount,
  }) async {
    if (filePaths.isEmpty) {
      return const [];
    }

    try {
      if (taglib.TagLibFile.isSupported) {
        final batchResults = await taglib.TagLibFile.readBatchAsync(
          filePaths,
          isolateCount: isolateCount ?? 0,
          readCover: getImage,
        );

        final results = <ScannedFileMetadata>[];
        int successCount = 0;
        int failCount = 0;
        int withGenreCount = 0;
        for (final item in batchResults) {
          final metadata = _scannedMetadataFromBatchItem(item);
          if (metadata.isSuccess) {
            successCount++;
            if (metadata.genres?.isNotEmpty ?? false) {
              withGenreCount++;
            }
          } else {
            failCount++;
            if (failCount <= 5) {
              debugPrint('[MetadataHelper] batch item failed: path=${item.path}, error=${item.error}');
            }
          }
          results.add(metadata);
        }
        debugPrint('[MetadataHelper] readMetadataBatch completed: total=${filePaths.length}, success=$successCount, fail=$failCount');
        // 扫描入库阶段「流派读到没有」是判断数据源是否可靠的关键指标：
        // 若 success 远大于 withGenre，说明批次读取没拿到 GENRE，流派缺失
        // 就不该再怀疑播放链路。一次扫描只打一行，不产生噪声。
        app_log.AppLog.log(
          '[ScanGenre] readMetadataBatch total=${filePaths.length} '
          'success=$successCount fail=$failCount withGenre=$withGenreCount',
          mirrorToConsole: true,
        );
        return results;
      }
    } catch (e, stackTrace) {
      debugPrint('[MetadataHelper] TagLib readBatchAsync failed: $e\n$stackTrace');
    }

    return compute(_readMetadataBatchIsolate, <String, dynamic>{
      'paths': filePaths,
      'getImage': getImage,
      'token': RootIsolateToken.instance,
    });
  }

  static ScannedFileMetadata _scannedMetadataFromBatchItem(
    taglib.BatchTagMetadata item,
  ) {
    final originalPath = item.path;
    final (format, codec) = resolveFormatAndCodec(
      path: originalPath,
      rawFormat: item.format,
    );

    int? lastModified;
    try {
      lastModified = File(originalPath).lastModifiedSync().millisecondsSinceEpoch;
    } catch (_) {}

    final isSuccess = item.success;
    final rawGenre = item.genre.trim();
    final List<String>? genres = rawGenre.isNotEmpty
        ? rawGenre
            .split(RegExp(r'[;,/、\\|]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
        : null;
    return ScannedFileMetadata(
      path: originalPath,
      title: item.title.trim().isNotEmpty ? item.title.trim() : null,
      album: item.album.trim().isNotEmpty ? item.album.trim() : null,
      artist: item.artist.trim().isNotEmpty ? item.artist.trim() : null,
      duration: item.duration.inMilliseconds > 0 ? item.duration.inMilliseconds : null,
      trackNumber: item.track > 0 ? item.track : null,
      hasArtwork: item.hasCover,
      artworkBytes: item.coverData,
      lastModifiedTime: lastModified,
      bitrate: item.bitrate > 0 ? item.bitrate * 1000 : null,
      sampleRate: item.sampleRate > 0 ? item.sampleRate : null,
      channels: item.channels > 0 ? item.channels : null,
      bitDepth: item.bitDepth,
      format: format,
      codec: codec,
      fileRating: item.rating > 0 ? item.rating.clamp(1, 5) : null,
      year: item.year > 0 ? item.year : null,
      genres: genres,
      error: isSuccess ? null : (item.error ?? 'Failed to read metadata'),
    );
  }

  static ScannedFileMetadata _scannedMetadataFromTagLibFile(
    String path,
    taglib.TagLibFile tagFile, {
    required bool getImage,
    int? lastModifiedTime,
  }) {
    final (format, codec) = resolveFormatAndCodec(
      path: path,
      rawFormat: tagFile.format,
    );
    final hasArtwork = tagFile.hasCover;
    final rawGenre = tagFile.genre.trim();
    final List<String>? genres = rawGenre.isNotEmpty
        ? rawGenre
            .split(RegExp(r'[;,/、\\|]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
        : null;

    return ScannedFileMetadata(
      path: path,
      title: tagFile.title.trim().isNotEmpty ? tagFile.title.trim() : null,
      album: tagFile.album.trim().isNotEmpty ? tagFile.album.trim() : null,
      artist: tagFile.artist.trim().isNotEmpty ? tagFile.artist.trim() : null,
      albumArtist: _extractAlbumArtist(tagFile),
      duration: tagFile.duration.inMilliseconds > 0 ? tagFile.duration.inMilliseconds : null,
      trackNumber: tagFile.track > 0 ? tagFile.track : null,
      hasArtwork: hasArtwork,
      artworkBytes: getImage && hasArtwork ? tagFile.coverData : null,
      lastModifiedTime: lastModifiedTime,
      bitrate: tagFile.bitrate > 0 ? tagFile.bitrate * 1000 : null,
      sampleRate: tagFile.sampleRate > 0 ? tagFile.sampleRate : null,
      channels: tagFile.channels > 0 ? tagFile.channels : null,
      bitDepth: tagFile.bitDepth,
      format: format,
      codec: codec,
      fileRating: tagFile.rating > 0 ? tagFile.rating.clamp(1, 5) : null,
      year: tagFile.year > 0 ? tagFile.year : null,
      genres: genres,
      error: null,
    );
  }

  static Future<List<ScannedFileMetadata>> _readMetadataBatchIsolate(
    Map<String, dynamic> args,
  ) async {
    final paths = (args['paths'] as List).cast<String>();
    final getImage = args['getImage'] as bool? ?? false;
    final token = args['token'] as RootIsolateToken?;

    if (Platform.isAndroid && token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }

    final results = <ScannedFileMetadata>[];
    for (final path in paths) {
      final file = File(path);
      try {
        if (!taglib.TagLibFile.isSupported) {
          _throwTagLibNotSupported();
        }
        try {
          if (file.existsSync() && file.lengthSync() == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        } catch (_) {}

        var tagFile = await taglib.TagLibFile.openAsync(path);
        if (tagFile == null) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          tagFile = await taglib.TagLibFile.openAsync(path);
        }
        if (tagFile == null) {
          throw Exception('Failed to open file via TagLib.');
        }
        try {
          final lastModified = _safeLastModifiedMillis(file);
          results.add(
            _scannedMetadataFromTagLibFile(
              path,
              tagFile,
              getImage: getImage,
              lastModifiedTime: lastModified,
            ),
          );
        } finally {
          tagFile.close();
        }
      } catch (e) {
        final lastModified = _safeLastModifiedMillis(file);
        results.add(
          ScannedFileMetadata(
            path: path,
            lastModifiedTime: lastModified,
            hasArtwork: false,
            error: e.toString(),
          ),
        );
      }
    }
    return results;
  }

  static int? _safeLastModifiedMillis(File file) {
    try {
      return file.lastModifiedSync().millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  /// Saves metadata to a single audio file.
  /// Returns true if successful, false if the format is not supported or an error occurred.
  static Future<bool> saveMetadataToFile(
    String filePath, {
    String? title,
    String? artist,
    String? album,
    int? trackNumber,
    List<String>? genres,
    String? o3ics,
    List<taglib.Picture>? pictures,
  }) async {
    if (!isMetadataWritable(filePath)) {
      return false;
    }

    try {
      final firstPictureBytes = (pictures?.isNotEmpty ?? false)
          ? pictures!.first.bytes
          : null;
      final success = await _writeSelectionMetadataToFile(
        filePath: filePath,
        metadata: SongMetadata(
          path: filePath,
          title: title ?? p.basenameWithoutExtension(filePath),
          album: album ?? 'Unknown Album',
          artist: artist ?? 'Unknown Artist',
          trackNumber: trackNumber,
          genres: genres,
        ),
        artworkBytes: firstPictureBytes,
        lyrics: o3ics,
        pictures: pictures
            ?.map(
              (picture) => TrackMetadataPicture(
                bytes: picture.bytes,
                mimeType: picture.mimeType,
                pictureType: picture.pictureType,
              ),
            )
            .toList(),
      );
      return success;
    } catch (e) {
      debugPrint('Error saving metadata to $filePath: $e');
      return false;
    }
  }

  /// Saves metadata for multiple songs.
  /// Returns a result indicating success count, unsupported count, and errors.
  static Future<SaveMetadataResult> saveMetadataToMultipleFiles(
    List<SongMetadata> songs, {
    List<String>? o3icsList,
    List<Uint8List?>? artworkBytesList,
  }) async {
    int savedCount = 0;
    int unsupportedCount = 0;
    final unsupportedFiles = <String>[];

    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];
      final o3ics = o3icsList != null && i < o3icsList.length
          ? o3icsList[i]
          : null;
      final artworkBytes =
          artworkBytesList != null && i < artworkBytesList.length
          ? artworkBytesList[i]
          : null;

      List<taglib.Picture>? pictures;
      if (artworkBytes != null) {
        pictures = [
          taglib.Picture(
            bytes: artworkBytes,
            mimeType: 'image/jpeg',
            pictureType: 'Front Cover',
          ),
        ];
      }

      final success = await saveMetadataToFile(
        song.path,
        title: song.title,
        artist: song.artist,
        album: song.album,
        trackNumber: song.trackNumber,
        genres: song.genres,
        o3ics: o3ics,
        pictures: pictures,
      );

      if (success) {
        savedCount++;
      } else {
        if (isMetadataWritable(song.path)) {
          debugPrint('Failed to save metadata to ${song.path}');
        } else {
          unsupportedCount++;
          unsupportedFiles.add(song.path);
        }
      }
    }

    return SaveMetadataResult(
      success: unsupportedCount == 0,
      unsupportedCount: unsupportedCount,
      savedCount: savedCount,
      unsupportedFiles: unsupportedFiles,
    );
  }

  /// Writes lyrics to a single audio file, preserving existing metadata and artwork.
  static Future<bool> saveLyricsToFile(String filePath, String lyricsText) async {
    lastWriteError = null;
    if (!isMetadataWritable(filePath)) {
      lastWriteError = 'File format is not supported for writing metadata';
      debugPrint('[MetadataHelper] $lastWriteError');
      return false;
    }
    if (!await canAccessAudioFile(filePath)) {
      lastWriteError = 'Cannot access file: no media permission or SAF authorization for $filePath';
      debugPrint('[MetadataHelper] $lastWriteError');
      return false;
    }

    try {
      final db = MetadataDatabase();
      var metadata = await db.getSongMetadata(filePath);
      metadata ??= await readMetadataFromFile(filePath);

      metadata ??= SongMetadata(
        path: filePath,
        title: p.basenameWithoutExtension(filePath),
        album: 'Unknown Album',
        artist: 'Unknown Artist',
      );

      Uint8List? artworkBytes;
      if (metadata.artworkPath != null && metadata.artworkPath!.isNotEmpty) {
        final artworkFile = File(metadata.artworkPath!);
        if (await artworkFile.exists()) {
          artworkBytes = await artworkFile.readAsBytes();
        }
      }

      artworkBytes ??= await decodeEmbeddedArtwork(filePath);

      final success = await _writeSelectionMetadataToFile(
        filePath: filePath,
        metadata: metadata,
        artworkBytes: artworkBytes,
        lyrics: lyricsText,
      );

      if (success) {
        final mtime = File(filePath).lastModifiedSync().millisecondsSinceEpoch;
        var updated = metadata.copyWith(
          lastModifiedTime: mtime,
          createdAt: mtime,
          isAppModified: false,
        );
        await db.insertOrUpdateSong(updated);
      }

      return success;
    } catch (e) {
      debugPrint('Error saving lyrics to file $filePath: $e');
      lastWriteError = e.toString();
      return false;
    }
  }

  /// Writes lyrics to an external .lrc file in the same directory as the song.
  /// On Android, resolves SAF tree URIs and uses the native saveFileToDirectory method if needed.
  static Future<bool> saveLyricsToExternalLrc(String songPath, String lyricsText) async {
    lastWriteError = null;

    final directory = p.dirname(songPath);
    final baseName = p.basenameWithoutExtension(songPath);
    final lrcFileName = '$baseName.lrc';
    final lrcFilePath = p.join(directory, lrcFileName);

    if (Platform.isAndroid) {
      // Check if we can write normally (e.g. if it's on local storage that supports regular File writing)
      try {
        final dir = Directory(directory);
        if (await dir.exists()) {
          final testFile = File(p.join(directory, '.vynody_write_test'));
          await testFile.writeAsString('test');
          await testFile.delete();
          // Regular write works!
          final file = File(lrcFilePath);
          await file.writeAsString(lyricsText);
          return true;
        }
      } catch (_) {
        // Fallback to SAF below
      }

      // Resolve SAF mapping
      final mapping = await AndroidSafStorageHelper.findBestMapping(songPath);
      if (mapping == null) {
        lastWriteError = 'No write permission for this folder. Please re-add the folder to grant permission.';
        debugPrint('[MetadataHelper] $lastWriteError');
        return false;
      }

      final rootDisplayPath = mapping.key;
      final treeUri = mapping.value;

      // Calculate relative path from SAF root to the lrc file
      String relativeLrcPath = '';
      try {
        relativeLrcPath = p.relative(lrcFilePath, from: rootDisplayPath);
      } catch (e) {
        relativeLrcPath = lrcFileName;
      }

      // Write lyric text to a temporary scratch file first
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, 'temp_lyrics_${DateTime.now().millisecondsSinceEpoch}.lrc'));
      await tempFile.writeAsString(lyricsText);

      try {
        final controller = AudioCoreController();
        if (!controller.isInitialized) {
          await controller.initialize();
        }

        // Call native channel via audio_converter channel
        final methodChannel = const MethodChannel('com.example.audio_converter/saf');
        final result = await methodChannel.invokeMapMethod<String, Object?>(
          'saveFileToDirectory',
          <String, Object?>{
            'treeUri': treeUri,
            'sourcePath': tempFile.path,
            'fileName': relativeLrcPath.replaceAll('\\', '/'),
            'overwrite': true,
          },
        );
        final savedUri = result?['savedUri']?.toString();
        if (savedUri != null && savedUri.isNotEmpty) {
          return true;
        } else {
          lastWriteError = 'Failed to write via SAF';
          return false;
        }
      } catch (e) {
        debugPrint('[MetadataHelper] Native save file via SAF failed: $e');
        lastWriteError = e.toString();
        return false;
      } finally {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } else {
      // Desktop / iOS: standard file write
      try {
        final file = File(lrcFilePath);
        await file.writeAsString(lyricsText);
        return true;
      } catch (e) {
        debugPrint('[MetadataHelper] Failed to save external LRC: $e');
        lastWriteError = e.toString();
        return false;
      }
    }
  }
}

class TagLibMetadata {
  final String? title;
  final String? album;
  final String? artist;
  final String? albumArtist;
  final Duration? duration;
  final int? trackNumber;
  final bool hasArtwork;
  final List<taglib.Picture> pictures;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final int? bitDepth;
  final String? format;
  final String? codec;
  final int? rating;
  final int? year;
  final List<String>? genres;

  TagLibMetadata({
    this.title,
    this.album,
    this.artist,
    this.albumArtist,
    this.duration,
    this.trackNumber,
    required this.hasArtwork,
    required this.pictures,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.bitDepth,
    this.format,
    this.codec,
    this.rating,
    this.year,
    this.genres,
  });
}

/// Strongly-typed metadata representation produced during batch or isolated scanning.
class ScannedFileMetadata {
  final String path;
  final String? title;
  final String? album;
  final String? artist;
  final String? albumArtist;
  final int? duration;
  final int? trackNumber;
  final int? year;
  final List<String>? genres;
  final bool hasArtwork;
  final Uint8List? artworkBytes;
  final int? lastModifiedTime;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final int? bitDepth;
  final String? format;
  final String? codec;
  final int? fileRating;
  final String? error;

  const ScannedFileMetadata({
    required this.path,
    this.title,
    this.album,
    this.artist,
    this.albumArtist,
    this.duration,
    this.trackNumber,
    this.year,
    this.genres,
    this.hasArtwork = false,
    this.artworkBytes,
    this.lastModifiedTime,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.bitDepth,
    this.format,
    this.codec,
    this.fileRating,
    this.error,
  });

  bool get hasError => error != null;
  bool get isSuccess => error == null;

  Map<String, dynamic> toMap() => {
    'path': path,
    'title': title,
    'album': album,
    'artist': artist,
    'albumArtist': albumArtist,
    'duration': duration,
    'trackNumber': trackNumber,
    'year': year,
    'genres': genres,
    'hasArtwork': hasArtwork,
    'artworkBytes': artworkBytes,
    'lastModifiedTime': lastModifiedTime,
    'bitrate': bitrate,
    'sampleRate': sampleRate,
    'channels': channels,
    'bitDepth': bitDepth,
    'format': format,
    'codec': codec,
    'fileRating': fileRating,
    'error': error,
  };

  factory ScannedFileMetadata.fromMap(Map<String, dynamic> map) =>
      ScannedFileMetadata(
        path: map['path'] as String? ?? '',
        title: map['title'] as String?,
        album: map['album'] as String?,
        artist: map['artist'] as String?,
        albumArtist: map['albumArtist'] as String?,
        duration: map['duration'] as int?,
        trackNumber: map['trackNumber'] as int?,
        year: map['year'] as int?,
        genres: (map['genres'] as List?)?.map((e) => e.toString()).toList(),
        hasArtwork: (map['hasArtwork'] as bool?) ?? false,
        artworkBytes: map['artworkBytes'] as Uint8List?,
        lastModifiedTime: map['lastModifiedTime'] as int?,
        bitrate: map['bitrate'] as int?,
        sampleRate: map['sampleRate'] as int?,
        channels: map['channels'] as int?,
        bitDepth: map['bitDepth'] as int?,
        format: map['format'] as String?,
        codec: map['codec'] as String?,
        fileRating: map['fileRating'] as int?,
        error: map['error'] as String?,
      );
}

class AndroidSafStorageHelper {
  static const String _prefKey = 'saf_tree_mappings_v1';

  static Future<Map<String, String>> getMappings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKey);
      if (jsonStr == null || jsonStr.isEmpty) return {};
      final map = jsonDecode(jsonStr);
      if (map is Map) {
        return map.map((key, value) => MapEntry(key.toString(), value.toString()));
      }
    } catch (e) {
      debugPrint('[AndroidSafStorageHelper] Error reading mappings: $e');
    }
    return {};
  }

  static Future<void> saveMapping(String displayPath, String treeUri) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getMappings();
      current[displayPath] = treeUri;
      await prefs.setString(_prefKey, jsonEncode(current));
      debugPrint('[AndroidSafStorageHelper] Saved mapping: $displayPath -> $treeUri');
    } catch (e) {
      debugPrint('[AndroidSafStorageHelper] Error saving mapping: $e');
    }
  }

  static Future<MapEntry<String, String>?> findBestMapping(String filePath) async {
    final mappings = await getMappings();
    if (mappings.isEmpty) return null;

    final normalizedFile = p.normalize(filePath).toLowerCase();
    MapEntry<String, String>? bestMatch;
    int longestMatchLength = 0;

    for (final entry in mappings.entries) {
      final normalizedRoot = p.normalize(entry.key).toLowerCase();
      if (normalizedFile.startsWith(normalizedRoot)) {
        if (entry.key.length > longestMatchLength) {
          longestMatchLength = entry.key.length;
          bestMatch = entry;
        }
      }
    }
    return bestMatch;
  }

  static String? resolvePhysicalPathToSafUri(String physicalPath, Map<String, String> mappings) {
    final normalizedFile = p.normalize(physicalPath).toLowerCase();
    String? bestRoot;
    String? bestTreeUriStr;

    for (final entry in mappings.entries) {
      final normalizedRoot = p.normalize(entry.key).toLowerCase();
      if (normalizedFile.startsWith(normalizedRoot)) {
        if (bestRoot == null || entry.key.length > bestRoot.length) {
          bestRoot = entry.key;
          bestTreeUriStr = entry.value;
        }
      }
    }

    if (bestRoot != null && bestTreeUriStr != null) {
      final relativePath = physicalPath.substring(bestRoot.length).replaceFirst(RegExp(r'^[/\\]+'), '');
      final normalizedRelativePath = relativePath.replaceAll('\\', '/');

      final treeUri = Uri.parse(bestTreeUriStr);
      if (treeUri.pathSegments.length >= 2 && treeUri.pathSegments[0] == 'tree') {
        final treeId = treeUri.pathSegments[1];
        final childDocumentId = normalizedRelativePath.isEmpty
            ? treeId
            : '$treeId/$normalizedRelativePath';

        final authority = treeUri.authority;
        final encodedTreeId = Uri.encodeComponent(treeId);
        final encodedChildDocId = Uri.encodeComponent(childDocumentId);
        return 'content://$authority/tree/$encodedTreeId/document/$encodedChildDocId';
      }
    }
    return null;
  }

  static Future<bool> fileExists(String treeUri, String relativePath) async {
    try {
      final methodChannel = const MethodChannel('com.example.audio_converter/saf');
      final result = await methodChannel.invokeMethod<bool>(
        'fileExistsInDirectory',
        <String, Object?>{
          'treeUri': treeUri,
          'fileName': relativePath.replaceAll('\\', '/'),
        },
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[AndroidSafStorageHelper] fileExists error: $e');
      return false;
    }
  }

  static Future<bool> directoryExists(String treeUri) async {
    try {
      final methodChannel = const MethodChannel('com.example.audio_converter/saf');
      final result = await methodChannel.invokeMethod<bool>(
        'directoryExists',
        <String, Object?>{
          'treeUri': treeUri,
        },
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[AndroidSafStorageHelper] directoryExists error: $e');
      return false;
    }
  }

  static Future<List<String>> listMusicFilesRecursively(
    String treeUri, {
    String relativeSubPath = '',
    List<String>? extensions,
  }) async {
    try {
      final methodChannel = const MethodChannel('com.example.audio_converter/saf');
      final result = await methodChannel.invokeListMethod<String>(
        'listMusicFilesInDirectory',
        <String, Object?>{
          'treeUri': treeUri,
          'relativeSubPath': relativeSubPath,
          'extensions': extensions ?? MusicFileUtils.supportedExtensionsWithoutDot,
        },
      );
      return result ?? const <String>[];
    } catch (e) {
      debugPrint('[AndroidSafStorageHelper] listMusicFilesRecursively error: $e');
      return const <String>[];
    }
  }
}

