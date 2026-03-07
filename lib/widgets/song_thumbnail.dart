import 'dart:io';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../player/scanner_service.dart';

class SongThumbnail extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) {
      if (id != null) {
        return QueryArtworkWidget(
          id: id!,
          type: ArtworkType.AUDIO,
          artworkWidth: size,
          artworkHeight: size,
          artworkBorder: BorderRadius.circular(4),
          nullArtworkWidget: _fallbackIcon(),
        );
      }
    } else if (Platform.isWindows) {
      final scanner = context.watch<ScannerService>();
      final metadata = scanner.metadataMap[path];
      if (metadata?.artworkPath != null) {
        final file = File(metadata!.artworkPath!);
        if (file.existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallbackIcon(),
            ),
          );
        }
      }
    }

    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(Icons.music_note, color: Colors.blue, size: size * 0.6),
    );
  }
}
