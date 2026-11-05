import 'package:flutter/foundation.dart';

import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/utils/language_code_utils.dart';

/// 跨设备同步时，把远端译文合并进本地。
///
/// 唯一实现，歌词同步（`/api/lyrics/import`）与文件传输的 `lyrics_package`
/// 共用同一个调用点——两者都走 `_importLyricsPackageWithConflict`。
///
/// 合并规则：
///
/// - **按 `(cacheKey, languageCode)` 逐条合并**。歌词译文表是
///   `UNIQUE(cacheKey, languageCode)`，一首歌可以同时存在 `zh-cn` / `ja` /
///   `ko` 多条。本机独有的语言原样保留。
/// - **同一语言比较 `updatedAtMillis`**，远端不比本地新就跳过。
/// - **绝不整表清空**。旧的实现先 `clearLyricsTranslationCacheByKey` 再逐条
///   插入，会把本机其它语言一起删掉；而且 clear 是裸 delete，会在删除与插入
///   之间给 watch 订阅方送出一份空快照，正在播放时歌词面板译文会整份闪空。
/// - **语言码归一后为空则丢弃**，否则会写出 `languageCode=''` 的脏行，语言
///   选择菜单里显示成空名。
class LyricsTranslationImporter {
  const LyricsTranslationImporter(this._db);

  final MetadataDatabase _db;

  /// 返回实际写入（或更新）的条数，供调用方统计。
  Future<int> merge({
    required String cacheKey,
    required List<LyricsTranslationCacheRecord> incoming,
  }) async {
    if (cacheKey.isEmpty || incoming.isEmpty) return 0;

    final localUpdatedAtByLanguage = <String, int>{};
    for (final local in await _db.getLyricsTranslationCaches(cacheKey)) {
      final languageCode = LanguageCodeUtils.normalizeLanguageCode(
        local.languageCode,
      );
      if (languageCode.isEmpty) continue;
      final previous = localUpdatedAtByLanguage[languageCode];
      if (previous == null || local.updatedAtMillis > previous) {
        localUpdatedAtByLanguage[languageCode] = local.updatedAtMillis;
      }
    }

    var written = 0;
    for (final translation in incoming) {
      final languageCode = LanguageCodeUtils.normalizeLanguageCode(
        translation.languageCode,
      );
      if (languageCode.isEmpty) {
        debugPrint(
          '[LyricsTranslationImporter] Skipped translation with empty '
          'languageCode: cacheKey="$cacheKey"',
        );
        continue;
      }

      final localUpdatedAt = localUpdatedAtByLanguage[languageCode];
      if (localUpdatedAt != null &&
          localUpdatedAt >= translation.updatedAtMillis) {
        continue;
      }

      await _db.insertOrUpdateLyricsTranslationCache(
        LyricsTranslationCacheRecord(
          cacheKey: cacheKey,
          languageCode: languageCode,
          translatedText: translation.translatedText,
          translatedLines: translation.translatedLines,
          provider: translation.provider,
          updatedAtMillis: translation.updatedAtMillis,
        ),
      );
      written++;
    }
    return written;
  }
}
