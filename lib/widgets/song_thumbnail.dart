import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:audio_core/audio_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/utils/memory_trace.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_service_providers.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'default_cover_art.dart';

class SongThumbnail extends ConsumerStatefulWidget {
  final String path;
  final int? id;
  final String? thumbnailPath;
  final String? artworkPath;
  final Uint8List? bytes;
  final double size;
  final double? width;
  final double? height;

  final BorderRadius? borderRadius;
  final Widget? fallbackWidget;

  const SongThumbnail({
    super.key,
    required this.path,
    this.id,
    this.thumbnailPath,
    this.artworkPath,
    this.bytes,
    this.size = 40.0,
    this.width,
    this.height,
    this.borderRadius,
    this.fallbackWidget,
  });

  /// Factory constructor for a [MusicFile].
  SongThumbnail.fromSong(
    MusicFile song, {
    super.key,
    this.size = 40.0,
    this.width,
    this.height,
    this.borderRadius,
    this.fallbackWidget,
  })  : path = ScannerPathUtils.resolveIosSandboxPath(song.path),
        id = song.id,
        thumbnailPath = song.thumbnailPath != null
            ? ScannerPathUtils.resolveIosSandboxPath(song.thumbnailPath!)
            : null,
        artworkPath = song.artworkPath != null
            ? ScannerPathUtils.resolveIosSandboxPath(song.artworkPath!)
            : null,
        bytes = song.artworkBytes;

  /// Factory constructor for an [AlbumSummary].
  SongThumbnail.fromAlbum(
    AlbumSummary album, {
    super.key,
    this.size = 40.0,
    this.width,
    this.height,
    this.borderRadius,
    this.fallbackWidget,
  })  : path = ScannerPathUtils.resolveIosSandboxPath(album.representativeSong.path),
        id = album.representativeSong.id,
        thumbnailPath = album.representativeSong.thumbnailPath != null
            ? ScannerPathUtils.resolveIosSandboxPath(album.representativeSong.thumbnailPath!)
            : null,
        artworkPath = album.representativeSong.artworkPath != null
            ? ScannerPathUtils.resolveIosSandboxPath(album.representativeSong.artworkPath!)
            : null,
        bytes = album.representativeSong.artworkBytes;

  /// Factory constructor for a [SongMetadata] database record.
  SongThumbnail.fromMetadata(
    SongMetadata metadata, {
    super.key,
    this.size = 40.0,
    this.width,
    this.height,
    this.borderRadius,
    this.fallbackWidget,
  })  : path = ScannerPathUtils.resolveIosSandboxPath(metadata.path),
        id = metadata.id,
        thumbnailPath = metadata.thumbnailPath != null
            ? ScannerPathUtils.resolveIosSandboxPath(metadata.thumbnailPath!)
            : null,
        artworkPath = metadata.artworkPath != null
            ? ScannerPathUtils.resolveIosSandboxPath(metadata.artworkPath!)
            : null,
        bytes = null;

  @override
  ConsumerState<SongThumbnail> createState() => _SongThumbnailState();
}

class _SongThumbnailState extends ConsumerState<SongThumbnail> {
  bool _loadTriggered = false;

  // Android/iOS: cache artwork file paths so parent rebuilds don't retrigger fetch.
  String? _artworkFilePath;
  bool _artworkQueried = false;

  // Remote artwork URL state
  String? _remoteArtworkUrl;

  static final LinkedHashMap<String, String> _artworkCache = LinkedHashMap<String, String>();
  static final LinkedHashMap<String, String> _remoteUrlCache = LinkedHashMap<String, String>();
  static final LinkedHashMap<String, String> _remoteThumbnailCache = LinkedHashMap<String, String>();
  static final Set<String> _failedRemoteUrls = <String>{};
  static final Set<String> _verifiedExistingPaths = <String>{};

  @override
  void initState() {
    super.initState();
    _checkOrQueryArtwork();
  }

  void _checkOrQueryArtwork() {
    if (RemoteMediaResolver.isRemoteUri(widget.path)) {
      final existingPath = widget.thumbnailPath ??
          ref.read(scannerServiceProvider).metadataMap[widget.path]?.thumbnailPath ??
          _artworkFilePath;
      if (existingPath != null && existingPath.isNotEmpty) {
        if (_verifiedExistingPaths.contains(existingPath) || File(existingPath).existsSync()) {
          _verifiedExistingPaths.add(existingPath);
          _artworkFilePath = existingPath;
          _artworkQueried = true;
          return;
        }
      }
      if (_remoteThumbnailCache.containsKey(widget.path)) {
        final cached = _remoteThumbnailCache[widget.path];
        if (cached != null && cached.isNotEmpty) {
          if (_verifiedExistingPaths.contains(cached) || File(cached).existsSync()) {
            _verifiedExistingPaths.add(cached);
            _artworkFilePath = cached;
            _artworkQueried = true;
            return;
          }
        }
      }

      _queryRemoteSongThumbnailFromDb();

      final cacheKey = '${widget.path}_${widget.artworkPath ?? ''}';
      if (_remoteUrlCache.containsKey(cacheKey)) {
        _remoteArtworkUrl = _remoteUrlCache[cacheKey];
      } else {
        _queryRemoteArtwork(cacheKey);
      }
      return;
    }

    final scanner = ref.read(scannerServiceProvider);
    final rawExisting = widget.thumbnailPath ??
        scanner.metadataMap[widget.path]?.thumbnailPath ??
        _artworkFilePath;
    final existingPath = rawExisting != null
        ? ScannerPathUtils.resolveIosSandboxPath(rawExisting)
        : null;
    if (existingPath != null && existingPath.isNotEmpty) {
      if (_verifiedExistingPaths.contains(existingPath) || File(existingPath).existsSync()) {
        _verifiedExistingPaths.add(existingPath);
        if (_verifiedExistingPaths.length > 2000) {
          _verifiedExistingPaths.clear();
        }
        _artworkFilePath = existingPath;
        _artworkQueried = true;
        return;
      }
    }
    if (Platform.isAndroid && widget.id != null) {
      final cacheKey = '${widget.id}_$_bucketedSize';
      if (_artworkCache.containsKey(cacheKey)) {
        final cachedPath = _artworkCache[cacheKey];
        _artworkFilePath = cachedPath;
        _artworkQueried = true;
        if (cachedPath != null && cachedPath.isNotEmpty) {
          scanner.updateSongThumbnailPath(widget.path, cachedPath);
        }
      } else {
        _queryArtwork(widget.id!);
      }
    } else {
      _triggerLoad();
    }
  }

  Future<void> _queryRemoteArtwork(String cacheKey) async {
    try {
      final resolver = await ref.read(remoteMediaResolverProvider.future);
      final url = await resolver.getArtworkUrlFromUri(
        widget.path,
        coverArtId: widget.artworkPath,
        size: (_bucketedSize * 2).toInt(),
      );
      if (url != null && url.isNotEmpty) {
        _remoteUrlCache[cacheKey] = url;
        if (_remoteUrlCache.length > 500) {
          _remoteUrlCache.remove(_remoteUrlCache.keys.first);
        }
      }
      if (mounted) {
        setState(() {
          _remoteArtworkUrl = url;
        });
      }
    } catch (_) {}
  }

  Future<void> _queryRemoteSongThumbnailFromDb() async {
    try {
      final db = MetadataDatabase();
      final songMeta = await db.getSongMetadata(widget.path);
      final thumbPath = songMeta?.thumbnailPath;
      if (thumbPath != null && thumbPath.isNotEmpty) {
        if (File(thumbPath).existsSync()) {
          _remoteThumbnailCache[widget.path] = thumbPath;
          if (_remoteThumbnailCache.length > 1000) {
            _remoteThumbnailCache.remove(_remoteThumbnailCache.keys.first);
          }
          if (mounted) {
            setState(() {
              _artworkFilePath = thumbPath;
              _artworkQueried = true;
            });
          }
        }
      }
    } catch (_) {}
  }

  double get _bucketedSize {
    if (widget.size <= 60.0) {
      return 60.0;
    } else if (widget.size <= 120.0) {
      return 120.0;
    } else if (widget.size <= 250.0) {
      return 250.0;
    } else {
      return 400.0;
    }
  }

  Future<void> _queryArtwork(int id) async {
    final scanner = ref.read(scannerServiceProvider);
    
    // Check if the song is from system MediaStore
    final metadata = scanner.metadataMap[widget.path];
    final isSystemMedia = (metadata != null && ((metadata.sourceFlags ?? 0) & SongSourceFlags.systemMedia) != 0) || widget.path.startsWith('content://');
    if (!isSystemMedia) {
      debugPrint('[SongThumbnail] Skip queryArtwork: not a system media song for path=${widget.path}');
      if (mounted) {
        setState(() {
          _artworkQueried = true;
        });
        _triggerLoad();
      }
      return;
    }

    // Check system permission on Android
    if (Platform.isAndroid && !scanner.hasPermission) {
      debugPrint('[SongThumbnail] Skip queryArtwork: no system permission for path=${widget.path}');
      if (mounted) {
        setState(() {
          _artworkQueried = true;
        });
        _triggerLoad();
      }
      return;
    }

    try {
      final double dpr = WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ?? 2.0;
      final int targetSize = (_bucketedSize * dpr).round();
      final bytes = await MetadataHelper.safeQueryArtwork(
        id,
        size: targetSize > 200 ? targetSize : 200,
        hasPermission: scanner.hasPermission,
      );
      String? savedPath;
      if (bytes != null && bytes.isNotEmpty) {
        final md5Hex = await calculateMd5(bytes: bytes);
        final supportDir = await getApplicationSupportDirectory();
        final thumbnailsDir = Directory('${supportDir.path}/thumbnails');
        if (!thumbnailsDir.existsSync()) {
          await thumbnailsDir.create(recursive: true);
        }
        final file = File('${thumbnailsDir.path}/${md5Hex}_thumb.jpg');
        if (!file.existsSync()) {
          await file.writeAsBytes(bytes);
        }
        savedPath = file.path;

        final db = MetadataDatabase();
        final record = ArtworkCacheRecord(
          md5: md5Hex,
          thumbnailPath: savedPath,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        );
        await db.insertOrUpdateArtworkCache(record);

        final cacheKey = '${id}_$_bucketedSize';
        _artworkCache[cacheKey] = savedPath;
        if (_artworkCache.length > 500) {
          _artworkCache.remove(_artworkCache.keys.first);
        }
        MemoryTrace.snapshot(
          'songThumbnail:queryArtwork',
          details: <String, Object?>{
            'id': id,
            'bucket': _bucketedSize,
            'path': savedPath,
            'cache': _artworkCache.length,
          },
        );

        if (savedPath.isNotEmpty) {
          scanner.updateSongThumbnailPath(widget.path, savedPath);
        }
      }
      if (mounted) {
        setState(() {
          _artworkFilePath = savedPath;
          _artworkQueried = true;
        });
        if (savedPath == null) {
          _triggerLoad();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _artworkQueried = true;
        });
        _triggerLoad();
      }
    }
  }

  void _triggerLoad() {
    if (_loadTriggered) return;
    // Run after the current frame so we don't call setState during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final scanner = ref.read(scannerServiceProvider);
        _loadTriggered = true;
        scanner.loadThumbnailForPath(widget.path);
      }
    });
  }

  @override
  void didUpdateWidget(SongThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset so we retry if the path/id/artworkPath changes (e.g. list recycling).
    if (oldWidget.path != widget.path ||
        oldWidget.id != widget.id ||
        oldWidget.artworkPath != widget.artworkPath ||
        oldWidget.thumbnailPath != widget.thumbnailPath) {
      _loadTriggered = false;
      _artworkFilePath = null;
      _artworkQueried = false;
      _remoteArtworkUrl = null;
      _checkOrQueryArtwork();
    }
  }

  @override
  Widget build(BuildContext context) {
    final metadata = ref.watch(
      scannerServiceProvider.select(
        (scanner) => scanner.metadataMap[widget.path],
      ),
    );
    final rawImagePath = (widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty)
        ? widget.thumbnailPath
        : (_artworkFilePath != null && _artworkFilePath!.isNotEmpty)
            ? _artworkFilePath
            : (_remoteThumbnailCache[widget.path]?.isNotEmpty ?? false)
                ? _remoteThumbnailCache[widget.path]
                : metadata?.thumbnailPath;
    final resolvedImagePath = rawImagePath != null
        ? ScannerPathUtils.resolveIosSandboxPath(rawImagePath)
        : null;
    final imagePath = (resolvedImagePath != null && resolvedImagePath.isNotEmpty)
        ? resolvedImagePath
        : null;

    final double dpr = MediaQuery.of(context).devicePixelRatio;
    final double adjustedSize = (widget.size * dpr).round() / dpr;
    final double layoutWidth = widget.width ?? adjustedSize;
    final double layoutHeight = widget.height ?? adjustedSize;
    final int cachePixels = (_bucketedSize * dpr).round();

    final artWidth = metadata?.artworkWidth;
    final artHeight = metadata?.artworkHeight;
    final int? targetCacheWidth;
    final int? targetCacheHeight;
    if (artWidth != null && artHeight != null && artWidth > 0 && artHeight > 0) {
      if (artWidth >= artHeight) {
        targetCacheWidth = null;
        targetCacheHeight = cachePixels;
      } else {
        targetCacheWidth = cachePixels;
        targetCacheHeight = null;
      }
    } else {
      targetCacheWidth = cachePixels;
      targetCacheHeight = null;
    }

    final radius = widget.borderRadius ?? BorderRadius.circular(4);

    if (widget.bytes != null && widget.bytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          widget.bytes!,
          width: layoutWidth,
          height: layoutHeight,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallbackIcon(layoutWidth, layoutHeight, radius),
        ),
      );
    }

    if (imagePath != null) {
      final file = File(imagePath);
      return ClipRRect(
        borderRadius: radius,
        child: Image.file(
          file,
          width: layoutWidth,
          height: layoutHeight,
          fit: BoxFit.cover,
          cacheWidth: targetCacheWidth,
          cacheHeight: targetCacheHeight,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => _fallbackIcon(layoutWidth, layoutHeight, radius),
        ),
      );
    }

    if (RemoteMediaResolver.isRemoteUri(widget.path)) {
      if (_remoteArtworkUrl != null &&
          _remoteArtworkUrl!.isNotEmpty &&
          !_failedRemoteUrls.contains(_remoteArtworkUrl!)) {
        return ClipRRect(
          borderRadius: radius,
          child: Image.network(
            _remoteArtworkUrl!,
            width: layoutWidth,
            height: layoutHeight,
            fit: BoxFit.cover,
            cacheWidth: targetCacheWidth,
            cacheHeight: targetCacheHeight,
            filterQuality: FilterQuality.low,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                return child;
              }
              return _fallbackIcon(layoutWidth, layoutHeight, radius);
            },
            errorBuilder: (_, _, _) {
              if (_remoteArtworkUrl != null) {
                _failedRemoteUrls.add(_remoteArtworkUrl!);
              }
              return _fallbackIcon(layoutWidth, layoutHeight, radius);
            },
          ),
        );
      }
      return _fallbackIcon(layoutWidth, layoutHeight, radius);
    }

    if (Platform.isAndroid || Platform.isIOS) {
      if (_artworkQueried && _artworkFilePath != null) {
        return ClipRRect(
          borderRadius: radius,
          child: Image.file(
            File(_artworkFilePath!),
            width: layoutWidth,
            height: layoutHeight,
            fit: BoxFit.cover,
            cacheWidth: targetCacheWidth,
            cacheHeight: targetCacheHeight,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => _fallbackIcon(layoutWidth, layoutHeight, radius),
          ),
        );
      }
      if (widget.id == null) {
        _triggerLoad();
      }
      // Still fetching or no artwork — show fallback without flickering.
      return _fallbackIcon(layoutWidth, layoutHeight, radius);
    } else if (metadata == null || metadata.thumbnailPath == null) {
      _triggerLoad();
    }

    return _fallbackIcon(layoutWidth, layoutHeight, radius);
  }

  Widget _fallbackIcon(double width, double height, BorderRadius radius) {
    if (widget.fallbackWidget != null) {
      return SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: radius,
          child: widget.fallbackWidget!,
        ),
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: DefaultCoverArt.song(
        borderRadius: radius,
      ),
    );
  }
}
