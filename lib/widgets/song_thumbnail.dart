import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_service_providers.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/artwork_resolver.dart';
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
  final bool isAlbum;

  /// 图片源（文件路径 <-> 内存字节）切换时保留上一帧画面，避免出现空白帧。
  ///
  /// 列表中行被回收复用时同一位置的 State 会换成另一首歌，此时应保持 false，
  /// 否则会短暂显示上一首的封面；只有始终代表「同一张封面」的场景（迷你播放器）才置 true。
  final bool gaplessPlayback;

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
    this.isAlbum = false,
    this.gaplessPlayback = false,
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
    this.isAlbum = false,
    this.gaplessPlayback = false,
  })  : path = song.path,
        id = song.id,
        thumbnailPath = song.thumbnailPath,
        artworkPath = song.artworkPath,
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
    this.isAlbum = true,
    this.gaplessPlayback = false,
  })  : path = album.representativeSong.path,
        id = album.representativeSong.id,
        thumbnailPath = album.representativeSong.thumbnailPath,
        artworkPath = album.representativeSong.artworkPath,
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
    this.isAlbum = false,
    this.gaplessPlayback = false,
  })  : path = metadata.path,
        id = metadata.id,
        thumbnailPath = metadata.thumbnailPath,
        artworkPath = metadata.artworkPath,
        bytes = null;

  @override
  ConsumerState<SongThumbnail> createState() => _SongThumbnailState();
}

class _SongThumbnailState extends ConsumerState<SongThumbnail> {
  // Android/iOS/Desktop: cache artwork file paths so parent rebuilds don't retrigger fetch.
  String? _artworkFilePath;

  // Remote artwork URL state
  String? _remoteArtworkUrl;

  /// 本次重建是否仍代表同一首歌。
  ///
  /// 播放一首歌时后台会补写/重算封面（thumbnailPath、artworkWidth/Height、内存字节），
  /// 这些变化都会让图片源（FileImage / ResizeImage / MemoryImage）的 key 改变，
  /// 而 [Image] 在源变化 + 非 gapless 时会把 `_imageInfo` 清空，
  /// 于是首帧就是空白 —— 表现为「第一次播放某首歌时列表里那张封面闪一下」。
  /// 同一首歌重绘时保留上一帧；换成另一首歌必须立刻清空，
  /// 否则列表行回收复用会短暂显示上一首的封面。
  bool _keepLastFrame = true;

  static final Set<String> _failedRemoteUrls = <String>{};
  static final Set<String> _verifiedExistingPaths = <String>{};

  @override
  void initState() {
    super.initState();
    _checkOrQueryArtwork();
  }

  void _checkOrQueryArtwork() {
    // 快速路径：同步检查是否有有效缩略图路径
    final scanner = ref.read(scannerServiceProvider);
    final rawExisting = widget.thumbnailPath ??
        scanner.metadataMap[widget.path]?.thumbnailPath ??
        _artworkFilePath;
    final existingPath = rawExisting != null
        ? ScannerPathUtils.resolveIosSandboxPath(rawExisting)
        : null;
    if (existingPath != null && existingPath.isNotEmpty) {
      if (_verifiedExistingPaths.contains(existingPath) ||
          File(existingPath).existsSync()) {
        _verifiedExistingPaths.add(existingPath);
        if (_verifiedExistingPaths.length > 2000) {
          _verifiedExistingPaths.clear();
        }
        _artworkFilePath = existingPath;
        return;
      }
    }

    _queryArtworkAsync();
  }

  Future<void> _queryArtworkAsync() async {
    try {
      RemoteMediaResolver? remoteResolver;
      if (RemoteMediaResolver.isRemoteUri(widget.path)) {
        remoteResolver = await ref.read(remoteMediaResolverProvider.future);
      }
      final scanner = ref.read(scannerServiceProvider);
      final result = await ArtworkResolver.resolveForThumbnail(
        path: widget.path,
        id: widget.id,
        thumbnailPath: widget.thumbnailPath ??
            scanner.metadataMap[widget.path]?.thumbnailPath,
        artworkPath: widget.artworkPath,
        remoteResolver: remoteResolver,
        onThumbnailGenerated: (newThumb) {
          scanner.updateSongThumbnailPath(widget.path, newThumb);
        },
      );
      if (!mounted) return;
      if (result != null && result.isNotEmpty) {
        if (result.startsWith('http://') || result.startsWith('https://')) {
          setState(() {
            _remoteArtworkUrl = result;
          });
        } else {
          setState(() {
            _artworkFilePath = result;
          });
          scanner.updateSongThumbnailPath(widget.path, result);
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

  @override
  void didUpdateWidget(SongThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有还是同一首歌时才允许保留上一帧；换歌必须清空（列表行回收复用场景）。
    _keepLastFrame = oldWidget.path == widget.path;
    // Reset so we retry if the path/id/artworkPath changes (e.g. list recycling).
    if (oldWidget.path != widget.path ||
        oldWidget.id != widget.id ||
        oldWidget.artworkPath != widget.artworkPath ||
        oldWidget.thumbnailPath != widget.thumbnailPath) {
      _artworkFilePath = null;
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
    final bool gaplessPlayback = widget.gaplessPlayback || _keepLastFrame;

    if (widget.bytes != null && widget.bytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          widget.bytes!,
          width: layoutWidth,
          height: layoutHeight,
          fit: BoxFit.cover,
          cacheWidth: targetCacheWidth,
          cacheHeight: targetCacheHeight,
          gaplessPlayback: gaplessPlayback,
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
          gaplessPlayback: gaplessPlayback,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => _fallbackIcon(layoutWidth, layoutHeight, radius),
        ),
      );
    }

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
          gaplessPlayback: gaplessPlayback,
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
      child: widget.isAlbum
          ? DefaultCoverArt.album(borderRadius: radius)
          : DefaultCoverArt.song(borderRadius: radius),
    );
  }
}
