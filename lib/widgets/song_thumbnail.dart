import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';

class SongThumbnail extends ConsumerStatefulWidget {
  final String path;
  final int? id;
  final double size;
  final double? width;
  final double? height;

  const SongThumbnail({
    super.key,
    required this.path,
    this.id,
    this.size = 40.0,
    this.width,
    this.height,
  });

  @override
  ConsumerState<SongThumbnail> createState() => _SongThumbnailState();
}

class _SongThumbnailState extends ConsumerState<SongThumbnail> {
  bool _loadTriggered = false;

  // Android/iOS: cache artwork bytes so parent rebuilds don't retrigger fetch.
  Uint8List? _artworkBytes;
  bool _artworkQueried = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      if (widget.id != null) {
        _queryArtwork(widget.id!);
      } else {
        _triggerLoad();
      }
    }
  }

  Future<void> _queryArtwork(int id) async {
    try {
      final bytes = await OnAudioQuery().queryArtwork(id, ArtworkType.AUDIO);
      if (mounted) {
        setState(() {
          _artworkBytes = bytes;
          _artworkQueried = true;
        });
        if (bytes == null || bytes.isEmpty) {
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
    // Reset so we retry if the path/id changes (e.g. list recycling).
    if (oldWidget.path != widget.path || oldWidget.id != widget.id) {
      _loadTriggered = false;
      _artworkBytes = null;
      _artworkQueried = false;
      if ((Platform.isAndroid || Platform.isIOS) && widget.id != null) {
        _queryArtwork(widget.id!);
      } else if (Platform.isAndroid || Platform.isIOS) {
        _triggerLoad();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      scannerServiceProvider.select(
        (scanner) => (scanner.metadataRevision, scanner.isScanning),
      ),
    );

    final scanner = ref.read(scannerServiceProvider);
    final metadata = scanner.metadataMap[widget.path];
    final imagePath = metadata?.thumbnailPath;

    final double dpr = MediaQuery.of(context).devicePixelRatio;
    final double adjustedSize = (widget.size * dpr).round() / dpr;
    final double layoutWidth = widget.width ?? adjustedSize;
    final double layoutHeight = widget.height ?? adjustedSize;
    final int cachePixels = (widget.size * dpr).round();

    if (imagePath != null) {
      final file = File(imagePath);
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          file,
          width: layoutWidth,
          height: layoutHeight,
          fit: BoxFit.cover,
          cacheWidth: cachePixels,
          cacheHeight: cachePixels,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => _fallbackIcon(layoutWidth, layoutHeight),
        ),
      );
    }

    if (Platform.isAndroid || Platform.isIOS) {
      if (_artworkQueried && _artworkBytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.memory(
            _artworkBytes!,
            width: layoutWidth,
            height: layoutHeight,
            fit: BoxFit.cover,
            cacheWidth: cachePixels,
            cacheHeight: cachePixels,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => _fallbackIcon(layoutWidth, layoutHeight),
          ),
        );
      }
      if (widget.id == null) {
        _triggerLoad();
      }
      // Still fetching or no artwork — show fallback without flickering.
      return _fallbackIcon(layoutWidth, layoutHeight);
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // Metadata not yet in map, or the cached entry still lacks a thumbnail.
      if (metadata == null || metadata.thumbnailPath == null) {
        _triggerLoad();
      }
    }

    return _fallbackIcon(layoutWidth, layoutHeight);
  }

  Widget _fallbackIcon(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Icons.music_note,
              color: Colors.blue,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}
