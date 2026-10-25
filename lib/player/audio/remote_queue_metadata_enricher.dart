/// 队列中远程曲目（SMB / WebDAV）的并发元数据补全器。
///
/// 为什么单独存在：`PlaybackQueueProcessor` 的 Phase 1 是「串行遍历 + 每次新的
/// 队列变动就 bump 进程号让当前循环直接 return」的模型，而远程曲目每首都要一次
/// 网络 TagLib range 读取（局域网 0.3~1s，慢时直到 10s 超时）。一个 20 首的文件夹
/// 串行就要十几秒，这期间任何一次 UI 操作（切歌 / 点选 / 切 tab）都会让循环提前
/// 退出，于是永远只解析到最前面一两首，剩下的保持「文件名 + 默认封面 + 0:00」。
///
/// 这里把远程解析从那条可被随时打断的串行链上摘出来：
/// * 并发有上限（默认 3，与远程文件夹批量解析保持一致，避免压垮 SMB 服务端）；
/// * 只受 [dispose] 控制，不会因为队列再次变化而丢弃进度；
/// * 每解析成功一首就立刻通过 [onMetadata] 回写队列，抽屉是逐首刷新而不是等整批；
/// * 已经解析过（`metadataTextScanned` 非空）的曲目直接跳过，重复入队不再联网。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/clients/webdav_client.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_storage.dart';
import 'package:vynody/player/remote/services/webdav_metadata_helper.dart';
import 'package:vynody/utils/app_log.dart';

/// 与 `PlaybackQueueProcessor.processQueue` 的 `onUpdate` 签名保持一致，
/// 便于队列后台处理器用同一个回写通道处理本地与远程结果。
typedef QueueMetadataUpdatesCallback = void Function(
  String path,
  Map<String, dynamic> updates,
);

class RemoteQueueMetadataEnricher {
  RemoteQueueMetadataEnricher({
    required MetadataDatabase db,
    required Future<RemoteServerStorage> Function() storageGetter,
    required QueueMetadataUpdatesCallback onMetadata,
    int concurrency = 3,
  })  : _db = db,
        _storageGetter = storageGetter,
        _onMetadata = onMetadata,
        _concurrency = concurrency;

  final MetadataDatabase _db;
  final Future<RemoteServerStorage> Function() _storageGetter;
  final QueueMetadataUpdatesCallback _onMetadata;
  final int _concurrency;

  /// 待解析曲目（保持入队顺序），[_queued] 负责去重，避免重复入队重复联网。
  final List<MusicFile> _pending = <MusicFile>[];
  final Set<String> _queued = <String>{};
  bool _pumping = false;
  bool _disposed = false;

  /// 收下一批曲目，只保留能走远程 range 读取的 WebDAV / SMB 路径。
  ///
  /// 非阻塞：调用方（队列后台处理器）不需要等待，解析进度自己回调。
  void enqueue(Iterable<MusicFile> songs) {
    if (_disposed) return;
    var added = 0;
    for (final song in songs) {
      final path = song.path;
      if (path.isEmpty) continue;
      final info = RemoteMediaResolver.parseUri(path);
      if (info == null) continue;
      if (info.type != RemoteServerType.webdav &&
          info.type != RemoteServerType.smb) {
        continue;
      }
      if (!MusicFileUtils.isMusicFilePath(info.trackIdOrPath)) continue;
      if (_queued.add(path)) {
        _pending.add(song);
        added++;
      }
    }
    if (added > 0) unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_pumping || _disposed) return;
    _pumping = true;
    try {
      while (_pending.isNotEmpty && !_disposed) {
        final batch = <MusicFile>[];
        while (batch.length < _concurrency && _pending.isNotEmpty) {
          batch.add(_pending.removeAt(0));
        }
        await Future.wait(batch.map(_process));
        // 让出事件循环，保证回写 UI 的 setState / notifyListeners 能及时排上。
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _process(MusicFile song) async {
    if (_disposed) return;
    final path = song.path;
    final stopwatch = Stopwatch()..start();
    try {
      final info = RemoteMediaResolver.parseUri(path);
      if (info == null) return;

      // 1) 数据库里已经有解析结果就只用缓存回填，不再联网。
      final existing = await _db.getSongMetadata(path);
      if (_alreadyParsed(existing)) {
        final cachedUpdates = _updatesFromMetadata(existing!);
        if (cachedUpdates.isNotEmpty) _onMetadata(path, cachedUpdates);
        return;
      }

      final storage = await _storageGetter();
      final server = storage.loadServers().cast<RemoteServer?>().firstWhere(
            (s) => s?.id == info.serverId,
            orElse: () => null,
          );
      if (server == null) {
        debugPrint(
          '[RemoteQueueMetadata] server ${info.serverId} not found for $path',
        );
        return;
      }
      if (_disposed) return;

      final password = await storage.getPassword(server.id) ?? '';
      final targetPath = info.trackIdOrPath;
      final metadata = await RemoteMetadataHelper.fetchSongMetadata(
        file: WebDavFile(
          path: targetPath,
          name: p.basename(targetPath),
          isDirectory: false,
          contentLength: 0,
        ),
        server: server,
        password: password,
        sourceFlags: SongSourceFlags.remote,
      );
      if (metadata == null || _disposed) return;

      final updates = _updatesFromMetadata(metadata);
      if (updates.isNotEmpty) _onMetadata(path, updates);
      AppLog.log(
        '[RemoteQueueMetadata] parsed in ${stopwatch.elapsedMilliseconds}ms: $path',
        mirrorToConsole: true,
      );
    } catch (e) {
      AppLog.log(
        '[RemoteQueueMetadata] parse failed for $path: $e',
        mirrorToConsole: true,
      );
    }
  }

  /// 判断库里这条记录是否已经解析过，避免每次队列变动都重新联网读同一首。
  ///
  /// `metadataTextScanned` 是新数据（本次改动后由 [RemoteMetadataHelper] 写入），
  /// `metadataImgScanned` 覆盖历史数据（老版本只在成功解析后写它）。
  static bool _alreadyParsed(SongMetadata? meta) {
    if (meta == null) return false;
    if (meta.metadataTextScanned != null) return true;
    if (meta.metadataImgScanned != null) return true;
    return meta.duration != null && meta.thumbnailPath != null;
  }

  Map<String, dynamic> _updatesFromMetadata(SongMetadata meta) {
    return <String, dynamic>{
      if (meta.title.isNotEmpty) 'title': meta.title,
      if (meta.artist.isNotEmpty &&
          meta.artist != 'Unknown Artist' &&
          meta.artist != 'Unknown')
        'artist': meta.artist,
      if (meta.album.isNotEmpty &&
          meta.album != 'Unknown Album' &&
          meta.album != 'Unknown')
        'album': meta.album,
      if (meta.trackNumber != null) 'trackNumber': meta.trackNumber,
      if (meta.duration != null) 'durationMillis': meta.duration,
      if (meta.thumbnailPath != null) 'thumbnailPath': meta.thumbnailPath,
      if (meta.artworkPath != null) 'artworkPath': meta.artworkPath,
      if (meta.artworkWidth != null) 'artworkWidth': meta.artworkWidth,
      if (meta.artworkHeight != null) 'artworkHeight': meta.artworkHeight,
      if (meta.themeColorsBlob != null) 'themeColorsBlob': meta.themeColorsBlob,
    };
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    _queued.clear();
  }
}
