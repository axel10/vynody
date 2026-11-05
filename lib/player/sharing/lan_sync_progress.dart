import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lan_sync_models.dart';

/// 一次同步当前处在哪一步。
///
/// 刻意做得比实际状态机更粗：UI 只需要「在干什么」和「做了多少」，
/// 每个链路各自更细的状态（收第几块、匹配到第几条）不值得暴露出来。
enum LanSyncStage {
  /// 整理要发出去的内容（查库、算 cacheKey、打包）。
  preparing,

  /// 正在收发数据（分块传输）。
  transferring,

  /// 已经发出去了，等对端确认。
  waitingPeer,

  /// 正在把收到的条目落到本地库（匹配 + 写库）。
  importing,

  /// 文件已落盘，正在让扫描器入库。
  ingesting,
}

/// 同步任务的实时进度。
///
/// 两端共用：发起方用它画进度对话框（可取消），被动方用它画「正在导入」。
/// 被动方的进度只有接收方向才有意义，主动发起的那台不会收到 incoming。
class LanSyncProgress {
  final LanSyncKind kind;
  final LanSyncDirection direction;
  final String deviceName;
  final LanSyncStage stage;

  /// 已处理条目数；[total] 为 0 时表示总量未知（只画不确定进度条）。
  final int processed;
  final int total;

  /// 用户已经点了「取消」，服务会在下一个检查点抛出 [LanSyncCancelledException]。
  ///
  /// 不立刻中断是因为分块请求正在进行：硬中断会让对端会话半截，反而要等 TTL。
  final bool cancelRequested;

  const LanSyncProgress({
    required this.kind,
    required this.direction,
    required this.deviceName,
    required this.stage,
    this.processed = 0,
    this.total = 0,
    this.cancelRequested = false,
  });

  double? get fraction =>
      total > 0 ? (processed / total).clamp(0.0, 1.0) : null;

  LanSyncProgress copyWith({
    String? deviceName,
    LanSyncStage? stage,
    int? processed,
    int? total,
    bool? cancelRequested,
  }) {
    return LanSyncProgress(
      kind: kind,
      direction: direction,
      deviceName: deviceName ?? this.deviceName,
      stage: stage ?? this.stage,
      processed: processed ?? this.processed,
      total: total ?? this.total,
      cancelRequested: cancelRequested ?? this.cancelRequested,
    );
  }
}

class LanSyncProgressNotifier extends Notifier<LanSyncProgress?> {
  @override
  LanSyncProgress? build() => null;

  /// 当前进度快照。`state` 是受保护的成员，服务侧要读它只能走这个 getter。
  LanSyncProgress? get current => state;

  LanSyncProgress? begin({
    required LanSyncKind kind,
    required LanSyncDirection direction,
    required String deviceName,
  }) {
    final progress = LanSyncProgress(
      kind: kind,
      direction: direction,
      deviceName: deviceName,
      stage: direction == LanSyncDirection.incoming
          ? LanSyncStage.transferring
          : LanSyncStage.preparing,
    );
    state = progress;
    return progress;
  }

  /// 换阶段。传 null 表示保持已有的 processed/total 不变。
  void setStage(LanSyncStage stage, {int? processed, int? total}) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(stage: stage, processed: processed, total: total);
  }

  /// 推进计数。进度条不需要精确到条目级别，掉帧比数字跳变更难看，
  /// 所以这里只在值真的变化时才重建。
  void advance([int delta = 1, int? total]) {
    final current = state;
    if (current == null) return;
    final nextProcessed = current.processed + delta;
    final nextTotal = total ?? current.total;
    if (nextProcessed == current.processed && nextTotal == current.total) {
      return;
    }
    state = current.copyWith(processed: nextProcessed, total: nextTotal);
  }

  void requestCancel() {
    final current = state;
    if (current == null || current.cancelRequested) return;
    state = current.copyWith(cancelRequested: true);
  }

  bool get cancelRequested => state?.cancelRequested ?? false;

  void clear() => state = null;
}

final lanSyncProgressProvider =
    NotifierProvider<LanSyncProgressNotifier, LanSyncProgress?>(
      LanSyncProgressNotifier.new,
    );
