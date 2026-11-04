import 'dart:io';

import 'package:audio_core/audio_core.dart' show AppleFileAccessHolder;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// 一次安全作用域占用。由 [AppleFileAccess.hold] 返回，只能释放自己那一份。
class AppleFileAccessLease {
  AppleFileAccessLease._({
    required this.path,
    required this.holder,
    required this.granted,
    required bool actuallyAcquired,
  }) : _actuallyAcquired = actuallyAcquired;

  /// 本次占用的路径（已规范化）。
  final String path;

  /// 占用的持有者标识，见 [AppleFileAccessHolder]。
  final String holder;

  /// 本次是否真的拿到了系统作用域。
  ///
  /// `false` 不代表失败：路径本来就在可访问范围内（沙盒容器、LaunchServices
  /// 给的临时扩展）时 `startAccessingSecurityScopedResource()` 天然返回 false，
  /// 系统没有为此增加引用计数，我们也就不能去减。
  final bool granted;

  /// 本次是否由自己真正 begin 过。去重命中时为 false。
  final bool _actuallyAcquired;

  bool _released = false;

  /// 释放本次占用。幂等。
  ///
  /// 只有真正 begin 成功过的租约才会下发 `endScopedAccess`，否则会把别的
  /// 调用方（或别的 holder）的计数减掉 —— 这正是原生改成按 holder 分账要防的事。
  Future<void> release() async {
    if (_released || !_actuallyAcquired) return;
    _released = true;
    AppleFileAccess._held.removeWhere((_, lease) => identical(lease, this));
    await AppleFileAccess._releaseRaw(path, holder);
  }
}

/// 苹果平台安全作用域（security-scoped resource）的**唯一** Dart 入口。
///
/// 原生只暴露 `beginScopedAccess` / `endScopedAccess` / `registerPersistentAccess`
/// 三个动作，本类把它们包成租约，调用方拿不到裸通道：
///
/// - **常驻租约** [hold]：同一 `(路径, holder)` 只真正 begin 一次，重复调用直接
///   复用已有占用（返回的租约 `_actuallyAcquired == false`，`release()` 是 no-op）。
/// - **瞬态租约** [withRead] / [withWrite]：begin/end 在 finally 内成对，不进登记表，
///   所以能和常驻租约叠加（原生侧各自计数）。
///
/// 为什么必须去重：原生只能计数，分不清「第二次 begin 是同一次占用的重入」。
/// 分享链路在初始化、可写性检查、接收请求三处都对同一个目录 begin 过，而真正的
/// 释放只发生在传输结束时一次，计数永远回不到零。
abstract final class AppleFileAccess {
  static const MethodChannel _channel = MethodChannel('audio_core.player');

  static bool get isSupported => Platform.isIOS || Platform.isMacOS;

  /// 已持有的常驻租约，key 为 `holder|规范化路径`。
  static final Map<String, AppleFileAccessLease> _held =
      <String, AppleFileAccessLease>{};

  /// 正在申请中的占用，避免并发重复 begin。
  static final Map<String, Future<AppleFileAccessLease>> _pending =
      <String, Future<AppleFileAccessLease>>{};

  static String _key(String holder, String path) => '$holder|$path';

  static String _normalize(String path) {
    if (path.isEmpty) return path;
    // 与原生侧一致：去掉尾部分隔符，折叠 `.` / `..`，避免同一目录两种写法
    // 在登记表里各占一条。
    final normalized = p.normalize(path);
    return normalized.length > 1 && normalized.endsWith(p.separator)
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  /// 申请一次常驻占用；同一 `(路径, holder)` 重复申请是 no-op。
  ///
  /// begin 失败时会先登记持久授权再重试一次（首次选目录、重启后恢复都走这条）。
  static Future<AppleFileAccessLease> hold({
    required String path,
    required String holder,
  }) {
    final normalized = _normalize(path);
    final key = _key(holder, normalized);

    final existing = _held[key];
    if (existing != null) return Future.value(_dedupedView(normalized, holder));

    // 并发申请（初始化与可写性检查同时跑）也必须只 begin 一次：
    // 原生只计数，两次 begin 就是两份额度，而释放只会发生一次。
    final inFlight = _pending[key];
    if (inFlight != null) {
      return inFlight.then((_) => _dedupedView(normalized, holder));
    }

    final future = _acquire(normalized, holder, key);
    _pending[key] = future;
    future.whenComplete(() => _pending.remove(key));
    return future;
  }

  static Future<AppleFileAccessLease> _acquire(
    String normalized,
    String holder,
    String key,
  ) async {
    if (!isSupported) {
      // 非苹果平台没有 scope 概念，占用恒为成功且无需释放。
      final lease = AppleFileAccessLease._(
        path: normalized,
        holder: holder,
        granted: true,
        actuallyAcquired: false,
      );
      _held[key] = lease;
      return lease;
    }

    var granted = await _beginRaw(normalized, holder);
    if (!granted) {
      await registerPersistent(normalized);
      granted = await _beginRaw(normalized, holder);
    }

    final lease = AppleFileAccessLease._(
      path: normalized,
      holder: holder,
      granted: granted,
      actuallyAcquired: granted,
    );
    _held[key] = lease;
    return lease;
  }

  /// 已有占用的「借用视图」：不计额度，因此释放它是 no-op。
  static AppleFileAccessLease _dedupedView(String path, String holder) {
    final existing = _held[_key(holder, path)];
    return AppleFileAccessLease._(
      path: path,
      holder: holder,
      granted: existing?.granted ?? false,
      actuallyAcquired: false,
    );
  }

  /// 释放某个 holder 名下的全部常驻占用（切换目录、关闭功能时用）。
  static Future<void> releaseAll({required String holder}) async {
    final keys = _held.entries
        .where((entry) => entry.value.holder == holder)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in keys) {
      final lease = _held.remove(key);
      if (lease != null) await lease.release();
    }
  }

  /// 当前 holder 是否已经持有该路径。
  static bool isHeld({required String path, required String holder}) =>
      _held.containsKey(_key(holder, _normalize(path)));

  /// 瞬态读租约：只覆盖 [body] 执行期间。
  static Future<T> withRead<T>(String path, Future<T> Function() body) =>
      _withTransient(<String>[path], AppleFileAccessHolder.fallback, body);

  /// 瞬态写租约：覆盖若干路径的写入过程（写标签、转码输出等）。
  ///
  /// 与 [hold] 不同，这里不做去重 —— 必须和 [body] 严格成对，否则会和常驻占用串账。
  static Future<T> withWrite<T>(
    Iterable<String> paths,
    Future<T> Function() body,
  ) => _withTransient(paths, AppleFileAccessHolder.fallback, body);

  static Future<T> _withTransient<T>(
    Iterable<String> paths,
    String holder,
    Future<T> Function() body,
  ) async {
    if (!isSupported) return body();

    final acquired = <String>[];
    try {
      for (final raw in paths) {
        if (raw.isEmpty) continue;
        final path = _normalize(raw);
        if (await _beginRaw(path, holder)) {
          acquired.add(path);
        }
      }
      return await body();
    } finally {
      for (final path in acquired) {
        await _releaseRaw(path, holder);
      }
    }
  }

  /// 登记持久授权（bookmark），不做占用。
  static Future<bool> registerPersistent(String path) async {
    if (!isSupported || path.isEmpty) return true;
    try {
      final result = await _channel.invokeMethod<bool>(
        'registerPersistentAccess',
        <String, Object?>{'path': _normalize(path)},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[AppleFileAccess] registerPersistentAccess failed: $e');
      return false;
    }
  }

  /// 弹系统目录选择器并当场拿到授权（目前仅 iOS 走原生）。
  ///
  /// 返回 `denied == true` 表示用户选了目录但系统没给可用 scope，调用方应把
  /// 它当成「授权失败」而不是「用户取消」—— 否则目录会被加进曲库却扫出 0 首。
  static Future<({String? path, bool denied})> pickAndAuthorizeDirectory() async {
    if (!Platform.isIOS) {
      return (path: null, denied: false);
    }
    try {
      final path = await _channel.invokeMethod<String>(
        'pickAndAuthorizeDirectory',
      );
      return (path: path, denied: false);
    } on PlatformException catch (e) {
      debugPrint('[AppleFileAccess] pickAndAuthorizeDirectory failed: $e');
      return (path: null, denied: e.code == 'DIRECTORY_ACCESS_DENIED');
    } catch (e) {
      debugPrint('[AppleFileAccess] pickAndAuthorizeDirectory failed: $e');
      return (path: null, denied: false);
    }
  }

  static Future<bool> _beginRaw(String path, String holder) async {
    if (!isSupported) return true;
    try {
      final result = await _channel.invokeMethod<bool>(
        'beginScopedAccess',
        <String, Object?>{'path': path, 'holder': holder},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[AppleFileAccess] beginScopedAccess failed for $path: $e');
      return false;
    }
  }

  static Future<void> _releaseRaw(String path, String holder) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(
        'endScopedAccess',
        <String, Object?>{'path': path, 'holder': holder},
      );
    } catch (_) {}
  }

  /// 清空进程内的登记表（仅测试用）。
  @visibleForTesting
  static void resetForTest() {
    _held.clear();
    _pending.clear();
  }
}
