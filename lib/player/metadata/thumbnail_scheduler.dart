import 'dart:async';
import 'dart:io';

import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';

/// 缩略图解析的**全局**并发闸门。
///
/// 扫描侧的 `ScannerMetadataStore.loadThumbnailForPath` 和浏览侧的
/// `ArtworkResolver.resolveForThumbnail` 跑的是同一种活。两边各自维护计数器时，
/// 实际并发是两份叠起来（2 + 3 = 5），正在播放的歌同时出现在队列窗口和专辑页时，
/// 同一首歌会被两边先后各解析一遍。名额收敛到这里之后，两侧共用同一组槽位。
///
/// 取值依据：
/// - **本地文件**：`clamp(cores ~/ 2, 2, 4)`。留一半核心给 UI 与音频线程；
///   上限压到 4 是内存约束 —— 一张 3000² 封面解码成 RGBA 约 36MB，
///   按核心数全开在移动端会顶到 OOM 阈值。
/// - **远程文件**：固定 2。SMB / WebDAV 走连接池，并发读高了自己抢带宽，
///   反而是同时变慢。
///
/// 注意这里只管「同时在飞多少个任务」，不管单任务内部。真正的解码 / 缩放 /
/// 调色板提取在 Rust 侧 `generateTrackArtwork` 里，并行度由 Rust 线程池决定；
/// Dart 侧开得再大也只是把 Rust 的排队队列拉长、把内存峰值抬高。
class ThumbnailScheduler {
  ThumbnailScheduler._();

  static final ThumbnailScheduler instance = ThumbnailScheduler._();

  static const int minLocalLimit = 2;
  static const int maxLocalLimit = 4;
  static const int remoteLimit = 2;

  /// 本地文件的并发上限，进程生命周期内固定。
  static final int localLimit = _computeLocalLimit();

  static int _computeLocalLimit() {
    final half = Platform.numberOfProcessors ~/ 2;
    if (half < minLocalLimit) return minLocalLimit;
    if (half > maxLocalLimit) return maxLocalLimit;
    return half;
  }

  final _SlotPool _localPool = _SlotPool(localLimit);
  final _SlotPool _remotePool = _SlotPool(remoteLimit);

  _SlotPool _poolFor(bool remote) => remote ? _remotePool : _localPool;

  /// 该路径是否走远程槽位。
  static bool isRemote(String path) => RemoteMediaResolver.isRemoteUri(path);

  /// 取得一个执行名额。必须在 `finally` 里配对调用 [release]。
  Future<void> acquire({required bool remote}) => _poolFor(remote).acquire();

  void release({required bool remote}) => _poolFor(remote).release();

  /// 自动取还名额地执行一次缩略图解析。
  Future<T> run<T>({
    required bool remote,
    required Future<T> Function() task,
  }) async {
    await acquire(remote: remote);
    try {
      return await task();
    } finally {
      release(remote: remote);
    }
  }
}

/// 固定上限的名额池。释放时把名额**直接移交**给队首等待者（`_active` 不变），
/// 避免「先减后加」之间被新来的任务抢走，导致瞬时并发超出上限。
class _SlotPool {
  _SlotPool(this.limit) : assert(limit > 0);

  final int limit;
  int _active = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  Future<void> acquire() {
    if (_active < limit) {
      _active++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else if (_active > 0) {
      _active--;
    }
  }
}
