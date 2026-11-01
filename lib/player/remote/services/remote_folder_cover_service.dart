import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../metadata/metadata_database.dart';
import '../../metadata/metadata_helper.dart';
import '../clients/smb_client.dart';
import '../clients/webdav_client.dart';
import '../proxy/remote_media_resolver.dart';
import '../remote_server_models.dart';
import 'webdav_metadata_helper.dart';

/// 远程目录（WebDAV / SMB）的「代表封面」解析与缓存。
///
/// 远程目录没有「文件夹封面」这种元数据，只能按下面的优先级**推**一张出来：
///
/// 1. `folder_entries` 里已缓存且文件仍在 → 直接命中，零网络；
/// 2. 目录已被索引（曲库里有它下面的歌）→ 取库里代表歌曲的缩略图，零网络；
/// 3. 从当前目录开始深度优先往下找，最多 [kMaxSearchDepth] 层，每层依次试：
///    a. 本目录里一张常见名字的封面图（`cover.jpg` / `folder.png` …）→ 下载它，
///       比读音频标签便宜，画质也更好；
///    b. 本目录第一首音频的内嵌封面 → 走一次 Range 标签读取。
///
/// 深度上限挡不住分支（5 层 × 每层 20 个子目录 = 320 万次 PROPFIND），所以真正
/// 起保护作用的是 [kMaxListedDirectories]：单次解析最多列这么多个目录。
///
/// **只有「查到封面」才写 `folder_entries`**。没查到（含预算耗尽）只留在
/// [_skipCache] 里，作用于本次进程：`folder_entries` 的封面列是「代表
/// 歌曲」语义，本地扫描会按它回填 `_folderRepresentativeSongs` 并反推目录统计，
/// 塞一行 `coverSongPath = <目录自身>` 的假数据会污染那条链路。
class RemoteFolderCoverService {
  RemoteFolderCoverService({MetadataDatabase? database})
      : _db = database ?? MetadataDatabase();

  final MetadataDatabase _db;

  /// 本次进程不再为这个目录花网络（确认没封面，或预算内已给不出）。
  ///
  /// 有它兜底，反复进出同一层目录不会每次都重走一遍网络；进程重启后失效，
  /// 也就自然给了远端新增封面图一次重新发现的机会。目录树在同一次会话里
  /// 不会变，所以「预算内给不出」这一结论对本次会话是可复用的。
  static final Set<String> _skipCache = <String>{};

  /// 跳过缓存上限。远程库可能有上万个目录，无界增长只是把内存换成一次省不下的
  /// 网络请求；超过上限就整体清空（按访问顺序淘汰太贵，收益也不大）。
  static const int _kSkipCacheLimit = 2000;

  static void _markSkip(String folderUri) {
    if (_skipCache.length >= _kSkipCacheLimit) {
      _skipCache.clear();
    }
    _skipCache.add(folderUri);
  }

  /// 一次批量查询的结果。
  ///
  /// [covers] 是有封面且文件仍在磁盘的目录；[settled] 是「查过并落定」的目录
  /// （含负缓存）。两条信息必须分开传：只看 [covers] 的话，负缓存等于不存在，
  /// 每次进目录都要重新走一遍网络。
  static const RemoteFolderCoverLookup emptyLookup = RemoteFolderCoverLookup(
    covers: {},
    settled: {},
  );

  /// 常见封面文件名（去扩展名、小写）。
  static const Set<String> _kCoverBaseNames = {
    'cover',
    'folder',
    'front',
    'album',
    'albumart',
    'albumartsmall',
    'folderart',
    'artwork',
    'thumb',
    'poster',
  };

  static const Set<String> _kImageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
  };

  /// 单张封面图下载上限，超过就放弃这次（避免把整张原图拉进内存）。
  static const int _kMaxCoverBytes = 12 * 1024 * 1024;

  /// 递归查找的最大层数（含当前目录）。
  ///
  /// 音乐目录树一般是「歌手 / 专辑 / 曲目」，两三层就到歌了；给到 5 层是留给
  /// 「分类 / 歌手 / 年代 / 专辑」这种多加了一层的整理习惯。
  static const int kMaxSearchDepth = 5;

  /// 单次解析最多列多少个目录。
  ///
  /// 深度上限挡不住分支：5 层 × 每个目录 20 个子目录就是 320 万次 PROPFIND。
  /// 所以真正起保护作用的是这个总预算——正常专辑树两层就用掉个位数，
  /// 用满只在「整棵树都没有封面」时才发生，那时多列也没有意义。
  static const int kMaxListedDirectories = 24;

  /// 单次解析最多读几首歌的标签。
  ///
  /// 读标签是一次 Range 请求 + 解析，比下载封面图便宜但仍有延迟；逐层各读一首
  /// 会累积成秒级等待，所以单独限流。
  static const int kMaxSongProbes = 6;

  /// 从一层目录列表里挑出「封面图」。
  ///
  /// 优先名字完全匹配（`cover.jpg`、`folder.png`…），其次名字里带
  /// cover/front/folder 的图片。都没有就返回 null，交给内嵌标签兜底。
  static WebDavFile? pickCoverImage(List<WebDavFile> items) {
    WebDavFile? looseMatch;
    for (final item in items) {
      if (item.isDirectory) continue;
      final ext = p.extension(item.name).toLowerCase();
      if (!_kImageExtensions.contains(ext)) continue;
      final base = p.basenameWithoutExtension(item.name).toLowerCase().trim();
      if (_kCoverBaseNames.contains(base)) return item;
      if (looseMatch != null) continue;
      if (base.contains('cover') ||
          base.contains('front') ||
          base.contains('folder')) {
        looseMatch = item;
      }
    }
    return looseMatch;
  }

  /// 批量读缓存。
  ///
  /// 键是调用方传的原路径（remote virtualUri）。
  Future<RemoteFolderCoverLookup> loadCachedCovers(
    Iterable<String> folderVirtualUris,
  ) async {
    final Map<String, FolderCoverSnapshot> rows;
    try {
      rows = await _db.getFolderCoversForPaths(folderVirtualUris);
    } catch (e) {
      debugPrint('[RemoteFolderCover] 读取封面缓存失败: $e');
      return emptyLookup;
    }

    final covers = <String, String>{};
    final settled = <String>{};
    rows.forEach((folderUri, cover) {
      final thumb = cover.thumbnailPath;
      if (thumb == null || thumb.isEmpty) return;
      if (!File(thumb).existsSync()) {
        // 缩略图被清掉了（清缓存 / 换设备），当作没查过，重新推一次。
        return;
      }
      covers[folderUri] = thumb;
      settled.add(folderUri);
    });
    // 内存里的负缓存也算「已落定」，但只对本次请求的那批目录生效。
    for (final uri in folderVirtualUris) {
      if (_skipCache.contains(uri)) settled.add(uri);
    }
    return RemoteFolderCoverLookup(covers: covers, settled: settled);
  }

  /// 解析单个远程目录的代表封面并写缓存。
  ///
  /// [forceRefresh] 为 true 时忽略缓存重新推导（下拉刷新用）。
  /// [maxDepth] 限制向下递归的层数（含当前目录），默认 [kMaxSearchDepth]。
  /// 返回本地缩略图路径；确认没有封面时返回 null。
  Future<String?> resolveCover({
    required RemoteServer server,
    required String password,
    required RemoteDirectoryClient client,
    required String folderPath,
    bool forceRefresh = false,
    int maxDepth = kMaxSearchDepth,
  }) async {
    final folderUri = RemoteMediaResolver.buildRemoteUri(server, folderPath);

    if (!forceRefresh) {
      final cached = await loadCachedCovers([folderUri]);
      final hit = cached.covers[folderUri];
      if (hit != null) return hit;
    }

    // 2) 已索引目录：库里代表歌曲的缩略图，零网络。
    //
    // 放在跳过缓存之前：目录先被判「没封面」、之后才被加入曲库索引时，
    // 仍然由这一条先拿到结果，不必等进程重启。
    final indexedThumb = await _thumbnailFromIndex(folderUri);
    if (indexedThumb != null) {
      await _persist(
        folderUri: folderUri,
        coverSourcePath: indexedThumb.$2,
        thumbnailPath: indexedThumb.$1,
        artworkPath: null,
      );
      return indexedThumb.$1;
    }

    // 本次进程已给过结论（确认没有 / 预算内给不出），不再花网络。
    if (!forceRefresh && _skipCache.contains(folderUri)) return null;

    // 3) 深度优先往下找（深度与总目录数都有上限）。
    final search = await searchSubtree(
      rootPath: folderPath,
      listDirectory: client.listFiles,
      probeImage: (image) => _hitFromCoverImage(
        server: server,
        client: client,
        file: image,
      ),
      probeSong: (song) => _hitFromSong(
        server: server,
        password: password,
        file: song,
      ),
      maxDepth: maxDepth,
    );

    final hit = search.hit;
    if (hit != null) {
      await _persist(
        folderUri: folderUri,
        // 封面图不是歌：`songPath` 留 null。若写成图片路径，扫描器冷启动
        // 会把它当「代表歌曲」塞进元数据缓存，反推出的目录统计全是脏数据。
        coverSourcePath: hit.sourcePath,
        thumbnailPath: hit.thumbnailPath,
        artworkPath: hit.artworkPath,
      );
      return hit.thumbnailPath;
    }

    // 只有「真的列到底、确实没有」和「预算内已给不出」才记跳过标记。列目录
    // 失败是瞬时故障，下次进同一层应该还能试，不能就此判死。
    if (!search.failed) _markSkip(folderUri);
    return null;
  }

  /// 在 [rootPath] 子树里找第一张能用的封面，深度优先。
  ///
  /// 为什么用深搜而不是逐层：音乐库常见结构是「分类 / 歌手 / 专辑 / 曲目」，
  /// 逐层要先把整层歌手列完才能下到专辑，深搜 3 次请求就能拿到封面。
  /// 代价是可能钻进一条很深的空分支——由 [maxListedDirectories] 兜底。
  ///
  /// 抽出为静态方法并接受注入，是为了能不建真的 WebDAV 就验证「深度、预算、
  /// 失败不落负缓存」几条成本边界，写错就是指数级请求。
  static Future<RemoteCoverSearchResult> searchSubtree({
    required String rootPath,
    required Future<List<WebDavFile>> Function(String path) listDirectory,
    required Future<RemoteFolderCoverHit?> Function(WebDavFile image)
        probeImage,
    required Future<RemoteFolderCoverHit?> Function(WebDavFile song) probeSong,
    int maxDepth = kMaxSearchDepth,
    int maxListedDirectories = kMaxListedDirectories,
    int maxSongProbes = kMaxSongProbes,
  }) async {
    var listed = 0;
    var songProbes = 0;
    var truncated = false;
    var failed = false;

    Future<RemoteFolderCoverHit?> dive(String path, int depth) async {
      // 预算按「列了几个目录」算，不按深度算：深度只决定能不能继续往下。
      if (listed >= maxListedDirectories) {
        truncated = true;
        return null;
      }
      listed++;

      List<WebDavFile> items;
      try {
        items = await listDirectory(path);
      } catch (e) {
        // 单个目录列失败不终止整棵树，但结果不再可信。
        debugPrint('[RemoteFolderCover] 列出目录失败 $path: $e');
        failed = true;
        return null;
      }

      // a. 本目录自带的封面图，最便宜也最好看。
      final image = pickCoverImage(items);
      if (image != null) {
        final hit = await probeImage(image);
        if (hit != null) return hit;
      }

      // b. 本目录第一首歌的内嵌封面。同一张专辑内嵌封面基本一致，试一首足够。
      if (songProbes < maxSongProbes) {
        final audios = items.where((f) => f.isAudio).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        if (audios.isNotEmpty) {
          songProbes++;
          final hit = await probeSong(audios.first);
          if (hit != null) return hit;
        }
      }

      if (depth + 1 >= maxDepth) return null;

      // 排序只为让结果稳定可复现（不同实现返回的条目顺序并不固定）。
      final subdirs = [
        for (final item in items)
          if (item.isDirectory) item.path,
      ]..sort();
      for (final subdir in subdirs) {
        if (listed >= maxListedDirectories) {
          truncated = true;
          return null;
        }
        final hit = await dive(subdir, depth + 1);
        if (hit != null) return hit;
      }
      return null;
    }

    final hit = await dive(rootPath, 0);
    return RemoteCoverSearchResult(
      hit: hit,
      truncated: hit == null && truncated,
      failed: hit == null && failed,
      listedDirectories: listed,
    );
  }

  /// 下载一张封面图并落成本地缩略图。失败返回 null，让调用方继续往下找。
  Future<RemoteFolderCoverHit?> _hitFromCoverImage({
    required RemoteServer server,
    required RemoteDirectoryClient client,
    required WebDavFile file,
  }) async {
    final bytes = await _fetchBytes(
      server: server,
      client: client,
      file: file,
    );
    if (bytes == null || bytes.isEmpty) return null;
    final imageUri = RemoteMediaResolver.buildRemoteUri(server, file.path);
    final info = await MetadataHelper.saveArtworkAndThumbnail(
      imageUri,
      bytes,
      saveLarge: false,
    );
    final thumb = info?['thumbnailPath'] as String?;
    if (thumb == null || thumb.isEmpty) return null;
    return RemoteFolderCoverHit(
      thumbnailPath: thumb,
      artworkPath: info?['artworkPath'] as String?,
    );
  }

  /// 读一首歌的标签，取内嵌封面。失败或无封面返回 null。
  Future<RemoteFolderCoverHit?> _hitFromSong({
    required RemoteServer server,
    required String password,
    required WebDavFile file,
  }) async {
    try {
      final meta = await RemoteMetadataHelper.fetchSongMetadata(
        file: file,
        server: server,
        password: password,
      );
      final thumb = meta?.thumbnailPath;
      if (thumb == null || thumb.isEmpty) return null;
      if (!File(thumb).existsSync()) return null;
      return RemoteFolderCoverHit(
        thumbnailPath: thumb,
        artworkPath: meta?.artworkPath,
        sourcePath: RemoteMediaResolver.buildRemoteUri(server, file.path),
      );
    } catch (e) {
      debugPrint('[RemoteFolderCover] 读取内嵌封面失败 ${file.path}: $e');
      return null;
    }
  }

  /// 已索引目录的缩略图：库里取一首有封面的歌。返回 (缩略图, 歌曲路径)。
  ///
  /// 走 `songs` 表而不是 `folder_entries`：远程扫描只写 `songs`，
  /// `folder_entries` 的 `coverSongPath` 对远程目录恒为空。
  Future<(String, String)?> _thumbnailFromIndex(String folderUri) async {
    try {
      final meta = await _db.getFirstSongWithArtworkUnderPath(folderUri);
      final thumb = meta?.thumbnailPath;
      if (meta == null || thumb == null || thumb.isEmpty) return null;
      if (!File(thumb).existsSync()) return null;
      return (thumb, meta.path);
    } catch (e) {
      debugPrint('[RemoteFolderCover] 索引封面查询失败 $folderUri: $e');
      return null;
    }
  }

  /// 只写「有封面」的结果。负结果不进 `folder_entries`（语义是代表歌曲，
/// 写空壳会污染本地扫描的回填链路），留 [_skipCache]。
  Future<void> _persist({
    required String folderUri,
    required String? coverSourcePath,
    required String? thumbnailPath,
    required String? artworkPath,
  }) async {
    if (thumbnailPath == null || thumbnailPath.isEmpty) return;
    try {
      await _db.batchWriteFolderCovers({
        folderUri: FolderCoverSnapshot(
          songPath: coverSourcePath,
          thumbnailPath: thumbnailPath,
          artworkPath: artworkPath,
        ),
      });
    } catch (e) {
      debugPrint('[RemoteFolderCover] 写入封面缓存失败 $folderUri: $e');
    }
  }

  /// 取整张图片的字节。超过 [maxBytes] 就放弃，不返回半张图。
  Future<Uint8List?> _fetchBytes({
    required RemoteServer server,
    required RemoteDirectoryClient client,
    required WebDavFile file,
    int maxBytes = _kMaxCoverBytes,
  }) async {
    try {
      if (client is SmbClient) {
        final (share, relativePath) =
            RemoteMediaResolver.parseSmbParts(file.path);
        return await _collect(
          client.streamFile(share, relativePath),
          maxBytes: maxBytes,
        );
      }
      if (client is WebDavClient) {
        final body = await client.inner.downloadStream(file.path);
        return await _collect(body.stream, maxBytes: maxBytes);
      }
    } catch (e) {
      debugPrint('[RemoteFolderCover] 下载封面失败 ${file.path}: $e');
    }
    return null;
  }

  Future<Uint8List?> _collect(
    Stream<Uint8List> stream, {
    required int maxBytes,
  }) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    var overflow = false;
    await for (final chunk in stream) {
      total += chunk.length;
      if (total > maxBytes) {
        overflow = true;
        break;
      }
      builder.add(chunk);
    }
    if (overflow || total == 0) return null;
    return builder.takeBytes();
  }
}

/// 一次批量缓存查询的结果。
class RemoteFolderCoverLookup {
  const RemoteFolderCoverLookup({
    required this.covers,
    required this.settled,
  });

  /// 有封面且缩略图文件仍在磁盘上：目录 virtualUri → 本地缩略图路径。
  final Map<String, String> covers;

  /// 已经「查过并落定」的目录（含本次进程跳过的目录）。
  final Set<String> settled;

  bool get isEmpty => covers.isEmpty && settled.isEmpty;
}

/// 递归查找时命中的一张封面。
class RemoteFolderCoverHit {
  const RemoteFolderCoverHit({
    required this.thumbnailPath,
    this.artworkPath,
    this.sourcePath,
  });

  final String thumbnailPath;
  final String? artworkPath;

  /// 命中的歌曲路径；命中目录封面图时为 null（图不是歌，不能进代表歌曲列）。
  final String? sourcePath;
}

/// [RemoteFolderCoverService.searchSubtree] 的结果。
class RemoteCoverSearchResult {
  const RemoteCoverSearchResult({
    required this.hit,
    required this.truncated,
    required this.failed,
    required this.listedDirectories,
  });

  final RemoteFolderCoverHit? hit;

  /// 预算用完了。目录树在本次会话里是确定的，重试也只会得到同样结论，
  /// 所以调用方可以把它当成「本次进程别再试了」。
  final bool truncated;

  /// 中途有目录列失败（网络/权限）。这是瞬时故障，**不能**据此判死，
  /// 下次进同一层目录还应该再试一次。
  final bool failed;

  /// 实际列了几个目录，成本回归用。
  final int listedDirectories;

  /// 是否「完整看过了这棵子树，确实没有封面」。
  bool get conclusive => hit == null && !truncated && !failed;
}
