import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'package:vynody/widgets/floating_capsule_header.dart';
import 'package:vynody/widgets/scroll_past_top.dart';

/// 「竖屏滚离顶部 → 浮出返回 + 更多」这套业务逻辑的唯一实现。
///
/// 以前 `library_page` / `remote_library_sub_host_page` / `remote_page_shell` /
/// `detail_page_shell` 各写一份，其中两处写死 36.0。
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  Widget verticalList({
    required List<bool> log,
    required ScrollController controller,
    bool enabled = true,
    int? tabIndex,
  }) {
    return ScrollPastTopScope(
      enabled: enabled,
      tabIndex: tabIndex,
      builder: (context, isPastTop) {
        log.add(isPastTop);
        return ListView.builder(
          controller: controller,
          itemCount: 60,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('$i')),
        );
      },
    );
  }

  testWidgets('纵向滚过阈值报告 true，回到顶部恢复 false', (tester) async {
    final log = <bool>[];
    final controller = ScrollController();

    await tester.pumpWidget(wrap(verticalList(log: log, controller: controller)));
    expect(log.last, isFalse, reason: '初始在顶部');

    controller.jumpTo(kHeaderFloatingCapsuleThreshold + 20);
    await tester.pump();
    expect(log.last, isTrue);

    controller.jumpTo(0);
    await tester.pump();
    expect(log.last, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('阈值只有一个来源，允许按需覆盖', (tester) async {
    final log = <bool>[];
    final controller = ScrollController();

    await tester.pumpWidget(
      wrap(
        ScrollPastTopScope(
          threshold: 200,
          builder: (context, isPastTop) {
            log.add(isPastTop);
            return ListView.builder(
              controller: controller,
              itemCount: 60,
              itemBuilder: (_, i) => SizedBox(height: 80, child: Text('$i')),
            );
          },
        ),
      ),
    );

    // 默认阈值早已越过，但本实例要 200。
    controller.jumpTo(kHeaderFloatingCapsuleThreshold + 20);
    await tester.pump();
    expect(log.last, isFalse);

    controller.jumpTo(240);
    await tester.pump();
    expect(log.last, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('横向滚动不算滚离顶部', (tester) async {
    final log = <bool>[];
    final controller = ScrollController();

    await tester.pumpWidget(
      wrap(
        ScrollPastTopScope(
          builder: (context, isPastTop) {
            log.add(isPastTop);
            return ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              itemCount: 60,
              itemBuilder: (_, i) => SizedBox(width: 80, child: Text('$i')),
            );
          },
        ),
      ),
    );

    controller.jumpTo(400);
    await tester.pump();
    expect(log.last, isFalse, reason: '面包屑、横向 tab 条也会发滚动通知');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('enabled=false 时不监听也不重建', (tester) async {
    final log = <bool>[];
    final controller = ScrollController();

    await tester.pumpWidget(
      wrap(verticalList(log: log, controller: controller, enabled: false)),
    );
    final int buildsBeforeScroll = log.length;

    controller.jumpTo(kHeaderFloatingCapsuleThreshold + 200);
    await tester.pump();

    expect(log.length, buildsBeforeScroll, reason: '关掉后不该有任何 setState');
    expect(log.last, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('按 tabIndex 分账：滚 A 分类不会让 B 分类跟着过顶', (tester) async {
    final log = <bool>[];
    final controller = ScrollController();
    int tab = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setTab) {
              return Column(
                children: [
                  TextButton(
                    onPressed: () => setTab(() => tab = 1),
                    child: const Text('switch'),
                  ),
                  TextButton(
                    onPressed: () => setTab(() => tab = 0),
                    child: const Text('back'),
                  ),
                  Expanded(
                    child: verticalList(
                      log: log,
                      controller: controller,
                      tabIndex: tab,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    controller.jumpTo(kHeaderFloatingCapsuleThreshold + 20);
    await tester.pump();
    expect(log.last, isTrue);

    await tester.tap(find.text('switch'));
    await tester.pump();
    expect(log.last, isFalse, reason: '另一个分类从未滚动过');

    await tester.tap(find.text('back'));
    await tester.pump();
    expect(log.last, isTrue, reason: '切回来要保留该分类自己的位置状态');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('FloatingCapsuleHeader：visible 控制淡出与点击穿透', (tester) async {
    Widget build(bool visible) => wrap(
      Stack(
        children: [
          FloatingCapsuleHeader(
            visible: visible,
            child: const SizedBox(
              key: ValueKey('capsule_tap_target'),
              width: 44,
              height: 44,
            ),
          ),
        ],
      ),
    );

    double opacityOf(WidgetTester t) =>
        t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

    bool ignoringOf(WidgetTester t) => t
        .widget<IgnorePointer>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('capsule_tap_target')),
                matching: find.byType(IgnorePointer),
              )
              .first,
        )
        .ignoring;

    await tester.pumpWidget(build(false));
    await tester.pumpAndSettle();
    expect(opacityOf(tester), 0.0);
    expect(ignoringOf(tester), isTrue, reason: '隐藏态必须让出点击');

    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1.0);
    expect(ignoringOf(tester), isFalse);
  });
}
