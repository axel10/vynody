import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../player/audio_riverpod.dart';

class SongThumbnail extends ConsumerStatefulWidget {
  final String path;
  final int? id;
  final double size;

  const SongThumbnail({
    super.key,
    required this.path,
    this.id,
    this.size = 40.0,
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
    if ((Platform.isAndroid || Platform.isIOS) && widget.id != null) {
      _queryArtwork(widget.id!);
    }
  }

  Future<void> _queryArtwork(int id) async {
    final bytes = await OnAudioQuery().queryArtwork(id, ArtworkType.AUDIO);
    if (mounted) {
      setState(() {
        _artworkBytes = bytes;
        _artworkQueried = true;
      });
    }
  }

  void _triggerLoad() {
    if (_loadTriggered) return;
    _loadTriggered = true;
    // Run after the current frame so we don't call setState during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final scanner = ref.read(scannerServiceProvider);
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
      if ((Platform.isAndroid || Platform.isIOS) && widget.id != null) {
        _artworkBytes = null;
        _artworkQueried = false;
        _queryArtwork(widget.id!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) {
      if (widget.id != null) {
        if (_artworkQueried && _artworkBytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              _artworkBytes!,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallbackIcon(),
            ),
          );
        }
        // Still fetching or no artwork — show fallback without flickering.
        return _fallbackIcon();
      }
    } else if (Platform.isWindows) {
      final scanner = ref.watch(scannerServiceProvider);
      final metadata = scanner.metadataMap[widget.path];

      final imagePath = metadata?.thumbnailPath;
      if (imagePath != null) {
        final file = File(imagePath);
        if (file.existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              file,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              cacheWidth: (widget.size * 2).toInt(),
              cacheHeight: (widget.size * 2).toInt(),
              errorBuilder: (_, _, _) => _fallbackIcon(),
            ),
          );
        }
      }

      // Metadata not yet in map, or the cached entry still lacks a thumbnail.
      if (metadata == null || metadata.thumbnailPath == null) {
        _triggerLoad();
      }
    }

    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.music_note,
        color: Colors.blue,
        size: widget.size * 0.6,
      ),
    );
  }
}
