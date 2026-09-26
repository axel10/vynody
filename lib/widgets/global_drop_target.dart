import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/utils/drop_data_utils.dart';
import '../utils/app_snack_bar.dart';

class GlobalDropTarget extends ConsumerStatefulWidget {
  final Widget child;
  final bool enable;

  const GlobalDropTarget({super.key, required this.child, this.enable = true});

  @override
  ConsumerState<GlobalDropTarget> createState() => _GlobalDropTargetState();
}

class _GlobalDropTargetState extends ConsumerState<GlobalDropTarget> {
  DateTime? _lastDropTime;

  bool _isDuplicateDrop() {
    final now = DateTime.now();
    if (_lastDropTime != null &&
        now.difference(_lastDropTime!) < const Duration(milliseconds: 600)) {
      return true;
    }
    _lastDropTime = now;
    return false;
  }

  Future<List<MusicFile>> _getFilesFromPath(String path) async {
    final List<MusicFile> results = [];
    final entityType = FileSystemEntity.typeSync(path);

    if (entityType == FileSystemEntityType.file) {
      if (MusicFileUtils.isMusicFilePath(path)) {
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
            if (MusicFileUtils.isMusicFilePath(item.path)) {
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

  Future<void> _handleDroppedPaths(List<String> droppedPaths) async {
    if (!mounted || droppedPaths.isEmpty) return;

    final audio = ref.read(audioServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final List<MusicFile> allFiles = [];

    // 1. 递归扫描拖入的所有路径（支持拖入单个文件或整个文件夹）
    for (final path in droppedPaths) {
      final files = await _getFilesFromPath(path);
      allFiles.addAll(files);
    }

    if (!mounted || allFiles.isEmpty) {
      return;
    }

    final uniqueFiles = <MusicFile>[];
    final seenPaths = <String>{};
    for (final song in allFiles) {
      if (seenPaths.add(song.path)) {
        uniqueFiles.add(song);
      }
    }

    if (uniqueFiles.length == 1) {
      final song = uniqueFiles.first;
      final queueIndex = audio.playbackQueue.indexWhere(
        (queuedSong) => queuedSong.path == song.path,
      );

      if (queueIndex >= 0) {
        await audio.playAtIndex(queueIndex);
      } else {
        await audio.playFile(song.path, song.name, append: true);
      }
      return;
    }

    final existingQueuePaths = audio.playbackQueue
        .map((song) => song.path)
        .toSet();
    final newSongs = <MusicFile>[];
    var existingCount = 0;

    for (final song in uniqueFiles) {
      if (existingQueuePaths.contains(song.path)) {
        existingCount++;
        continue;
      }
      newSongs.add(song);
    }

    if (newSongs.isNotEmpty) {
      final db = MetadataDatabase();
      final cachedMap =
          await db.getSongMetadataByPaths(newSongs.map((s) => s.path));
      for (var i = 0; i < newSongs.length; i++) {
        final s = newSongs[i];
        final cached = cachedMap[s.path];
        if (cached != null) {
          newSongs[i] = newSongs[i].copyWith(
            title: cached.title,
            artist: cached.artist,
            albumArtist: cached.albumArtist,
            album: cached.album,
            trackNumber: cached.trackNumber,
            durationMillis: cached.duration,
            thumbnailPath: cached.thumbnailPath,
            artworkPath: cached.artworkPath,
            artworkWidth: cached.artworkWidth,
            artworkHeight: cached.artworkHeight,
            themeColorsBlob: cached.themeColorsBlob,
            waveformBlob: cached.waveformBlob,
            lastModifiedTime: cached.lastModifiedTime,
          );
        }
      }
      await audio.appendToQueue(newSongs);
    }

    if (!mounted || !context.mounted) return;

    final message = existingCount > 0
        ? l10n.dropAddedSongsWithExisting(newSongs.length, existingCount)
        : l10n.dropAddedSongs(newSongs.length);

    AppSnackBar.show(context, ref, SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enable) {
      return widget.child;
    }

    return DropRegion(
      formats: const [Formats.fileUri, Formats.plainText, Formats.uri],
      hitTestBehavior: HitTestBehavior.translucent,
      onDropOver: (event) {
        // Global drop is strictly for external files from outside the app (Finder, Explorer, etc.).
        // In-app dragging should never be captured by the global backdrop.
        final hasLocalData =
            event.session.items.any((item) => item.localData != null);
        if (hasLocalData || DropDataUtils.isInternalDragActive) {
          return DropOperation.none;
        }
        return DropOperation.copy;
      },
      onPerformDrop: (event) async {
        if (DropDataUtils.isInternalDragActive) {
          debugPrint('[GlobalDropTarget] onPerformDrop ignored: in-app drag active');
          return;
        }
        final hasLocalData =
            event.session.items.any((item) => item.localData != null);
        if (hasLocalData) {
          debugPrint('[GlobalDropTarget] onPerformDrop ignored: localData exists');
          return;
        }
        if (_isDuplicateDrop()) return;
        final droppedPaths = await DropDataUtils.extractPathsFromDrop(event);
        debugPrint('[GlobalDropTarget] onPerformDrop extracted ${droppedPaths.length} paths');
        if (droppedPaths.isNotEmpty) {
          await _handleDroppedPaths(droppedPaths);
        }
      },
      child: widget.child,
    );
  }
}
