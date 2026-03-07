import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../player/audio_service.dart';

class PlaybackPage extends StatelessWidget {
  const PlaybackPage({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();

    if (audio.currentFilePath == null) {
      return const Center(
        child: Text('当前无播放内容', style: TextStyle(color: Colors.grey)),
      );
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;

        final albumArt = Hero(
          tag: 'album_art',
          child: Container(
            width: isLandscape ? 200 : 240,
            height: isLandscape ? 200 : 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black87,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: isLandscape ? 50 : 60,
                height: isLandscape ? 50 : 60,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white24,
                ),
                child: Icon(
                  Icons.music_note,
                  size: isLandscape ? 30 : 40,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );

        final controls = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: isLandscape
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Text(
              audio.currentFileName ?? '未知',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: isLandscape ? TextAlign.left : TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: isLandscape ? 16 : 32),
            Slider(
              value: audio.progress,
              onChanged: (val) {
                final position = Duration(
                  milliseconds: (val * audio.duration.inMilliseconds).toInt(),
                );
                audio.seek(position);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(audio.position)),
                  Text(_formatDuration(audio.duration)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous, size: 40),
                  onPressed: () {},
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: audio.togglePlay,
                  child: Icon(audio.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.skip_next, size: 40),
                  onPressed: () {},
                ),
              ],
            ),
          ],
        );

        if (isLandscape) {
          return Padding(
            padding: const EdgeInsets.all(32.0),
            child: Row(
              children: [
                Expanded(flex: 2, child: Center(child: albumArt)),
                const SizedBox(width: 32),
                Expanded(flex: 3, child: controls),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [albumArt, const SizedBox(height: 48), controls],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
