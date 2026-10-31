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
import 'artwork_fade.dart';
import 'default_cover_art.dart';

/// 网格条目封面解码尺寸的**兜底值**（dp）。
///
/// 条目侧的真实取值为 `zoomItemThumbnailSizeFor(metrics)`（见
/// `folder_layout_utils.dart`）：网格态的封面边长等于网格卡片宽度，而横屏列数
/// 固定 6/7/8 列、与窗口宽度无关，桌面端卡片会被撑到 180~270dp，按 120 解码
/// 只会得到被放大近两倍的糊图。
///
/// 这里只剩两个用途：不带缩放度量的横幅页兜底，以及 `thumbnailBucketSizeFor`
/// 分桶时的最小档参考。
const double kZoomItemThumbnailSize = 120.0;

/// 缩略图解码尺寸分桶。
///
/// 同一个桶内的请求共用一份 [ResizeImage] key，也就共用 [ImageCache] 里同一条
/// 已解码纹理。**任何想「复用列表/网格已经解码好那张图」的地方都必须走这个函数**，
/// 自己写 `cacheWidth` 会算出一个新 key，命中不了缓存，白解一遍。
double thumbnailBucketSizeFor(double size) {
  if (size <= 60.0) {
    return 60.0;
  } else if (size <= 120.0) {
    return 120.0;
  } else if (size <= 250.0) {
    return 250.0;
  }
  return 400.0;
}

/// 歌曲 / 专辑 / 文件夹的封面缩略图。
///
/// 淡入策略由组件自己统一决定，不提供开关：只要缩略图还没就位（没解析出来、
/// 或解析出来了但还没解码出首帧），该区域保持空白；就位那一刻按
/// [kArtworkFadeInDuration] 淡入。
///
/// 唯一的例外是**解析结果确认没有封面**：此时落定的就是默认图标，它不再套
/// [kArtworkFadeInDuration]，直接以 1.0 呈现。默认图标自己再排一段淡入的话，
/// 它和外层档位过渡的不透明度是两条时钟，会明显晚一拍（详见 [_SongThumbnailState._needsFadeIn]）。
/// 所有调用方（歌曲行、文件夹条目、专辑卡片、播放列表封面……）行为一致。
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

  /// 本次挂载或更新是否需要淡入展示。
  ///
  /// - 命中已有本地缓存（已有缩略图文件/内存字节）：false，首帧直接展示，不套淡入；
  /// - 尚未生成缩略图（等待动画结束或后台生成完毕）：true，就位时由外层统一平滑淡入；
  /// - 解析落定为「没有封面」（结果是默认图标）：false。默认图标不该有自己的淡入时钟，
  ///   否则换档过渡时它会比有封面的条目晚一整段 [kArtworkFadeInDuration]。
  bool _needsFadeIn = false;

  /// 异步解析（查找 / 生成缩略图）是否仍在进行。
  ///
  /// 为 true 且手上还没有任何图片源时，缩略图区保持空白；结果落定后再统一淡入，
  /// 此时露出的可能是新生成的封面，也可能是默认图标。
  bool _isGenerating = false;

  static final Set<String> _failedRemoteUrls = <String>{};
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _checkOrQueryArtwork(fromInitState: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 若初次挂载时需要异步慢解析，挂接到当前路由转场动画监听
    if (_artworkFilePath == null && _remoteArtworkUrl == null && widget.bytes == null) {
      _scheduleQueryArtwork();
    }
  }

  void _checkOrQueryArtwork({bool fromInitState = false}) {
    // 快速路径：直接复用已知缩略图路径，不在 UI 线程同步调用 File.existsSync()
    final scanner = ref.read(scannerServiceProvider);
    final rawExisting = widget.thumbnailPath ??
        scanner.metadataMap[widget.path]?.thumbnailPath ??
        _artworkFilePath;
    final existingPath = rawExisting != null
        ? ScannerPathUtils.resolveIosSandboxPath(rawExisting)
        : null;
    if (existingPath != null && existingPath.isNotEmpty) {
      _artworkFilePath = existingPath;
      _isGenerating = false;
      if (fromInitState) {
        _needsFadeIn = false;
      }
      return;
    }

    if (widget.bytes != null && widget.bytes!.isNotEmpty) {
      _isGenerating = false;
      if (fromInitState) {
        _needsFadeIn = false;
      }
      return;
    }

    _isGenerating = true;
    _needsFadeIn = true;
    if (!fromInitState) {
      _scheduleQueryArtwork();
    }
  }

  void _scheduleQueryArtwork() {
    if (!mounted) return;
    final routeAnimation = ModalRoute.of(context)?.animation;
    if (routeAnimation != null && !routeAnimation.isCompleted) {
      _cleanupRouteAnimation();
      _routeAnimation = routeAnimation;
      routeAnimation.addStatusListener(_handleRouteAnimationStatus);
      return;
    }
    _queryArtworkAsync();
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _cleanupRouteAnimation();
      if (mounted && _artworkFilePath == null && _remoteArtworkUrl == null && widget.bytes == null) {
        _queryArtworkAsync();
      }
    }
  }

  void _cleanupRouteAnimation() {
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _routeAnimation = null;
  }

  @override
  void dispose() {
    _cleanupRouteAnimation();
    super.dispose();
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
            _isGenerating = false;
          });
        } else {
          setState(() {
            _artworkFilePath = result;
            _isGenerating = false;
          });
          scanner.updateSongThumbnailPath(widget.path, result);
        }
      } else {
        setState(() {
          _isGenerating = false;
          // 解析确认「没有封面」时，落定的就是默认图标本身，不需要再为它单独排一段
          // 淡入：那 280ms 与条目级的不透明度（换档过渡的 `Opacity(transition.opacity)`）
          // 是两条时钟，会让默认图标条目比有封面的条目明显晚一拍。
          // 这里直接置 1.0：换档尚未结束时它跟着条目那条曲线一起淡入，已经结束则立即显示。
          _needsFadeIn = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          // 解析异常同样落定为默认图标，理由同上。
          _needsFadeIn = false;
        });
      }
    }
  }

  double get _bucketedSize => thumbnailBucketSizeFor(widget.size);

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
      final isSameSong = oldWidget.path == widget.path;
      if (!isSameSong) {
        _artworkFilePath = null;
        _remoteArtworkUrl = null;
        _isGenerating = false;
        _needsFadeIn = false;
        _checkOrQueryArtwork(fromInitState: true);
      } else {
        final hadCover = _artworkFilePath != null || widget.bytes != null;
        _checkOrQueryArtwork();
        final nowHasCover = _artworkFilePath != null || widget.bytes != null;
        if (!hadCover && nowHasCover) {
          _needsFadeIn = true;
        }
      }
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

    final bool hasValidRemoteUrl = _remoteArtworkUrl != null &&
        _remoteArtworkUrl!.isNotEmpty &&
        !_failedRemoteUrls.contains(_remoteArtworkUrl!);
    final bool hasBytes = widget.bytes != null && widget.bytes!.isNotEmpty;
    final bool hasImage = imagePath != null;

    final bool hasSource = hasBytes || hasImage || hasValidRemoteUrl;
    if (hasSource && _isGenerating) {
      _isGenerating = false;
    }

    // 解析（查找/生成）还没结束、手上也没有任何图片源：缩略图区保持空白，
    // 等结果落定后再统一淡入 —— 落定的结果可能是封面，也可能是默认图标。
    // 首批已有本地缓存的条目挂载即就绪，直接展示无需淡入。
    final bool isPending = _isGenerating && !hasSource;

    final bool shouldFadeIn = _needsFadeIn && !isPending;

    final Widget content;
    if (isPending) {
      content = SizedBox(
        width: layoutWidth,
        height: layoutHeight,
      );
    } else if (hasBytes) {
      content = ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          widget.bytes!,
          width: layoutWidth,
          height: layoutHeight,
          fit: BoxFit.cover,
          cacheWidth: targetCacheWidth,
          cacheHeight: targetCacheHeight,
          gaplessPlayback: gaplessPlayback,
          frameBuilder: _holdLastFrame,
          errorBuilder: (_, _, _) => _fallbackIcon(layoutWidth, layoutHeight, radius),
        ),
      );
    } else if (hasImage) {
      final file = File(imagePath);
      content = ClipRRect(
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
          frameBuilder: _holdLastFrame,
          errorBuilder: (_, _, _) {
            if (_artworkFilePath != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _artworkFilePath != null) {
                  setState(() {
                    _artworkFilePath = null;
                    _isGenerating = true;
                    _needsFadeIn = true;
                  });
                  _scheduleQueryArtwork();
                }
              });
            }
            return _fallbackIcon(layoutWidth, layoutHeight, radius);
          },
        ),
      );
    } else if (hasValidRemoteUrl) {
      content = ClipRRect(
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
          frameBuilder: _holdLastFrame,
          errorBuilder: (_, _, _) {
            if (_remoteArtworkUrl != null) {
              _failedRemoteUrls.add(_remoteArtworkUrl!);
            }
            return _fallbackIcon(layoutWidth, layoutHeight, radius);
          },
        ),
      );
    } else {
      content = _fallbackIcon(layoutWidth, layoutHeight, radius);
    }

    // 由外层这唯一一层 AnimatedOpacity 统一管理淡入：
    // - 首批已有缓存条目：duration 为 zero，首帧直接展示，不套淡入层；
    // - 慢路径新生成完毕：以 kArtworkFadeInDuration 平滑淡入；
    // - 解析确认没有封面（落定默认图标）：duration 为 zero，图标直接呈现；
    // - 已经展示着封面的重建（列表滚动、播放状态变化）：duration 为 zero，不重复淡入。
    return AnimatedOpacity(
      opacity: isPending ? 0.0 : 1.0,
      duration: shouldFadeIn ? kArtworkFadeInDuration : Duration.zero,
      curve: Curves.easeOutCubic,
      onEnd: () {
        _needsFadeIn = false;
      },
      child: content,
    );
  }

  /// 已经有画面在显示时的 frameBuilder：原样返回，交给 [Image] 按
  /// gaplessPlayback 决定保留上一帧还是清空。
  static Widget _holdLastFrame(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    return child;
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
