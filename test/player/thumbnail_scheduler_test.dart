import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/metadata/thumbnail_scheduler.dart';

/// 造一个能稳定观测并发峰值的任务。
Future<void> _probe(
  List<int> counter,
  Duration delay, {
  bool throwAtEnd = false,
}) async {
  counter[0]++;
  if (counter[0] > counter[1]) counter[1] = counter[0];
  await Future<void>.delayed(delay);
  counter[0]--;
  if (throwAtEnd) throw StateError('boom');
}

void main() {
  final scheduler = ThumbnailScheduler.instance;

  test('本地名额上限落在 [2, 4] 区间', () {
    expect(ThumbnailScheduler.localLimit, greaterThanOrEqualTo(2));
    expect(ThumbnailScheduler.localLimit, lessThanOrEqualTo(4));
    expect(ThumbnailScheduler.remoteLimit, 2);
  });

  test('本地任务并发不超过上限，且能跑满上限', () async {
    final counter = <int>[0, 0]; // [当前并发, 峰值]
    final futures = <Future<void>>[];

    for (var i = 0; i < ThumbnailScheduler.localLimit * 4; i++) {
      futures.add(
        scheduler.run<void>(
          remote: false,
          task: () => _probe(counter, const Duration(milliseconds: 5)),
        ),
      );
    }
    await Future.wait(futures);

    expect(counter[1], ThumbnailScheduler.localLimit);
    expect(counter[0], 0, reason: '全部结束后名额应归还干净');
  });

  test('任务抛异常也会归还名额', () async {
    await expectLater(
      scheduler.run<void>(
        remote: false,
        task: () => _probe(<int>[0, 0], Duration.zero, throwAtEnd: true),
      ),
      throwsStateError,
    );

    // 名额若泄漏，这里会永远等不到执行
    var ran = false;
    await scheduler
        .run<void>(
          remote: false,
          task: () async {
            ran = true;
          },
        )
        .timeout(const Duration(seconds: 2));

    expect(ran, isTrue);
  });

  test('远程池与本地池互不占用名额', () async {
    final localCounter = <int>[0, 0];
    final remoteCounter = <int>[0, 0];

    // 先把本地名额全部占住
    final blockers = List<Future<void>>.generate(
      ThumbnailScheduler.localLimit,
      (_) => scheduler.run<void>(
        remote: false,
        task: () async {
          localCounter[0]++;
          if (localCounter[0] > localCounter[1]) {
            localCounter[1] = localCounter[0];
          }
          await Future<void>.delayed(const Duration(milliseconds: 40));
          localCounter[0]--;
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // 此时远程任务不应被本地占满而阻塞
    final remote = scheduler.run<void>(
      remote: true,
      task: () async {
        remoteCounter[0]++;
        if (remoteCounter[0] > remoteCounter[1]) {
          remoteCounter[1] = remoteCounter[0];
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
        remoteCounter[0]--;
      },
    );

    await Future.wait([remote, ...blockers]);

    expect(remoteCounter[1], 1);
    expect(localCounter[1], ThumbnailScheduler.localLimit);
  });

  test('isRemote 只把网络来源判为远程', () {
    expect(ThumbnailScheduler.isRemote('/Users/me/Music/a.flac'), isFalse);
    expect(ThumbnailScheduler.isRemote('subsonic://x/1.flac'), isTrue);
    expect(ThumbnailScheduler.isRemote('webdav://x/1.flac'), isTrue);
    expect(ThumbnailScheduler.isRemote('smb://x/1.flac'), isTrue);
    expect(ThumbnailScheduler.isRemote('jellyfin://x/1.flac'), isTrue);
  });

  test('排队任务按进入顺序获得名额', () async {
    final order = <int>[];
    final limit = ThumbnailScheduler.localLimit;

    // 占满名额
    final blockers = List<Future<void>>.generate(
      limit,
      (_) => scheduler.run<void>(
        remote: false,
        task: () => Future<void>.delayed(const Duration(milliseconds: 30)),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final queued = <Future<void>>[];
    for (var i = 0; i < 3; i++) {
      final index = i;
      queued.add(
        scheduler.run<void>(
          remote: false,
          task: () async {
            order.add(index);
          },
        ),
      );
    }

    await Future.wait([...blockers, ...queued]);
    expect(order, [0, 1, 2]);
  });
}
