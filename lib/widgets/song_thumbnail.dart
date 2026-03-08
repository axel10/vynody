import 'dart:io';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../player/scanner_service.dart';

class SongThumbnail extends StatefulWidget {
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
  State<SongThumbnail> createState() => _SongThumbnailState();
}

class _SongThumbnailState extends State<SongThumbnail> {
  bool _loadTriggered = false;

  void _triggerLoad(ScannerService scanner) {
    if (_loadTriggered) return;
    _loadTriggered = true;
    // Run after the current frame so we don't call setState during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        scanner.loadMetadataForPath(widget.path);
      }
    });
  }

  @override
  void didUpdateWidget(SongThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset so we retry if the path changes (e.g. list recycling).
    if (oldWidget.path != widget.path) {
      _loadTriggered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) {
      if (widget.id != null) {
        return QueryArtworkWidget(
          id: widget.id!,
          type: ArtworkType.AUDIO,
          artworkWidth: widget.size,
          artworkHeight: widget.size,
          artworkBorder: BorderRadius.circular(4),
          nullArtworkWidget: _fallbackIcon(),
        );
      }
    } else if (Platform.isWindows) {
      final scanner = context.watch<ScannerService>();
      final metadata = scanner.metadataMap[widget.path];

      if (metadata?.artworkPath != null) {
        final file = File(metadata!.artworkPath!);
        if (file.existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              file,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallbackIcon(),
            ),
          );
        }
      }

      // Metadata not yet in map — trigger a one-shot load from DB/file.
      if (metadata == null) {
        _triggerLoad(scanner);
      }
    }

    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
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
