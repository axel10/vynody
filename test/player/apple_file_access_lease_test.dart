import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/platform/apple_file_access.dart';

/// 记录原生侧收到的调用，用来验证「同一 (路径, holder) 只真正 begin 一次」
/// 以及「释放只减自己那一份」。
class _ChannelLog {
  final List<String> calls = <String>[];

  int get begins => calls.where((c) => c.startsWith('begin:')).length;
  int get ends => calls.where((c) => c.startsWith('end:')).length;
  int get registers => calls.where((c) => c.startsWith('register:')).length;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('audio_core.player'),
          (call) async {
            final args = (call.arguments as Map?) ?? const <String, Object?>{};
            final path = args['path'] as String? ?? '';
            final holder = args['holder'] as String? ?? '';
            switch (call.method) {
              case 'beginScopedAccess':
                calls.add('begin:$holder:$path');
                return true;
              case 'endScopedAccess':
                calls.add('end:$holder:$path');
                return null;
              case 'registerPersistentAccess':
                calls.add('register:$holder:$path');
                return true;
            }
            return null;
          },
        );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('audio_core.player'),
          null,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ChannelLog log;

  setUp(() {
    AppleFileAccess.resetForTest();
    log = _ChannelLog()..install();
  });

  tearDown(() {
    log.uninstall();
    AppleFileAccess.resetForTest();
  });

  test('重复申请同一目录只真正 begin 一次', () async {
    final first = await AppleFileAccess.hold(path: '/music/a', holder: 'sharing');
    final second = await AppleFileAccess.hold(
      path: '/music/a',
      holder: 'sharing',
    );

    expect(first.granted, isTrue);
    expect(log.begins, 1);
    expect(second.granted, isTrue);
    expect(log.begins, 1, reason: '去重命中不应再下发 begin');
  });

  test('借用视图释放是 no-op，不误减持有方的额度', () async {
    final owner = await AppleFileAccess.hold(
      path: '/music/a',
      holder: 'sharing',
    );
    final borrower = await AppleFileAccess.hold(
      path: '/music/a',
      holder: 'sharing',
    );

    await borrower.release();
    expect(log.ends, 0, reason: '借用者没有 begin 过，不能下发 end');

    await owner.release();
    expect(log.ends, 1);
    expect(AppleFileAccess.isHeld(path: '/music/a', holder: 'sharing'), isFalse);
  });

  test('重复释放同一份租约只下发一次 end', () async {
    final lease = await AppleFileAccess.hold(path: '/music/b', holder: 'sharing');
    await lease.release();
    await lease.release();
    expect(log.ends, 1);
  });

  test('不同 holder 各自记账，互不影响', () async {
    await AppleFileAccess.hold(path: '/music/a', holder: 'scanner');
    await AppleFileAccess.hold(path: '/music/a', holder: 'sharing');
    expect(log.begins, 2);

    await AppleFileAccess.releaseAll(holder: 'sharing');
    expect(log.ends, 1);
    expect(AppleFileAccess.isHeld(path: '/music/a', holder: 'scanner'), isTrue);
  });

  test('并发申请同一目录也只 begin 一次', () async {
    await Future.wait([
      AppleFileAccess.hold(path: '/music/a', holder: 'sharing'),
      AppleFileAccess.hold(path: '/music/a', holder: 'sharing'),
      AppleFileAccess.hold(path: '/music/a', holder: 'sharing'),
    ]);
    expect(log.begins, 1);
  });

  test('路径写法不同视为同一目录', () async {
    await AppleFileAccess.hold(path: '/music/a', holder: 'sharing');
    await AppleFileAccess.hold(path: '/music/./a/', holder: 'sharing');
    expect(log.begins, 1);
  });

  test('withWrite 成对下发 begin/end', () async {
    final result = await AppleFileAccess.withWrite(<String>[
      '/music/a.mp3',
    ], () async => 42);

    expect(result, 42);
    expect(log.begins, 1);
    expect(log.ends, 1);
  });

  test('withWrite 内部抛错也会释放', () async {
    await expectLater(
      AppleFileAccess.withWrite(<String>['/music/a.mp3'], () async {
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(log.begins, 1);
    expect(log.ends, 1);
  });
}
