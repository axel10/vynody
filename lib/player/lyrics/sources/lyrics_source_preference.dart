import 'package:vynody/player/lyrics/lyrics_cache_models.dart';

/// 用户手工选过的来源。
///
/// 曾经还有一个 `languageCode` 维度，用来区分「同来源不同语言的歌词记录」。
/// 但 `lyrics_cache` 是 `UNIQUE(cacheKey)`，一个 key 只有一行，这个维度从来
/// 不可能命中；对应字段已于 schema 49 删除。
typedef LyricsSourcePreference = ({LyricsCacheSource source});

/// 从候选记录里挑出「默认应当展示」的那一条。
///
/// 这是唯一的挑选入口：
/// - `LyricsController._syncLyricsCacheWatch` 决定实际显示哪条
/// - 「换源」弹窗决定哪一项打勾
///
/// 两处此前各自实现过一遍（弹窗自己遍历顺序表），于是会出现弹窗高亮 A、
/// 实际显示 B。顺序本身由 [LyricsCacheSource.displayPriority] 派生，
/// 本函数不再维护任何来源列表。
///
/// [preference] 是用户上次手工选择的结果。没命中（比如缓存被重新查询覆盖成
/// 别的来源）时回退到优先级顺序，而不是让弹窗一项都不打勾。
LyricsCacheRecord? pickPreferredLyricsRecord(
  List<LyricsCacheRecord> records, {
  LyricsSourcePreference? preference,
}) {
  if (records.isEmpty) return null;

  if (preference != null) {
    for (final record in records) {
      if (record.source == preference.source) return record;
    }
  }

  for (final source in lyricsSourceDisplayOrder) {
    for (final record in records) {
      if (record.source == source) return record;
    }
  }
  // 只剩 none（已确认无词）时保持调用方传入的第一条。
  return records.first;
}
