import 'package:vynody/player/lyrics/lyrics_cache_models.dart';

/// 单条歌词包导入的结果。
///
/// 区分 added / updated 是为了让统计口径对得上直觉：旧实现只有一个
/// `overwritten`，本地本来没有歌词时也计入「覆盖 N 首」，用户看到的
/// 「更新 N 首」里其实混着「新增 N 首」。
enum LyricsImportOutcome { added, updated, skipped }

/// 跨设备比较 `updatedAtMillis` 的容差。
///
/// 该字段是各设备各自的系统时间，离线设备、未校时的盒子上可能差几天。差值
/// 超过这个阈值时视为「不可比较」，保留本地，避免时钟快的一方恒定单向覆盖。
const int kLanSyncTimestampToleranceMillis = 24 * 60 * 60 * 1000;

/// 判断一条远端歌词该不该写进本地。
///
/// 唯一的冲突判定实现，歌词同步与文件传输复用。判定顺序固定：
///
/// 1. 本地没有记录 → 新增。
/// 2. 本地是「已确认无词」（`none`）→ 跳过。那是用户显式意图，自动同步不得推翻。
/// 3. 来源优先级只读 [LyricsCacheSource.displayPriority]（越小越优先），
///    禁止另建一张表 —— 曾经的第二张表把 `embedded` 判得比 AI 还低，导致远端
///    AI 歌词覆盖本机内嵌 LRC。
/// 4. 同档才比时间戳，且带容差；超出容差视为不可比较，保留本地。
LyricsImportOutcome decideLyricsImport({
  required LyricsCacheSource? localSource,
  required int localUpdatedAtMillis,
  required LyricsCacheSource incomingSource,
  required int incomingUpdatedAtMillis,
}) {
  if (localSource == null) return LyricsImportOutcome.added;
  if (localSource == LyricsCacheSource.none) return LyricsImportOutcome.skipped;

  final localPriority = localSource.displayPriority;
  final incomingPriority = incomingSource.displayPriority;

  if (incomingPriority < localPriority) return LyricsImportOutcome.updated;
  if (incomingPriority > localPriority) return LyricsImportOutcome.skipped;

  final deltaMillis = incomingUpdatedAtMillis - localUpdatedAtMillis;
  // 远端不更新。
  if (deltaMillis <= 0) return LyricsImportOutcome.skipped;
  // 差值大到不像是「真的有人改过」，只可能是两台设备时钟不对齐。
  // 此时保留本地，避免时钟快的一方恒定单向覆盖。
  if (deltaMillis > kLanSyncTimestampToleranceMillis) {
    return LyricsImportOutcome.skipped;
  }
  return LyricsImportOutcome.updated;
}
