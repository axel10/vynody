import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../models/music_file.dart';
import '../../../transcode/transcode_riverpod.dart';
import '../../../utils/file_selector_helper.dart';
import '../../../utils/localized_text.dart';
import '../../audio/audio_riverpod.dart';
import '../../library/music_file_utils.dart';
import '../../metadata/metadata_helper.dart';
import '../../sharing/sharing_riverpod.dart';
import '../clients/subsonic_client.dart';
import '../clients/webdav_client.dart';
import '../clients/smb_client.dart';
import '../clients/jellyfin_client.dart';
import '../proxy/local_stream_proxy.dart';
import '../proxy/remote_media_resolver.dart';
import '../remote_server_models.dart';
import 'remote_download_request.dart';
import 'remote_payload_guard.dart';
import 'remote_track_load_progress.dart';

// 落盘层级 / 请求模型与下载执行分开维护，但对外仍从本文件导出，
// 调用方只认一个 import。
export 'remote_download_request.dart';

enum RemoteDownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

class RemoteDownloadTask {
  final String id;
  final RemoteServer server;
  final MusicFile song;
  final String? trackId;
  final String? webDavPath;
  final String? smbShare;
  final String? smbPath;
  final String downloadUrl;
  final Map<String, String>? headers;
  final String targetPath;
  final RemoteDownloadStatus status;
  final int bytesDownloaded;
  final int totalBytes;
  final double speedBytesPerSec;
  final String? error;
  final DateTime createdAt;
  final DateTime? completedAt;

  RemoteDownloadTask({
    required this.id,
    required this.server,
    required this.song,
    this.trackId,
    this.webDavPath,
    this.smbShare,
    this.smbPath,
    required this.downloadUrl,
    this.headers,
    required this.targetPath,
    this.status = RemoteDownloadStatus.pending,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0.0,
    this.error,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress =>
      totalBytes > 0 ? (bytesDownloaded / totalBytes).clamp(0.0, 1.0) : 0.0;
  bool get isSubsonic => server.type == RemoteServerType.subsonic;
  bool get isWebDav => server.type == RemoteServerType.webdav;
  bool get isSmb => server.type == RemoteServerType.smb;
  bool get isJellyfin => server.type == RemoteServerType.jellyfin;

  RemoteDownloadTask copyWith({
    RemoteDownloadStatus? status,
    int? bytesDownloaded,
    int? totalBytes,
    double? speedBytesPerSec,
    String? error,
    DateTime? completedAt,
  }) {
    return RemoteDownloadTask(
      id: id,
      server: server,
      song: song,
      trackId: trackId,
      webDavPath: webDavPath,
      smbShare: smbShare,
      smbPath: smbPath,
      downloadUrl: downloadUrl,
      headers: headers,
      targetPath: targetPath,
      status: status ?? this.status,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      error: error,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

class RemoteDownloadNotifier extends Notifier<List<RemoteDownloadTask>> {
  static const int _maxConcurrent = 3;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 5,
    ),
  );

  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, int> _lastBytesMap = {};
  final Map<String, DateTime> _lastTimeMap = {};

  /// 已提示过的「服务器侧问题」（serverId → 问题种类），避免批量下载时
  /// 每条失败任务各弹一次 Toast。某台服务器成功下载后整组清空。
  final Map<String, Set<String>> _warnedServerIssues = {};

  bool _shouldWarnServerIssue(String serverId, String kind) {
    return _warnedServerIssues
        .putIfAbsent(serverId, () => <String>{})
        .add(kind);
  }

  void _clearServerIssues(String serverId) {
    _warnedServerIssues.remove(serverId);
  }

  /// 把「服务端用 HTTP 状态码拒绝」翻成能和服务器设置对上的话。
  ///
  /// Jellyfin 的下载走 `/Audio/{id}/stream`，不受用户策略里的「允许下载」约束，
  /// 所以不存在 Subsonic 那种「200 + 失败 JSON」；它拒绝时用的是标准状态码，
  /// Dio 直接抛 DioException。原样透出 `DioException [bad response]...`
  /// 用户既看不懂也定位不到问题。
  ({String? kind, String message})? _describeHttpFailure(Object error) {
    if (error is! DioException) return null;
    switch (error.response?.statusCode) {
      // 401 = token 失效 / 密码错；403 = 该账号无权限（也可能是反代 / WAF 拦截）。
      case 401:
      case 403:
        return (
          kind: 'download_rejected',
          message: currentAppL10n.remoteDownloadUnauthorized,
        );
      // 404 = 曲目已从库里移除，或当前账号看不到它。
      case 404:
        return (kind: null, message: currentAppL10n.remoteDownloadTrackMissing);
    }
    return null;
  }

  @override
  List<RemoteDownloadTask> build() {
    return [];
  }

  /// Resolves the destination directory for downloaded music.
  Future<String> getDownloadFolderPath() async {
    final settings = ref.read(settingsServiceProvider);
    if (settings.hasLanSharingFolderPath) {
      return settings.lanSharingFolderPath;
    }
    final sharingService = ref.read(sharingServiceProvider);
    return await sharingService.getDefaultSharingFolderPath();
  }

  /// Ensures the destination download directory is writable.
  /// If not writable, or if on Android and the target is an internal folder, prompts the user to select/grant an external folder.
  /// Returns `true` if ready and writable, or `false` if user cancelled.
  Future<bool> ensureDownloadFolderWritable() async {
    final sharingService = ref.read(sharingServiceProvider);
    final settings = ref.read(settingsServiceProvider);
    final currentPath = await getDownloadFolderPath();

    bool needsPicker = false;
    if (Platform.isAndroid) {
      if (!settings.hasLanSharingFolderPath) {
        needsPicker = true;
      } else {
        try {
          final docDir = await getApplicationDocumentsDirectory();
          if (p.isWithin(docDir.path, currentPath) ||
              p.equals(docDir.path, currentPath) ||
              currentPath.startsWith('/data/user/') ||
              currentPath.startsWith('/data/data/')) {
            needsPicker = true;
          }
        } catch (_) {}

        if (!needsPicker) {
          final isWritable =
              await sharingService.checkSharingFolderWritable(currentPath);
          if (!isWritable) {
            needsPicker = true;
          }
        }
      }
    } else {
      final isWritable =
          await sharingService.checkSharingFolderWritable(currentPath);
      if (!isWritable) {
        needsPicker = true;
      }
    }

    if (!needsPicker) {
      return true;
    }

    // Directory is internal, not writable, or unmapped on Android
    if (Platform.isAndroid) {
      final androidOutputDirectory = await ref
          .read(transcodeServiceProvider)
          .pickAndroidOutputDirectory();
      if (androidOutputDirectory != null) {
        await AndroidSafStorageHelper.saveMapping(
          androidOutputDirectory.displayPath,
          androidOutputDirectory.treeUri,
        );
        await sharingService.updateSharingFolderPath(
          androidOutputDirectory.displayPath,
        );
        final scanner = ref.read(scannerServiceProvider);
        await scanner.ready;
        if (!scanner.rootPaths.any((p0) => p.equals(p0, androidOutputDirectory.displayPath))) {
          await scanner.addRootPath(androidOutputDirectory.displayPath);
        }
        return true;
      }
      return false;
    } else {
      final dirPath = await FileSelectorHelper.pickDirectory(lockParentWindow: false);
      if (dirPath != null) {
        await sharingService.updateSharingFolderPath(dirPath);
        final scanner = ref.read(scannerServiceProvider);
        await scanner.ready;
        if (!scanner.rootPaths.any((p0) => p.equals(p0, dirPath))) {
          await scanner.addRootPath(dirPath);
        }
        return true;
      }
      return false;
    }
  }

  Future<bool> _checkFileExistsLocally(String targetPath) async {
    try {
      final targetFile = File(targetPath);
      if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
        return true;
      }
    } catch (_) {}

    if (Platform.isAndroid) {
      final mapping = await AndroidSafStorageHelper.findBestMapping(targetPath);
      if (mapping != null) {
        String relativePath = '';
        try {
          relativePath = p.relative(targetPath, from: mapping.key);
        } catch (_) {
          relativePath = p.basename(targetPath);
        }
        return await AndroidSafStorageHelper.fileExists(
          mapping.value,
          relativePath,
        );
      }
    }
    return false;
  }

  String _sanitize(String? input, {String fallback = 'Unknown'}) {
    if (input == null || input.trim().isEmpty) return fallback;
    return input.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  /// Builds the local destination file path for a remote music track.
  ///
  /// [layout] 决定集合层与专辑层，[collectionFolder] 是集合目录名
  /// （艺术家名 / 歌单名，专辑层级不需要）：
  /// - [RemoteDownloadLayout.album]：`<专辑>/`
  /// - [RemoteDownloadLayout.artist]：`<艺术家>/<专辑>/`，缺集合名时逐曲回落到
  ///   专辑艺术家（合辑才不会散架）
  /// - [RemoteDownloadLayout.playlist]：`<歌单>/`，缺集合名时退回 `<专辑>/`
  Future<String> buildLocalTrackPath({
    required MusicFile song,
    required String baseFolder,
    RemoteServer? server,
    String? webDavPath,
    String? collectionFolder,
    RemoteDownloadLayout layout = RemoteDownloadLayout.album,
  }) async {
    // 1. For WebDAV, preserve the exact directory hierarchy from the server
    String? resolvedWebDavPath = webDavPath;
    if (resolvedWebDavPath == null || resolvedWebDavPath.isEmpty) {
      final info = RemoteMediaResolver.parseUri(song.path);
      if (info != null && info.type == RemoteServerType.webdav) {
        resolvedWebDavPath = info.trackIdOrPath;
      }
    }

    if (resolvedWebDavPath != null && resolvedWebDavPath.isNotEmpty) {
      var relPath = resolvedWebDavPath.trim();
      try {
        relPath = Uri.decodeFull(relPath);
      } catch (_) {}

      // Strip server customPath prefix if present (e.g. /dav or /webdav)
      if (server?.customPath != null &&
          server!.customPath!.trim().isNotEmpty &&
          server.customPath!.trim() != '/') {
        final cleanCustom =
            server.customPath!.trim().replaceAll(RegExp(r'/+$'), '');
        if (relPath == cleanCustom) {
          relPath = '';
        } else if (relPath.startsWith('$cleanCustom/')) {
          relPath = relPath.substring(cleanCustom.length);
        }
      }

      final segments = relPath
          .split('/')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .map((s) => _sanitize(s, fallback: 'file'))
          .toList();

      if (segments.isNotEmpty) {
        return p.joinAll([baseFolder, ...segments]);
      }
    }

    // 2. Subsonic / generic remote tracks: 集合目录（可选）+ 专辑目录（可选）+ 曲目。
    // 不套单曲艺术家：合辑里 song.artist 每首都不同，按它分层会把一张专辑拆散。
    final resolvedCollection = collectionFolder != null &&
            collectionFolder.trim().isNotEmpty
        ? collectionFolder
        : (layout == RemoteDownloadLayout.artist
            ? (song.albumArtist ?? song.artist)
            : null);
    final hasCollection =
        resolvedCollection != null && resolvedCollection.trim().isNotEmpty;
    final folderSegments = <String>[
      if (hasCollection) _sanitize(resolvedCollection, fallback: 'Unknown'),
      // 歌单目录下不再按专辑分层，专辑页与艺术家页都要专辑层。
      // 没有集合名时（例如勾选里混进了认不出名字的歌单）统一退回专辑层，
      // 免得整批文件平铺到下载根目录。
      if (!hasCollection || layout != RemoteDownloadLayout.playlist)
        _sanitize(song.album, fallback: 'Unknown Album'),
    ];
    final trackNum = song.trackNumber;
    final trackPrefix = trackNum != null && trackNum > 0
        ? '${trackNum.toString().padLeft(2, '0')} - '
        : '';
    final title = _sanitize(song.title ?? song.name, fallback: 'Track');

    final filename = '$trackPrefix$title${_resolveExtension(song)}';
    return p.joinAll([baseFolder, ...folderSegments, filename]);
  }

  /// 解析远端曲目的落盘扩展名。
  ///
  /// 远端路径是虚拟 URI（如 `subsonic://server/trackId`），从里面取不到扩展名；
  /// 所以优先看 `name`（Subsonic 侧为 `title.suffix`），只认已知音频扩展名，
  /// 最后才回落到 `.mp3`。
  String _resolveExtension(MusicFile song) {
    for (final raw in [song.name, song.path]) {
      if (raw.isEmpty) continue;
      String candidate = raw;
      if (raw.contains('://')) {
        final uri = Uri.tryParse(raw);
        if (uri == null) continue;
        candidate = uri.path;
      }
      final ext = p.extension(candidate).toLowerCase();
      if (MusicFileUtils.supportedAudioExtensions.contains(ext)) {
        return ext;
      }
    }
    return '.mp3';
  }

  /// 结构化媒体服务器（Subsonic / Jellyfin）唯一的入队入口。
  ///
  /// 落盘层级由 [RemoteDownloadRequest.batches] 里每一批的
  /// [RemoteDownloadBatch.layout] 决定：调用方一次性描述「哪些曲目、按哪一层
  /// 落盘」，service 不再替调用方猜。这样同一页面里单曲下载与勾选下载必然同构。
  Future<List<RemoteDownloadTask>> enqueue(RemoteDownloadRequest request) async {
    final source = _structuredSourceFor(request.server, request.password);
    if (source == null) {
      debugPrint(
        '[RemoteDownload] 跳过入队：${request.server.type.name} 不是结构化媒体服务器',
      );
      return const [];
    }

    final batches = request.nonEmptyBatches;
    if (batches.isEmpty) return const [];

    // 取消后连目录可写性检查都不该再跑（没配目录时它会弹选择框）。
    final progress = remoteTrackLoadProgress;
    progress.throwIfCancelled();
    final ready = await ensureDownloadFolderWritable();
    if (!ready) return const [];

    // 鉴权等一次性准备在整批里只做一次（原实现每首都要 authenticate）。
    await source.prepare();

    final created = <RemoteDownloadTask>[];
    final all = <RemoteDownloadTask>[];
    progress.setStage(RemoteTrackLoadStage.queueing);
    progress.setTotal(request.songCount);
    debugPrint(
      '[RemoteDownload] 入队 ${request.songCount} 首 / ${batches.length} 批 '
      '(${request.server.type.name}: ${request.server.name})',
    );
    try {
      for (final batch in batches) {
        for (final song in batch.songs) {
          progress.throwIfCancelled();
          final result = await _enqueueStructuredTrack(
            request: request,
            source: source,
            song: song,
            layout: batch.layout,
            collectionFolder: batch.collectionFolder,
          );
          all.add(result.task);
          // 只记「本次新建」的任务：取消回滚时不能误删队列里早就下完的条目。
          if (result.created) created.add(result.task);
          progress.advance();
        }
      }
    } on RemoteTrackLoadCancelled {
      _discardEnqueued(created);
      rethrow;
    }
    return all;
  }

  /// 单条结构化曲目的入队：去重 → 本地已存在检查 → 造任务 → 调度。
  ///
  /// 协议差异全部收敛在 [_StructuredDownloadSource] 里，Subsonic 与 Jellyfin
  /// 共用这一条流程。
  Future<({RemoteDownloadTask task, bool created})> _enqueueStructuredTrack({
    required RemoteDownloadRequest request,
    required _StructuredDownloadSource source,
    required MusicFile song,
    RemoteDownloadLayout layout = RemoteDownloadLayout.album,
    String? collectionFolder,
  }) async {
    final baseFolder = await getDownloadFolderPath();
    final trackId = source.resolveTrackId(song);
    final targetPath = await buildLocalTrackPath(
      song: song,
      baseFolder: baseFolder,
      server: request.server,
      collectionFolder: collectionFolder,
      layout: layout,
    );
    final taskId = '${source.taskIdPrefix}_${request.server.id}_$trackId';

    // If already in queue, don't duplicate
    final existingIndex = state.indexWhere((t) => t.id == taskId);
    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      if (existing.status == RemoteDownloadStatus.failed ||
          existing.status == RemoteDownloadStatus.cancelled ||
          existing.status == RemoteDownloadStatus.paused) {
        retryTask(taskId);
        return (
          task: state.firstWhere((t) => t.id == taskId),
          created: false,
        );
      }
      return (task: existing, created: false);
    }

    final downloadUrl = source.buildDownloadUrl(trackId);

    // Check if target file already exists locally
    if (await _checkFileExistsLocally(targetPath)) {
      int fileSize = 0;
      try {
        final targetFile = File(targetPath);
        if (targetFile.existsSync()) {
          fileSize = targetFile.lengthSync();
        }
      } catch (_) {}

      final skipped = RemoteDownloadTask(
        id: taskId,
        server: request.server,
        song: song,
        trackId: trackId,
        downloadUrl: downloadUrl,
        targetPath: targetPath,
        status: RemoteDownloadStatus.completed,
        bytesDownloaded: fileSize,
        totalBytes: fileSize,
        completedAt: DateTime.now(),
      );
      debugPrint('[RemoteDownload] 本地已存在，跳过：$targetPath');
      state = [skipped, ...state];
      return (task: skipped, created: false);
    }

    final task = RemoteDownloadTask(
      id: taskId,
      server: request.server,
      song: song,
      trackId: trackId,
      downloadUrl: downloadUrl,
      targetPath: targetPath,
      status: RemoteDownloadStatus.pending,
    );

    state = [...state, task];
    _processQueue();
    return (task: task, created: true);
  }

  /// 按服务器类型挑出协议适配器；WebDAV / SMB 走文件浏览器那条链路。
  _StructuredDownloadSource? _structuredSourceFor(
    RemoteServer server,
    String password,
  ) {
    switch (server.type) {
      case RemoteServerType.subsonic:
        return _SubsonicDownloadSource(server, password);
      case RemoteServerType.jellyfin:
        return _JellyfinDownloadSource(server, password);
      case RemoteServerType.webdav:
      case RemoteServerType.smb:
        return null;
    }
  }

  /// Enqueues a WebDAV file for download.
  Future<RemoteDownloadTask?> enqueueWebDavFile({
    required RemoteServer server,
    required String password,
    required WebDavFile file,
    bool skipWritableCheck = false,
  }) async {
    if (!skipWritableCheck) {
      final ready = await ensureDownloadFolderWritable();
      if (!ready) return null;
    }

    if (server.type == RemoteServerType.smb) {
      final (share, relPath) = RemoteMediaResolver.parseSmbParts(file.path);
      final smbFile = SmbFile(
        share: share,
        path: relPath,
        name: file.name,
        isDirectory: file.isDirectory,
        contentLength: file.contentLength,
        lastModified: file.lastModified,
      );
      return enqueueSmbFile(
        server: server,
        file: smbFile,
        skipWritableCheck: true,
      );
    }

    final client = WebDavClient(server: server, password: password);
    final baseFolder = await getDownloadFolderPath();
    final song = RemoteMediaResolver.buildMusicFileFromWebDav(file, server);

    final targetPath = await buildLocalTrackPath(
      song: song,
      baseFolder: baseFolder,
      server: server,
      webDavPath: file.path,
    );

    final taskId = 'webdav_${server.id}_${file.path.hashCode}';

    // If already in queue, don't duplicate
    final existingIndex = state.indexWhere((t) => t.id == taskId);
    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      if (existing.status == RemoteDownloadStatus.completed) {
        return existing;
      }
      if (existing.status == RemoteDownloadStatus.failed ||
          existing.status == RemoteDownloadStatus.cancelled ||
          existing.status == RemoteDownloadStatus.paused) {
        retryTask(taskId);
        return state.firstWhere((t) => t.id == taskId);
      }
      return existing;
    }

    // Check if target file already exists locally
    final exists = await _checkFileExistsLocally(targetPath);
    if (exists) {
      int fileSize = file.contentLength;
      try {
        final targetFile = File(targetPath);
        if (targetFile.existsSync()) {
          fileSize = targetFile.lengthSync();
        }
      } catch (_) {}

      final task = RemoteDownloadTask(
        id: taskId,
        server: server,
        song: song,
        webDavPath: file.path,
        downloadUrl: client.buildFullUrl(file.path),
        headers: client.authHeaders,
        targetPath: targetPath,
        status: RemoteDownloadStatus.completed,
        bytesDownloaded: fileSize,
        totalBytes: fileSize,
        completedAt: DateTime.now(),
      );
      state = [task, ...state];
      return task;
    }

    final downloadUrl = client.buildFullUrl(file.path);
    final task = RemoteDownloadTask(
      id: taskId,
      server: server,
      song: song,
      webDavPath: file.path,
      downloadUrl: downloadUrl,
      headers: client.authHeaders,
      targetPath: targetPath,
      status: RemoteDownloadStatus.pending,
      totalBytes: file.contentLength,
    );

    state = [...state, task];
    _processQueue();
    return task;
  }

  /// Enqueues multiple WebDAV files.
  Future<List<RemoteDownloadTask>> enqueueWebDavFiles({
    required RemoteServer server,
    required String password,
    required List<WebDavFile> files,
  }) async {
    final ready = await ensureDownloadFolderWritable();
    if (!ready) return [];

    final List<RemoteDownloadTask> enqueued = [];
    final progress = remoteTrackLoadProgress;
    final audioFiles =
        files.where((file) => !file.isDirectory && file.isAudio).toList();
    progress.setStage(RemoteTrackLoadStage.queueing);
    progress.setTotal(audioFiles.length);
    try {
      for (final file in audioFiles) {
        progress.throwIfCancelled();
        final task = await enqueueWebDavFile(
          server: server,
          password: password,
          file: file,
          skipWritableCheck: true,
        );
        if (task != null) {
          enqueued.add(task);
        }
        progress.advance();
      }
    } on RemoteTrackLoadCancelled {
      _discardEnqueued(enqueued);
      rethrow;
    }
    return enqueued;
  }

  /// Enqueues an SMB file for download.
  Future<RemoteDownloadTask?> enqueueSmbFile({
    required RemoteServer server,
    required SmbFile file,
    bool skipWritableCheck = false,
  }) async {
    if (!skipWritableCheck) {
      final ready = await ensureDownloadFolderWritable();
      if (!ready) return null;
    }

    final baseFolder = await getDownloadFolderPath();
    final song = RemoteMediaResolver.buildMusicFileFromSmb(file, server);

    final targetPath = await buildLocalTrackPath(
      song: song,
      baseFolder: baseFolder,
      server: server,
      webDavPath: '${file.share}/${file.path}',
    );

    final taskId = 'smb_${server.id}_${file.share}_${file.path.hashCode}';

    final existingIndex = state.indexWhere((t) => t.id == taskId);
    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      if (existing.status == RemoteDownloadStatus.completed) {
        return existing;
      }
      if (existing.status == RemoteDownloadStatus.failed ||
          existing.status == RemoteDownloadStatus.cancelled ||
          existing.status == RemoteDownloadStatus.paused) {
        retryTask(taskId);
        return state.firstWhere((t) => t.id == taskId);
      }
      return existing;
    }

    final exists = await _checkFileExistsLocally(targetPath);
    if (exists) {
      int fileSize = file.contentLength;
      try {
        final targetFile = File(targetPath);
        if (targetFile.existsSync()) {
          fileSize = targetFile.lengthSync();
        }
      } catch (_) {}

      final downloadUrl = await LocalStreamProxy.instance.buildSmbStreamUrl(
        serverId: server.id,
        share: file.share,
        relativePath: file.path,
      );

      final task = RemoteDownloadTask(
        id: taskId,
        server: server,
        song: song,
        smbShare: file.share,
        smbPath: file.path,
        downloadUrl: downloadUrl,
        targetPath: targetPath,
        status: RemoteDownloadStatus.completed,
        bytesDownloaded: fileSize,
        totalBytes: fileSize,
        completedAt: DateTime.now(),
      );
      state = [task, ...state];
      return task;
    }

    final downloadUrl = await LocalStreamProxy.instance.buildSmbStreamUrl(
      serverId: server.id,
      share: file.share,
      relativePath: file.path,
    );

    final task = RemoteDownloadTask(
      id: taskId,
      server: server,
      song: song,
      smbShare: file.share,
      smbPath: file.path,
      downloadUrl: downloadUrl,
      targetPath: targetPath,
      status: RemoteDownloadStatus.pending,
      totalBytes: file.contentLength,
    );

    state = [...state, task];
    _processQueue();
    return task;
  }

  /// Enqueues multiple SMB files.
  Future<List<RemoteDownloadTask>> enqueueSmbFiles({
    required RemoteServer server,
    required List<SmbFile> files,
  }) async {
    final ready = await ensureDownloadFolderWritable();
    if (!ready) return [];

    final List<RemoteDownloadTask> enqueued = [];
    final progress = remoteTrackLoadProgress;
    final audioFiles =
        files.where((file) => !file.isDirectory && file.isAudio).toList();
    progress.setStage(RemoteTrackLoadStage.queueing);
    progress.setTotal(audioFiles.length);
    try {
      for (final file in audioFiles) {
        progress.throwIfCancelled();
        final task = await enqueueSmbFile(
          server: server,
          file: file,
          skipWritableCheck: true,
        );
        if (task != null) {
          enqueued.add(task);
        }
        progress.advance();
      }
    } on RemoteTrackLoadCancelled {
      _discardEnqueued(enqueued);
      rethrow;
    }
    return enqueued;
  }

  /// Concurrency scheduler: starts pending tasks up to [_maxConcurrent].
  void _processQueue() {
    final activeDownloadingCount =
        state.where((t) => t.status == RemoteDownloadStatus.downloading).length;

    if (activeDownloadingCount >= _maxConcurrent) {
      return;
    }

    final slotsAvailable = _maxConcurrent - activeDownloadingCount;
    final pendingTasks = state
        .where((t) => t.status == RemoteDownloadStatus.pending)
        .take(slotsAvailable)
        .toList();

    for (final task in pendingTasks) {
      _startDownload(task);
    }
  }

  Future<void> _startDownload(RemoteDownloadTask task) async {
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;
    _lastBytesMap[task.id] = 0;
    _lastTimeMap[task.id] = DateTime.now();

    _updateTask(task.id, (t) => t.copyWith(
          status: RemoteDownloadStatus.downloading,
          error: null,
        ));

    // Download into app temporary cache directory first (safe on all platforms)
    final tempDir = await getTemporaryDirectory();
    final tempFileName =
        'vynody_dl_${task.id.hashCode}_${DateTime.now().millisecondsSinceEpoch}.part';
    final tempPath = p.join(tempDir.path, tempFileName);
    final tempFile = File(tempPath);

    try {
      final response = await _dio.download(
        task.downloadUrl,
        tempPath,
        cancelToken: cancelToken,
        options: Options(
          headers: task.headers,
        ),
        onReceiveProgress: (received, total) {
          final now = DateTime.now();
          final lastTime = _lastTimeMap[task.id] ?? now;
          final lastBytes = _lastBytesMap[task.id] ?? 0;
          final diffMs = now.difference(lastTime).inMilliseconds;

          double speed = 0.0;
          if (diffMs >= 500) {
            final byteDiff = received - lastBytes;
            speed = (byteDiff / (diffMs / 1000.0));
            _lastBytesMap[task.id] = received;
            _lastTimeMap[task.id] = now;
          }

          // Throttle UI task updates to avoid overwhelming Riverpod/Flutter pipeline
          if (diffMs < 100 && received < total) {
            return;
          }

          _updateTask(task.id, (t) {
            return t.copyWith(
              bytesDownloaded: received,
              totalBytes: total > 0 ? total : t.totalBytes,
              speedBytesPerSec: speed > 0 ? speed : t.speedBytesPerSec,
            );
          });
        },
      );

      // 二进制端点失败时同样回 200，只是响应体换成了失败 JSON（Subsonic code 50）
      // 或反代自己的 HTML 错误页。必须在「有没有字节」的判定之前识别，否则这些
      // 载荷会被当音频搬进音乐库并标记完成。
      final payloadError = RemotePayloadGuard.inspect(
        tempFile,
        contentType: response.headers.value(HttpHeaders.contentTypeHeader),
        parseSubsonicError: task.isSubsonic,
      );
      if (payloadError != null) throw payloadError;

      if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
        bool savedSuccessfully = false;
        String? saveError;

        // 1. Try standard file write first (desktop, iOS, app-internal directories)
        try {
          final targetFile = File(task.targetPath);
          final dir = targetFile.parent;
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          if (targetFile.existsSync()) {
            targetFile.deleteSync();
          }
          try {
            tempFile.renameSync(task.targetPath);
          } on FileSystemException {
            // Handle cross-device link (errno 18 / EXDEV) when moving between different drives/volumes
            tempFile.copySync(task.targetPath);
            try {
              tempFile.deleteSync();
            } catch (_) {}
          }
          savedSuccessfully = true;
        } catch (e) {
          savedSuccessfully = false;
          saveError = e.toString();
        }

        // 2. If standard write failed and on Android, try SAF
        if (!savedSuccessfully && Platform.isAndroid) {
          try {
            final mapping = await AndroidSafStorageHelper.findBestMapping(task.targetPath);
            if (mapping != null) {
              final rootDisplayPath = mapping.key;
              final treeUri = mapping.value;
              String relativePath = '';
              try {
                relativePath = p.relative(task.targetPath, from: rootDisplayPath);
              } catch (_) {
                relativePath = p.basename(task.targetPath);
              }

              const methodChannel = MethodChannel('com.example.audio_converter/saf');
              final result = await methodChannel.invokeMapMethod<String, Object?>(
                'saveFileToDirectory',
                <String, Object?>{
                  'treeUri': treeUri,
                  'sourcePath': tempFile.path,
                  'fileName': relativePath.replaceAll('\\', '/'),
                  'overwrite': true,
                },
              );
              final savedUri = result?['savedUri']?.toString();
              if (savedUri != null && savedUri.isNotEmpty) {
                savedSuccessfully = true;
                saveError = null;
              } else {
                saveError = result?['error']?.toString() ?? 'SAF save failed';
              }
            } else {
              saveError = 'No SAF folder permission mapped for: ${task.targetPath}';
            }
          } catch (e) {
            saveError = 'SAF save error: $e';
          }
        }

        if (savedSuccessfully) {
          // Ensure base directory is registered with scanner
          final baseFolder = await getDownloadFolderPath();
          final scanner = ref.read(scannerServiceProvider);
          await scanner.ready;
          if (!scanner.rootPaths.any((path) => p.equals(path, baseFolder))) {
            await scanner.addRootPath(baseFolder);
          }

          _cancelTokens.remove(task.id);
          _lastBytesMap.remove(task.id);
          _lastTimeMap.remove(task.id);

          // 该服务器已恢复正常：清掉去重标记，下次再出问题时仍会提示。
          _clearServerIssues(task.server.id);

          int finalSize = task.totalBytes;
          try {
            final targetFile = File(task.targetPath);
            if (targetFile.existsSync()) {
              finalSize = targetFile.lengthSync();
            }
          } catch (_) {}

          _updateTask(task.id, (t) => t.copyWith(
                status: RemoteDownloadStatus.completed,
                bytesDownloaded: finalSize > 0 ? finalSize : t.totalBytes,
                speedBytesPerSec: 0,
                completedAt: DateTime.now(),
              ));
        } else {
          _cancelTokens.remove(task.id);
          _updateTask(task.id, (t) => t.copyWith(
                status: RemoteDownloadStatus.failed,
                error: saveError ?? 'Failed to save downloaded file to storage',
                speedBytesPerSec: 0,
              ));
        }
      } else {
        if (tempFile.existsSync()) {
          try {
            tempFile.deleteSync();
          } catch (_) {}
        }
        _cancelTokens.remove(task.id);
        _updateTask(task.id, (t) => t.copyWith(
              status: RemoteDownloadStatus.failed,
              error: 'Empty response received from server',
              speedBytesPerSec: 0,
            ));
      }
    } catch (e) {
      if (cancelToken.isCancelled) {
        // Paused or cancelled by user
        final current = state.firstWhere((t) => t.id == task.id, orElse: () => task);
        if (current.status != RemoteDownloadStatus.paused &&
            current.status != RemoteDownloadStatus.cancelled) {
          _updateTask(task.id, (t) => t.copyWith(
                status: RemoteDownloadStatus.cancelled,
                speedBytesPerSec: 0,
              ));
        }
      } else {
        final isBinaryEndpointError = e is SubsonicException;
        final downloadsDisabled =
            isBinaryEndpointError && e.isDownloadsDisabled;
        // 反向代理返回的 HTML 错误页 / 非音频内容，与「关闭下载」是两回事：
        // 前者是部署问题，文案要指向代理，不能让用户去翻服务端下载开关。
        final nonMediaPayload = isBinaryEndpointError &&
            e.code == RemotePayloadGuard.errorNonMediaPayload;
        // Jellyfin / WebDAV 的拒绝走标准状态码，Dio 直接抛 DioException。
        final httpFailure = _describeHttpFailure(e);

        final String? friendlyMessage = downloadsDisabled
            ? currentAppL10n.remoteServerDownloadsDisabled
            : nonMediaPayload
                ? currentAppL10n.remoteDownloadNotAudioResponse
                : httpFailure?.message;

        final issueKind = downloadsDisabled
            ? 'downloads_disabled'
            : nonMediaPayload
                ? 'non_media_payload'
                : httpFailure?.kind;
        if (issueKind != null &&
            friendlyMessage != null &&
            _shouldWarnServerIssue(task.server.id, issueKind)) {
          _showServerIssueToast(friendlyMessage);
        }

        debugPrint('[RemoteDownload] Download error for ${task.song.displayName}: $e');
        _updateTask(task.id, (t) => t.copyWith(
              status: RemoteDownloadStatus.failed,
              error: friendlyMessage ?? e.toString(),
              speedBytesPerSec: 0,
            ));
      }
      _cancelTokens.remove(task.id);
      _lastBytesMap.remove(task.id);
      _lastTimeMap.remove(task.id);
    } finally {
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    }

    _processQueue();
  }

  void pauseTask(String id) {
    final token = _cancelTokens[id];
    if (token != null && !token.isCancelled) {
      token.cancel('User paused download');
    }
    _cancelTokens.remove(id);
    _updateTask(id, (t) => t.copyWith(
          status: RemoteDownloadStatus.paused,
          speedBytesPerSec: 0,
        ));
    _processQueue();
  }

  void resumeTask(String id) {
    _updateTask(id, (t) => t.copyWith(
          status: RemoteDownloadStatus.pending,
          error: null,
          speedBytesPerSec: 0,
        ));
    _processQueue();
  }

  void cancelTask(String id) {
    final token = _cancelTokens[id];
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled download');
    }
    _cancelTokens.remove(id);

    final task = state.firstWhere((t) => t.id == id, orElse: () => state.first);
    final tempFile = File('${task.targetPath}.part');
    if (tempFile.existsSync()) {
      try {
        tempFile.deleteSync();
      } catch (_) {}
    }

    state = state.where((t) => t.id != id).toList();
    _processQueue();
  }

  /// 用户在「加载曲目」浮层里取消时，把本次已入队、尚未下完的任务一并撤掉。
  /// 点取消就是「这批不要了」，留着继续下载会让人以为取消没生效。
  void _discardEnqueued(List<RemoteDownloadTask> tasks) {
    if (tasks.isEmpty) return;
    final ids = tasks.map((t) => t.id).toSet();
    for (final id in ids) {
      final token = _cancelTokens[id];
      if (token != null && !token.isCancelled) {
        token.cancel('Cancelled by user');
      }
      _cancelTokens.remove(id);
      _lastBytesMap.remove(id);
      _lastTimeMap.remove(id);
    }
    state = state.where((t) => !ids.contains(t.id)).toList();
    _processQueue();
  }

  void retryTask(String id) {
    final token = _cancelTokens[id];
    if (token != null && !token.isCancelled) {
      token.cancel('Retrying');
    }
    _cancelTokens.remove(id);

    _updateTask(id, (t) => t.copyWith(
          status: RemoteDownloadStatus.pending,
          bytesDownloaded: 0,
          speedBytesPerSec: 0,
          error: null,
        ));
    _processQueue();
  }

  void pauseAll() {
    for (final task in state) {
      if (task.status == RemoteDownloadStatus.downloading ||
          task.status == RemoteDownloadStatus.pending) {
        final token = _cancelTokens[task.id];
        if (token != null && !token.isCancelled) {
          token.cancel('User paused all');
        }
        _cancelTokens.remove(task.id);
      }
    }
    state = state.map((t) {
      if (t.status == RemoteDownloadStatus.downloading ||
          t.status == RemoteDownloadStatus.pending) {
        return t.copyWith(
          status: RemoteDownloadStatus.paused,
          speedBytesPerSec: 0,
        );
      }
      return t;
    }).toList();
  }

  void resumeAll() {
    state = state.map((t) {
      if (t.status == RemoteDownloadStatus.paused ||
          t.status == RemoteDownloadStatus.failed) {
        return t.copyWith(
          status: RemoteDownloadStatus.pending,
          error: null,
          speedBytesPerSec: 0,
        );
      }
      return t;
    }).toList();
    _processQueue();
  }

  void cancelAll() {
    for (final task in state) {
      if (task.status == RemoteDownloadStatus.downloading ||
          task.status == RemoteDownloadStatus.pending ||
          task.status == RemoteDownloadStatus.paused) {
        final token = _cancelTokens[task.id];
        if (token != null && !token.isCancelled) {
          token.cancel('User cancelled all');
        }
        _cancelTokens.remove(task.id);

        final tempFile = File('${task.targetPath}.part');
        if (tempFile.existsSync()) {
          try {
            tempFile.deleteSync();
          } catch (_) {}
        }
      }
    }
    state = state.where((t) => t.status == RemoteDownloadStatus.completed).toList();
  }

  void clearCompleted() {
    state = state
        .where((t) =>
            t.status == RemoteDownloadStatus.downloading ||
            t.status == RemoteDownloadStatus.pending ||
            t.status == RemoteDownloadStatus.paused)
        .toList();
  }

  void removeTask(String id) {
    cancelTask(id);
  }

  void _updateTask(String id, RemoteDownloadTask Function(RemoteDownloadTask) updater) {
    void apply() {
      state = [
        for (final task in state)
          if (task.id == id) updater(task) else task,
      ];
    }

    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  /// 提示「服务端已关闭下载」。
  ///
  /// 下载队列可能在没有界面的场景里跑（后台续传、测试、桌面托盘），没有 Toast
  /// 宿主时 showToast 会抛异常；这里降级为只记任务错误文案。
  void _showServerIssueToast(String message) {
    try {
      showToast(message);
    } catch (_) {}
  }
}

final remoteDownloadTasksProvider =
    NotifierProvider<RemoteDownloadNotifier, List<RemoteDownloadTask>>(
  RemoteDownloadNotifier.new,
);

final activeDownloadsCountProvider = Provider<int>((ref) {
  final tasks = ref.watch(remoteDownloadTasksProvider);
  return tasks
      .where((t) =>
          t.status == RemoteDownloadStatus.downloading ||
          t.status == RemoteDownloadStatus.pending)
      .length;
});

final activeTotalSpeedProvider = Provider<double>((ref) {
  final tasks = ref.watch(remoteDownloadTasksProvider);
  return tasks
      .where((t) => t.status == RemoteDownloadStatus.downloading)
      .fold(0.0, (sum, t) => sum + t.speedBytesPerSec);
});

/// 结构化媒体服务器的协议差异点。
///
/// 入队流程本身（去重、已存在检查、任务构造、并发调度、取消回滚）两种协议
/// 完全一致，差异只有：任务 id 前缀、trackId 解析、下载 URL 构造，
/// 以及 Jellyfin 需要在整批开始前鉴权一次。
abstract class _StructuredDownloadSource {
  /// 任务 id 前缀，只用于区分来源，不参与落盘路径。
  String get taskIdPrefix;

  /// 入队前的一次性准备。
  Future<void> prepare() async {}

  String resolveTrackId(MusicFile song);

  String buildDownloadUrl(String trackId);

  /// 远端路径里取不到 id 时的兜底，保证同一首歌在队列里稳定同一个 id。
  static String fallbackTrackId(MusicFile song) =>
      song.id != null && song.id! > 0
          ? song.id.toString()
          : 'unknown_${song.path.hashCode}';
}

class _SubsonicDownloadSource extends _StructuredDownloadSource {
  _SubsonicDownloadSource(RemoteServer server, String password)
      : _client = SubsonicClient(server: server, password: password);

  final SubsonicClient _client;

  @override
  String get taskIdPrefix => 'subsonic';

  @override
  String resolveTrackId(MusicFile song) =>
      RemoteMediaResolver.extractSubsonicTrackId(song) ??
      _StructuredDownloadSource.fallbackTrackId(song);

  @override
  String buildDownloadUrl(String trackId) => _client.buildDownloadUrl(trackId);
}

class _JellyfinDownloadSource extends _StructuredDownloadSource {
  _JellyfinDownloadSource(RemoteServer server, String password)
      : _client = JellyfinClient(server: server, password: password);

  final JellyfinClient _client;

  @override
  String get taskIdPrefix => 'jellyfin';

  @override
  Future<void> prepare() async {
    try {
      await _client.authenticate();
    } catch (e) {
      // 鉴权失败也继续：后续下载请求会带着会话缓存失败，错误会落到任务上。
      debugPrint('[RemoteDownload] Jellyfin 鉴权失败：$e');
    }
  }

  @override
  String resolveTrackId(MusicFile song) =>
      RemoteMediaResolver.parseUri(song.path)?.trackIdOrPath ??
      _StructuredDownloadSource.fallbackTrackId(song);

  @override
  String buildDownloadUrl(String trackId) => _client.buildStreamUrl(trackId);
}
