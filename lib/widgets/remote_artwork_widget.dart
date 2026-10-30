import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../player/remote/remote_server_models.dart';
import '../player/remote/clients/subsonic_client.dart';
import '../player/remote/clients/jellyfin_client.dart';
import 'artist_avatar.dart';
import 'artwork_fade.dart';

class RemoteArtworkWidget extends StatefulWidget {
  /// In-memory cache for resolved cover art URLs
  static final Map<String, String> _resolvedUrlCache = <String, String>{};

  /// Failure tracker with retry cooldown (avoids permanent blacklisting on scroll cancel/timeout)
  static final Map<String, int> _failedAttempts = <String, int>{};
  static final Map<String, DateTime> _failedTimestamps = <String, DateTime>{};

  /// Disk cache paths in memory
  static final Map<String, String> _diskFileCache = <String, String>{};
  static final Set<String> _activeDownloads = <String>{};
  static String? _thumbnailsDirPath;

  /// Method to clear cache if needed (e.g. on manual refresh)
  static void clearFailedCache() {
    _failedAttempts.clear();
    _failedTimestamps.clear();
    _resolvedUrlCache.clear();
  }

  final RemoteServer? server;
  final String? password;
  final String? coverArtId;
  final double size;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final bool isArtist;
  final IconData? fallbackIcon;

  const RemoteArtworkWidget({
    super.key,
    this.server,
    this.password,
    this.coverArtId,
    this.size = 50.0,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.isArtist = false,
    this.fallbackIcon,
  });

  @override
  State<RemoteArtworkWidget> createState() => _RemoteArtworkWidgetState();
}

class _RemoteArtworkWidgetState extends State<RemoteArtworkWidget> {
  String? _localDiskPath;

  /// 上一次渲染所用图片 URL，用于判断本次重建是否仍是同一张封面。
  ///
  /// 同一张封面在「网络图 → 磁盘图」之间切换时源（NetworkImage/FileImage）会变，
  /// 非 gapless 会让 Image 清空已解码的帧，于是先闪一下空白再出新图；
  /// 换成另一张封面（列表行复用）时必须立刻清空，否则会短暂显示上一张。
  String? _renderedImageUrl;

  @override
  void initState() {
    super.initState();
    _checkLocalDiskCache();
  }

  @override
  void didUpdateWidget(covariant RemoteArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverArtId != widget.coverArtId ||
        oldWidget.server?.id != widget.server?.id) {
      // 行被回收复用成另一个条目：先丢掉上一张的磁盘路径，
      // 否则 build 里的 existsSync 会让它继续顶着旧封面。
      _localDiskPath = null;
      _renderedImageUrl = null;
      _checkLocalDiskCache();
    }
  }

  String? _resolveImageUrl() {
    if (widget.server == null ||
        widget.password == null ||
        widget.coverArtId == null ||
        widget.coverArtId!.isEmpty ||
        (widget.server!.type != RemoteServerType.subsonic &&
            widget.server!.type != RemoteServerType.jellyfin)) {
      return null;
    }

    final cacheKey =
        '${widget.server!.id}_${widget.server!.type.name}_${widget.coverArtId}_${(widget.size * 2).toInt()}';
    var imageUrl = RemoteArtworkWidget._resolvedUrlCache[cacheKey];
    if (imageUrl == null) {
      imageUrl = widget.server!.type == RemoteServerType.jellyfin
          ? JellyfinClient(server: widget.server!, password: widget.password!)
              .buildCoverArtUrl(widget.coverArtId!, size: (widget.size * 2).toInt())
          : SubsonicClient(server: widget.server!, password: widget.password!)
              .buildCoverArtUrl(widget.coverArtId!, size: (widget.size * 2).toInt());
      if (RemoteArtworkWidget._resolvedUrlCache.length > 5000) {
        RemoteArtworkWidget._resolvedUrlCache.clear();
      }
      RemoteArtworkWidget._resolvedUrlCache[cacheKey] = imageUrl;
    }
    return imageUrl;
  }

  Future<void> _checkLocalDiskCache() async {
    final imageUrl = _resolveImageUrl();
    if (imageUrl == null) return;

    final diskKey = md5.convert(utf8.encode(imageUrl)).toString();
    final cachedPath = RemoteArtworkWidget._diskFileCache[diskKey];
    if (cachedPath != null && File(cachedPath).existsSync()) {
      // initState / didUpdateWidget 之后紧跟一次 build，直接赋值即可；
      // 在这里 setState 只会多排一帧，且首帧仍走不到磁盘分支。
      _localDiskPath = cachedPath;
      return;
    }

    // Try finding on disk
    try {
      if (RemoteArtworkWidget._thumbnailsDirPath == null) {
        final supportDir = await getApplicationSupportDirectory();
        final dir = Directory('${supportDir.path}/thumbnails');
        if (!dir.existsSync()) {
          await dir.create(recursive: true);
        }
        RemoteArtworkWidget._thumbnailsDirPath = dir.path;
      }

      final filePath =
          '${RemoteArtworkWidget._thumbnailsDirPath}/remote_$diskKey.jpg';
      if (File(filePath).existsSync()) {
        RemoteArtworkWidget._diskFileCache[diskKey] = filePath;
        // await 期间可能已经被复用到别的条目，URL 变了就不要把旧图塞进来。
        if (mounted && _resolveImageUrl() == imageUrl) {
          setState(() {
            _localDiskPath = filePath;
          });
        }
      }
    } catch (_) {}
  }

  void _triggerBackgroundDiskCache(String imageUrl) {
    final diskKey = md5.convert(utf8.encode(imageUrl)).toString();
    if (RemoteArtworkWidget._diskFileCache.containsKey(diskKey) ||
        RemoteArtworkWidget._activeDownloads.contains(diskKey)) {
      return;
    }

    RemoteArtworkWidget._activeDownloads.add(diskKey);
    Future(() async {
      try {
        if (RemoteArtworkWidget._thumbnailsDirPath == null) {
          final supportDir = await getApplicationSupportDirectory();
          final dir = Directory('${supportDir.path}/thumbnails');
          if (!dir.existsSync()) {
            await dir.create(recursive: true);
          }
          RemoteArtworkWidget._thumbnailsDirPath = dir.path;
        }

        final targetFile =
            File('${RemoteArtworkWidget._thumbnailsDirPath}/remote_$diskKey.jpg');
        if (targetFile.existsSync()) {
          RemoteArtworkWidget._diskFileCache[diskKey] = targetFile.path;
          return;
        }

        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        if (widget.server?.ignoreSsl == true) {
          client.badCertificateCallback = (cert, host, port) => true;
        }
        final request = await client.getUrl(Uri.parse(imageUrl));
        final response = await request.close().timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final bytes = await response.fold<List<int>>(
            <int>[],
            (acc, chunk) => acc..addAll(chunk),
          );
          if (bytes.isNotEmpty) {
            await targetFile.writeAsBytes(bytes);
            RemoteArtworkWidget._diskFileCache[diskKey] = targetFile.path;
            // 故意不在这里切到 Image.file：此刻网络图已经显示在用户眼前，
            // 换成 FileImage 会重新解码、中间空一帧，表现为「封面加载完又闪一下」。
            // 落盘只服务下次进入（内存 imageCache 未命中时），本次渲染维持现状。
          }
        }
      } catch (_) {
      } finally {
        RemoteArtworkWidget._activeDownloads.remove(diskKey);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width ?? widget.size;
    final h = widget.height ?? widget.size;
    final radius = widget.borderRadius ?? BorderRadius.circular(8);

    final imageUrl = _resolveImageUrl();
    // 仍是同一张封面（URL 未变）时保留上一帧，避免换图片源那一帧变空白；
    // 换成另一张封面时必须立刻清空，否则行复用会闪出上一张。
    final bool keepLastFrame = imageUrl != null && _renderedImageUrl == imageUrl;
    _renderedImageUrl = imageUrl;
    if (imageUrl == null) {
      return _buildFallback(context, w, h, radius);
    }

    // 1. If we have a local disk cache file, render directly from disk (0 network latency, never lost on scroll)
    if (_localDiskPath != null && File(_localDiskPath!).existsSync()) {
      final cacheW = (w.isFinite && w > 0)
          ? (w * 2).round()
          : (widget.size > 0 ? (widget.size * 2).round() : null);
      final cacheH = (h.isFinite && h > 0)
          ? (h * 2).round()
          : (widget.size > 0 ? (widget.size * 2).round() : null);
      return ClipRRect(
        borderRadius: radius,
        child: _withFallbackUnderlay(
          context: context,
          w: w,
          h: h,
          radius: radius,
          image: Image.file(
            File(_localDiskPath!),
            width: w,
            height: h,
            cacheWidth: (cacheW != null && cacheW > 0) ? cacheW : null,
            cacheHeight: (cacheH != null && cacheH > 0) ? cacheH : null,
            fit: widget.fit,
            gaplessPlayback: keepLastFrame,
            frameBuilder: artworkFadeInFrameBuilder,
            errorBuilder: (_, _, _) {
              // If local file was somehow deleted/corrupted, fall back to network
              return _buildNetworkImage(
                context,
                imageUrl,
                w,
                h,
                radius,
                keepLastFrame: keepLastFrame,
              );
            },
          ),
        ),
      );
    }

    return _buildNetworkImage(
      context,
      imageUrl,
      w,
      h,
      radius,
      keepLastFrame: keepLastFrame,
    );
  }

  Widget _buildNetworkImage(
    BuildContext context,
    String imageUrl,
    double w,
    double h,
    BorderRadius radius, {
    bool keepLastFrame = false,
  }) {
    // 2. Check retry cooldown (instead of permanent blacklisting)
    final attempts = RemoteArtworkWidget._failedAttempts[imageUrl] ?? 0;
    final lastFailed = RemoteArtworkWidget._failedTimestamps[imageUrl];
    if (attempts >= 3 && lastFailed != null) {
      if (DateTime.now().difference(lastFailed) < const Duration(seconds: 15)) {
        return _buildFallback(context, w, h, radius);
      } else {
        // Cooldown expired, clear and allow retry
        RemoteArtworkWidget._failedAttempts.remove(imageUrl);
        RemoteArtworkWidget._failedTimestamps.remove(imageUrl);
      }
    }

    final cacheW = (w.isFinite && w > 0)
        ? (w * 2).round()
        : (widget.size > 0 ? (widget.size * 2).round() : null);
    final cacheH = (h.isFinite && h > 0)
        ? (h * 2).round()
        : (widget.size > 0 ? (widget.size * 2).round() : null);

    return ClipRRect(
      borderRadius: radius,
      child: _withFallbackUnderlay(
        context: context,
        w: w,
        h: h,
        radius: radius,
        image: Image.network(
          imageUrl,
          width: w,
          height: h,
          cacheWidth: (cacheW != null && cacheW > 0) ? cacheW : null,
          cacheHeight: (cacheH != null && cacheH > 0) ? cacheH : null,
          fit: widget.fit,
          gaplessPlayback: keepLastFrame,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              // Trigger disk caching once image successfully loads
              _triggerBackgroundDiskCache(imageUrl);
            }
            return artworkFadeInFrameBuilder(
              context,
              child,
              frame,
              wasSynchronouslyLoaded,
            );
          },
          errorBuilder: (_, _, _) {
            // 占位已经垫在底下，这里不再重复画一遍；只记账，冷却结束后重试。
            final count = (RemoteArtworkWidget._failedAttempts[imageUrl] ?? 0) + 1;
            RemoteArtworkWidget._failedAttempts[imageUrl] = count;
            RemoteArtworkWidget._failedTimestamps[imageUrl] = DateTime.now();
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  /// 把默认占位垫在封面底下，封面解出首帧后淡入盖上去。
  ///
  /// 远程封面走网络，等待时间比本地缩略图长得多，所以这里不能用「空白 → 淡入」
  /// 那条路径，否则每个格子都要先空一截。占位垫底既保证不闪空框，
  /// 又不影响淡入节奏 —— 与 [SongThumbnail] 用的是同一个 [kArtworkFadeInDuration]。
  Widget _withFallbackUnderlay({
    required BuildContext context,
    required double w,
    required double h,
    required BorderRadius radius,
    required Widget image,
  }) {
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        _buildFallback(context, w, h, radius),
        image,
      ],
    );
  }

  Widget _buildFallback(
    BuildContext context,
    double w,
    double h,
    BorderRadius radius,
  ) {
    final theme = Theme.of(context);
    final minSide = math.min(w, h);
    final effectiveMinSide = minSide.isFinite && minSide > 0 ? minSide : 48.0;

    if (widget.isArtist && widget.fallbackIcon == null) {
      return ArtistPlaceholder(
        width: w,
        height: h,
        borderRadius: radius,
        shape: widget.borderRadius != null
            ? BoxShape.rectangle
            : BoxShape.circle,
      );
    }

    final icon = widget.fallbackIcon ??
        (widget.isArtist ? Icons.mic_rounded : Icons.music_note_rounded);
    final bgColor = widget.isArtist
        ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.7)
        : theme.colorScheme.primary.withValues(alpha: 0.1);
    final iconColor = widget.isArtist
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.primary.withValues(alpha: 0.7);

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: radius,
      ),
      child: Center(
        child: Icon(
          icon,
          color: iconColor,
          size: (effectiveMinSide * 0.5).clamp(16.0, 48.0),
        ),
      ),
    );
  }
}
