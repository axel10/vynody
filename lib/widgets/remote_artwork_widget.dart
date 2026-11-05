import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show Codec, ImmutableBuffer;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show
        DiagnosticsNode,
        DiagnosticsProperty,
        SynchronousFuture,
        visibleForTesting;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../player/remote/remote_server_models.dart';
import '../player/remote/clients/subsonic_client.dart';
import '../player/remote/clients/jellyfin_client.dart';
import 'artist_avatar.dart';
import 'artwork_fade.dart';

/// 一次解析得到的封面源信息。
///
/// [url] 供 `Image` 使用，[diskKey] 用于磁盘缓存与「已显示过」登记，
/// [tier] 同时决定「向服务器请求的尺寸」与「解码尺寸」，三者同源，
/// 避免 widget.size 连续抖动时产生多条 URL / 多个 ResizeImage key。
class _ArtworkSource {
  const _ArtworkSource({
    required this.url,
    required this.diskKey,
    required this.tier,
  });

  final String url;
  final String diskKey;
  final int tier;
}

/// A1：与 `Image.network` 同一条路径的网络图片源（由 `Image` widget 驱动，
/// 仍走 `ResizeImage` / `imageCache` / `frameBuilder` / `gaplessPlayback`，
/// **不是** `Image.memory`）。
///
/// Flutter 自带的 `NetworkImage` 不暴露已下载的字节，旧实现为了落盘只能
/// 另开一个 `HttpClient` 把同一张图再下一遍。这里让一次下载同时服务
/// 「解码显示」与「写磁盘」：请求数严格为 1，且磁盘缓存命中时直接读本地
/// 字节解码，完全不发网络请求。
class _CachingRemoteImage extends ImageProvider<_CachingRemoteImage> {
  const _CachingRemoteImage({
    required this.url,
    required this.diskKey,
    this.ignoreSsl = false,
  });

  final String url;
  final String diskKey;
  final bool ignoreSsl;

  @override
  Future<_CachingRemoteImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_CachingRemoteImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _CachingRemoteImage key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode, chunkEvents),
      chunkEvents: chunkEvents.stream,
      scale: 1.0,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('diskKey', key.diskKey),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    _CachingRemoteImage key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    try {
      // 磁盘缓存是纯加速：读不到 / path_provider 不可用都直接落回网络，
      // 不能因为缓存异常把封面显示搞挂。
      final diskBytes = await RemoteArtworkWidget._readDiskBytes(key.diskKey);
      if (diskBytes != null && diskBytes.isNotEmpty) {
        return decode(await ui.ImmutableBuffer.fromUint8List(diskBytes));
      }

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      if (key.ignoreSsl) {
        client.badCertificateCallback = (_, _, _) => true;
      }
      try {
        final uri = Uri.parse(key.url);
        final request = await client.getUrl(uri);
        final response =
            await request.close().timeout(const Duration(seconds: 15));
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<List<int>>(<int>[]);
          throw NetworkImageLoadException(
            statusCode: response.statusCode,
            uri: uri,
          );
        }

        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
          if (!chunkEvents.isClosed) {
            chunkEvents.add(ImageChunkEvent(
              cumulativeBytesLoaded: builder.length,
              expectedTotalBytes: null,
            ));
          }
        }
        final bytes = builder.takeBytes();
        if (bytes.isEmpty) {
          throw Exception('RemoteArtworkWidget: empty image for ${key.url}');
        }
        RemoteArtworkWidget.debugNetworkRequests++;
        // 同一次响应的字节拿去落盘，不阻塞解码；下次冷启动 / imageCache
        // 未命中时由上面的分支直接读盘。
        unawaited(RemoteArtworkWidget._writeDiskBytes(key.diskKey, bytes));
        return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      } finally {
        client.close(force: true);
      }
    } finally {
      unawaited(chunkEvents.close());
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _CachingRemoteImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

class RemoteArtworkWidget extends StatefulWidget {
  /// 解析后的封面源（含稳定尺寸档位），key 不含 token / 密码。
  static final Map<String, _ArtworkSource> _sourceCache =
      <String, _ArtworkSource>{};

  /// 失败次数与冷却起点，避免滑动取消 / 超时后永久黑图。
  static final Map<String, int> _failedAttempts = <String, int>{};
  static final Map<String, DateTime> _failedTimestamps = <String, DateTime>{};

  /// 进程内「这张封面已经成功显示过至少一帧」。
  ///
  /// 列表条目滚出视口会被回收，滚回来是全新 State。命中这个集合就说明
  /// 不该再重播「默认图标 → 280ms 淡入」：与 `SongThumbnail` 的
  /// `peekCachedThumbnail` + `_needsFadeIn` 是同一套语义。
  static final Set<String> _everDisplayed = <String>{};

  static String? _thumbnailsDirPath;

  /// 仅供测试：覆盖磁盘缓存目录（避免依赖 path_provider 平台通道）。
  @visibleForTesting
  static String? debugThumbnailsDir;

  /// 仅供测试：真正发出网络请求的次数（命中磁盘缓存时不增加）。
  @visibleForTesting
  static int debugNetworkRequests = 0;

  /// 仅供测试：预置磁盘缓存字节。
  @visibleForTesting
  static Future<void> debugSeedDiskCache(
    String diskKey,
    Uint8List bytes,
  ) async {
    final dir = await _thumbnailsDir();
    if (dir == null) return;
    await File('$dir/remote_$diskKey.bin').writeAsBytes(bytes);
  }

  /// 仅供测试：算出与生产代码同源的磁盘 key。
  @visibleForTesting
  static String diskKeyFor({
    required String serverId,
    required String serverType,
    required String coverArtId,
    required double size,
  }) {
    final tier = _sizeTierFor(size);
    return md5
        .convert(utf8.encode('${serverId}_${serverType}_${coverArtId}_$tier'))
        .toString();
  }

  /// 仅供测试：模拟「首帧已经到达」（frameBuilder 的登记动作）。
  /// flutter_test 的 fake clock 不会让自定义 ImageProvider 的真实解码产出帧，
  /// 回归测试用这个入口驱动「已显示过」状态。
  @visibleForTesting
  static void debugRecordFrame(String diskKey) => _markDisplayed(diskKey);

  /// 仅供测试：模拟一次加载失败（驱动冷却计数）。
  @visibleForTesting
  static void debugRecordFailure(String diskKey) => _registerFailure(diskKey);

  /// 仅供测试：清空全部进程内状态。
  @visibleForTesting
  static void debugResetCaches() {
    _sourceCache.clear();
    _everDisplayed.clear();
    debugNetworkRequests = 0;
    clearFailedCache();
  }

  /// 手动刷新时调用：清掉失败冷却与已解析 URL，让服务器换图 / 换会话生效。
  static void clearFailedCache() {
    _failedAttempts.clear();
    _failedTimestamps.clear();
    _sourceCache.clear();
  }

  /// 请求尺寸与解码尺寸共用这三个档位。
  ///
  /// 旧实现用 `widget.size * 2` 直接进 URL 和 `ResizeImage` key：同一个封面
  /// 在 38 / 52 / 200 / 300 / 400 各处调用点会生成 5 条 URL、5 个缓存 key，
  /// `imageCache` 永远互不命中，条目重挂载必然重新下载 + 重播淡入。
  /// 压到 320 后单张解码约 0.4MB，默认 100MB 的 imageCache 能放下两百多张，
  /// 竖屏往复滚动不再把封面挤出去。
  static int _sizeTierFor(double size) {
    final logical = (size.isFinite && size > 0) ? size : 50.0;
    if (logical <= 96) return 160;
    if (logical <= 320) return 320;
    return 512;
  }

  static void _evictHalf<T>(Map<String, T> cache) {
    final toRemove = cache.keys.take(cache.length ~/ 2).toList();
    for (final key in toRemove) {
      cache.remove(key);
    }
  }

  static void _markDisplayed(String diskKey) {
    if (_everDisplayed.length >= 2000) {
      _everDisplayed.removeAll(_everDisplayed.take(500).toList());
    }
    _everDisplayed.add(diskKey);
  }

  static bool _inCooldown(String diskKey) {
    final attempts = _failedAttempts[diskKey] ?? 0;
    final lastFailed = _failedTimestamps[diskKey];
    if (attempts >= 3 && lastFailed != null) {
      if (DateTime.now().difference(lastFailed) < const Duration(seconds: 15)) {
        return true;
      }
      _failedAttempts.remove(diskKey);
      _failedTimestamps.remove(diskKey);
    }
    return false;
  }

  static void _registerFailure(String diskKey) {
    _failedAttempts[diskKey] = (_failedAttempts[diskKey] ?? 0) + 1;
    _failedTimestamps[diskKey] = DateTime.now();
    if (_failedAttempts.length > 1000) {
      _evictHalf(_failedAttempts);
      _evictHalf(_failedTimestamps);
    }
  }

  static Future<String?> _thumbnailsDir() async {
    if (debugThumbnailsDir != null) return debugThumbnailsDir;
    final cached = _thumbnailsDirPath;
    if (cached != null) return cached;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory('${supportDir.path}/thumbnails');
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return _thumbnailsDirPath = dir.path;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _readDiskBytes(String diskKey) async {
    try {
      final dir = await _thumbnailsDir();
      if (dir == null) return null;
      final file = File('$dir/remote_$diskKey.bin');
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeDiskBytes(
    String diskKey,
    Uint8List bytes,
  ) async {
    try {
      final dir = await _thumbnailsDir();
      if (dir == null) return;
      await File('$dir/remote_$diskKey.bin')
          .writeAsBytes(bytes, flush: false);
    } catch (_) {}
  }

  /// 加载失败时把 `ResizeImage` 那条缓存 key 也逐出，冷却结束后才能真正重试。
  static Future<void> _evictImageCache(
    ImageProvider provider,
    int tier,
  ) async {
    final resized = ResizeImage.resizeIfNeeded(tier, tier, provider);
    await resized.evict();
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
  /// 上一次渲染所用图片 URL，用于判断本次重建是否仍是同一张封面。
  ///
  /// 保持同一张封面时让 `Image` 保留上一帧（gaplessPlayback），换成另一张
  /// （列表行复用）必须立刻清空，否则会短暂显示上一张。
  String? _renderedImageUrl;

  /// 非 null 表示这张封面在进程内已成功显示过 → 首帧不淡入、不画默认图标。
  String? _displayedKey;

  @override
  void initState() {
    super.initState();
    _syncDisplayedKey();
  }

  @override
  void didUpdateWidget(covariant RemoteArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverArtId != widget.coverArtId ||
        oldWidget.server?.id != widget.server?.id ||
        oldWidget.size != widget.size) {
      _renderedImageUrl = null;
      _syncDisplayedKey();
    }
  }

  void _syncDisplayedKey() {
    final diskKey = _resolveSource()?.diskKey;
    _displayedKey =
        (diskKey != null && RemoteArtworkWidget._everDisplayed.contains(diskKey))
            ? diskKey
            : null;
  }

  _ArtworkSource? _resolveSource() {
    final server = widget.server;
    final password = widget.password;
    final coverArtId = widget.coverArtId;
    if (server == null ||
        password == null ||
        coverArtId == null ||
        coverArtId.isEmpty ||
        (server.type != RemoteServerType.subsonic &&
            server.type != RemoteServerType.jellyfin)) {
      return null;
    }

    final tier = RemoteArtworkWidget._sizeTierFor(widget.size);
    final cacheKey =
        '${server.id}_${server.type.name}_${coverArtId}_$tier';
    final cached = RemoteArtworkWidget._sourceCache[cacheKey];
    if (cached != null) return cached;

    final url = server.type == RemoteServerType.jellyfin
        ? JellyfinClient(server: server, password: password)
            .buildCoverArtUrl(coverArtId, size: tier)
        : SubsonicClient(server: server, password: password)
            .buildCoverArtUrl(coverArtId, size: tier);
    final diskKey = md5.convert(utf8.encode(cacheKey)).toString();
    final source = _ArtworkSource(url: url, diskKey: diskKey, tier: tier);
    RemoteArtworkWidget._sourceCache[cacheKey] = source;
    if (RemoteArtworkWidget._sourceCache.length > 2000) {
      RemoteArtworkWidget._evictHalf(RemoteArtworkWidget._sourceCache);
    }
    return source;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width ?? widget.size;
    final h = widget.height ?? widget.size;
    final radius = widget.borderRadius ?? BorderRadius.circular(8);

    final source = _resolveSource();
    if (source == null) {
      return _buildFallback(context, w, h, radius, showIcon: true);
    }

    final keepLastFrame = _renderedImageUrl == source.url;
    _renderedImageUrl = source.url;

    final skipFadeIn = _displayedKey == source.diskKey;
    if (RemoteArtworkWidget._inCooldown(source.diskKey)) {
      return _buildFallback(context, w, h, radius, showIcon: !skipFadeIn);
    }

    final provider = _CachingRemoteImage(
      url: source.url,
      diskKey: source.diskKey,
      ignoreSsl: widget.server?.ignoreSsl ?? false,
    );

    return ClipRRect(
      borderRadius: radius,
      child: _withFallbackUnderlay(
        context: context,
        w: w,
        h: h,
        radius: radius,
        // 已显示过的封面不再把默认图标垫在底下：即便 imageCache 偶发
        // 未命中、解码晚一帧，也不会出现「先变回图标再冒出图片」。
        showFallback: !skipFadeIn,
        // 默认 `Image` 构造不带 cacheWidth/cacheHeight（只有 Image.network
        // 等命名构造才会内部包 ResizeImage），这里显式包一层：provider key
        // 与解码尺寸都收敛到稳定档位，滚动回收后 imageCache 才能命中。
        image: Image(
          image: ResizeImage.resizeIfNeeded(source.tier, source.tier, provider),
          width: w,
          height: h,
          fit: widget.fit,
          gaplessPlayback: keepLastFrame,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              RemoteArtworkWidget._markDisplayed(source.diskKey);
            }
            if (skipFadeIn) {
              // 包装层常驻：仍返回 AnimatedOpacity，只是 duration 归零。
              // 按条件增删包裹层会换根 Widget 类型 → 整条子树重建、
              // 封面 State 丢失、淡入重播（MEMORY-ui 第 24/33 条）。
              return AnimatedOpacity(
                opacity: 1.0,
                duration: Duration.zero,
                child: child,
              );
            }
            return artworkFadeInFrameBuilder(
              context,
              child,
              frame,
              wasSynchronouslyLoaded,
            );
          },
          errorBuilder: (_, _, _) {
            RemoteArtworkWidget._registerFailure(source.diskKey);
            unawaited(Future<void>.microtask(
              () => RemoteArtworkWidget._evictImageCache(provider, source.tier),
            ));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  /// 把默认占位垫在封面底下，封面解出首帧后淡入盖上去。
  ///
  /// `Stack` 与两个 child 必须常驻：不能改成「有图就不垫底」。
  Widget _withFallbackUnderlay({
    required BuildContext context,
    required double w,
    required double h,
    required BorderRadius radius,
    required bool showFallback,
    required Widget image,
  }) {
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        showFallback
            ? _buildFallback(context, w, h, radius, showIcon: true)
            : const SizedBox.shrink(),
        image,
      ],
    );
  }

  Widget _buildFallback(
    BuildContext context,
    double w,
    double h,
    BorderRadius radius, {
    required bool showIcon,
  }) {
    final theme = Theme.of(context);
    final minSide = math.min(w, h);
    final effectiveMinSide = minSide.isFinite && minSide > 0 ? minSide : 48.0;

    if (!showIcon) {
      return SizedBox(width: w, height: h);
    }

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
