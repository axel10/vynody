import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:vynody/player/lyrics/lyrics_cache_models.dart';

/// 跨设备同步协议版本。
///
/// 只用于**能力协商**：v1 客户端不广播 `sync` 属性，也不会发分块请求。
/// 接收端两种格式都认，所以新旧互连不会报错。
const int kLanSyncProtocolVersion = 2;

/// mDNS TXT 里表示「支持 v2 同步协议」的键。
///
/// 不能复用已有的 `proto`：那个属性从 TLS 那一版起就恒为 `'2'`，老客户端
/// 一样会广播它，拿它判断分块能力会让老客户端收到它不认识的分块请求。
const String kLanSyncCapabilityAttribute = 'sync';

/// 响应头，回给对端「我这边支持到哪个版本」。发送端据此决定能否分块 / gzip。
const String kLanSyncVersionHeader = 'X-Vynody-Sync-Version';

/// 跨设备传输的体积与批次约束。
class LanSyncLimits {
  /// 单个请求体上限。超过直接回 413，不解析 body —— 否则一个畸形请求就能把
  /// 接收端内存吃光（旧实现 `utf8.decoder.bind(request).join()` 无任何上限）。
  ///
  /// 64MB 是给 v1 对端留的余量：老版本把整个曲库塞进一个请求，3000 首带逐字
  /// 歌词大概 30MB 级别。再大就只能让对端升级（v2 会分块，单块 ≤ 2MB）。
  static const int maxBodyBytes = 64 * 1024 * 1024;

  /// 每批的条目数上限。
  static const int chunkItemCount = 200;

  /// 每批的估算字节上限（按 JSON 编码后的长度估）。
  static const int chunkByteBudget = 2 * 1024 * 1024;

  /// 请求体超过这个大小才值得 gzip。
  static const int gzipThresholdBytes = 512 * 1024;

  /// 分块会话超时。发送端中途放弃时，接收端靠它回收半截数据。
  static const Duration chunkSessionTtl = Duration(minutes: 5);

  /// 读响应体的超时。`connectionTimeout` 只管建连。
  static const Duration readTimeout = Duration(seconds: 45);
}

/// 按条目数与估算字节数切批，供分块发送使用。
///
/// 纯函数，便于单测：条目不可变，返回的是同一批 Map 的切片。
List<List<Map<String, dynamic>>> chunkLanSyncItems(
  List<Map<String, dynamic>> items, {
  int maxItems = LanSyncLimits.chunkItemCount,
  int maxBytes = LanSyncLimits.chunkByteBudget,
}) {
  if (items.isEmpty) return const [];

  final chunks = <List<Map<String, dynamic>>>[];
  var current = <Map<String, dynamic>>[];
  var currentBytes = 2; // 外层 `[]` 的两个字符

  for (final item in items) {
    final itemBytes = jsonEncode(item).length;
    final wouldOverflow =
        current.isNotEmpty &&
        (current.length >= maxItems || currentBytes + itemBytes > maxBytes);
    if (wouldOverflow) {
      chunks.add(current);
      current = <Map<String, dynamic>>[];
      currentBytes = 2;
    }
    current.add(item);
    currentBytes += itemBytes + 1; // 逗号
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

/// 解码请求体：[contentEncoding] 为 `gzip` 时先解压。
///
/// 解压失败直接抛 `FormatException`，由调用方转成 400 —— 不能把压缩字节当
/// UTF-8 硬解，那会得到一堆替换字符，后面 `jsonDecode` 的报错完全看不出原因。
String decodeLanSyncBody(List<int> bytes, {String? contentEncoding}) {
  final encoding = contentEncoding?.trim().toLowerCase();
  if (encoding == 'gzip' || encoding == 'x-gzip') {
    return utf8.decode(gzip.decode(bytes));
  }
  return utf8.decode(bytes);
}

/// 歌词内容指纹：只由「文本 + 逐字行 + 偏移」决定。
///
/// 用于跳过「内容一样、只是 `updatedAtMillis` 不同」的重写。不带 `source`：
/// 同一份歌词换了来源但不该被动重写，否则会顺带刷新时间戳、影响后续冲突判定。
String lyricsContentHash({
  required String? syncedLyrics,
  required Object? syncedLinesJson,
  required int timelineOffsetMillis,
}) {
  final payload = jsonEncode({
    't': syncedLyrics ?? '',
    'l': syncedLinesJson ?? const <Object?>[],
    'o': timelineOffsetMillis,
  });
  return sha1.convert(utf8.encode(payload)).toString();
}

/// 一条歌词缓存记录的内容指纹。
///
/// 双方都用它：发送端写进载荷的 `content_hash`，接收端拿本地记录重算一遍比对。
String lyricsContentHashOf(LyricsCacheRecord record) {
  return lyricsContentHash(
    syncedLyrics: record.syncedLyrics,
    syncedLinesJson: record.syncedLines
        .map((line) => line.toJson())
        .toList(growable: false),
    timelineOffsetMillis: record.timelineOffsetMillis,
  );
}

/// 跨设备传输的一条歌曲载荷。
///
/// 三条链路共用同一份结构，但只填各自需要的那部分：
/// - 歌词同步：`lyricsCache` + `translations`（标签类字段仅供日志与可读性）
/// - 歌单同步：只填匹配用的 `senderPath` / `title` / `artist` / `durationMs`
/// - 文件传输：全填，另附文件字节（走 `/api/transfer/upload`，不在本结构里）
///
/// `toJson()` 刻意保持 v1 的键名（`title` / `artist` / `album` / `duration_ms`
/// / `lyrics_cache` / `translations`），新增字段都是可忽略的附加项 —— 这样
/// v2 发送端发给 v1 接收端时，对方仍能按老逻辑导入。
class SongMetadataPackage {
  const SongMetadataPackage({
    this.senderPath,
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
    this.lyricsCache,
    this.translations = const [],
    this.contentHash,
  });

  final String? senderPath;
  final String title;
  final String artist;
  final String? album;
  final int? durationMs;
  final Map<String, dynamic>? lyricsCache;
  final List<Map<String, dynamic>> translations;
  final String? contentHash;

  bool get hasLyrics => lyricsCache != null;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'duration_ms': durationMs,
      if (senderPath != null) 'sender_path': senderPath,
      if (lyricsCache != null) 'lyrics_cache': lyricsCache,
      if (translations.isNotEmpty) 'translations': translations,
      if (contentHash != null) 'content_hash': contentHash,
    };
  }

  /// 解析失败（缺 `lyrics_cache`）时返回 null：歌词同步不带歌词的条目应当跳过，
  /// 歌单同步则只看匹配字段。
  factory SongMetadataPackage.fromJson(Map<String, dynamic> json) {
    return SongMetadataPackage(
      senderPath: json['sender_path'] as String?,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String?,
      durationMs: json['duration_ms'] as int?,
      lyricsCache: json['lyrics_cache'] as Map<String, dynamic>?,
      translations:
          (json['translations'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList(growable: false) ??
          const [],
      contentHash: json['content_hash'] as String?,
    );
  }
}
