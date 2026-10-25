import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/audio/playback_queue_processor.dart';
import 'package:vynody/player/audio/remote_queue_metadata_enricher.dart';
import 'package:vynody/player/remote/remote_server_storage.dart';
import 'package:vynody/utils/memory_trace.dart';

class QueueBackgroundProcessor {
  final MetadataDatabase db;
  final PlaybackQueueProcessor queueProcessor;

  /// 远程曲目的并发补全器。
  ///
  /// 与 [queueProcessor] 的串行 Phase 1 分开：远程每首都要一次网络读取，
  /// 放进可被新一次触发打断的串行循环里会永远只处理完最前面一两首。
  late final RemoteQueueMetadataEnricher _remoteEnricher;

  /// 每次 [start] 都会换成新的闭包，补全器只持有这个可变引用。
  QueueMetadataUpdatesCallback? _activeOnUpdate;

  /// 能让队列抽屉肉眼可见变化的字段；只有这些字段变化才值得回写 playlist。
  static const Set<String> _playlistVisibleKeys = <String>{
    'title',
    'artist',
    'album',
    'trackNumber',
    'durationMillis',
    'thumbnailPath',
    'artworkPath',
    'artworkWidth',
    'artworkHeight',
    'themeColorsBlob',
  };

  QueueBackgroundProcessor({
    required this.db,
    required this.queueProcessor,
    required Future<RemoteServerStorage> Function() remoteStorageGetter,
  }) {
    _remoteEnricher = RemoteQueueMetadataEnricher(
      db: db,
      storageGetter: remoteStorageGetter,
      onMetadata: (path, updates) => _applyMetadataUpdates(path, updates),
    );
  }

  /// 把一次元数据更新写进内存队列并把整首曲目交给调用方回写。
  void _applyMetadataUpdates(String path, Map<String, dynamic> updates) {
    _activeOnUpdate?.call(path, updates);
  }

  void dispose() {
    _remoteEnricher.dispose();
  }

  void start({
    required List<MusicFile> queue,
    required String? priorityPath,
    required void Function() onChanged,
    required void Function(Map<String, Color>) onThemeChanged,
    required MusicFile? Function() currentMusic,
    required void Function(String) logTrace,
    required String Function(MusicFile?) debugSongLabel,
    required void Function(MusicFile song) onSongUpdated,
    bool isBackground = false,
  }) {
    if (queue.isEmpty) return;
    MemoryTrace.snapshot(
      'audio:queueBackground:start',
      details: <String, Object?>{
        'priority': priorityPath ?? currentMusic()?.path ?? '-',
        'queue': queue.length,
        'current': currentMusic()?.path ?? '-',
      },
    );

    final String? currentPath = priorityPath ?? currentMusic()?.path;
    final Set<String> artworkPriorityPaths = <String>{};
    final Set<String> waveformMemoryPaths = <String>{};
    final Set<int> priorityIndices = <int>{};

    if (currentPath != null) {
      final int currIdx = queue.indexWhere((s) => s.path == currentPath);
      if (currIdx != -1) {
        for (int i = -1; i <= 1; i++) {
          final idx = (currIdx + i) % queue.length;
          final safeIdx = idx < 0 ? idx + queue.length : idx;
          artworkPriorityPaths.add(queue[safeIdx].path);
        }
        for (int i = -1; i <= 1; i++) {
          final idx = (currIdx + i) % queue.length;
          final safeIdx = idx < 0 ? idx + queue.length : idx;
          waveformMemoryPaths.add(queue[safeIdx].path);
        }
        for (int i = -2; i <= 3; i++) {
          final idx = (currIdx + i) % queue.length;
          final safeIdx = idx < 0 ? idx + queue.length : idx;
          priorityIndices.add(safeIdx);
        }
      }
    }

    bool changed = false;
    for (int i = 0; i < queue.length; i++) {
      final song = queue[i];
      if (!artworkPriorityPaths.contains(song.path) &&
          song.artworkBytes != null) {
        queue[i] = queue[i].copyWith(artworkBytes: null);
        changed = true;
      }
      if (!waveformMemoryPaths.contains(song.path) &&
          song.waveformBlob != null) {
        queue[i] = queue[i].copyWith(waveformBlob: null);
        changed = true;
      }
    }
    if (changed) {
      onChanged();
    }

    if (priorityIndices.isNotEmpty && (artworkPriorityPaths.isNotEmpty || waveformMemoryPaths.isNotEmpty)) {
      unawaited(() async {
        bool asyncChanged = false;
        for (final i in priorityIndices) {
          if (i >= queue.length) continue;
          final song = queue[i];
          final bool inWaveform = waveformMemoryPaths.contains(song.path);
          final bool needsDbSync = song.thumbnailPath == null ||
              (inWaveform && song.waveformBlob == null);

          if (needsDbSync) {
            final existing = await db.getSongMetadata(song.path);
            if (existing != null) {
              String? newTitle = song.title;
              String? newArtist = song.artist;
              String? newAlbum = song.album;
              int? newTrackNumber = song.trackNumber;
              int? newDuration = song.durationMillis;
              Uint8List? newWaveformBlob = song.waveformBlob;
              String? newThumbnailPath = song.thumbnailPath;
              String? newArtworkPath = song.artworkPath;
              int? newArtworkWidth = song.artworkWidth;
              int? newArtworkHeight = song.artworkHeight;
              Uint8List? newThemeColorsBlob = song.themeColorsBlob;

              if (song.title == null && existing.title.isNotEmpty) {
                newTitle = existing.title;
              }
              if ((song.artist == null || song.artist == 'Unknown Artist') &&
                  existing.artist.isNotEmpty &&
                  existing.artist != 'Unknown Artist') {
                newArtist = existing.artist;
              }
              if ((song.album == null || song.album == 'Unknown Album') &&
                  existing.album.isNotEmpty &&
                  existing.album != 'Unknown Album') {
                newAlbum = existing.album;
              }
              if (song.trackNumber == null && existing.trackNumber != null) {
                newTrackNumber = existing.trackNumber;
              }
              if (song.durationMillis == null && existing.duration != null) {
                newDuration = existing.duration;
              }
              if (inWaveform && song.waveformBlob == null) {
                newWaveformBlob = existing.waveformBlob;
              }
              if (existing.thumbnailPath != null) {
                newThumbnailPath = existing.thumbnailPath;
              }
              if (existing.artworkPath != null) {
                newArtworkPath = existing.artworkPath;
              }
              if (existing.artworkWidth != null) {
                newArtworkWidth = existing.artworkWidth;
              }
              if (existing.artworkHeight != null) {
                newArtworkHeight = existing.artworkHeight;
              }
              if (existing.themeColorsBlob != null) {
                newThemeColorsBlob = existing.themeColorsBlob;
              }

              if (i < queue.length && queue[i].path == song.path) {
                queue[i] = queue[i].copyWith(
                  title: newTitle,
                  artist: newArtist,
                  album: newAlbum,
                  trackNumber: newTrackNumber,
                  durationMillis: newDuration,
                  waveformBlob: newWaveformBlob,
                  thumbnailPath: newThumbnailPath,
                  artworkPath: newArtworkPath,
                  artworkWidth: newArtworkWidth,
                  artworkHeight: newArtworkHeight,
                  themeColorsBlob: newThemeColorsBlob,
                );
                asyncChanged = true;
              }
            }
          }
        }
        if (asyncChanged) {
          onChanged();
        }
      }());
    }

    logTrace(
      '_startQueueBackgroundProcessing priority='
      '${priorityPath ?? currentMusic()?.path ?? '-'} '
      'current=${debugSongLabel(currentMusic())}',
    );

    // 远程曲目交给并发补全器：它不受进程号影响，不会被下一次触发打断，
    // 也不会和下面的串行 Phase 1 抢同一批网络读取。
    // 注意必须在 [_activeOnUpdate] 赋值之后才能入队，否则首批回写会被丢掉。
    void handleUpdate(String path, Map<String, dynamic> updates) {
      logTrace(
        '_queueProcessor onUpdate path=$path '
        'keys=${updates.keys.toList()} '
        'current=${debugSongLabel(currentMusic())}',
      );

      final String? currentPath = currentMusic()?.path;
      final Set<String> waveformMemPaths = <String>{};
      if (currentPath != null) {
        final int currIdx = queue.indexWhere((s) => s.path == currentPath);
        if (currIdx != -1) {
          for (int i = -1; i <= 1; i++) {
            final idx = (currIdx + i) % queue.length;
            final safeIdx = idx < 0 ? idx + queue.length : idx;
            waveformMemPaths.add(queue[safeIdx].path);
          }
        }
      }

      MusicFile? updatedSong;
      bool queueChanged = false;
      for (int i = 0; i < queue.length; i++) {
        if (queue[i].path == path) {
          final bool inWaveformMemoryRange = waveformMemPaths.contains(path);
          queue[i] = queue[i].copyWith(
            title: updates['title'] as String? ?? queue[i].title,
            artist: updates['artist'] as String? ?? queue[i].artist,
            album: updates['album'] as String? ?? queue[i].album,
            trackNumber: updates['trackNumber'] as int? ?? queue[i].trackNumber,
            durationMillis:
                updates['durationMillis'] as int? ?? queue[i].durationMillis,
            themeColorsBlob:
                updates['themeColorsBlob'] as Uint8List? ??
                    queue[i].themeColorsBlob,
            waveformBlob: inWaveformMemoryRange
                ? (updates['waveformBlob'] as Uint8List? ??
                    queue[i].waveformBlob)
                : null,
            thumbnailPath:
                updates['thumbnailPath'] as String? ?? queue[i].thumbnailPath,
            artworkPath:
                updates['artworkPath'] as String? ?? queue[i].artworkPath,
            artworkWidth:
                updates['artworkWidth'] as int? ?? queue[i].artworkWidth,
            artworkHeight:
                updates['artworkHeight'] as int? ?? queue[i].artworkHeight,
          );
          updatedSong ??= queue[i];
          queueChanged = true;
        }
      }

      if (path == currentMusic()?.path && updates.containsKey('themeColors')) {
        onThemeChanged(updates['themeColors'] as Map<String, Color>);
      }
      // 队列抽屉读的是 playlist track 里缓存的 MusicFile。只改上面这个局部
      // list 不会反映到 UI，必须把整首曲目交回去覆盖 track 元数据。
      if (updatedSong != null && updates.keys.any(_playlistVisibleKeys.contains)) {
        onSongUpdated(updatedSong);
      }
      if (queueChanged) {
        onChanged();
      }
    }

    _activeOnUpdate = handleUpdate;

    // 远程曲目按「当前曲 + 后面几首」优先入队：一次拖进来几十首时，
    // 马上要播的那几首应该先解析出来，而不是从队列第 0 首逐个往后排。
    final remoteOrder = <MusicFile>[];
    if (currentPath != null) {
      final int currIdx = queue.indexWhere((s) => s.path == currentPath);
      if (currIdx != -1) {
        for (final offset in const <int>[0, 1, 2, 3, -1, -2]) {
          final idx = (currIdx + offset) % queue.length;
          remoteOrder.add(queue[idx < 0 ? idx + queue.length : idx]);
        }
      }
    }
    remoteOrder.addAll(queue);
    _remoteEnricher.enqueue(remoteOrder);

    unawaited(
      queueProcessor.processQueue(
        playlist: List.from(queue),
        currentFilePath: priorityPath ?? currentMusic()?.path,
        isBackground: isBackground,
        onUpdate: handleUpdate,

        onHdArtworkLoaded: (path, artworkPath) {
          logTrace(
            '_queueProcessor onHdArtworkLoaded path=$path '
            'artworkPath=$artworkPath '
            'current=${debugSongLabel(currentMusic())}',
          );
          MemoryTrace.snapshot(
            'audio:queueBackground:artworkLoaded',
            details: <String, Object?>{
              'path': path,
              'artworkPath': artworkPath,
              'queue': queue.length,
            },
          );

          final String? currentPath = currentMusic()?.path;
          final Set<String> artworkPriority = <String>{};
          if (currentPath != null) {
            final int currIdx =
                queue.indexWhere((s) => s.path == currentPath);
            if (currIdx != -1) {
              for (int i = -1; i <= 1; i++) {
                final idx = (currIdx + i) % queue.length;
                final safeIdx = idx < 0 ? idx + queue.length : idx;
                artworkPriority.add(queue[safeIdx].path);
              }
            }
          }

          if (artworkPriority.contains(path)) {
            for (int i = 0; i < queue.length; i++) {
              if (queue[i].path == path) {
                queue[i] = queue[i].copyWith(artworkPath: artworkPath);
              }
            }

            if (path == currentMusic()?.path) {
              onChanged();
            }

            const int limit = 800;

            final provider = ResizeImage(
              FileImage(File(artworkPath)),
              width: limit,
              height: limit,
              allowUpscaling: false,
            );
            provider.resolve(ImageConfiguration.empty);
          }
        },
      ),
    );
  }
}
