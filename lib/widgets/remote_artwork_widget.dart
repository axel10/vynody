import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../player/remote/remote_server_models.dart';
import '../player/remote/clients/subsonic_client.dart';
import '../player/remote/clients/jellyfin_client.dart';

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
      if (mounted && _localDiskPath != cachedPath) {
        setState(() {
          _localDiskPath = cachedPath;
        });
      }
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
        if (mounted) {
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
            if (mounted && _localDiskPath == null) {
              setState(() {
                _localDiskPath = targetFile.path;
              });
            }
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
    if (imageUrl == null) {
      return _buildFallback(context, w, h, radius);
    }

    // 1. If we have a local disk cache file, render directly from disk (0 network latency, never lost on scroll)
    if (_localDiskPath != null && File(_localDiskPath!).existsSync()) {
      final cacheW = (w * 2).round();
      final cacheH = (h * 2).round();
      return ClipRRect(
        borderRadius: radius,
        child: Image.file(
          File(_localDiskPath!),
          width: w,
          height: h,
          cacheWidth: cacheW > 0 ? cacheW : null,
          cacheHeight: cacheH > 0 ? cacheH : null,
          fit: widget.fit,
          errorBuilder: (_, _, _) {
            // If local file was somehow deleted/corrupted, fall back to network
            return _buildNetworkImage(context, imageUrl, w, h, radius);
          },
        ),
      );
    }

    return _buildNetworkImage(context, imageUrl, w, h, radius);
  }

  Widget _buildNetworkImage(
    BuildContext context,
    String imageUrl,
    double w,
    double h,
    BorderRadius radius,
  ) {
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

    final cacheW = (w * 2).round();
    final cacheH = (h * 2).round();

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        imageUrl,
        width: w,
        height: h,
        cacheWidth: cacheW > 0 ? cacheW : null,
        cacheHeight: cacheH > 0 ? cacheH : null,
        fit: widget.fit,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            // Trigger disk caching once image successfully loads
            _triggerBackgroundDiskCache(imageUrl);
            return child;
          }
          return _buildFallback(context, w, h, radius);
        },
        errorBuilder: (_, _, _) {
          final count = (RemoteArtworkWidget._failedAttempts[imageUrl] ?? 0) + 1;
          RemoteArtworkWidget._failedAttempts[imageUrl] = count;
          RemoteArtworkWidget._failedTimestamps[imageUrl] = DateTime.now();
          return _buildFallback(context, w, h, radius);
        },
      ),
    );
  }

  Widget _buildFallback(
    BuildContext context,
    double w,
    double h,
    BorderRadius radius,
  ) {
    final theme = Theme.of(context);
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
          size: (widget.size * 0.5).clamp(16.0, 48.0),
        ),
      ),
    );
  }
}
