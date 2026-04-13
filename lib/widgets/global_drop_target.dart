import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import '../player/audio_riverpod.dart';
import '../models/music_file.dart';

class GlobalDropTarget extends ConsumerStatefulWidget {
  final Widget child;

  const GlobalDropTarget({super.key, required this.child});

  @override
  ConsumerState<GlobalDropTarget> createState() => _GlobalDropTargetState();
}

class _GlobalDropTargetState extends ConsumerState<GlobalDropTarget> {
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
      // 处理拖放完成事件
      onDragDone: (details) async {
        final audio = ref.read(audioServiceProvider);
        final List<MusicFile> allFiles = [];

        // 1. 递归扫描拖入的所有路径（支持拖入单个文件或整个文件夹）
        for (final file in details.files) {
          // 获取路径下符合音频扩展名的文件列表
          final files = await _getFilesFromPath(file.path);
          allFiles.addAll(files);
        }

        // 2. 如果找到了音频文件，执行播放逻辑
        if (allFiles.isNotEmpty && mounted) {
          // 逻辑设计：拖入多个时，播放其中的第一个，剩下的添加到队列
          // audio.playFile(append: true) 的特性是移动到队列末尾并切换
          await audio.playFile(
            allFiles[0].path,
            allFiles[0].name,
            append: true,
          );

          // 3. 将后续文件全部补充到播放队列中（不切歌，静默添加）
          if (allFiles.length > 1) {
            await audio.addToPlaylist(allFiles.sublist(1));
          }

          // 注意：此处并未像双击那样切换 Tab，是为了尽量不打扰用户的当前浏览操作
        }
      },
      child: widget.child,
    );
  }
}
