import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../player/audio_service.dart';
import '../models/music_file.dart';

class GlobalDropTarget extends StatefulWidget {
  final Widget child;

  const GlobalDropTarget({super.key, required this.child});

  @override
  State<GlobalDropTarget> createState() => _GlobalDropTargetState();
}

class _GlobalDropTargetState extends State<GlobalDropTarget> {
  final List<String> _audioExtensions = const [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg',
  ];

  Future<List<MusicFile>> _getFilesFromPath(String path) async {
    final List<MusicFile> results = [];
    final entityType = FileSystemEntity.typeSync(path);

    if (entityType == FileSystemEntityType.file) {
      final ext = p.extension(path).toLowerCase();
      if (_audioExtensions.contains(ext)) {
        results.add(MusicFile(path: path, name: p.basename(path)));
      }
    } else if (entityType == FileSystemEntityType.directory) {
      final dir = Directory(path);
      try {
        await for (final item in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (item is File) {
            final ext = p.extension(item.path).toLowerCase();
            if (_audioExtensions.contains(ext)) {
              results.add(
                MusicFile(path: item.path, name: p.basename(item.path)),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning directory $path: $e');
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: (details) async {
        final List<MusicFile> allFiles = [];
        for (final file in details.files) {
          final files = await _getFilesFromPath(file.path);
          allFiles.addAll(files);
        }

        if (allFiles.isNotEmpty && mounted) {
          final audio = context.read<AudioService>();
          
          // Use the established pattern: play the first file and add others
          // playFile(append: true) adds to end and plays it.
          await audio.playFile(allFiles[0].path, allFiles[0].name, append: true);
          
          if (allFiles.length > 1) {
            await audio.addToPlaylist(allFiles.sublist(1));
          }
          
          // Optional: navigate to playback page to show it's playing
          // This is often expected when dragging files in
          // But I'll leave it to the user or see if they requested it.
          // They said "原地播放", which usually implies stay where you are but start playing.
          // However, MainLayout handleFileOpen navigates to tab 1.
        }
      },
      child: widget.child,
    );
  }
}
