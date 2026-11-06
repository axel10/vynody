/// 后台 UI 通知判据（纯函数，唯一入口）。
///
/// Rust 引擎的 statusStream 每 500ms 无条件推一条播放状态；[AudioService]
/// 收到后若照常 `state = snapshot`，整棵 UI 就会每 500ms rebuild 一次并出
/// 一帧 —— 即使窗口已经最小化、FFT 采集和 position tick 都已停。
///
/// 节流期间只放行：强制刷新、播放态变化（播放/暂停/切歌/时长）、真 seek。
/// 纯位置推进一律压住，连低频心跳也不留 —— 窗口不可见时刷新 UI 没有
/// 意义，恢复可见时由调用方 force 一次补齐进度。
library;

const Duration kForegroundUiNotifyInterval = Duration(milliseconds: 120);
const int kForegroundPositionJumpMs = 120;

/// 节流期间只有真 seek 才立刻刷新；500ms 的正常推进不能命中。
const int kThrottledSeekJumpMs = 2000;

bool shouldNotifyUi({
  required bool force,
  required bool playbackChanged,
  required int positionJumpMs,
  required Duration elapsedSinceNotify,
  required bool isPlaying,
  required bool throttled,
}) {
  if (force || playbackChanged) return true;
  // 后台不留心跳：任何「隔几秒一帧」都是纯粹的浪费。
  if (throttled) return positionJumpMs >= kThrottledSeekJumpMs;
  return positionJumpMs >= kForegroundPositionJumpMs ||
      (isPlaying && elapsedSinceNotify >= kForegroundUiNotifyInterval);
}
