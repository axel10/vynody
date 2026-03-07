import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import '../player/audio_service.dart';
import '../player/scanner_service.dart';
import '../widgets/song_thumbnail.dart';

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key});

  final List<String> _audioExtensions = const [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg',
  ];

  Future<List<MusicFile>> _getFilesFromPath(String path) async {
    final List<MusicFile> results = [];
    final entity = FileSystemEntity.typeSync(path);

    if (entity == FileSystemEntityType.file) {
      final ext = p.extension(path).toLowerCase();
      if (_audioExtensions.contains(ext)) {
        results.add(MusicFile(path: path, name: p.basename(path)));
      }
    } else if (entity == FileSystemEntityType.directory) {
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
    final audio = context.watch<AudioService>();
    final playlist = audio.playlist;

    return DropTarget(
      onDragDone: (details) async {
        final List<MusicFile> allFiles = [];
        for (final file in details.files) {
          final files = await _getFilesFromPath(file.path);
          allFiles.addAll(files);
        }
        if (allFiles.isNotEmpty) {
          audio.addToPlaylist(allFiles);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('播放列表'),
          actions: [
            if (playlist.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear_all),
                tooltip: '清空列表',
                onPressed: () => audio.clearPlaylist(),
              ),
          ],
        ),
        body: playlist.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.playlist_add,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '列表为空',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    if (Platform.isWindows)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          '拖入文件或文件夹以添加音乐',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.only(bottom: Platform.isWindows ? 84 : 0),
                itemCount: playlist.length,
                itemBuilder: (context, index) {
                  final song = playlist[index];
                  final isCurrent = audio.currentIndex == index;

                  return ListTile(
                    leading: SongThumbnail(path: song.path, id: song.id),
                    title: Text(
                      song.name,
                      style: TextStyle(
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        fontWeight: isCurrent ? FontWeight.bold : null,
                      ),
                    ),
                    subtitle: Text(
                      p.dirname(song.path),
                      style: const TextStyle(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: () => audio.removeFromPlaylist(index),
                    ),
                    onTap: () {
                      audio.playPlaylist(playlist, initialIndex: index);
                    },
                  );
                },
              ),
      ),
    );
  }
}
