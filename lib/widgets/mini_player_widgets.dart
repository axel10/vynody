import 'dart:io';
import 'package:flutter/material.dart';
import '../player/audio_service.dart';

class MiniArtwork extends StatelessWidget {
  const MiniArtwork({super.key, required this.audio});

  final AudioService audio;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          ? const Icon(Icons.music_note, color: Colors.white, size: 20)
          : null,
    );
  }
}

class MiniControlButton extends StatelessWidget {
  const MiniControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 24),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: onPressed,
    );
  }
}