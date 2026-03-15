import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../player/audio_service.dart';

class DynamicIslandPlayer extends StatelessWidget {
  const DynamicIslandPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();
    if (audio.currentFilePath == null) return const SizedBox.shrink();

    return Hero(
      tag: 'player_capsule',
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Album Art
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  image: audio.currentArtworkBytes != null
                      ? DecorationImage(
                          image: MemoryImage(audio.currentArtworkBytes!),
                          fit: BoxFit.cover,
                        )
                      : audio.currentArtworkPath != null
                      ? DecorationImage(
                          image: FileImage(File(audio.currentArtworkPath!)),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: Colors.grey[900],
                ),
                child:
                    (audio.currentArtworkBytes == null &&
                        audio.currentArtworkPath == null)
                    ? const Icon(
                        Icons.music_note,
                        color: Colors.white,
                        size: 20,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              // Song Info
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audio.currentFileName ?? '未知',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Progress mini bar
                    Stack(
                      children: [
                        Container(
                          height: 2,
                          width: 100,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                        Container(
                          height: 2,
                          width: 100 * audio.progress.clamp(0.0, 1.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Controls
              IconButton(
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: audio.previous,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  audio.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: audio.togglePlay,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: audio.next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
