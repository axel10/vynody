import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/audio/ui_notify_throttle.dart';

/// 回归：最小化后 Rust 的 500ms statusStream 不能再把整棵 UI 拉起来出帧。
///
/// 现场证据：DevTools 时间线 28 帧里 26 帧间隔严格 ~500ms，每帧 build
/// 12~15ms；IdleProbe 显示 `transient=0 scheduledFrame=false`，即帧不是
/// Ticker 驱动的，而是 `AudioService.notifyListeners -> state = snapshot`
/// 的全量 rebuild。修复落在 shouldNotifyUi 这道唯一闸上。
void main() {
  bool notify({
    bool force = false,
    bool playbackChanged = false,
    int positionJumpMs = 500,
    Duration elapsedSinceNotify = const Duration(milliseconds: 500),
    bool isPlaying = true,
    bool throttled = true,
  }) {
    return shouldNotifyUi(
      force: force,
      playbackChanged: playbackChanged,
      positionJumpMs: positionJumpMs,
      elapsedSinceNotify: elapsedSinceNotify,
      isPlaying: isPlaying,
      throttled: throttled,
    );
  }

  group('前台行为不变', () {
    test('500ms 的 status 推进照常通知', () {
      expect(notify(throttled: false), isTrue);
    });

    test('120ms 闸内的微小推进不通知', () {
      expect(
        notify(
          throttled: false,
          positionJumpMs: 20,
          elapsedSinceNotify: const Duration(milliseconds: 20),
        ),
        isFalse,
      );
    });

    test('暂停且无状态变化时不通知', () {
      expect(
        notify(
          throttled: false,
          isPlaying: false,
          positionJumpMs: 0,
          elapsedSinceNotify: const Duration(seconds: 1),
        ),
        isFalse,
      );
    });
  });

  group('最小化 / 后台节流', () {
    test('500ms 纯位置推进不通知（1%+ GPU 的根因）', () {
      expect(notify(), isFalse);
    });

    test('10s 心跳也不放行（回归：最小化后隔几秒跳一帧）', () {
      expect(
        notify(elapsedSinceNotify: const Duration(seconds: 10)),
        isFalse,
      );
      expect(
        notify(elapsedSinceNotify: const Duration(seconds: 60)),
        isFalse,
      );
    });

    test('真 seek 立即放行，2s 以内的正常推进不误判', () {
      expect(notify(positionJumpMs: 3000), isTrue);
      expect(notify(positionJumpMs: 1500), isFalse);
    });

    test('播放态变化与 force 不受节流影响', () {
      expect(notify(playbackChanged: true), isTrue);
      expect(notify(force: true), isTrue);
    });

    test('暂停时同样不通知', () {
      expect(
        notify(
          isPlaying: false,
          elapsedSinceNotify: const Duration(seconds: 30),
        ),
        isFalse,
      );
    });
  });
}
