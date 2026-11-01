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
/// 3. 目录里有一张常见名字的封面图（`cover.jpg` / `folder.png` …）→ 下载它，
///    比读音频标签便宜，画质也更好；
/// 4. 目录里第一首音频的内嵌封面 → 走一次 Range 标签读取。
///
/// **只有「查到封面」才写 `folder_entries`**。负结果（确认这层没封面）留在
/// [_negativeCache] 里，只作用于本次进程：`folder_entries` 的封面列是「代表
/// 歌曲」语义，本地扫描会按它回填 `_folderRepresentativeSongs` 并反推目录统计，
/// 塞一行 `coverSongPath = <目录自身>` 的假数据会污染那条链路。
class RemoteFolderCoverService {
  RemoteFolderCoverService({MetadataDatabase? database})
      : _db = database ?? MetadataDatabase();

  final MetadataDatabase _db;

  /// 确认过「这层没有封面」的目录（目录 virtualUri），只在内存里。
  ///
  /// 有它兜底，反复进出同一层目录不会每次都重走一遍网络；进程重启后失效，
  /// 也就自然给了远端新增封面图一次重新发现的机会。
  static final Set<String> _negativeCache = <String>{};

  /// 负缓存上限。远程库可能有上万个目录，无界增长只是把内存换成一次省不下的
  /// 网络请求；超过上限就整体清空（按访问顺序淘汰太贵，收益也不大）。
  static const int _kNegativeCacheLimit = 2000;

  static void _rememberNoCover(String folderUri) {
    if (_negativeCache.length >= _kNegativeCacheLimit) {
      _negativeCache.clear();
    }
    _negativeCache.add(folderUri);
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
      if (_negativeCache.contains(uri)) settled.add(uri);
    }
    return RemoteFolderCoverLookup(covers: covers, settled: settled);
  }

  /// 解析单个远程目录的代表封面并写缓存。
  ///
  /// [forceRefresh] 为 true 时忽略缓存重新推导（下拉刷新用）。
  /// 返回本地缩略图路径；确认没有封面时返回 null。
  Future<String?> resolveCover({
    required RemoteServer server,
    required String password,
    required RemoteDirectoryClient client,
    required String folderPath,
    bool forceRefresh = false,
  }) async {
    final folderUri = RemoteMediaResolver.buildRemoteUri(server, folderPath);

    if (!forceRefresh) {
      final cached = await loadCachedCovers([folderUri]);
      final hit = cached.covers[folderUri];
      if (hit != null) return hit;
    }

    // 2) 已索引目录：库里代表歌曲的缩略图，零网络。
    //
    // 放在负缓存之前：目录先被判「没封面」、之后才被加入曲库索引时，
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

    // 负缓存：本次进程已经确认过这层没有封面，不再花网络。
    if (!forceRefresh && _negativeCache.contains(folderUri)) return null;

    List<WebDavFile> items;
    try {
      items = await client.listFiles(folderPath);
    } catch (e) {
      debugPrint('[RemoteFolderCover] 列出目录失败 $folderPath: $e');
      // 网络层面的失败不算「确认没封面」，不写负缓存，下次还能重试。
      return null;
    }

    // 3) 目录自带的封面图。
    final coverImage = pickCoverImage(items);
    if (coverImage != null) {
      final bytes = await _fetchBytes(
        server: server,
        client: client,
        file: coverImage,
      );
      if (bytes != null && bytes.isNotEmpty) {
        final imageUri =
            RemoteMediaResolver.buildRemoteUri(server, coverImage.path);
        final info = await MetadataHelper.saveArtworkAndThumbnail(
          imageUri,
          bytes,
          saveLarge: false,
        );
        final thumb = info?['thumbnailPath'] as String?;
        if (thumb != null && thumb.isNotEmpty) {
          await _persist(
            folderUri: folderUri,
            // 封面图不是歌：`songPath` 留 null。若写成图片路径，扫描器冷启动
            // 会把它当「代表歌曲」塞进元数据缓存，反推出的目录统计全是脏数据。
            coverSourcePath: null,
            thumbnailPath: thumb,
            artworkPath: info?['artworkPath'] as String?,
          );
          return thumb;
        }
      }
    }

    // 4) 第一首音频的内嵌封面。
    final audios = items.where((f) => f.isAudio).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (audios.isEmpty) {
      // 这层目录本身没有歌 → 确认没封面，写负缓存（不落库）。
      _rememberNoCover(folderUri);
      return null;
    }

    final first = audios.first;
    final firstUri = RemoteMediaResolver.buildRemoteUri(server, first.path);
    String? embeddedThumb;
    String? embeddedArtwork;
    try {
      final meta = await RemoteMetadataHelper.fetchSongMetadata(
        file: first,
        server: server,
        password: password,
      );
      embeddedThumb = meta?.thumbnailPath;
      embeddedArtwork = meta?.artworkPath;
    } catch (e) {
      debugPrint('[RemoteFolderCover] 读取内嵌封面失败 ${first.path}: $e');
    }

    final usable = (embeddedThumb != null &&
            embeddedThumb.isNotEmpty &&
            File(embeddedThumb).existsSync())
        ? embeddedThumb
        : null;
    if (usable == null) {
      // 读过标签也没有封面：确认结果，写负缓存。
      _rememberNoCover(folderUri);
      return null;
    }
    await _persist(
      folderUri: folderUri,
      coverSourcePath: firstUri,
      thumbnailPath: usable,
      artworkPath: embeddedArtwork,
    );
    return usable;
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
/// 写空壳会污染本地扫描的回填链路），留 [_negativeCache]。
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

  /// 已经「查过并落定」的目录（含确认无封面的负缓存）。
  final Set<String> settled;

  bool get isEmpty => covers.isEmpty && settled.isEmpty;
}
