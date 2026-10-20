import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/remote/services/remote_track_load_progress.dart';

void main() {
  group('RemoteTrackLoadProgressNotifier', () {
    late RemoteTrackLoadProgressNotifier progress;

    setUp(() {
      progress = RemoteTrackLoadProgressNotifier();
    });

    tearDown(() {
      progress.dispose();
    });

    test('begin 复位计数与取消标志', () {
      progress.begin();
      progress.addToTotal(48);
      progress.advance(12);
      progress.cancel();

      progress.begin();

      expect(progress.isActive, isTrue);
      expect(progress.isCancelled, isFalse);
      expect(progress.total, 0);
      expect(progress.loaded, 0);
      expect(progress.stage, RemoteTrackLoadStage.loading);
    });

    test('未开始流程时的上报与取消都被忽略', () {
      progress.cancel();
      progress.addToTotal(10);
      progress.advance();

      expect(progress.isCancelled, isFalse);
      expect(progress.total, 0);
      expect(progress.loaded, 0);
      // 「播放 / 加入队列」也走同一批拉取函数，没有活动流程时不能抛。
      expect(progress.throwIfCancelled, returnsNormally);
    });

    test('取消后 throwIfCancelled 抛出取消异常', () {
      progress.begin();
      progress.cancel();

      expect(progress.throwIfCancelled, throwsA(isA<RemoteTrackLoadCancelled>()));
    });

    test('取消后不再接受进度上报', () {
      progress.begin();
      progress.addToTotal(10);
      progress.advance(3);
      progress.cancel();

      progress.addToTotal(10);
      progress.advance();
      progress.setTotal(99);

      expect(progress.total, 10);
      expect(progress.loaded, 3);
    });

    test('addToTotal 累加分母而不是覆盖', () {
      progress.begin();
      progress.addToTotal(9);
      progress.advance(9);
      progress.addToTotal(11);
      progress.advance(11);

      expect(progress.total, 20);
      expect(progress.loaded, 20);
      expect(progress.fraction, 1.0);
    });

    test('总数未知时 fraction 为 null', () {
      progress.begin();
      progress.advance(5);

      expect(progress.fraction, isNull);
    });

    test('切阶段会清零已计数', () {
      progress.begin();
      progress.addToTotal(20);
      progress.advance(20);

      progress.setStage(RemoteTrackLoadStage.queueing);

      expect(progress.stage, RemoteTrackLoadStage.queueing);
      expect(progress.loaded, 0);
      expect(progress.total, 20);
    });
  });
}
