import 'package:flutter/foundation.dart';

import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/sharing/lan_sync_protocol.dart';
import 'package:vynody/player/sharing/lyrics_import_conflict.dart';
import 'package:vynody/player/sharing/lyrics_translation_importer.dart';

/// 把对端的一个歌词包落到本地数据库。
///
/// 唯一实现。两条链路共用：
/// - 歌词同步（`/api/lyrics/import` 与 `GET /api/lyrics/export` 的落地）
/// - 文件传输（`TransferFileItem.lyricsPackage`）
///
/// 承载的是**重新扫描也拿不到的数据**：歌词正文与逐字行、全部语言的译文、
/// 时间轴偏移、来源与「是否已同步」标志。标签类元数据（标题 / 艺术家 / 专辑）
/// 不在这里处理 —— 它们扫描文件内嵌标签就能重建，同步过来反而会和扫描打架。
///
/// 判定顺序见 [decideLyricsImport]：本地没有才新增；本地是「已确认无词」
/// 不推翻；来源优先级只读 `displayPriority`；同档时间戳带容差。
///
/// 歌词本体与译文**不做解耦**：本体判为不覆盖时整条终止，译文一条也不导入。
/// 远端译文是基于远端那份歌词文本翻的，本机保留了自己的歌词文本时，行数与
/// 断句可能不同，硬塞会逐行错位。
class LyricsPackageImporter {
  const LyricsPackageImporter(this._db);

  final MetadataDatabase _db;

  Future<LyricsImportOutcome> import({
    required String localCacheKey,
    required Map<String, dynamic> incomingPackage,
  }) async {
    final rawIncomingLyrics =
        incomingPackage['lyrics_cache'] as Map<String, dynamic>?;
    if (rawIncomingLyrics == null) return LyricsImportOutcome.skipped;

    final incomingLyrics = LyricsCacheRecord.fromMap(rawIncomingLyrics);
    final incomingTranslations =
        (incomingPackage['translations'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(LyricsTranslationCacheRecord.fromMap)
            .toList(growable: false) ??
        const <LyricsTranslationCacheRecord>[];

    final localLyrics = await _db.getLyricsCache(localCacheKey);

    // 内容指纹短路：内容一样、只是 `updatedAtMillis` 不同时不重写。
    // 不做这道判断的话，同一份歌词会因为「远端时间戳较新」被整条覆盖一遍，
    // 连带刷新本地时间戳、让后续冲突判定偏向远端。
    final incomingHash = incomingPackage['content_hash'] as String?;
    if (localLyrics != null &&
        incomingHash != null &&
        incomingHash == lyricsContentHashOf(localLyrics)) {
      return LyricsImportOutcome.skipped;
    }

    final outcome = decideLyricsImport(
      localSource: localLyrics?.source,
      localUpdatedAtMillis: localLyrics?.updatedAtMillis ?? 0,
      incomingSource: incomingLyrics.source,
      incomingUpdatedAtMillis: incomingLyrics.updatedAtMillis,
    );
    if (outcome == LyricsImportOutcome.skipped) {
      return LyricsImportOutcome.skipped;
    }

    debugPrint(
      '[LyricsPackageImporter] ${outcome.name} lyrics for cacheKey: '
      '$localCacheKey (incoming=${incomingLyrics.source.dbValue}, '
      'local=${localLyrics?.source.dbValue ?? 'none'}, '
      'translations=${incomingTranslations.length})',
    );

    // toImported 固定丢弃远端自增主键（会按 id 命中本地另一首歌的行）与本机
    // 用户选的展示语言（设备级偏好，不随同步走）。
    await _db.insertOrUpdateLyricsCache(
      incomingLyrics.toImported(cacheKey: localCacheKey),
    );

    // 译文按 (cacheKey, languageCode) 逐条合并，绝不整表清空 —— 一首歌可以
    // 同时有 zh-cn / ja / ko 多条，clear 会把本机独有的语言一起删掉，而且裸
    // delete 会在删除与插入之间给 watch 订阅方送空快照。
    await LyricsTranslationImporter(
      _db,
    ).merge(cacheKey: localCacheKey, incoming: incomingTranslations);

    return outcome;
  }
}
