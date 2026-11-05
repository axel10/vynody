import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audio_core/audio_core.dart' show AppleFileAccessHolder;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:vynody/player/metadata/remote_song_matcher.dart';
import 'package:vynody/player/platform/apple_file_access.dart';
import 'package:flutter/services.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:bonsoir/bonsoir.dart';
import 'lan_device.dart';
import 'lan_sync_history.dart';
import 'lan_sync_models.dart';
import 'lan_sync_progress.dart';
import 'lan_sync_protocol.dart';
import 'lyrics_import_conflict.dart';
import 'lyrics_package_importer.dart';
import 'sharing_riverpod.dart';
import 'remote_control/remote_control_service.dart';
import 'security/tls_certificate_service.dart';
import 'package:vynody/main.dart';
import 'package:vynody/dialogs/transfer_dialogs.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/utils/m3u_utils.dart';

// 这些类型原来定义在本文件里，抽到 `lan_sync_models.dart` 之后依然从这里
// 可见 —— 外部一直是 `import sharing_service.dart` 取 LanSyncReceipt 等类型，
// 不想为了搬文件让几十处 import 一起改。
export 'lan_sync_models.dart';
export 'lan_sync_progress.dart';

/// Formats an IP address or hostname for use in HTTP URLs.
/// If [host] is an IPv6 address containing colons and not already enclosed in brackets,
/// it will be returned enclosed in brackets, e.g. `[fe80::1]`.
String formatHostForUrl(String host) {
  if (host.contains(':') && !host.startsWith('[')) {
    return '[$host]';
  }
  return host;
}

// Riverpod states for UI communication

/// 待确认请求的排队基类。
///
/// 三条链路原先各是一个单槽 `Notifier<T?>`：两台设备同时推过来时，后一条
/// 直接覆盖前一条，前一条的 `Completer` 永远不会完成，那条 HTTP 请求会一直挂到
/// 连接层超时（用户看到「对方没反应」）。
///
/// 这里改成队列：`state` 始终是**队首**，UI 的 `ref.listen` 不用改；处理完一条
/// 用 `setRequest(null)` 出队，下一条自动顶上。排太久的自动按拒绝处理，避免
/// 发送端一直等。
abstract class QueuedIncomingRequestNotifier<T> extends Notifier<T?> {
  /// 请在发送端的读超时之前过期：否则发送端已经放弃了，这边还弹着对话框，
  /// 用户点「接受」后对面已经不在等这份回执。
  static const Duration requestTtl = Duration(seconds: 30);

  final List<({T request, DateTime enqueuedAt})> _pending = [];
  Timer? _expiryTimer;

  @override
  T? build() {
    ref.onDispose(() {
      _expiryTimer?.cancel();
      _expiryTimer = null;
    });
    return _pending.isEmpty ? null : _pending.first.request;
  }

  /// 入队一个请求；传 null 表示队首已有结论，出队并让下一条顶上来。
  void setRequest(T? request) {
    if (request != null) {
      _pending.add((request: request, enqueuedAt: DateTime.now()));
      _ensureExpiryTimer();
      _sync();
      return;
    }
    if (_pending.isNotEmpty) _pending.removeAt(0);
    _sync();
  }

  /// 超时或连接断开时由外部调用，等价于用户拒绝。
  void rejectAllPending() {
    if (_pending.isEmpty) return;
    final pending = List.of(_pending);
    _pending.clear();
    for (final entry in pending) {
      rejectExpired(entry.request);
    }
    _sync();
  }

  /// 该请求因超时被判为拒绝时怎么通知发起方。
  void rejectExpired(T request);

  void _sync() {
    final next = _pending.isEmpty ? null : _pending.first.request;
    if (!identical(state, next)) {
      state = next;
    }
    if (_pending.isEmpty) {
      _expiryTimer?.cancel();
      _expiryTimer = null;
    }
  }

  void _ensureExpiryTimer() {
    _expiryTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (_pending.isEmpty) return;
      final deadline = DateTime.now().subtract(requestTtl);

      // 只处理队首：队首是用户此刻看到的那条。排队的其它条目过期没有意义，
      // 而且乱序出队会让回调里的 `setRequest(null)` 弹错一条。
      final head = _pending.first;
      if (!head.enqueuedAt.isBefore(deadline)) return;

      rejectExpired(head.request);
      // 回调通常会自己 `setRequest(null)` 出队；没出队就兜底移除。
      if (_pending.isNotEmpty && identical(_pending.first.request, head.request)) {
        _pending.removeAt(0);
        _sync();
      }
    });
  }
}

class IncomingRequestNotifier
    extends QueuedIncomingRequestNotifier<IncomingTransferRequest> {
  @override
  void rejectExpired(IncomingTransferRequest request) =>
      request.onDecision(false);
}

final incomingRequestProvider =
    NotifierProvider<IncomingRequestNotifier, IncomingTransferRequest?>(
      IncomingRequestNotifier.new,
    );

enum IncomingLyricsRequestType { importLyrics, exportLyrics }

class IncomingLyricsRequest {
  final String senderId;
  final String senderName;
  final IncomingLyricsRequestType type;
  final int lyricsCount;
  final void Function(bool accepted) onDecision;

  IncomingLyricsRequest({
    required this.senderId,
    required this.senderName,
    required this.type,
    this.lyricsCount = 0,
    required this.onDecision,
  });
}

class IncomingLyricsRequestNotifier
    extends QueuedIncomingRequestNotifier<IncomingLyricsRequest> {
  @override
  void rejectExpired(IncomingLyricsRequest request) =>
      request.onDecision(false);
}

final incomingLyricsRequestProvider =
    NotifierProvider<IncomingLyricsRequestNotifier, IncomingLyricsRequest?>(
      IncomingLyricsRequestNotifier.new,
    );

enum IncomingPlaylistRequestType { importPlaylists, exportPlaylists }

class IncomingPlaylistRequest {
  final String senderId;
  final String senderName;
  final IncomingPlaylistRequestType type;
  final int playlistCount;
  final int songsCount;
  final void Function(bool accepted) onDecision;

  IncomingPlaylistRequest({
    required this.senderId,
    required this.senderName,
    required this.type,
    this.playlistCount = 0,
    this.songsCount = 0,
    required this.onDecision,
  });
}

class IncomingPlaylistRequestNotifier
    extends QueuedIncomingRequestNotifier<IncomingPlaylistRequest> {
  @override
  void rejectExpired(IncomingPlaylistRequest request) =>
      request.onDecision(false);
}

final incomingPlaylistRequestProvider =
    NotifierProvider<
      IncomingPlaylistRequestNotifier,
      IncomingPlaylistRequest?
    >(IncomingPlaylistRequestNotifier.new);

/// 分块接收的临时会话。
///
/// 只在内存里，靠 [LanSyncLimits.chunkSessionTtl] 回收：发送端中途放弃时，
/// 半截数据不能一直留着占内存。
class _LanChunkSession {
  _LanChunkSession({required this.totalChunks, required this.senderId});

  final int totalChunks;
  final String senderId;
  final List<dynamic> items = [];
  final Set<int> receivedChunks = {};
  DateTime lastTouched = DateTime.now();
}

class SharingWarningNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setWarning(String? warning) {
    state = warning;
  }
}

final sharingWarningProvider =
    NotifierProvider<SharingWarningNotifier, String?>(
      SharingWarningNotifier.new,
    );

class ActiveTransfersNotifier extends Notifier<List<TransferSession>> {
  @override
  List<TransferSession> build() => [];

  int _lastNotifyMs = 0;

  void addSession(TransferSession session) {
    state = [session, ...state];
  }

  void updateProgress(
    String id,
    int bytesTransferred, {
    TransferStatus? status,
    int? completedFilesCount,
    List<ActiveFileProgress>? activeFiles,
    bool force = false,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final isTerminal = status == TransferStatus.success ||
        status == TransferStatus.failed ||
        status == TransferStatus.cancelled;

    // Throttle high-frequency progress updates during transfer to 100ms unless terminal, status change, or forced
    if (!force && !isTerminal && status == null && (nowMs - _lastNotifyMs < 100)) {
      return;
    }
    _lastNotifyMs = nowMs;

    state = [
      for (final s in state)
        if (s.id == id)
          s.copyWith(
            bytesTransferred: bytesTransferred,
            status: status ?? s.status,
            completedFilesCount: completedFilesCount ?? s.completedFilesCount,
            activeFiles: activeFiles ?? s.activeFiles,
          )
        else
          s,
    ];
  }

  void updateStatus(String id, TransferStatus status, {String? cancelReason}) {
    state = [
      for (final s in state)
        if (s.id == id)
          s.copyWith(status: status, cancelReason: cancelReason)
        else
          s,
    ];
  }

  void clearCompleted() {
    state = state
        .where(
          (s) =>
              s.status == TransferStatus.transferring ||
              s.status == TransferStatus.pending,
        )
        .toList();
  }
}

final activeTransfersProvider =
    NotifierProvider<ActiveTransfersNotifier, List<TransferSession>>(
      ActiveTransfersNotifier.new,
    );

class IncomingTransferRequest {
  final String senderId;
  final String senderName;
  final List<TransferFileItem> files;
  final void Function(bool accepted) onDecision;

  IncomingTransferRequest({
    required this.senderId,
    required this.senderName,
    required this.files,
    required this.onDecision,
  });
}

class TransferFileItem {
  final String name;
  final int size;
  final int durationMs;
  final String? title;
  final String? artist;
  final String? album;
  final Map<String, dynamic>? lyricsPackage;

  TransferFileItem({
    required this.name,
    required this.size,
    required this.durationMs,
    this.title,
    this.artist,
    this.album,
    this.lyricsPackage,
  });
}

/// 文件传输会话的状态。
///
/// [indexing] 是「字节已经收完、但扫描器还没把这些文件读进库」这段窗口：
/// 旧实现直接在落盘后立刻标 success，用户点开曲库搜不到刚传的歌，得等下一次
/// 全库扫描。现在这个状态让进度框多停一会儿，同时把扫描改成只扫新增目录。
enum TransferStatus { pending, transferring, indexing, success, failed, cancelled }

class ActiveFileProgress {
  final String fileName;
  final int bytesTransferred;
  final int totalBytes;

  ActiveFileProgress({
    required this.fileName,
    required this.bytesTransferred,
    required this.totalBytes,
  });

  double get progress => totalBytes > 0 ? bytesTransferred / totalBytes : 0.0;
}

class TransferSession {
  final String id;
  final String fileName;
  final int totalBytes;
  final int bytesTransferred;
  final bool isSending; // true = upload/send, false = download/receive
  final String deviceName;
  final TransferStatus status;
  final int? filesCount;
  final int? completedFilesCount;
  final List<ActiveFileProgress> activeFiles;
  final String? cancelReason;

  TransferSession({
    required this.id,
    required this.fileName,
    required this.totalBytes,
    required this.bytesTransferred,
    required this.isSending,
    required this.deviceName,
    required this.status,
    this.filesCount,
    this.completedFilesCount,
    this.activeFiles = const [],
    this.cancelReason,
  });

  double get progress => totalBytes > 0 ? bytesTransferred / totalBytes : 0.0;

  TransferSession copyWith({
    String? id,
    String? fileName,
    int? totalBytes,
    int? bytesTransferred,
    bool? isSending,
    String? deviceName,
    TransferStatus? status,
    int? filesCount,
    int? completedFilesCount,
    List<ActiveFileProgress>? activeFiles,
    String? cancelReason,
  }) {
    return TransferSession(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      isSending: isSending ?? this.isSending,
      deviceName: deviceName ?? this.deviceName,
      status: status ?? this.status,
      filesCount: filesCount ?? this.filesCount,
      completedFilesCount: completedFilesCount ?? this.completedFilesCount,
      activeFiles: activeFiles ?? this.activeFiles,
      cancelReason: cancelReason ?? this.cancelReason,
    );
  }
}

// ActiveTransfersNotifier relocated to top of file

class SharingService {
  final Ref _ref;

  HttpServer? _httpServer;
  BonsoirBroadcast? _bonsoirBroadcast;
  BonsoirDiscovery? _bonsoirDiscovery;
  TlsCertificateService? _tlsCertService;

  String? _localIp;
  int? _httpPort;
  String _deviceId = '';
  String _deviceName = 'Unknown Device';
  String _deviceType = 'unknown';
  String _sharingFolderPath = '';

  final Map<String, _UploadRequestMetadata> _activeTokens = {};

  final Map<String, List<HttpClientRequest>> _currentUploadRequests = {};
  final Map<String, List<HttpRequest>> _currentReceiverRequests = {};

  /// 进行中的分块接收会话，键为 `senderId/transferId`。
  final Map<String, _LanChunkSession> _lyricsChunkSessions = {};
  final Map<String, _LanChunkSession> _playlistChunkSessions = {};

  /// 同一目标设备上正在跑的同步任务，键为 `kind/deviceId`。
  ///
  /// 只用来防重复点击，不做排队：重复发起直接报「正在进行中」，比并发跑两份
  /// 各写一遍数据安全得多。
  final Map<String, Future<void>> _inFlightSyncs = {};

  /// 接收方向的进度心跳定时器（见 [_armIncomingProgressTimeout]）。
  Timer? _incomingProgressTimer;

  void cancelTransfer(String sessionId) {
    debugPrint(
      '[SharingService] cancelTransfer called for session: $sessionId',
    );
    _ref
        .read(activeTransfersProvider.notifier)
        .updateStatus(sessionId, TransferStatus.cancelled);

    // Abort sender requests if any
    final sendReqs = _currentUploadRequests[sessionId];
    if (sendReqs != null) {
      debugPrint(
        '[SharingService] Aborting sender upload requests for session: $sessionId',
      );
      for (final req in List.from(sendReqs)) {
        try {
          req.abort();
        } catch (e) {
          debugPrint('[SharingService] Error aborting sender request: $e');
        }
      }
      _currentUploadRequests.remove(sessionId);
    }

    // Abort receiver requests if any
    final recvReqs = _currentReceiverRequests[sessionId];
    if (recvReqs != null) {
      debugPrint(
        '[SharingService] Aborting receiver upload requests for session: $sessionId',
      );
      for (final req in List.from(recvReqs)) {
        try {
          req.response.statusCode = HttpStatus.internalServerError;
          req.response.close();
        } catch (e) {
          debugPrint('[SharingService] Error aborting receiver request: $e');
        }
      }
      _currentReceiverRequests.remove(sessionId);
    }
  }

  void _checkAndResumeScanner({bool triggerScan = true}) {
    if (_activeTokens.isNotEmpty) return;
    _ref
        .read(scannerServiceProvider)
        .resumeMediaObserver(triggerScan: triggerScan);
  }

  /// 传输收尾：只让扫描器重扫这次写入了文件的目录。
  ///
  /// 返回 false 表示「没有可增量的目录」（比如所有文件都被跳过），调用方
  /// 需要退回全量扫描。
  Future<bool> _ingestReceivedDirectories(_UploadRequestMetadata metadata) async {
    final scanner = _ref.read(scannerServiceProvider);
    final directories = metadata.receivedDirectories
        .where((dir) => dir.isNotEmpty)
        .toList(growable: false);
    if (directories.isEmpty) return false;

    for (final directory in directories) {
      try {
        await scanner.rescanDirectory(directory);
      } catch (e) {
        debugPrint(
          '[SharingService] Failed to rescan directory "$directory": $e',
        );
        return false;
      }
    }
    return true;
  }

  /// 文件全部落盘后的后台收尾：增量扫描 → 标记成功 → 恢复媒体观察者。
  ///
  /// 放在 `unawaited` 里跑，是为了不把最后一个上传请求拖到扫描结束：
  /// 发送端读超时只有 45 秒，大文件目录的入库可能更久。
  Future<void> _finalizeReceivedFiles(
    String sessionId,
    _UploadRequestMetadata metadata,
  ) async {
    var incremental = false;
    try {
      incremental = await _ingestReceivedDirectories(metadata);
    } catch (e) {
      debugPrint('[SharingService] Ingest failed, falling back to full scan: $e');
    }

    _ref
        .read(activeTransfersProvider.notifier)
        .updateProgress(
          sessionId,
          metadata.totalSize,
          status: TransferStatus.success,
          completedFilesCount: metadata.completedFiles.length,
          activeFiles: [],
        );

    // 增量扫描成功就不要再触发整库扫描；失败/没目录时退回旧行为。
    _checkAndResumeScanner(triggerScan: !incremental);
  }

  // Discovered devices list managed locally, updated to UI via Riverpod
  final StreamController<List<LanDevice>> _devicesController =
      StreamController<List<LanDevice>>.broadcast();
  final Map<String, LanDevice> _discoveredDevicesMap = {};

  SharingService(this._ref);

  Stream<List<LanDevice>> get discoveredDevicesStream =>
      _devicesController.stream;
  List<LanDevice> get discoveredDevices =>
      _discoveredDevicesMap.values.toList();

  String get deviceId => _deviceId;
  String? get localIp => _localIp;
  int? get httpPort => _httpPort;
  String get deviceName => _deviceName;
  String get deviceType => _deviceType;
  String get sharingFolderPath => _sharingFolderPath;

  Future<void> init() async {
    // 0. Initialize TLS Certificate Service
    _tlsCertService = _ref.read(tlsCertificateServiceProvider);
    await _tlsCertService!.initialize();

    // 1. Load or Generate Device ID
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('lan_share_device_id') ?? '';
    if (_deviceId.isEmpty) {
      _deviceId =
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1000000)}';
      await prefs.setString('lan_share_device_id', _deviceId);
    }

    // 2. Resolve Device Type and Name
    _deviceType = Platform.operatingSystem;
    _ref.read(
      scannerServiceProvider,
    ); // Make sure scanner service provider is referenced/initialized

    // We can query device name from Platform or standard system environment
    _deviceName = Platform.localHostname;
    try {
      if (Platform.isMacOS) {
        _deviceName = Platform.localHostname.replaceAll('.local', '');
      } else if (Platform.isWindows) {
        _deviceName =
            Platform.environment['COMPUTERNAME'] ?? Platform.localHostname;
      } else if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        if (androidInfo.brand.isNotEmpty &&
            !androidInfo.model.toLowerCase().startsWith(
              androidInfo.brand.toLowerCase(),
            )) {
          _deviceName = '${androidInfo.brand} ${androidInfo.model}';
        } else {
          _deviceName = androidInfo.model;
        }
      } else if (Platform.isIOS) {
        final deviceInfo = DeviceInfoPlugin();
        final iosInfo = await deviceInfo.iosInfo;
        _deviceName = iosInfo.name;
      }
    } catch (_) {}

    // 3. Resolve Sharing Path
    await _resolveSharingPath();
  }

  /// 分享目录的常驻占用。
  ///
  /// 走 [AppleFileAccess.hold]，同一目录重复申请只会真正 begin 一次 —— 之前
  /// 初始化、可写性检查、接收请求三处各 begin 一次而只在传输结束时释放一次，
  /// 计数只会越来越大，目录被删掉之后那份 scope 就一直悬着。
  Future<AppleFileAccessLease> _holdSharingFolder(String path) =>
      AppleFileAccess.hold(
        path: path,
        holder: AppleFileAccessHolder.sharing,
      );

  Future<void> _resolveSharingPath() async {
    String basePath = '';
    final settings = _ref.read(settingsServiceProvider);
    final savedPath = settings.lanSharingFolderPath;

    if (savedPath.isNotEmpty) {
      basePath = savedPath;
    } else {
      if (Platform.isIOS || Platform.isAndroid) {
        final docDir = await getApplicationDocumentsDirectory();
        basePath = p.join(docDir.path, 'Vynody Music');
      } else if (Platform.isMacOS) {
        basePath = p.join(
          Platform.environment['HOME'] ?? '',
          'Music',
          'Vynody Music',
        );
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'] ?? '';
        basePath = p.join(userProfile, 'Music', 'Vynody Music');
      } else {
        basePath = p.join(
          Platform.environment['HOME'] ?? '',
          'Music',
          'Vynody Music',
        );
      }
    }

    _sharingFolderPath = basePath;

    if (_sharingFolderPath.isNotEmpty) {
      await _holdSharingFolder(_sharingFolderPath);
    }

    // Note: We intentionally do NOT create the directory here or register it in scanner upfront.
    // Directories will be created on-demand and registered in scanner when files are actually received.
  }

  Future<String> getDefaultSharingFolderPath() async {
    if (Platform.isIOS || Platform.isAndroid) {
      final docDir = await getApplicationDocumentsDirectory();
      return p.join(docDir.path, 'Vynody Music');
    } else if (Platform.isMacOS) {
      return p.join(
        Platform.environment['HOME'] ?? '',
        'Music',
        'Vynody Music',
      );
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      return p.join(userProfile, 'Music', 'Vynody Music');
    } else {
      return p.join(
        Platform.environment['HOME'] ?? '',
        'Music',
        'Vynody Music',
      );
    }
  }

  Future<void> resetSharingFolderPathToDefault() async {
    _ref.read(settingsServiceProvider).lanSharingFolderPath = '';
    await _resolveSharingPath();
  }

  Future<void> updateSharingFolderPath(String newPath) async {
    // 先放掉旧目录，再占用新目录：否则旧目录那份 scope 会一直开到这个进程结束。
    await AppleFileAccess.releaseAll(holder: AppleFileAccessHolder.sharing);
    if (newPath.isNotEmpty) {
      await _holdSharingFolder(newPath);
    }
    _ref.read(settingsServiceProvider).lanSharingFolderPath = newPath;
    _sharingFolderPath = newPath;
  }

  Future<bool> checkSharingFolderWritable([String? pathToCheck]) async {
    final target = pathToCheck ?? _sharingFolderPath;
    if (target.isEmpty) return false;

    // 常驻占用已覆盖分享目录时这里是 no-op；换了目录（例如用户刚手输路径）
    // 才真正 begin 一次并把结果留在这份占用上。
    await _holdSharingFolder(target);

    if (Platform.isAndroid) {
      final mapping = await AndroidSafStorageHelper.findBestMapping(target);
      if (mapping != null) {
        return await AndroidSafStorageHelper.directoryExists(mapping.value);
      }
    }

    try {
      final dir = Directory(target);
      if (!dir.existsSync()) {
        // Probe nearest existing ancestor directory to avoid preemptively creating empty directories.
        var checkDir = dir;
        while (!checkDir.existsSync() && checkDir.path != checkDir.parent.path) {
          checkDir = checkDir.parent;
        }
        final probeFile = File(
          p.join(
            checkDir.path,
            '.probe_write_${DateTime.now().microsecondsSinceEpoch}',
          ),
        );
        probeFile.writeAsStringSync('probe', flush: true);
        if (probeFile.existsSync()) {
          probeFile.deleteSync();
        }
        return true;
      }
      final probeFile = File(
        p.join(
          dir.path,
          '.probe_write_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      probeFile.writeAsStringSync('probe', flush: true);
      if (probeFile.existsSync()) {
        probeFile.deleteSync();
      }
      return true;
    } catch (e) {
      debugPrint('[SharingService] Directory $target write test failed: $e');
      return false;
    }
  }

  Future<void> _cleanObsoleteIosPaths() async {
    if (!Platform.isIOS) return;
    final scanner = _ref.read(scannerServiceProvider);
    await scanner.ready;

    // iOS app sandbox path contains a dynamic UUID that can change on each run/update.
    // Clean up obsolete sharing folders from previous launches.
    final obsoletePaths = scanner.rootPaths.where((path) {
      return !p.equals(path, _sharingFolderPath) &&
          (path.endsWith('/Documents/Vynody Music') ||
              path.endsWith('\\Documents\\Vynody Music'));
    }).toList();

    if (obsoletePaths.isNotEmpty) {
      debugPrint(
        '[SharingService] Removing obsolete iOS sharing folders: $obsoletePaths',
      );
      await scanner.removeRootPaths(obsoletePaths);
    }
  }

  Future<void> _ensureRegisteredInScanner() async {
    final scanner = _ref.read(scannerServiceProvider);
    await scanner.ready;

    if (!scanner.rootPaths.any((path) => p.equals(path, _sharingFolderPath))) {
      debugPrint(
        '[SharingService] Adding sharing folder to scanner: $_sharingFolderPath',
      );
      await scanner.addRootPath(_sharingFolderPath);
    }
  }

  Future<bool>? _startFuture;

  Future<bool> start() async {
    if (_httpServer != null) {
      return true;
    }
    if (_startFuture != null) {
      return _startFuture!;
    }
    final future = _startInternal();
    _startFuture = future;
    try {
      return await future;
    } finally {
      if (_startFuture == future) {
        _startFuture = null;
      }
    }
  }

  Future<bool> _startInternal() async {
    await init();
    await _cleanObsoleteIosPaths();

    // 1. Resolve Local IP
    _localIp = await _getLocalIpAddress();
    if (_localIp == null) {
      debugPrint('[SharingService] No valid local IPv4/IPv6 address found.');
      return false;
    }

    // 2. Start HTTPS Server on random port starting at 53536
    final secContext = _tlsCertService?.serverSecurityContext;
    if (secContext == null) {
      debugPrint('[SharingService] Failed to load SecurityContext for TLS.');
      return false;
    }

    int port = 53536;
    while (_httpServer == null && port < 53600) {
      try {
        // Try IPv6 dual-stack binding (v6Only: false allows accepting both IPv4 & IPv6 requests)
        _httpServer = await HttpServer.bindSecure(
          InternetAddress.anyIPv6,
          port,
          secContext,
          v6Only: false,
        );
        _httpPort = port;
        debugPrint(
          '[SharingService] Dual-stack HTTPS Server running on $_localIp:$_httpPort',
        );
      } catch (e) {
        try {
          // Fallback to IPv4-only binding if IPv6 dual-stack fails on this system
          _httpServer = await HttpServer.bindSecure(
            InternetAddress.anyIPv4,
            port,
            secContext,
          );
          _httpPort = port;
          debugPrint(
            '[SharingService] IPv4-only HTTPS Server running on $_localIp:$_httpPort',
          );
        } catch (e2) {
          port++;
        }
      }
    }

    if (_httpServer == null) {
      debugPrint('[SharingService] Failed to bind HTTPS Server.');
      return false;
    }

    _httpServer!.listen(_handleHttpRequest);

    // 3. Start Bonsoir Broadcast
    final service = BonsoirService(
      name: 'Vynody_$_deviceId',
      type: '_vynody-share._tcp',
      port: _httpPort!,
      attributes: {
        'id': _deviceId,
        'name': _deviceName,
        'deviceType': _deviceType,
        'version': '0.11.0',
        'proto': '2',
        // 分块 / gzip 的能力标志。老客户端不广播这个键，发送端就按 v1 的
        // 单请求格式发 —— `proto` 不能用，它从 TLS 那一版起就恒为 2。
        'sync': '$kLanSyncProtocolVersion',
        'tls': '1',
        if (_tlsCertService?.fingerprint != null) 'fp': _tlsCertService!.fingerprint!,
      },
    );
    _bonsoirBroadcast = BonsoirBroadcast(service: service, printLogs: false);
    try {
      await _bonsoirBroadcast!.initialize();
      await _bonsoirBroadcast!.start();
      debugPrint(
        '[SharingService] Bonsoir broadcast started: Vynody_$_deviceId on port $_httpPort (TLS fp: ${_tlsCertService?.fingerprint})',
      );
    } catch (e) {
      debugPrint('[SharingService] Bonsoir broadcast starting failed: $e');
    }

    // 4. Start Bonsoir Discovery
    _bonsoirDiscovery = BonsoirDiscovery(type: '_vynody-share._tcp');
    try {
      await _bonsoirDiscovery!.initialize();
      _bonsoirDiscovery!.eventStream!.listen((event) {
        if (_bonsoirDiscovery == null) return;

        if (event is BonsoirDiscoveryServiceFoundEvent) {
          debugPrint(
            '[SharingService] mDNS Service found: ${event.service.name}',
          );
          event.service.resolve(_bonsoirDiscovery!.serviceResolver);
        } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
          debugPrint(
            '[SharingService] mDNS Service resolved: ${event.service.name}',
          );
          final resolvedService = event.service;
          final attrs = resolvedService.attributes;

          final id =
              attrs['id'] ?? resolvedService.name.replaceFirst('Vynody_', '');
          if (id == _deviceId) {
            // Ignore self
            return;
          }

          final name = attrs['name'] ?? 'Unknown Device';
          final deviceType = attrs['deviceType'] ?? 'unknown';
          final httpPort = resolvedService.port;

          String? resolvedIp;
          // First pass: prefer IPv4 for highest network compatibility
          for (final addressStr in resolvedService.hostAddresses) {
            final addr = InternetAddress.tryParse(addressStr);
            if (addr != null && addr.type == InternetAddressType.IPv4) {
              resolvedIp = addressStr;
              break;
            }
          }
          // Second pass: if no IPv4 address found, use IPv6 address
          if (resolvedIp == null) {
            for (final addressStr in resolvedService.hostAddresses) {
              final addr = InternetAddress.tryParse(addressStr);
              if (addr != null && addr.type == InternetAddressType.IPv6) {
                resolvedIp = addressStr;
                break;
              }
            }
          }

          if (resolvedIp != null) {
            final certFingerprint = attrs['fp'] ?? attrs['certFingerprint'];

            // If this device was previously seen on a different IP, clean up the stale IP mapping
            final existingDevice = _discoveredDevicesMap[id];
            if (existingDevice != null && existingDevice.ip != resolvedIp) {
              TlsCertificateService.unregisterDeviceFingerprint(existingDevice.ip);
            }

            final device = LanDevice(
              id: id,
              name: name,
              deviceType: deviceType,
              httpPort: httpPort,
              ip: resolvedIp,
              lastSeen: DateTime.now(),
              isOnline: true,
              certFingerprint: certFingerprint,
              syncProtocol:
                  int.tryParse(attrs[kLanSyncCapabilityAttribute] ?? '') ?? 1,
            );
            if (certFingerprint != null && certFingerprint.isNotEmpty) {
              TlsCertificateService.registerDeviceFingerprint(id, certFingerprint);
              TlsCertificateService.registerDeviceFingerprint(resolvedIp, certFingerprint);
            }
            debugPrint(
              '[SharingService] Discovered/Updated device: ${device.name} ($resolvedIp) isOnline=${device.isOnline} fp=$certFingerprint',
            );
            _discoveredDevicesMap[id] = device;
            _devicesController.add(_discoveredDevicesMap.values.toList());
          }
        } else if (event is BonsoirDiscoveryServiceLostEvent) {
          debugPrint(
            '[SharingService] mDNS Service lost: ${event.service.name}',
          );
          final lostService = event.service;
          final id = lostService.name.replaceFirst('Vynody_', '');
          final isTrusted = _ref.read(trustedDevicesProvider).any((d) => d.id == id);
          if (!isTrusted) {
            final existingDevice = _discoveredDevicesMap[id];
            if (existingDevice != null) {
              TlsCertificateService.unregisterDeviceFingerprint(existingDevice.ip);
            }
            TlsCertificateService.unregisterDeviceFingerprint(id);
          }
          if (_discoveredDevicesMap.containsKey(id)) {
            final device = _discoveredDevicesMap[id]!;
            if (device.isOnline) {
              _discoveredDevicesMap[id] = device.copyWith(isOnline: false);
              _devicesController.add(_discoveredDevicesMap.values.toList());
            }
          }
        }
      });
      await _bonsoirDiscovery!.start();
      debugPrint('[SharingService] Bonsoir discovery started');
    } catch (e) {
      debugPrint('[SharingService] Bonsoir discovery starting failed: $e');
    }

    return true;
  }

  Future<void> stop() async {
    if (_bonsoirBroadcast != null) {
      try {
        await _bonsoirBroadcast!.stop();
      } catch (e) {
        debugPrint('[SharingService] Error stopping Bonsoir broadcast: $e');
      }
      _bonsoirBroadcast = null;
    }

    if (_bonsoirDiscovery != null) {
      try {
        await _bonsoirDiscovery!.stop();
      } catch (e) {
        debugPrint('[SharingService] Error stopping Bonsoir discovery: $e');
      }
      _bonsoirDiscovery = null;
    }

    await _httpServer?.close(force: true);
    _httpServer = null;

    // 关掉共享时，排队等确认的请求要给发起方一个明确的拒绝：否则对方的
    // HTTP 请求会一直挂着，直到连接层超时（用户看到的是「没反应」）。
    try {
      _ref.read(incomingRequestProvider.notifier).rejectAllPending();
      _ref.read(incomingLyricsRequestProvider.notifier).rejectAllPending();
      _ref.read(incomingPlaylistRequestProvider.notifier).rejectAllPending();
    } catch (e) {
      // provider 容器已销毁时读不到，属于正常收尾路径。
      debugPrint('[SharingService] Skip rejecting pending requests: $e');
    }
    _lyricsChunkSessions.clear();
    _playlistChunkSessions.clear();
    _inFlightSyncs.clear();

    for (final device in _discoveredDevicesMap.values) {
      TlsCertificateService.unregisterDeviceFingerprint(device.id);
      TlsCertificateService.unregisterDeviceFingerprint(device.ip);
    }
    _discoveredDevicesMap.clear();
    _devicesController.add([]);

    debugPrint('[SharingService] Sharing service stopped.');
  }

  Future<bool> checkLocalNetworkPermission() async {
    final ip = await _getLocalIpAddress();
    if (ip == null) {
      debugPrint(
        '[SharingService] No valid local IP address found during permission check.',
      );
      return false;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      try {
        final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        // Send a dummy 0-byte packet to mDNS multicast address to trigger the permission prompt
        // or check if it throws a SocketException.
        socket.send(Uint8List(0), InternetAddress('224.0.0.251'), 5353);
        socket.close();
      } catch (e) {
        try {
          final socketV6 = await RawDatagramSocket.bind(
            InternetAddress.anyIPv6,
            0,
          );
          socketV6.send(Uint8List(0), InternetAddress('ff02::fb'), 5353);
          socketV6.close();
        } catch (eV6) {
          debugPrint(
            '[SharingService] Socket binding/multicast failed: $e, v6: $eV6',
          );
          return false;
        }
      }
    }
    return true;
  }

  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.any,
      );

      // Filter out unwanted interfaces (cellular, virtual, VPN, loopback, AWDL)
      final filteredInterfaces = interfaces.where((interface) {
        final name = interface.name.toLowerCase();

        // Skip loopback, VPNs, tunnels, virtual machines
        if (name.contains('lo') ||
            name.contains('tun') ||
            name.contains('ppp') ||
            name.contains('docker') ||
            name.contains('vbox') ||
            name.contains('vmnet')) {
          return false;
        }

        // Skip cellular interfaces
        if (name.contains('pdp_ip') ||
            name.contains('rmnet') ||
            name.contains('ccmni') ||
            name.contains('cellular') ||
            name.contains('mobile')) {
          return false;
        }

        // Skip Apple Wireless Direct Link (AirDrop, etc.)
        if (name.contains('awdl')) {
          return false;
        }

        return true;
      }).toList();

      // Prioritize Wi-Fi and Ethernet interfaces
      filteredInterfaces.sort((a, b) {
        final nameA = a.name.toLowerCase();
        final nameB = b.name.toLowerCase();

        final isWifiOrEthA =
            nameA.contains('en') ||
            nameA.contains('wlan') ||
            nameA.contains('eth') ||
            nameA.contains('wifi') ||
            nameA.contains('ethernet');

        final isWifiOrEthB =
            nameB.contains('en') ||
            nameB.contains('wlan') ||
            nameB.contains('eth') ||
            nameB.contains('wifi') ||
            nameB.contains('ethernet');

        if (isWifiOrEthA && !isWifiOrEthB) return -1;
        if (!isWifiOrEthA && isWifiOrEthB) return 1;
        return 0;
      });

      // 1. First pass: look for IPv4 non-loopback address across sorted filtered interfaces
      for (final interface in filteredInterfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }

      // 2. Second pass: look for IPv6 non-loopback address across sorted filtered interfaces
      for (final interface in filteredInterfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv6) {
            return addr.address;
          }
        }
      }

      // Fallback: IPv4
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }

      // Fallback: IPv6
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv6) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('[SharingService] Error resolving IP: $e');
    }
    return null;
  }

  // --- mDNS Discovery (Bonsoir) Helper methods ---

  // --- HTTP Request Handler ---

  Future<void> _handleHttpRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    // Set CORS headers
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS',
    );
    request.response.headers.add(
      'Access-Control-Allow-Headers',
      'Origin, X-Requested-With, Content-Type, Accept, Authorization, X-File-Name',
    );

    if (method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    // 能力回告：对端（新版本）据此判断能不能发分块 / gzip 请求。
    // 老客户端不会读它，加了也没有副作用。
    if (path.startsWith('/api/lyrics') || path.startsWith('/api/playlists')) {
      request.response.headers.set(
        kLanSyncVersionHeader,
        '$kLanSyncProtocolVersion',
      );
    }

    try {
      final remoteService = _ref.read(remoteControlServiceProvider);

      if (method == 'POST' && path == '/api/transfer/request') {
        await _handleTransferRequest(request);
      } else if (method == 'POST' && path == '/api/transfer/upload') {
        await _handleTransferUpload(request);
      } else if (method == 'GET' && path == '/api/lyrics/export') {
        await _handleExportLyrics(request);
      } else if (method == 'POST' && path == '/api/lyrics/import') {
        await _handleImportLyrics(request);
      } else if (method == 'GET' && path == '/api/playlists/export') {
        await _handleExportPlaylists(request);
      } else if (method == 'POST' && path == '/api/playlists/import') {
        await _handleImportPlaylists(request);
      } else if (method == 'POST' && path == '/api/remote/pair') {
        await remoteService.handlePairRequest(request);
      } else if (method == 'POST' && path == '/api/remote/pair/verify') {
        await remoteService.handlePairVerify(request);
      } else if (method == 'POST' && path == '/api/remote/pair/cancel') {
        await remoteService.handlePairCancel(request);
      } else if (method == 'GET' && path == '/api/remote/ws') {
        await remoteService.handleWebSocketUpgrade(request);
      } else if (method == 'GET' && path == '/api/remote/cover') {
        await remoteService.handleCoverRequest(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (e, st) {
      debugPrint('[SharingService] Error handling request $path: $e\n$st');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'error': 'Server error: $e', 'stack': st.toString()}),
      );
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  /// 读同步请求体：先看 `Content-Length` 上限，边读边累计，超限立即 413。
  ///
  /// 旧实现是 `utf8.decoder.bind(request).join()`，没有任何上限，也没有处理
  /// `Content-Encoding` —— 一个畸形请求就能把接收端内存吃光。
  ///
  /// 返回 null 表示已经写好并关闭了响应，调用方直接 return。
  Future<Map<String, dynamic>?> _readSyncJsonBody(
    HttpRequest request, {
    int maxBytes = LanSyncLimits.maxBodyBytes,
  }) async {
    if (request.contentLength > maxBytes) {
      await _rejectPayloadTooLarge(request, request.contentLength);
      return null;
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        await _rejectPayloadTooLarge(request, builder.length);
        return null;
      }
    }

    final String text;
    try {
      text = decodeLanSyncBody(
        builder.takeBytes(),
        contentEncoding: request.headers.value(
          HttpHeaders.contentEncodingHeader,
        ),
      );
    } on FormatException catch (e) {
      debugPrint('[SharingService] Bad request body encoding: $e');
      await _closeWithJson(request, HttpStatus.badRequest, {
        'error': 'Malformed request body',
      });
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      debugPrint('[SharingService] Bad request JSON: $e');
      await _closeWithJson(request, HttpStatus.badRequest, {
        'error': 'Malformed JSON body',
      });
      return null;
    }

    if (decoded is! Map<String, dynamic>) {
      await _closeWithJson(request, HttpStatus.badRequest, {
        'error': 'Expected a JSON object',
      });
      return null;
    }
    return decoded;
  }

  Future<void> _rejectPayloadTooLarge(HttpRequest request, int size) async {
    debugPrint(
      '[SharingService] Rejecting oversized body: $size bytes '
      '(limit ${LanSyncLimits.maxBodyBytes})',
    );
    await _closeWithJson(request, HttpStatus.requestEntityTooLarge, {
      'error': 'Payload too large',
      'limit': LanSyncLimits.maxBodyBytes,
      'received': size,
    });
  }

  Future<void> _closeWithJson(
    HttpRequest request,
    int statusCode,
    Map<String, dynamic> payload,
  ) async {
    try {
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(payload));
      await request.response.close();
    } catch (e) {
      debugPrint('[SharingService] Failed to close response: $e');
    }
  }

  /// 回收超时的分块会话。
  void _pruneChunkSessions(Map<String, _LanChunkSession> sessions) {
    final deadline = DateTime.now().subtract(LanSyncLimits.chunkSessionTtl);
    sessions.removeWhere((_, session) => session.lastTouched.isBefore(deadline));
  }

  /// 同设备互斥：重复点击直接抛 [LanSyncBusyException]，不并发跑两份。
  Future<T> _runSyncExclusive<T>(
    String key,
    LanSyncKind kind,
    Future<T> Function() action,
  ) async {
    if (_inFlightSyncs.containsKey(key)) {
      throw LanSyncBusyException(kind);
    }
    final gate = Completer<void>();
    _inFlightSyncs[key] = gate.future;
    try {
      return await action();
    } finally {
      _inFlightSyncs.remove(key);
      if (!gate.isCompleted) gate.complete();
    }
  }

  /// 进度 provider 在容器已销毁时会抛异常，这时同步本身还在跑，不能因此中断。
  LanSyncProgressNotifier? get _progress {
    try {
      return _ref.read(lanSyncProgressProvider.notifier);
    } catch (_) {
      return null;
    }
  }

  void _beginProgress(
    LanSyncKind kind,
    LanSyncDirection direction,
    String deviceName,
  ) {
    _progress?.begin(
      kind: kind,
      direction: direction,
      deviceName: deviceName,
    );
    _armIncomingProgressTimeout();
  }

  /// 换阶段。没有进行中的任务时是 no-op —— 同一条收集逻辑被
  /// 「主动推送」和「对端拉取」共用，后者不一定有进度对话框。
  void _progressStage(LanSyncStage stage, {int? processed, int? total}) {
    _progress?.setStage(stage, processed: processed, total: total);
  }

  void _progressAdvance([int delta = 1, int? total]) {
    _progress?.advance(delta, total);
    _armIncomingProgressTimeout();
  }

  void _endProgress() {
    _incomingProgressTimer?.cancel();
    _incomingProgressTimer = null;
    _progress?.clear();
  }

  /// 接收方向的心跳超时。
  ///
  /// 发送端中途放弃时，这边不会再收到任何分块，进度条会永远停在「正在接收」。
  /// 每个分块到达或推进时重置计时，超过分块会话 TTL 就自己收掉。
  void _armIncomingProgressTimeout() {
    _incomingProgressTimer?.cancel();
    final progress = _progress;
    if (progress?.current?.direction != LanSyncDirection.incoming) return;
    _incomingProgressTimer = Timer(
      LanSyncLimits.chunkSessionTtl + const Duration(seconds: 5),
      () {
        if (_progress?.current?.direction == LanSyncDirection.incoming) {
          _endProgress();
        }
      },
    );
  }

  /// 发布一条完成回执：写「最近一次同步」历史 + 通知 UI。
  ///
  /// 两个动作必须绑在一起 —— 之前只 notify，历史只能靠调用方自己补记，
  /// 结果是发起方有记录、被动方没有，回看得看运气。
  void _publishReceipt(LanSyncReceipt receipt) {
    LanSyncHistoryStore.record(receipt);
    _ref.read(lanSyncReceiptProvider.notifier).notify(receipt);
  }

  /// 取消检查点。放在分块之间而不是随时中断：硬断一个正在进行的 HTTP
  /// 请求会让对端留半截会话，反而要等 TTL 才能重来。
  void _throwIfCancelled() {
    if (_progress?.cancelRequested ?? false) {
      throw const LanSyncCancelledException();
    }
  }


  /// 发一个同步请求，返回状态码与解析后的 JSON。
  ///
  /// - 超时覆盖「建连 + 写 body + 读响应」三段，`connectionTimeout` 只管建连；
  /// - [allowGzip] 为 true 且体积超过阈值时压缩，并带上 `Content-Encoding`。
  ///   只有确认对端支持 v2 才允许，否则老版本会把压缩字节当 UTF-8 解。
  Future<({int status, Map<String, dynamic> body})> _postSyncJson(
    HttpClient client,
    Uri uri,
    Map<String, dynamic> payload, {
    bool allowGzip = false,
  }) async {
    final body = utf8.encode(jsonEncode(payload));

    final request = await client
        .postUrl(uri)
        .timeout(LanSyncLimits.readTimeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(kLanSyncVersionHeader, '$kLanSyncProtocolVersion');

    if (allowGzip && body.length >= LanSyncLimits.gzipThresholdBytes) {
      final compressed = gzip.encode(body);
      request.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      request.contentLength = compressed.length;
      request.add(compressed);
    } else {
      request.contentLength = body.length;
      request.add(body);
    }

    final response = await request.close().timeout(LanSyncLimits.readTimeout);
    final text = await utf8.decoder
        .bind(response)
        .join()
        .timeout(LanSyncLimits.readTimeout);

    final Object? decoded = text.isEmpty ? null : jsonDecode(text);
    return (
      status: response.statusCode,
      body: decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{},
    );
  }

  String _deriveSessionName(List<TransferFileItem> files) {    if (files.isEmpty) return '未命名传输';
    if (files.length == 1) {
      final name = files[0].name.replaceAll('\\', '/');
      return p.basename(name);
    }

    final firstPath = files[0].name.replaceAll('\\', '/');
    final parts = firstPath.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length > 1) {
      return parts[0];
    }
    return '批量传输 (${files.length} 个文件)';
  }

  Future<void> _handleTransferRequest(HttpRequest request) async {
    // 与歌词/歌单同一条读 body 路径：带体积上限与 gzip 解码。
    final json = await _readSyncJsonBody(request);
    if (json == null) return;

    final senderId = json['sender_id'] as String? ?? 'unknown';
    final senderName = json['sender_name'] as String? ?? 'Unknown';
    final filesJson = json['files'] as List<dynamic>? ?? [];

    final files = filesJson.map((f) {
      final map = f as Map<String, dynamic>;
      return TransferFileItem(
        name: map['name'] as String? ?? 'Unnamed',
        size: map['size'] as int? ?? 0,
        durationMs: map['duration_ms'] as int? ?? 0,
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        lyricsPackage: map['lyrics_package'] as Map<String, dynamic>?,
      );
    }).toList();

    if (files.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(
        jsonEncode({'accepted': false, 'reason': 'No files specified'}),
      );
      await request.response.close();
      return;
    }

    // Trigger UI Prompt
    final completer = Completer<bool>();
    _ref
        .read(incomingRequestProvider.notifier)
        .setRequest(
          IncomingTransferRequest(
            senderId: senderId,
            senderName: senderName,
            files: files,
            onDecision: (accepted) {
              completer.complete(accepted);
              _ref
                  .read(incomingRequestProvider.notifier)
                  .setRequest(null); // Clear request
            },
          ),
        );

    // Wait for user input
    final accepted = await completer.future;

    if (accepted) {
      if (_sharingFolderPath.isNotEmpty) {
        // 常驻占用（初始化时建立的）已覆盖这次接收；重复申请不会再加计数。
        await _holdSharingFolder(_sharingFolderPath);
      }

      bool useSaf = false;
      String? treeUri;
      if (Platform.isAndroid) {
        final mapping =
            await AndroidSafStorageHelper.findBestMapping(_sharingFolderPath);
        if (mapping != null) {
          useSaf = true;
          treeUri = mapping.value;
        }
      }

      final List<String> conflictingFiles = [];
      if (useSaf && treeUri != null) {
        // Fetch all existing files under treeUri in one batch IPC call (milliseconds instead of 500+ sequential IPC calls)
        final existingList =
            await AndroidSafStorageHelper.listMusicFilesRecursively(treeUri);
        final existingSet = existingList
            .map((s) => s.replaceAll('\\', '/').toLowerCase())
            .toSet();
        final existingBasenames = existingList
            .map((s) => p.basename(s.replaceAll('\\', '/')).toLowerCase())
            .toSet();

        for (final file in files) {
          final relPath = file.name.replaceAll('\\', '/');
          final relLower = relPath.toLowerCase();
          final baseLower = p.basename(relPath).toLowerCase();
          if (existingSet.contains(relLower) ||
              existingBasenames.contains(baseLower)) {
            conflictingFiles.add(relPath);
          }
        }
      } else {
        for (final file in files) {
          var relPath = file.name.replaceAll('\\', '/');
          final pathSegments = relPath
              .split('/')
              .where((s) => s.isNotEmpty && s != '.' && s != '..')
              .map((s) => s.replaceAll(RegExp(r'[:*?"<>|]'), '_'))
              .toList();
          if (pathSegments.isEmpty) continue;
          final targetPath =
              p.normalize(p.joinAll([_sharingFolderPath, ...pathSegments]));

          if (File(targetPath).existsSync()) {
            conflictingFiles.add(relPath);
          }
        }
      }

      String? conflictAction;
      List<String> skippedFiles = [];

      if (conflictingFiles.isNotEmpty) {
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          final displayFileName = conflictingFiles.length == 1
              ? p.basename(conflictingFiles.first)
              : '${p.basename(conflictingFiles.first)} 等 ${conflictingFiles.length} 个同名文件';
          debugPrint(
            '[SharingService] Receiver: Prompting preflight conflict dialog for $displayFileName',
          );
          final action = await showConflictDialog(context, displayFileName);
          debugPrint(
            '[SharingService] Receiver: User chose preflight action: $action',
          );

          if (action == 'skip_all') {
            conflictAction = 'skip_all';
            skippedFiles = List.from(conflictingFiles);
          } else if (action == 'skip') {
            skippedFiles = [conflictingFiles.first];
          } else if (action == 'overwrite_all') {
            conflictAction = 'overwrite_all';
          } else if (action == 'overwrite') {
            // overwrite individual file
          } else {
            conflictAction = 'skip_all';
            skippedFiles = List.from(conflictingFiles);
          }
        }
      }

      final token =
          'tkn_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(100000)}';
      final totalSize = files.fold<int>(0, (sum, f) => sum + f.size);
      final sessionName = _deriveSessionName(files);

      final skippedSet = skippedFiles.toSet();
      final skippedBytes = files
          .where(
            (f) =>
                skippedSet.contains(f.name.replaceAll('\\', '/')) ||
                skippedSet.contains(p.basename(f.name.replaceAll('\\', '/'))),
          )
          .fold<int>(0, (sum, f) => sum + f.size);

      final metadata = _UploadRequestMetadata(
        sessionName: sessionName,
        files: files,
        totalSize: totalSize,
        senderName: senderName,
      );
      metadata.conflictAction = conflictAction;
      metadata.completedFiles.addAll(skippedFiles);
      metadata.bytesTransferredCumulative = skippedBytes;
      _activeTokens[token] = metadata;

      final isAllSkipped =
          skippedFiles.length >= files.length && files.isNotEmpty;

      if (!isAllSkipped) {
        // Pause scanner media observer during active transfer to prevent 100% freezing
        _ref.read(scannerServiceProvider).pauseMediaObserver();
      }

      // Add TransferSession on receiver side immediately upon acceptance
      _ref
          .read(activeTransfersProvider.notifier)
          .addSession(
            TransferSession(
              id: token,
              fileName: files.length > 1
                  ? '$sessionName (${files.length}个文件)'
                  : sessionName,
              totalBytes: totalSize,
              bytesTransferred: isAllSkipped ? totalSize : skippedBytes,
              isSending: false,
              deviceName: senderName,
              status: isAllSkipped
                  ? TransferStatus.success
                  : TransferStatus.transferring,
              filesCount: files.length,
              completedFilesCount:
                  isAllSkipped ? files.length : skippedFiles.length,
            ),
          );

      if (isAllSkipped) {
        _activeTokens.remove(token);
        // 一个文件都没写，没有什么可入库的：只恢复媒体观察者，不触发扫描。
        _checkAndResumeScanner(triggerScan: false);
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.write(
        jsonEncode({
          'accepted': true,
          'token': token,
          'conflict_action': conflictAction,
          'skipped_files': skippedFiles,
        }),
      );
    } else {
      request.response.statusCode = HttpStatus.ok;
      request.response.write(
        jsonEncode({'accepted': false, 'reason': 'Rejected by receiver'}),
      );
    }
    await request.response.close();
  }

  Future<void> _handleTransferUpload(HttpRequest request) async {
    final auth = request.headers.value('Authorization') ?? '';
    final token = auth.replaceFirst('Bearer ', '').trim();

    if (!_activeTokens.containsKey(token)) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write(
        jsonEncode({'error': 'Invalid or expired upload token'}),
      );
      await request.response.close();
      return;
    }

    final sessionId = token;
    final isCancelled = _ref
        .read(activeTransfersProvider)
        .any((s) => s.id == sessionId && s.status == TransferStatus.cancelled);
    if (isCancelled) {
      debugPrint(
        '[SharingService] Receiver: Session $sessionId is cancelled. Rejecting incoming upload.',
      );
      _activeTokens.remove(token);
      _checkAndResumeScanner();
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': 'Transfer cancelled'}));
      await request.response.close();
      return;
    }

    final metadata = _activeTokens[token]!;

    // Fallback if client doesn't use standard request streaming body
    String relativePath = metadata.sessionName;
    final encodedFileName = request.headers.value('X-File-Name');
    if (encodedFileName != null) {
      try {
        relativePath = Uri.decodeComponent(encodedFileName);
      } catch (_) {}
    }

    // Always normalize relativePath to forward slashes for cross-platform compatibility
    relativePath = relativePath.replaceAll('\\', '/');

    // Build targetPath using sanitized path segments to prevent path traversal
    final pathSegments = relativePath
        .split('/')
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .map((s) => s.replaceAll(RegExp(r'[:*?"<>|]'), '_'))
        .toList();

    if (pathSegments.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': 'Invalid file name'}));
      await request.response.close();
      return;
    }

    String targetPath = p.normalize(p.joinAll([_sharingFolderPath, ...pathSegments]));

    // Security boundary check: Ensure targetPath is strictly within _sharingFolderPath
    final canonicalSharingDir = p.canonicalize(_sharingFolderPath);
    final canonicalTargetPath = p.canonicalize(targetPath);

    if (!p.isWithin(canonicalSharingDir, canonicalTargetPath) &&
        !p.equals(canonicalSharingDir, canonicalTargetPath)) {
      debugPrint(
        '[SharingService] Receiver: Path traversal blocked for $relativePath -> $targetPath',
      );
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write(
        jsonEncode({'error': 'Access denied: Path outside sharing directory'}),
      );
      await request.response.close();
      return;
    }

    debugPrint(
      '[SharingService] Receiver: Incoming file upload request for $relativePath -> $targetPath',
    );

    final fileItem = metadata.files.firstWhere(
      (f) => f.name.replaceAll('\\', '/') == relativePath,
      orElse: () => metadata.files.firstWhere(
        (f) =>
            p.basename(f.name.replaceAll('\\', '/')) ==
            p.basename(relativePath),
        orElse: () => TransferFileItem(name: '', size: 0, durationMs: 0),
      ),
    );
    final fileSize = fileItem.size;

    metadata.activeFilesMap[relativePath] = ActiveFileProgress(
      fileName: p.basename(relativePath),
      bytesTransferred: 0,
      totalBytes: fileSize,
    );

    _currentReceiverRequests.putIfAbsent(sessionId, () => []).add(request);
    _ref
        .read(activeTransfersProvider.notifier)
        .updateProgress(
          sessionId,
          metadata.bytesTransferredCumulative,
          activeFiles: metadata.activeFilesMap.values.toList(),
        );

    // 分享目录的常驻占用通常已经建立，这里拿到的是同一份（去重命中，
    // `release()` 是 no-op），所以不会出现「分享目录与它下面的 targetPath
    // resolve 到同一个 scope key、各减一次」把扫描器那份计数打掉的问题。
    AppleFileAccessLease? transferLease;
    if (Platform.isIOS || Platform.isMacOS) {
      transferLease = await _holdSharingFolder(_sharingFolderPath);
    }

    bool useSaf = false;
    String? treeUri;
    if (Platform.isAndroid) {
      final mapping = await AndroidSafStorageHelper.findBestMapping(targetPath);
      if (mapping != null) {
        useSaf = true;
        treeUri = mapping.value;
      }
    }

    bool fileExists = false;
    if (useSaf && treeUri != null) {
      final relativeFileName = p.relative(targetPath, from: _sharingFolderPath);
      fileExists = await AndroidSafStorageHelper.fileExists(
        treeUri,
        relativeFileName,
      );
    } else {
      fileExists = File(targetPath).existsSync();
    }

    bool shouldSkip = false;
    bool shouldOverwrite = false;

    if (fileExists) {
      // If another worker is currently showing the conflict dialog, wait for it to finish.
      while (metadata.activeConflictFuture != null) {
        await metadata.activeConflictFuture;
      }

      if (metadata.conflictAction == 'skip_all') {
        shouldSkip = true;
      } else if (metadata.conflictAction == 'overwrite_all') {
        shouldOverwrite = true;
      } else {
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          debugPrint(
            '[SharingService] Receiver: Prompting conflict dialog for $relativePath',
          );

          final completer = Completer<void>();
          metadata.activeConflictFuture = completer.future;

          try {
            final action = await showConflictDialog(
              context,
              p.basename(relativePath),
            );
            debugPrint(
              '[SharingService] Receiver: User chose $action for $relativePath',
            );
            if (action == 'skip') {
              shouldSkip = true;
            } else if (action == 'skip_all') {
              metadata.conflictAction = 'skip_all';
              shouldSkip = true;
            } else if (action == 'overwrite') {
              shouldOverwrite = true;
            } else if (action == 'overwrite_all') {
              metadata.conflictAction = 'overwrite_all';
              shouldOverwrite = true;
            } else {
              shouldSkip = true;
            }
          } finally {
            metadata.activeConflictFuture = null;
            completer.complete();
          }
        } else {
          debugPrint(
            '[SharingService] Receiver: Global context not available. Falling back to counter renaming.',
          );
        }
      }
    }

    if (fileExists && !shouldSkip && !shouldOverwrite) {
      final lastSlashIndex = relativePath.lastIndexOf('/');
      final dirName = lastSlashIndex != -1
          ? relativePath.substring(0, lastSlashIndex)
          : '';
      final fileNameOnly = lastSlashIndex != -1
          ? relativePath.substring(lastSlashIndex + 1)
          : relativePath;

      final extension = p.extension(fileNameOnly);
      final baseName = p.basenameWithoutExtension(fileNameOnly);
      int counter = 1;
      while (true) {
        final newRelative = dirName.isEmpty
            ? '$baseName ($counter)$extension'
            : '$dirName/$baseName ($counter)$extension';

        final newSegments = newRelative
            .split('/')
            .where((s) => s.isNotEmpty)
            .toList();
        targetPath = p.joinAll([_sharingFolderPath, ...newSegments]);

        bool currentExists = false;
        if (useSaf && treeUri != null) {
          currentExists = await AndroidSafStorageHelper.fileExists(
            treeUri,
            newRelative,
          );
        } else {
          currentExists = File(targetPath).existsSync();
        }

        if (!currentExists) {
          break;
        }
        counter++;
      }
      debugPrint(
        '[SharingService] Receiver: Duplicate file renamed to $targetPath',
      );
    }

    if (shouldSkip) {
      debugPrint(
        '[SharingService] Receiver: Skipping file $relativePath. Discarding request body...',
      );
      try {
        await for (final _ in request) {
          // Just discard chunks
        }

        // Track completed file
        metadata.completedFiles.add(relativePath);

        // Check if all files in the metadata session are completed
        final allFiles = metadata.files
            .map((f) => f.name.replaceAll('\\', '/'))
            .toSet();
        final isFinished =
            metadata.completedFiles.containsAll(allFiles) ||
            metadata.completedFiles.length >= metadata.files.length;

        // Clean up from active files map
        metadata.activeFilesMap.remove(relativePath);

        if (isFinished) {
          _activeTokens.remove(token);
          unawaited(_finalizeReceivedFiles(sessionId, metadata));
        } else {
          _ref
              .read(activeTransfersProvider.notifier)
              .updateProgress(
                sessionId,
                metadata.bytesTransferredCumulative,
                completedFilesCount: metadata.completedFiles.length,
                activeFiles: metadata.activeFilesMap.values.toList(),
              );
        }

        request.response.statusCode = HttpStatus.ok;
        request.response.write(
          jsonEncode({'success': true, 'path': targetPath, 'skipped': true}),
        );
      } catch (e) {
        debugPrint(
          '[SharingService] Receiver: Error while skipping/discarding file $relativePath: $e',
        );
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(
          jsonEncode({'error': 'Error skipping file: $e'}),
        );
      } finally {
        if (_currentReceiverRequests[sessionId] != null) {
          _currentReceiverRequests[sessionId]!.remove(request);
          if (_currentReceiverRequests[sessionId]!.isEmpty) {
            _currentReceiverRequests.remove(sessionId);
          }
        }
        metadata.activeFilesMap.remove(relativePath);
      }
      await request.response.close();
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      p.join(
        tempDir.path,
        'temp_transfer_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}',
      ),
    );
    final nonSafTempFile = File('$targetPath.vynody_tmp');
    final targetFile = useSaf ? tempFile : nonSafTempFile;

    if (!useSaf) {
      // Ensure parent directories exist for normal file writes across all platforms
      final parentDir = Directory(p.dirname(targetPath));
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }
      if (nonSafTempFile.existsSync()) {
        try {
          nonSafTempFile.deleteSync();
        } catch (_) {}
      }
    }

    final ioSink = targetFile.openWrite();

    try {
      debugPrint(
        '[SharingService] Receiver: Starting to write to file: ${targetFile.path}',
      );
      int fileBytesReceived = 0;
      DateTime lastLogTime = DateTime.now();

      int lastProgressUpdateMs = 0;

      final progressStream = request.map((chunk) {
        fileBytesReceived += chunk.length;

        final newCumulative =
            metadata.bytesTransferredCumulative + chunk.length;
        metadata.bytesTransferredCumulative = newCumulative;

        final current = metadata.activeFilesMap[relativePath];
        if (current != null) {
          metadata.activeFilesMap[relativePath] = ActiveFileProgress(
            fileName: current.fileName,
            bytesTransferred: current.bytesTransferred + chunk.length,
            totalBytes: current.totalBytes,
          );
        }

        final now = DateTime.now();
        final nowMs = now.millisecondsSinceEpoch;
        if (nowMs - lastProgressUpdateMs >= 100) {
          lastProgressUpdateMs = nowMs;

          // Check cancellation throttled to 100ms
          final currentSessions = _ref.read(activeTransfersProvider);
          final currentSession = currentSessions.firstWhere(
            (s) => s.id == sessionId,
            orElse: () => TransferSession(
              id: '',
              fileName: '',
              totalBytes: 0,
              bytesTransferred: 0,
              isSending: true,
              deviceName: '',
              status: TransferStatus.failed,
            ),
          );
          if (currentSession.status == TransferStatus.cancelled) {
            debugPrint(
              '[SharingService] Receiver: Transfer was cancelled by user during download of $relativePath',
            );
            throw Exception('Cancelled by user');
          }

          _ref
              .read(activeTransfersProvider.notifier)
              .updateProgress(
                sessionId,
                newCumulative,
                activeFiles: metadata.activeFilesMap.values.toList(),
              );
        }

        if (now.difference(lastLogTime).inSeconds >= 2) {
          debugPrint(
            '[SharingService] Receiver: Downloading $relativePath: '
            '${(fileBytesReceived / (1024 * 1024)).toStringAsFixed(2)} MB received',
          );
          lastLogTime = now;
        }
        return chunk;
      });

      // Use addStream to pipe chunk data to ioSink.
      // This handles all underlying write/open errors on the main thread inside the try-catch block!
      await ioSink.addStream(progressStream);

      debugPrint(
        '[SharingService] Receiver: Finished reading request stream for $relativePath. Flushing and closing file...',
      );
      await ioSink.flush();
      await ioSink.close();

      if (useSaf && treeUri != null) {
        debugPrint(
          '[SharingService] Receiver: Writing temp file to SAF folder: $targetPath',
        );
        final relativeFileName = p.relative(
          targetPath,
          from: _sharingFolderPath,
        );
        final methodChannel = const MethodChannel(
          'com.example.audio_converter/saf',
        );
        final result = await methodChannel.invokeMapMethod<String, Object?>(
          'saveFileToDirectory',
          <String, Object?>{
            'treeUri': treeUri,
            'sourcePath': tempFile.path,
            'fileName': relativeFileName.replaceAll('\\', '/'),
            'overwrite':
                true, // We already handled conflict renaming/overwrite choice above
          },
        );

        final savedUri = result?['savedUri']?.toString();
        if (savedUri == null || savedUri.isEmpty) {
          throw Exception('Failed to write via SAF');
        }
        debugPrint(
          '[SharingService] Receiver: Saved file successfully via SAF: $targetPath',
        );
      } else {
        // Atomic rename from temp file (.vynody_tmp) to final targetPath
        final finalFile = File(targetPath);
        final parentDir = finalFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        if (await finalFile.exists()) {
          try {
            await finalFile.delete();
          } catch (_) {}
        }
        await nonSafTempFile.rename(targetPath);
        debugPrint(
          '[SharingService] Receiver: Saved file successfully: $targetPath',
        );
      }

      // Ensure the sharing folder is added to scanner now that we have received a file
      try {
        await _ensureRegisteredInScanner();
      } catch (e, st) {
        debugPrint(
          '[SharingService] Receiver: Warning - failed to register folder in scanner: $e\n$st',
        );
      }

      // Save lyrics package if available
      try {
        final fileItem = metadata.files.firstWhere(
          (f) => f.name.replaceAll('\\', '/') == relativePath,
          orElse: () => metadata.files.firstWhere(
            (f) =>
                p.basename(f.name.replaceAll('\\', '/')) ==
                p.basename(relativePath),
            orElse: () => TransferFileItem(name: '', size: 0, durationMs: 0),
          ),
        );
        if (fileItem.name.isNotEmpty && fileItem.lyricsPackage != null) {
          final localQuery = LyricsQuery(
            filePath: targetPath,
            fileName: p.basename(targetPath),
            title: fileItem.title ?? p.basenameWithoutExtension(targetPath),
            artist: fileItem.artist,
            album: fileItem.album,
            duration: fileItem.durationMs > 0
                ? Duration(milliseconds: fileItem.durationMs)
                : null,
          );
          await _importLyricsPackageWithConflict(
            localCacheKey: localQuery.cacheKey,
            incomingPackage: fileItem.lyricsPackage!,
          );
        }
      } catch (e, st) {
        debugPrint('[SharingService] Error importing lyrics package: $e\n$st');
      }

      // Track completed file
      metadata.completedFiles.add(relativePath);
      metadata.receivedDirectories.add(p.dirname(targetPath));

      // Check if all files in the metadata session are completed
      final allFiles = metadata.files
          .map((f) => f.name.replaceAll('\\', '/'))
          .toSet();
      final isFinished =
          metadata.completedFiles.containsAll(allFiles) ||
          metadata.completedFiles.length >= metadata.files.length;

      // Remove from active files map first
      metadata.activeFilesMap.remove(relativePath);

      if (isFinished) {
        // 先把状态切到「入库中」，再回响应：最后一个上传请求不能等扫描，
        // 否则发送端会卡在 45 秒读超时上。扫描在后台跑完再切 success。
        _ref
            .read(activeTransfersProvider.notifier)
            .updateProgress(
              sessionId,
              metadata.totalSize,
              status: TransferStatus.indexing,
              completedFilesCount: metadata.completedFiles.length,
              activeFiles: [],
            );
        _activeTokens.remove(token);
        unawaited(_finalizeReceivedFiles(sessionId, metadata));
      } else {
        _ref
            .read(activeTransfersProvider.notifier)
            .updateProgress(
              sessionId,
              metadata.bytesTransferredCumulative,
              completedFilesCount: metadata.completedFiles.length,
              activeFiles: metadata.activeFilesMap.values.toList(),
            );
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'path': targetPath}));
    } catch (e, st) {
      debugPrint(
        '[SharingService] Receiver: Error uploading file $relativePath: $e\n$st',
      );
      try {
        await ioSink.close();
      } catch (_) {}
      if (!useSaf && targetFile.existsSync()) {
        try {
          targetFile.deleteSync();
        } catch (_) {}
      }
      final currentSessionsInner = _ref.read(activeTransfersProvider);
      final currentSessionInner = currentSessionsInner.firstWhere(
        (s) => s.id == sessionId,
        orElse: () => TransferSession(
          id: '',
          fileName: '',
          totalBytes: 0,
          bytesTransferred: 0,
          isSending: true,
          deviceName: '',
          status: TransferStatus.failed,
        ),
      );
      if (currentSessionInner.status != TransferStatus.cancelled) {
        _ref
            .read(activeTransfersProvider.notifier)
            .updateStatus(sessionId, TransferStatus.failed);
      }
      _activeTokens.remove(token);
      _checkAndResumeScanner();

      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'error': 'Transfer interrupted: $e',
          'stack': st.toString(),
          'file': relativePath,
        }),
      );
    } finally {
      await transferLease?.release();
      if (_currentReceiverRequests[sessionId] != null) {
        _currentReceiverRequests[sessionId]!.remove(request);
        if (_currentReceiverRequests[sessionId]!.isEmpty) {
          _currentReceiverRequests.remove(sessionId);
        }
      }
      metadata.activeFilesMap.remove(relativePath);
      if (useSaf && tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    }
    await request.response.close();
  }

  // --- Sending File to Remote App ---

  Future<bool> sendFile(LanDevice targetDevice, String filePath) {
    return sendFiles(targetDevice: targetDevice, filePaths: [filePath]);
  }

  Future<bool> sendFiles({
    required LanDevice targetDevice,
    required List<String> filePaths,
    String? baseSourcePath,
  }) async {
    final List<Map<String, dynamic>> filesPayload = [];
    final List<_FileToSend> filesToSend = [];
    int totalSize = 0;

    for (final path in filePaths) {
      final file = File(path);
      if (!file.existsSync()) continue;

      final size = file.lengthSync();
      totalSize += size;

      String relativeName = p.basename(path);
      if (baseSourcePath != null) {
        relativeName = p.relative(path, from: baseSourcePath);
      }
      relativeName = relativeName.replaceAll('\\', '/');

      Map<String, dynamic>? lyricsPackage;
      SongMetadata? song;
      try {
        song = await MetadataDatabase().getSongMetadata(path);
        if (song != null) {
          final query = LyricsQuery(
            filePath: song.path,
            fileName: p.basename(song.path),
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: song.duration != null
                ? Duration(milliseconds: song.duration!)
                : null,
          );
          final cacheRecord = await MetadataDatabase().getLyricsCache(
            query.cacheKey,
          );
          if (cacheRecord != null &&
              cacheRecord.source != LyricsCacheSource.none) {
            final translations = await MetadataDatabase()
                .getLyricsTranslationCaches(query.cacheKey);
            lyricsPackage = {
              'lyrics_cache': cacheRecord.toMap(),
              'translations': translations.map((t) => t.toMap()).toList(),
            };
          }
        }
      } catch (e) {
        debugPrint(
          '[SharingService] Error reading local lyrics for file $path: $e',
        );
      }

      filesPayload.add({
        'name': relativeName,
        'size': size,
        'duration_ms': song?.duration ?? 0,
        'title': song?.title,
        'artist': song?.artist,
        'album': song?.album,
        'lyrics_package': lyricsPackage,
      });

      filesToSend.add(
        _FileToSend(path: path, relativeName: relativeName, size: size),
      );

      // Check if a same-named LRC file exists in the same directory, and add it for physical transfer
      try {
        final directory = p.dirname(path);
        final baseName = p.basenameWithoutExtension(path);
        final lrcPath = p.join(directory, '$baseName.lrc');
        var lrcFile = File(lrcPath);
        if (!lrcFile.existsSync()) {
          final lrcPathUpper = p.join(directory, '$baseName.LRC');
          final lrcFileUpper = File(lrcPathUpper);
          if (lrcFileUpper.existsSync()) {
            lrcFile = lrcFileUpper;
          } else {
            lrcFile = File('');
          }
        }

        if (lrcFile.path.isNotEmpty && lrcFile.existsSync()) {
          final lrcSize = lrcFile.lengthSync();
          totalSize += lrcSize;

          String lrcRelativeName = p.basename(lrcFile.path);
          if (baseSourcePath != null) {
            lrcRelativeName = p.relative(lrcFile.path, from: baseSourcePath);
          }
          lrcRelativeName = lrcRelativeName.replaceAll('\\', '/');

          filesPayload.add({
            'name': lrcRelativeName,
            'size': lrcSize,
            'duration_ms': 0,
            'title': null,
            'artist': null,
            'album': null,
            'lyrics_package': null,
          });

          filesToSend.add(
            _FileToSend(
              path: lrcFile.path,
              relativeName: lrcRelativeName,
              size: lrcSize,
            ),
          );
        }
      } catch (e) {
        debugPrint(
          '[SharingService] Error checking/adding local lrc file for transfer: $e',
        );
      }
    }

    if (filesToSend.isEmpty) return false;

    // Derive display name for progress dialog
    final firstRelPath = filesToSend[0].relativeName.replaceAll('\\', '/');
    final parts = firstRelPath.split('/').where((s) => s.isNotEmpty).toList();
    final sessionName = parts.length > 1
        ? parts[0]
        : p.basename(filesToSend[0].path);

    final sessionId = 'send_${DateTime.now().millisecondsSinceEpoch}';
    _ref
        .read(activeTransfersProvider.notifier)
        .addSession(
          TransferSession(
            id: sessionId,
            fileName: filesToSend.length > 1
                ? '$sessionName (${filesToSend.length}个文件)'
                : sessionName,
            totalBytes: totalSize,
            bytesTransferred: 0,
            isSending: true,
            deviceName: targetDevice.name,
            status: TransferStatus.pending,
            filesCount: filesToSend.length,
            completedFilesCount: 0,
          ),
        );

    debugPrint(
      '[SharingService] Starting sendFiles to ${targetDevice.name} (${targetDevice.ip}:${targetDevice.httpPort}). '
      'Total files count: ${filesToSend.length}, total size: ${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB',
    );

    final client = TlsCertificateService.createPinnedHttpClient(
      expectedFingerprint: targetDevice.certFingerprint,
    );
    client.connectionTimeout = const Duration(seconds: 5);

    try {
      // 1. Post Preflight Request
      final formattedHost = formatHostForUrl(targetDevice.ip);
      final requestUri = Uri.parse(
        'https://$formattedHost:${targetDevice.httpPort}/api/transfer/request',
      );
      debugPrint('[SharingService] Sending preflight request to: $requestUri');
      final request = await client.postUrl(requestUri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'sender_id': _deviceId,
          'sender_name': _deviceName,
          'files': filesPayload,
        }),
      );

      final response = await request.close();
      debugPrint(
        '[SharingService] Preflight response status: ${response.statusCode}',
      );
      if (response.statusCode != HttpStatus.ok) {
        String preflightError = '';
        try {
          preflightError = await utf8.decoder.bind(response).join();
        } catch (_) {}
        debugPrint(
          '[SharingService] Preflight failed with status ${response.statusCode}. Response: $preflightError',
        );
        _ref
            .read(activeTransfersProvider.notifier)
            .updateStatus(sessionId, TransferStatus.failed);
        return false;
      }

      final responseBody = await utf8.decoder.bind(response).join();
      final responseJson = jsonDecode(responseBody) as Map<String, dynamic>;
      final accepted = responseJson['accepted'] == true;
      debugPrint('[SharingService] Preflight decision accepted: $accepted');

      if (!accepted) {
        final reason = responseJson['reason'] as String?;
        if (reason == '接收端设备未设置文件保存目录') {
          _ref
              .read(sharingWarningProvider.notifier)
              .setWarning('接收端设备未设置文件保存目录，无法接收您的文件');
        } else if (reason == '接收端文件保存目录已不存在') {
          _ref
              .read(sharingWarningProvider.notifier)
              .setWarning('接收端文件保存目录已不存在，无法接收您的文件');
        }
        _ref
            .read(activeTransfersProvider.notifier)
            .updateStatus(
              sessionId,
              TransferStatus.cancelled,
              cancelReason: reason,
            );
        return false;
      }

      final token = responseJson['token'] as String;

      final skippedList = (responseJson['skipped_files'] as List<dynamic>?)
              ?.map((e) => e.toString().replaceAll('\\', '/'))
              .toSet() ??
          <String>{};

      final filesToActuallySend = <_FileToSend>[];
      int initialSkippedBytes = 0;
      int initialSkippedCount = 0;

      for (final fileInfo in filesToSend) {
        final relNormalized = fileInfo.relativeName.replaceAll('\\', '/');
        final baseName = p.basename(relNormalized);
        if (skippedList.contains(relNormalized) ||
            skippedList.contains(baseName)) {
          initialSkippedBytes += fileInfo.size;
          initialSkippedCount++;
        } else {
          filesToActuallySend.add(fileInfo);
        }
      }

      if (filesToActuallySend.isEmpty) {
        debugPrint(
          '[SharingService] Sender: All ${filesToSend.length} files skipped per receiver conflict choice. Transfer finished instantly.',
        );
        _ref
            .read(activeTransfersProvider.notifier)
            .updateProgress(
              sessionId,
              totalSize,
              status: TransferStatus.success,
              completedFilesCount: filesToSend.length,
              activeFiles: [],
            );
        return true;
      }

      // 2. Perform Uploads concurrently
      _ref
          .read(activeTransfersProvider.notifier)
          .updateProgress(
            sessionId,
            initialSkippedBytes,
            status: TransferStatus.transferring,
            completedFilesCount: initialSkippedCount,
            activeFiles: [],
          );

      int totalBytesSent = initialSkippedBytes;
      int completedFilesCount = initialSkippedCount;
      final Map<String, ActiveFileProgress> localActiveFiles = {};

      int nextFileIndex = 0;
      bool hasError = false;
      String? errorMessage;
      bool isCancelled = false;

      Future<void> uploadWorker() async {
        while (true) {
          if (hasError || isCancelled) return;

          int fileIndex;
          if (nextFileIndex >= filesToActuallySend.length) {
            break;
          }
          fileIndex = nextFileIndex;
          nextFileIndex++;

          final fileInfo = filesToActuallySend[fileIndex];

          // Check cancellation
          final currentSession = _ref
              .read(activeTransfersProvider)
              .firstWhere(
                (s) => s.id == sessionId,
                orElse: () => TransferSession(
                  id: '',
                  fileName: '',
                  totalBytes: 0,
                  bytesTransferred: 0,
                  isSending: true,
                  deviceName: '',
                  status: TransferStatus.failed,
                ),
              );
          if (currentSession.status == TransferStatus.cancelled) {
            isCancelled = true;
            return;
          }

          final formattedHost = formatHostForUrl(targetDevice.ip);
          final uploadUri = Uri.parse(
            'https://$formattedHost:${targetDevice.httpPort}/api/transfer/upload',
          );
          debugPrint(
            '[SharingService] Worker: Starting upload of "${fileInfo.relativeName}" '
            '(${(fileInfo.size / (1024 * 1024)).toStringAsFixed(2)} MB) to $uploadUri',
          );

          HttpClientRequest? uploadRequest;
          try {
            uploadRequest = await client.postUrl(uploadUri);
            _currentUploadRequests
                .putIfAbsent(sessionId, () => [])
                .add(uploadRequest);

            uploadRequest.headers.add('Authorization', 'Bearer $token');
            uploadRequest.headers.add(
              'X-File-Name',
              Uri.encodeComponent(fileInfo.relativeName),
            );
            uploadRequest.headers.contentType = ContentType.binary;
            uploadRequest.contentLength = fileInfo.size;

            localActiveFiles[fileInfo.relativeName] = ActiveFileProgress(
              fileName: p.basename(fileInfo.relativeName),
              bytesTransferred: 0,
              totalBytes: fileInfo.size,
            );

            _ref
                .read(activeTransfersProvider.notifier)
                .updateProgress(
                  sessionId,
                  totalBytesSent,
                  completedFilesCount: completedFilesCount,
                  activeFiles: localActiveFiles.values.toList(),
                );

            final fileStream = File(fileInfo.path).openRead();

            int lastProgressUpdateMs = 0;

            await for (final chunk in fileStream) {
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              if (nowMs - lastProgressUpdateMs >= 100) {
                lastProgressUpdateMs = nowMs;
                final currentSessionInner = _ref
                    .read(activeTransfersProvider)
                    .firstWhere(
                      (s) => s.id == sessionId,
                      orElse: () => TransferSession(
                        id: '',
                        fileName: '',
                        totalBytes: 0,
                        bytesTransferred: 0,
                        isSending: true,
                        deviceName: '',
                        status: TransferStatus.failed,
                      ),
                    );
                if (currentSessionInner.status == TransferStatus.cancelled) {
                  isCancelled = true;
                  uploadRequest.abort();
                  return;
                }

                _ref
                    .read(activeTransfersProvider.notifier)
                    .updateProgress(
                      sessionId,
                      totalBytesSent,
                      completedFilesCount: completedFilesCount,
                      activeFiles: localActiveFiles.values.toList(),
                    );
              }

              uploadRequest.add(chunk);
              totalBytesSent += chunk.length;

              final current = localActiveFiles[fileInfo.relativeName]!;
              localActiveFiles[fileInfo.relativeName] = ActiveFileProgress(
                fileName: current.fileName,
                bytesTransferred: current.bytesTransferred + chunk.length,
                totalBytes: current.totalBytes,
              );
            }

            debugPrint(
              '[SharingService] Request stream completed for ${fileInfo.relativeName}. Waiting for response...',
            );
            final uploadResponse = await uploadRequest.close().timeout(
              const Duration(seconds: 120),
            );
            debugPrint(
              '[SharingService] Response received for ${fileInfo.relativeName}: ${uploadResponse.statusCode}',
            );

            if (uploadResponse.statusCode != HttpStatus.ok) {
              String errorDetail = '';
              try {
                errorDetail = await utf8.decoder.bind(uploadResponse).join();
              } catch (_) {}
              debugPrint(
                '[SharingService] Upload failed with status ${uploadResponse.statusCode} for ${fileInfo.relativeName}. Response: $errorDetail',
              );
              throw Exception(
                'Upload failed with status code ${uploadResponse.statusCode}: $errorDetail',
              );
            } else {
              await uploadResponse.drain();
            }

            localActiveFiles.remove(fileInfo.relativeName);
            completedFilesCount++;

            _ref
                .read(activeTransfersProvider.notifier)
                .updateProgress(
                  sessionId,
                  totalBytesSent,
                  completedFilesCount: completedFilesCount,
                  activeFiles: localActiveFiles.values.toList(),
                );
          } catch (e) {
            debugPrint(
              '[SharingService] Error uploading file ${fileInfo.relativeName}: $e',
            );
            hasError = true;
            errorMessage = e.toString();
            try {
              uploadRequest?.abort();
            } catch (_) {}
            return;
          } finally {
            if (uploadRequest != null) {
              if (_currentUploadRequests[sessionId] != null) {
                _currentUploadRequests[sessionId]!.remove(uploadRequest);
                if (_currentUploadRequests[sessionId]!.isEmpty) {
                  _currentUploadRequests.remove(sessionId);
                }
              }
            }
          }
        }
      }

      final concurrencyLimit = min(3, filesToActuallySend.length);
      final workers = List.generate(concurrencyLimit, (_) => uploadWorker());
      await Future.wait(workers);

      if (isCancelled) {
        return false;
      }

      if (hasError) {
        throw Exception(errorMessage ?? 'Unknown transfer error');
      }

      debugPrint('[SharingService] All uploads completed successfully.');
      _ref
          .read(activeTransfersProvider.notifier)
          .updateProgress(
            sessionId,
            totalSize,
            status: TransferStatus.success,
            completedFilesCount: filesToSend.length,
            activeFiles: [],
          );
      return true;
    } catch (e) {
      debugPrint('[SharingService] Failed to send files: $e');
      final currentSessionsInner = _ref.read(activeTransfersProvider);
      final currentSessionInner = currentSessionsInner.firstWhere(
        (s) => s.id == sessionId,
        orElse: () => TransferSession(
          id: '',
          fileName: '',
          totalBytes: 0,
          bytesTransferred: 0,
          isSending: true,
          deviceName: '',
          status: TransferStatus.failed,
        ),
      );
      if (currentSessionInner.status != TransferStatus.cancelled) {
        _ref
            .read(activeTransfersProvider.notifier)
            .updateStatus(sessionId, TransferStatus.failed);
      }
      return false;
    } finally {
      _currentUploadRequests.remove(sessionId);
      client.close();
    }
  }

  Future<LyricsImportOutcome> _importLyricsPackageWithConflict({
    required String localCacheKey,
    required Map<String, dynamic> incomingPackage,
  }) {
    return LyricsPackageImporter(
      MetadataDatabase(),
    ).import(localCacheKey: localCacheKey, incomingPackage: incomingPackage);
  }

  Future<LanSyncOutcome> _importLyricsList(List<dynamic> lyrics) async {
    final db = MetadataDatabase();

    _progressStage(
      LanSyncStage.importing,
      processed: 0,
      total: lyrics.length,
    );

    // 曲库只读一遍、归一化只算一遍，之后每条远端条目都是内存查表。
    // 此前是「每条条目对全库跑一次 title/artist 正则归一化」：3000 首的库
    // 约 1800 万次 replaceAll，主 isolate 会僵住几十秒。
    final matcher = await RemoteSongMatcher.build(db: db);

    int matchedCount = 0;
    int addedCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;
    int missingCount = 0;
    int ambiguousCount = 0;
    final missingSamples = <String>[];
    final ambiguousSamples = <String>[];

    for (final item in lyrics) {
      _throwIfCancelled();

      final map = item as Map<String, dynamic>;
      final title = map['title'] as String? ?? '';
      final artist = map['artist'] as String? ?? '';
      final album = map['album'] as String?;
      final durationMs = map['duration_ms'] as int?;
      final displayName = title.isEmpty ? '?' : title;

      final match = matcher.matchByMetadata(
        title: title,
        artist: artist,
        album: album,
        durationMs: durationMs,
      );

      if (match.isEmpty) {
        // 「本地压根没有这首歌」和「本地有但本机这份更好」是两件事：
        // 前者用户可以补文件 / 检查歌名，后者不需要做任何事。
        missingCount++;
        if (missingSamples.length < LanSyncReceipt.maxSamples) {
          missingSamples.add(displayName);
        }
        _progressAdvance();
        continue;
      }

      // 按「条目」计数，不按命中歌曲数：一首远端条目命中多首本地版本
      // （live / 伴奏 / 不同采样率）时，matched 虚高会让统计对不上直觉。
      matchedCount++;

      if (match.matches.length > 1) {
        ambiguousCount++;
        if (ambiguousSamples.length < LanSyncReceipt.maxSamples) {
          ambiguousSamples.add(displayName);
        }
      }

      for (final song in match.matches) {
        final localQuery = LyricsQuery(
          filePath: song.path,
          fileName: p.basename(song.path),
          title: song.title,
          artist: song.artist,
          album: song.album,
          duration: song.duration != null
              ? Duration(milliseconds: song.duration!)
              : null,
        );
        final localCacheKey = localQuery.cacheKey;

        final outcome = await _importLyricsPackageWithConflict(
          localCacheKey: localCacheKey,
          incomingPackage: map,
        );
        switch (outcome) {
          case LyricsImportOutcome.added:
            addedCount++;
          case LyricsImportOutcome.updated:
            updatedCount++;
          case LyricsImportOutcome.skipped:
            skippedCount++;
        }
      }

      _progressAdvance();
    }

    return LanSyncOutcome(
      matched: matchedCount,
      added: addedCount,
      updated: updatedCount,
      skipped: skippedCount,
      missing: missingCount,
      ambiguous: ambiguousCount,
      missingSamples: missingSamples,
      ambiguousSamples: ambiguousSamples,
    );
  }

  /// 收集本机所有「有歌词」的曲目，供推送与导出共用。
  ///
  /// 先把 cacheKey 全算出来，再用两次批量查询取缓存与译文。旧实现是逐首
  /// `getLyricsCache` + `getLyricsTranslationCaches`：3000 首就是 6000 次
  /// 数据库往返，全程只显示一个 toast，看起来像卡死。
  Future<List<SongMetadataPackage>> _collectLyricsPackages() async {
    final db = MetadataDatabase();
    _progressStage(LanSyncStage.preparing);
    final songs = await db.getAllSongMetadata();

    final songByCacheKey = <String, SongMetadata>{};
    for (final song in songs) {
      final query = LyricsQuery(
        filePath: song.path,
        fileName: p.basename(song.path),
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration != null
            ? Duration(milliseconds: song.duration!)
            : null,
      );
      songByCacheKey[query.cacheKey] = song;
    }

    final caches = await db.getLyricsCachesByKeys(songByCacheKey.keys);
    final exportKeys = caches.entries
        .where((entry) => entry.value.source != LyricsCacheSource.none)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (exportKeys.isEmpty) return const [];

    final translationsByCacheKey = await db.getLyricsTranslationCachesByKeys(
      exportKeys,
    );

    final packages = <SongMetadataPackage>[];
    for (final cacheKey in exportKeys) {
      final song = songByCacheKey[cacheKey];
      final cacheRecord = caches[cacheKey];
      if (song == null || cacheRecord == null) continue;
      final translations =
          translationsByCacheKey[cacheKey] ??
          const <LyricsTranslationCacheRecord>[];
      packages.add(
        SongMetadataPackage(
          senderPath: song.path,
          title: song.title,
          artist: song.artist,
          album: song.album,
          durationMs: song.duration,
          lyricsCache: cacheRecord.toMap(),
          translations: translations
              .map((t) => t.toMap())
              .toList(growable: false),
          // 内容指纹：接收端据此跳过「内容一样、只是时间戳不同」的重写。
          contentHash: lyricsContentHashOf(cacheRecord),
        ),
      );
    }
    return packages;
  }

  Future<LanSyncOutcome> syncLyricsToDevice(LanDevice targetDevice) async {
    return _runSyncExclusive(
      'lyrics/${targetDevice.id}',
      LanSyncKind.lyrics,
      () async {
        _beginProgress(
          LanSyncKind.lyrics,
          LanSyncDirection.outgoing,
          targetDevice.name,
        );
        try {
          final packages = await _collectLyricsPackages();
          if (packages.isEmpty) {
            // 本机没有任何歌词可发：不是失败，但也不该说「同步完成 0 首」。
            return const LanSyncOutcome();
          }
          return await _sendLyricsPackages(targetDevice, packages);
        } finally {
          _endProgress();
        }
      },
    );
  }

  Future<LanSyncOutcome> _sendLyricsPackages(
    LanDevice targetDevice,
    List<SongMetadataPackage> packages,
  ) async {
    final items = packages
        .map((package) => package.toJson())
        .toList(growable: false);

    // v1 对端只能收「一个请求装全部」的老格式；v2 按批发送，单请求体积有上限。
    final canChunk = targetDevice.supportsChunkedSync;
    final chunks = canChunk
        ? chunkLanSyncItems(items)
        : <List<Map<String, dynamic>>>[items];

    _progressStage(
      LanSyncStage.transferring,
      processed: 0,
      total: items.length,
    );

    final client = TlsCertificateService.createPinnedHttpClient(
      expectedFingerprint: targetDevice.certFingerprint,
    );
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final formattedHost = formatHostForUrl(targetDevice.ip);
      final uri = Uri.parse(
        'https://$formattedHost:${targetDevice.httpPort}/api/lyrics/import',
      );

      final transferId =
          '${DateTime.now().microsecondsSinceEpoch}_${chunks.length}';
      var matched = 0;
      var added = 0;
      var updated = 0;
      var skipped = 0;

      for (var index = 0; index < chunks.length; index++) {
        _throwIfCancelled();
        final isLast = index == chunks.length - 1;
        final payload = <String, dynamic>{
          'version': kLanSyncProtocolVersion,
          'sender_id': _deviceId,
          'sender_name': _deviceName,
          'lyrics': chunks[index],
          if (canChunk) ...{
            'transfer_id': transferId,
            'chunk_index': index,
            'chunk_total': chunks.length,
            'total_items': items.length,
          },
        };

        final result = await _postSyncJson(
          client,
          uri,
          payload,
          allowGzip: canChunk,
        );

        if (result.status == HttpStatus.forbidden ||
            result.body['accepted'] == false) {
          throw Exception('rejected');
        }
        if (result.status == HttpStatus.conflict) {
          // 分块会话过期（对端 TTL 到了，或中途重启）：让用户重试，
          // 不能把 409 笼统当成网络错误。
          throw Exception('chunk session expired');
        }
        if (result.status != HttpStatus.ok) {
          throw Exception('Server returned status code ${result.status}');
        }

        _progressAdvance(chunks[index].length);

        // 中间块只有「收到了」，统计以最后一块为准。
        if (isLast) {
          matched = result.body['matched'] as int? ?? 0;
          skipped = result.body['skipped'] as int? ?? 0;
          added = result.body['added'] as int? ?? 0;
          updated = result.body['updated'] as int? ?? 0;
        }
      }

      return LanSyncOutcome(
        matched: matched,
        added: added,
        updated: updated,
        skipped: skipped,
      );
    } finally {
      client.close();
    }
  }

  Future<LanSyncOutcome> pullLyricsFromDevice(LanDevice targetDevice) {
    return _runSyncExclusive(
      'lyrics-pull/${targetDevice.id}',
      LanSyncKind.lyrics,
      () async {
        _beginProgress(
          LanSyncKind.lyrics,
          LanSyncDirection.outgoing,
          targetDevice.name,
        );
        try {
          return await _pullLyricsFromDevice(targetDevice);
        } finally {
          _endProgress();
        }
      },
    );
  }

  Future<LanSyncOutcome> _pullLyricsFromDevice(LanDevice targetDevice) async {
    // 拉取时本地在等对端把整包发过来，期间没有任何可量化的进度。
    _progressStage(LanSyncStage.waitingPeer);
    final client = TlsCertificateService.createPinnedHttpClient(
      expectedFingerprint: targetDevice.certFingerprint,
    );
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final formattedHost = formatHostForUrl(targetDevice.ip);
      final encodedSenderId = Uri.encodeComponent(_deviceId);
      final encodedSenderName = Uri.encodeComponent(_deviceName);
      final uri = Uri.parse(
        'https://$formattedHost:${targetDevice.httpPort}/api/lyrics/export?sender_id=$encodedSenderId&sender_name=$encodedSenderName',
      );
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(LanSyncLimits.readTimeout);

      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder
            .bind(response)
            .join()
            .timeout(LanSyncLimits.readTimeout);
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json['accepted'] == false) {
          throw Exception('rejected');
        }

        final lyrics = json['lyrics'] as List<dynamic>? ?? [];
        return await _importLyricsList(lyrics);
      } else if (response.statusCode == HttpStatus.forbidden) {
        throw Exception('rejected');
      } else {
        throw Exception('Server returned status code ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> _handleExportLyrics(HttpRequest request) async {
    final senderId = request.uri.queryParameters['sender_id'] ?? 'unknown';
    final senderName = request.uri.queryParameters['sender_name'] ?? 'Unknown';

    final completer = Completer<bool>();
    _ref
        .read(incomingLyricsRequestProvider.notifier)
        .setRequest(
          IncomingLyricsRequest(
            senderId: senderId,
            senderName: senderName,
            type: IncomingLyricsRequestType.exportLyrics,
            onDecision: (accepted) {
              completer.complete(accepted);
              _ref
                  .read(incomingLyricsRequestProvider.notifier)
                  .setRequest(null);
            },
          ),
        );

    final accepted = await completer.future;
    if (!accepted) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'accepted': false, 'reason': 'Request rejected by user'}),
      );
      await request.response.close();
      return;
    }

    // 与推送方向共用同一个收集器：批量查询、内容指纹、载荷结构都只有一份。
    final packages = await _collectLyricsPackages();
    final exportedList = packages
        .map((package) => package.toJson())
        .toList(growable: false);

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'version': kLanSyncProtocolVersion,
        'accepted': true,
        'lyrics': exportedList,
      }),
    );
    await request.response.close();

    // 导出方向（对端来拉取）在这台设备上也给一条回执，否则用户点完「接受」
    // 同样什么都看不到。
    if (exportedList.isNotEmpty) {
      _publishReceipt(
        LanSyncReceipt(
          kind: LanSyncKind.lyrics,
          direction: LanSyncDirection.outgoing,
          added: exportedList.length,
          deviceName: senderName,
        ),
      );
    }
  }

  /// 收歌词导入请求。
  ///
  /// 兼容两种格式：
  /// - v1：`{sender_id, lyrics:[...]}`，一次性整包；
  /// - v2：`{transfer_id, chunk_index, chunk_total, lyrics:[...]}`，按批到达。
  ///   确认框只在第一块弹一次，最后一块才真正落库。老客户端不带这些字段，
  ///   等价于 `chunk_total == 1`，走同一条路径。
  Future<void> _handleImportLyrics(HttpRequest request) async {
    final json = await _readSyncJsonBody(request);
    if (json == null) return;

    final senderId = json['sender_id'] as String? ?? 'unknown';
    final senderName = json['sender_name'] as String? ?? 'Unknown';
    final incoming = json['lyrics'] as List<dynamic>? ?? const [];
    final chunkTotal = json['chunk_total'] as int? ?? 1;
    final chunkIndex = json['chunk_index'] as int? ?? 0;
    final transferId = json['transfer_id'] as String? ?? 'single';
    final totalItems = json['total_items'] as int? ?? incoming.length;

    if (chunkTotal <= 1) {
      final accepted = await _confirmIncomingLyrics(
        senderId: senderId,
        senderName: senderName,
        itemCount: totalItems,
      );
      if (!accepted) {
        await _closeWithJson(request, HttpStatus.forbidden, {
          'accepted': false,
          'reason': 'Request rejected by user',
        });
        return;
      }
      // 单块（v1 对端或内容很少）时整包已经在手上，直接进入导入。
      _beginProgress(
        LanSyncKind.lyrics,
        LanSyncDirection.incoming,
        senderName,
      );
      _progressStage(
        LanSyncStage.importing,
        processed: 0,
        total: totalItems,
      );
      try {
        await _finishLyricsImport(request, incoming, senderName: senderName);
      } finally {
        _endProgress();
      }
      return;
    }

    _pruneChunkSessions(_lyricsChunkSessions);
    final sessionKey = '$senderId/$transferId';

    if (chunkIndex == 0) {
      final accepted = await _confirmIncomingLyrics(
        senderId: senderId,
        senderName: senderName,
        itemCount: totalItems,
      );
      if (!accepted) {
        _lyricsChunkSessions.remove(sessionKey);
        await _closeWithJson(request, HttpStatus.forbidden, {
          'accepted': false,
          'reason': 'Request rejected by user',
        });
        return;
      }
      final session = _LanChunkSession(
        totalChunks: chunkTotal,
        senderId: senderId,
      )..items.addAll(incoming);
      session.receivedChunks.add(chunkIndex);
      _lyricsChunkSessions[sessionKey] = session;
      // 用户已经点过「接受」，接下来几分钟都在传数据：给一个可见的进度，
      // 否则屏幕上除了那个已经消失的确认框什么都没有。
      _beginProgress(
        LanSyncKind.lyrics,
        LanSyncDirection.incoming,
        senderName,
      );
      _progressStage(
        LanSyncStage.transferring,
        processed: incoming.length,
        total: totalItems,
      );
      await _closeWithJson(request, HttpStatus.ok, {
        'accepted': true,
        'chunk_index': chunkIndex,
        'chunk_total': chunkTotal,
      });
      return;
    }

    final session = _lyricsChunkSessions[sessionKey];
    if (session == null || session.totalChunks != chunkTotal) {
      // 会话过期（超过 TTL）、发送端换了 transfer_id、或批次总数对不上：
      // 让对端重头再来，而不是把这一批当成一次完整导入（那会把确认框弹第二遍）。
      _lyricsChunkSessions.remove(sessionKey);
      await _closeWithJson(request, HttpStatus.conflict, {
        'accepted': false,
        'reason': 'chunk session expired',
      });
      return;
    }

    if (!session.receivedChunks.add(chunkIndex)) {
      // 同一批被重发（发送端重试）：只回应，不重复追加。
      await _closeWithJson(request, HttpStatus.ok, {
        'accepted': true,
        'chunk_index': chunkIndex,
        'chunk_total': chunkTotal,
      });
      return;
    }

    session.items.addAll(incoming);
    session.lastTouched = DateTime.now();
    _progressAdvance(incoming.length);

    if (chunkIndex < chunkTotal - 1) {
      await _closeWithJson(request, HttpStatus.ok, {
        'accepted': true,
        'chunk_index': chunkIndex,
        'chunk_total': chunkTotal,
      });
      return;
    }

    _lyricsChunkSessions.remove(sessionKey);
    try {
      await _finishLyricsImport(
        request,
        session.items,
        senderName: senderName,
      );
    } finally {
      _endProgress();
    }
  }

  Future<bool> _confirmIncomingLyrics({
    required String senderId,
    required String senderName,
    required int itemCount,
  }) {
    final completer = Completer<bool>();
    _ref
        .read(incomingLyricsRequestProvider.notifier)
        .setRequest(
          IncomingLyricsRequest(
            senderId: senderId,
            senderName: senderName,
            type: IncomingLyricsRequestType.importLyrics,
            lyricsCount: itemCount,
            onDecision: (accepted) {
              if (!completer.isCompleted) completer.complete(accepted);
              _ref
                  .read(incomingLyricsRequestProvider.notifier)
                  .setRequest(null);
            },
          ),
        );
    return completer.future;
  }

  Future<void> _finishLyricsImport(
    HttpRequest request,
    List<dynamic> lyrics, {
    String? senderName,
  }) async {
    final startedAt = DateTime.now();
    final outcome = await _importLyricsList(lyrics);
    // 被动方此前完全没有反馈：点「接受」→ 对话框消失 → 什么都没发生。
    // 导入本身可能是几十秒的匹配 + 写库，用户只能猜。
    _publishReceipt(
      outcome.toReceipt(
        kind: LanSyncKind.lyrics,
        direction: LanSyncDirection.incoming,
        deviceName: senderName,
        elapsed: DateTime.now().difference(startedAt),
      ),
    );

    await _closeWithJson(request, HttpStatus.ok, {
      'accepted': true,
      'matched': outcome.matched,
      'added': outcome.added,
      'updated': outcome.updated,
      'skipped': outcome.skipped,
      // 旧版客户端只认 overwritten。
      'overwritten': outcome.added + outcome.updated,
    });
  }

  Future<LanSyncOutcome> sendPlaylistsToDevice(
    LanDevice targetDevice,
    List<Playlist> playlists,
  ) async {
    if (playlists.isEmpty) {
      return const LanSyncOutcome();
    }

    return _runSyncExclusive(
      'playlists/${targetDevice.id}',
      LanSyncKind.playlists,
      () async {
        _beginProgress(
          LanSyncKind.playlists,
          LanSyncDirection.outgoing,
          targetDevice.name,
        );
        try {
          return await _sendPlaylistsPayload(targetDevice, playlists);
        } finally {
          _endProgress();
        }
      },
    );
  }

  Future<LanSyncOutcome> _sendPlaylistsPayload(
    LanDevice targetDevice,
    List<Playlist> playlists,
  ) async {
    final scannerRoots = _ref.read(scannerServiceProvider).rootPaths;
    final payload = <Map<String, dynamic>>[];
    for (final playlist in playlists) {
      payload.add({
        'id': playlist.id,
        'name': playlist.name,
        'm3u_content': M3uUtils.generate(
          playlist.songs,
          playlistName: playlist.name,
          rootPaths: scannerRoots,
        ),
        'songs_count': playlist.songs.length,
      });
    }

    // 老对端只认整包；v2 按批发，单请求体积有上限。
    final canChunk = targetDevice.supportsChunkedSync;
    final chunks = canChunk
        ? chunkLanSyncItems(payload)
        : <List<Map<String, dynamic>>>[payload];

    _progressStage(
      LanSyncStage.transferring,
      processed: 0,
      total: payload.length,
    );

    final client = TlsCertificateService.createPinnedHttpClient(
      expectedFingerprint: targetDevice.certFingerprint,
    );
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final formattedHost = formatHostForUrl(targetDevice.ip);
      final uri = Uri.parse(
        'https://$formattedHost:${targetDevice.httpPort}/api/playlists/import',
      );

      final transferId =
          '${DateTime.now().microsecondsSinceEpoch}_${chunks.length}';

      for (var index = 0; index < chunks.length; index++) {
        _throwIfCancelled();
        final isLast = index == chunks.length - 1;
        final result = await _postSyncJson(
          client,
          uri,
          {
            'version': kLanSyncProtocolVersion,
            'sender_id': _deviceId,
            'sender_name': _deviceName,
            'playlists': chunks[index],
            if (canChunk) ...{
              'transfer_id': transferId,
              'chunk_index': index,
              'chunk_total': chunks.length,
              'total_items': payload.length,
            },
          },
          allowGzip: canChunk,
        );

        if (result.status == HttpStatus.forbidden ||
            result.body['accepted'] == false) {
          throw Exception('rejected');
        }
        if (result.status == HttpStatus.conflict) {
          // 分块会话过期（对端 TTL 到了，或中途重启）：让用户重试，
          // 不能把 409 笼统当成网络错误。
          throw Exception('chunk session expired');
        }
        if (result.status != HttpStatus.ok) {
          throw Exception('Server returned status code ${result.status}');
        }

        _progressAdvance(chunks[index].length);

        if (isLast) {
          // 对端视角的落地数只用于日志：给用户看的数字用本机口径，
          // 因为合并语义下对端可能一首都没新增，显示「共 0 首」像没发成功。
          debugPrint(
            '[SharingService] Playlists received by peer: '
            '${result.body['imported_playlists'] ?? 0} playlist(s), '
            '${result.body['imported_songs'] ?? 0} song(s)',
          );
        }
      }

      return LanSyncOutcome(
        containers: playlists.length,
        added: playlists.fold<int>(0, (sum, p) => sum + p.songs.length),
      );
    } finally {
      client.close();
    }
  }

  Future<LanSyncOutcome> pullPlaylistsFromDevice(
    LanDevice targetDevice,
  ) {
    return _runSyncExclusive(
      'playlists-pull/${targetDevice.id}',
      LanSyncKind.playlists,
      () async {
        _beginProgress(
          LanSyncKind.playlists,
          LanSyncDirection.outgoing,
          targetDevice.name,
        );
        try {
          return await _pullPlaylistsFromDevice(targetDevice);
        } finally {
          _endProgress();
        }
      },
    );
  }

  Future<LanSyncOutcome> _pullPlaylistsFromDevice(
    LanDevice targetDevice,
  ) async {
    _progressStage(LanSyncStage.waitingPeer);
    final client = TlsCertificateService.createPinnedHttpClient(
      expectedFingerprint: targetDevice.certFingerprint,
    );
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final formattedHost = formatHostForUrl(targetDevice.ip);
      final encodedSenderId = Uri.encodeComponent(_deviceId);
      final encodedSenderName = Uri.encodeComponent(_deviceName);
      final uri = Uri.parse(
        'https://$formattedHost:${targetDevice.httpPort}/api/playlists/export?sender_id=$encodedSenderId&sender_name=$encodedSenderName',
      );
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(LanSyncLimits.readTimeout);

      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder
            .bind(response)
            .join()
            .timeout(LanSyncLimits.readTimeout);
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json['accepted'] == false) {
          throw Exception('rejected');
        }

        final playlistsJson = json['playlists'] as List<dynamic>? ?? [];
        return await _importPlaylistsPayload(playlistsJson);
      } else if (response.statusCode == HttpStatus.forbidden) {
        throw Exception('rejected');
      } else {
        throw Exception('Server returned status code ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<LanSyncOutcome> _importPlaylistsPayload(
    List<dynamic> playlistsJson,
  ) async {
    int importedPlaylistsCount = 0;
    int mergedPlaylistsCount = 0;
    int importedSongsCount = 0;
    int skippedSongsCount = 0;
    int missingSongsCount = 0;
    int ambiguousSongsCount = 0;
    final missingSamples = <String>[];
    final ambiguousSamples = <String>[];

    final playlistService = _ref.read(playlistServiceProvider);
    final scannerRoots = _ref.read(scannerServiceProvider).rootPaths;

    _progressStage(
      LanSyncStage.importing,
      processed: 0,
      total: playlistsJson.length,
    );

    for (final item in playlistsJson) {
      _throwIfCancelled();
      if (item is! Map<String, dynamic>) {
        _progressAdvance();
        continue;
      }
      final rawName = item['name'] as String? ?? 'Imported Playlist';
      final m3uContent = item['m3u_content'] as String?;

      if (m3uContent != null && m3uContent.isNotEmpty) {
        final data = M3uUtils.parse(m3uContent);
        final playlistName = data.playlistName ?? rawName;

        // 占位条目不入库：它们没有对应本地文件，播不了，UI 又没有任何缺失
        // 标记，用户只会看到「导入 N 首」然后播到一半失败。
        final missingEntries = <M3uEntry>[];
        final ambiguousEntries = <M3uEntry>[];
        final songs = await M3uUtils.resolveMusicFiles(
          data.entries,
          rootPaths: scannerRoots,
          includeMissingPlaceholders: false,
          missingEntries: missingEntries,
          ambiguousEntries: ambiguousEntries,
        );

        // 同名歌单合并而不是新建「名字 (1)」副本。
        final result = await playlistService.mergeOrAddPlaylist(
          name: playlistName,
          songs: songs,
        );

        importedPlaylistsCount++;
        importedSongsCount += result.addedSongs;
        skippedSongsCount += result.skippedSongs;
        missingSongsCount += missingEntries.length;
        ambiguousSongsCount += ambiguousEntries.length;
        if (result.merged) mergedPlaylistsCount++;

        for (final entry in missingEntries) {
          if (missingSamples.length >= LanSyncReceipt.maxSamples) break;
          missingSamples.add(_m3uEntryDisplayName(entry));
        }
        for (final entry in ambiguousEntries) {
          if (ambiguousSamples.length >= LanSyncReceipt.maxSamples) break;
          ambiguousSamples.add(_m3uEntryDisplayName(entry));
        }
      }
      _progressAdvance();
    }

    debugPrint(
      '[SharingService] Playlists imported: $importedPlaylistsCount '
      '($mergedPlaylistsCount merged), songs +$importedSongsCount',
    );

    return LanSyncOutcome(
      containers: importedPlaylistsCount,
      added: importedSongsCount,
      skipped: skippedSongsCount,
      missing: missingSongsCount,
      ambiguous: ambiguousSongsCount,
      missingSamples: missingSamples,
      ambiguousSamples: ambiguousSamples,
    );
  }

  String _m3uEntryDisplayName(M3uEntry entry) {
    final title = entry.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final normalized = entry.path.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    return name.isEmpty ? entry.path : name;
  }

  Future<void> _handleExportPlaylists(HttpRequest request) async {
    final senderId = request.uri.queryParameters['sender_id'] ?? 'unknown';
    final senderName = request.uri.queryParameters['sender_name'] ?? 'Unknown';

    final completer = Completer<bool>();
    _ref
        .read(incomingPlaylistRequestProvider.notifier)
        .setRequest(
          IncomingPlaylistRequest(
            senderId: senderId,
            senderName: senderName,
            type: IncomingPlaylistRequestType.exportPlaylists,
            onDecision: (accepted) {
              completer.complete(accepted);
              _ref
                  .read(incomingPlaylistRequestProvider.notifier)
                  .setRequest(null);
            },
          ),
        );

    final accepted = await completer.future;
    if (!accepted) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'accepted': false, 'reason': 'Request rejected by user'}),
      );
      await request.response.close();
      return;
    }

    final playlists = _ref.read(playlistServiceProvider).playlists;
    final scannerRoots = _ref.read(scannerServiceProvider).rootPaths;
    final List<Map<String, dynamic>> exportedList = [];

    for (final playlist in playlists) {
      if (playlist.songs.isNotEmpty) {
        exportedList.add({
          'id': playlist.id,
          'name': playlist.name,
          'm3u_content': M3uUtils.generate(
            playlist.songs,
            playlistName: playlist.name,
            rootPaths: scannerRoots,
          ),
          'songs_count': playlist.songs.length,
        });
      }
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({'accepted': true, 'playlists': exportedList}),
    );
    await request.response.close();

    if (exportedList.isNotEmpty) {
      _publishReceipt(
        LanSyncReceipt(
          kind: LanSyncKind.playlists,
          direction: LanSyncDirection.outgoing,
          containers: exportedList.length,
          added: exportedList.fold<int>(
            0,
            (sum, item) => sum + (item['songs_count'] as int? ?? 0),
          ),
          deviceName: senderName,
        ),
      );
    }
  }

  Future<void> _handleImportPlaylists(HttpRequest request) async {
    final json = await _readSyncJsonBody(request);
    if (json == null) return;

    final senderId = json['sender_id'] as String? ?? 'unknown';
    final senderName = json['sender_name'] as String? ?? 'Unknown';
    final incoming = json['playlists'] as List<dynamic>? ?? const [];
    final chunkTotal = json['chunk_total'] as int? ?? 1;
    final chunkIndex = json['chunk_index'] as int? ?? 0;
    final transferId = json['transfer_id'] as String? ?? 'single';

    if (chunkTotal <= 1) {
      final accepted = await _confirmIncomingPlaylists(
        senderId: senderId,
        senderName: senderName,
        playlists: incoming,
      );
      if (!accepted) {
        await _closeWithJson(request, HttpStatus.forbidden, {
          'accepted': false,
          'reason': 'Request rejected by user',
        });
        return;
      }
      _beginProgress(
        LanSyncKind.playlists,
        LanSyncDirection.incoming,
        senderName,
      );
      _progressStage(
        LanSyncStage.importing,
        processed: 0,
        total: incoming.length,
      );
      try {
        await _finishPlaylistImport(
          request,
          incoming,
          senderName: senderName,
        );
      } finally {
        _endProgress();
      }
      return;
    }

    _pruneChunkSessions(_playlistChunkSessions);
    final sessionKey = '$senderId/$transferId';

    if (chunkIndex == 0) {
      final accepted = await _confirmIncomingPlaylists(
        senderId: senderId,
        senderName: senderName,
        playlists: incoming,
      );
      if (!accepted) {
        _playlistChunkSessions.remove(sessionKey);
        await _closeWithJson(request, HttpStatus.forbidden, {
          'accepted': false,
          'reason': 'Request rejected by user',
        });
        return;
      }
      final session = _LanChunkSession(
        totalChunks: chunkTotal,
        senderId: senderId,
      )..items.addAll(incoming);
      session.receivedChunks.add(chunkIndex);
      _playlistChunkSessions[sessionKey] = session;
      _beginProgress(
        LanSyncKind.playlists,
        LanSyncDirection.incoming,
        senderName,
      );
      _progressStage(
        LanSyncStage.transferring,
        processed: incoming.length,
      );
      await _closeWithJson(request, HttpStatus.ok, {
        'accepted': true,
        'chunk_index': chunkIndex,
        'chunk_total': chunkTotal,
      });
      return;
    }

    final session = _playlistChunkSessions[sessionKey];
    if (session == null || session.totalChunks != chunkTotal) {
      _playlistChunkSessions.remove(sessionKey);
      await _closeWithJson(request, HttpStatus.conflict, {
        'accepted': false,
        'reason': 'chunk session expired',
      });
      return;
    }

    if (!session.receivedChunks.add(chunkIndex)) {
      await _closeWithJson(request, HttpStatus.ok, {
        'accepted': true,
        'chunk_index': chunkIndex,
        'chunk_total': chunkTotal,
      });
      return;
    }

    session.items.addAll(incoming);
    session.lastTouched = DateTime.now();
    _progressAdvance(incoming.length);

    if (chunkIndex < chunkTotal - 1) {
      await _closeWithJson(request, HttpStatus.ok, {
        'accepted': true,
        'chunk_index': chunkIndex,
        'chunk_total': chunkTotal,
      });
      return;
    }

    _playlistChunkSessions.remove(sessionKey);
    try {
      await _finishPlaylistImport(
        request,
        session.items,
        senderName: senderName,
      );
    } finally {
      _endProgress();
    }
  }

  Future<bool> _confirmIncomingPlaylists({
    required String senderId,
    required String senderName,
    required List<dynamic> playlists,
  }) {
    var totalSongs = 0;
    for (final p in playlists) {
      if (p is Map<String, dynamic>) {
        totalSongs += p['songs_count'] as int? ?? 0;
      }
    }

    final completer = Completer<bool>();
    _ref
        .read(incomingPlaylistRequestProvider.notifier)
        .setRequest(
          IncomingPlaylistRequest(
            senderId: senderId,
            senderName: senderName,
            type: IncomingPlaylistRequestType.importPlaylists,
            playlistCount: playlists.length,
            songsCount: totalSongs,
            onDecision: (accepted) {
              if (!completer.isCompleted) completer.complete(accepted);
              _ref
                  .read(incomingPlaylistRequestProvider.notifier)
                  .setRequest(null);
            },
          ),
        );
    return completer.future;
  }

  Future<void> _finishPlaylistImport(
    HttpRequest request,
    List<dynamic> playlists, {
    String? senderName,
  }) async {
    final startedAt = DateTime.now();
    final outcome = await _importPlaylistsPayload(playlists);
    _publishReceipt(
      outcome.toReceipt(
        kind: LanSyncKind.playlists,
        direction: LanSyncDirection.incoming,
        deviceName: senderName,
        elapsed: DateTime.now().difference(startedAt),
      ),
    );

    await _closeWithJson(request, HttpStatus.ok, {
      'accepted': true,
      'imported_playlists': outcome.containers,
      'imported_songs': outcome.added,
      'skipped_songs': outcome.skipped,
      'missing_songs': outcome.missing,
      'ambiguous_songs': outcome.ambiguous,
    });
  }
}

class _UploadRequestMetadata {
  final String sessionName;
  final List<TransferFileItem> files;
  final int totalSize;
  final String senderName;
  int bytesTransferredCumulative = 0;
  final Set<String> completedFiles = {};

  /// 本次实际写入了文件的目录。
  ///
  /// 传输结束后只重扫这些目录（`rescanDirectory`），不再整库扫一遍：
  /// 传一首歌触发全库扫描，在大库上是几十秒的事，而这段时间里曲库里
  /// 看不到新歌 —— 用户以为传输失败了。
  final Set<String> receivedDirectories = {};
  String? conflictAction; // 'skip_all', 'overwrite_all', or null
  Future<void>? activeConflictFuture; // Track currently visible conflict dialog
  final Map<String, ActiveFileProgress> activeFilesMap = {};

  _UploadRequestMetadata({
    required this.sessionName,
    required this.files,
    required this.totalSize,
    required this.senderName,
  });
}

class _FileToSend {
  final String path;
  final String relativeName;
  final int size;
  _FileToSend({
    required this.path,
    required this.relativeName,
    required this.size,
  });
}
