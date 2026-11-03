import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/lyrics_panel_views.dart';

/// 用一个只在 initState 计数的 StatefulWidget 当探针：
/// 计数增加就说明这一行的子树被重建了（行内译文淡入会跟着重播）。
class _LineProbe extends StatefulWidget {
  const _LineProbe({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_LineProbe> createState() => _LineProbeState();
}

class _LineProbeState extends State<_LineProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    return const Text('line', textDirection: TextDirection.ltr);
  }
}

Widget _host({
  required bool enabled,
  required int scrollTriggerTime,
  required VoidCallback onProbeInit,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: <Widget>[
        StaggeredAppleLyricsScrollWrapper(
          index: 3,
          activeIndex: 2,
          scrollDelta: 40,
          scrollTriggerTime: scrollTriggerTime,
          isEnteringFocusMode: false,
          firstVisibleIndex: 0,
          isTransitioning: false,
          enabled: enabled,
          child: _LineProbe(onInit: onProbeInit),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('进出错峰窗口不重建行子树（译文淡入不会重播）', (tester) async {
    var probeInits = 0;

    await tester.pumpWidget(
      _host(enabled: true, scrollTriggerTime: 0, onProbeInit: () => probeInits++),
    );
    expect(probeInits, 1);

    // 模拟滚动让 firstVisibleIndex 越过窗口边界：enabled 翻成 false
    await tester.pumpWidget(
      _host(
        enabled: false,
        scrollTriggerTime: 0,
        onProbeInit: () => probeInits++,
      ),
    );
    expect(probeInits, 1, reason: '退出窗口不能重建行子树');

    // 再滚回来：enabled 翻回 true，并按新的滚动参数补播错峰动画
    final int trigger = DateTime.now().millisecondsSinceEpoch;
    await tester.pumpWidget(
      _host(
        enabled: true,
        scrollTriggerTime: trigger,
        onProbeInit: () => probeInits++,
      ),
    );
    expect(probeInits, 1, reason: '重新进入窗口不能重建行子树');

    // 让错峰 Timer 与 550ms 动画跑完，避免残留 Timer
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabled=false 时只透传 child，动画期间位置不偏移', (tester) async {
    await tester.pumpWidget(
      _host(
        enabled: false,
        scrollTriggerTime: DateTime.now().millisecondsSinceEpoch,
        onProbeInit: () {},
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    final Transform? transform = tester
        .widgetList<Transform>(find.byType(Transform))
        .cast<Transform?>()
        .firstWhere(
          (t) => t!.transform.getTranslation().y != 0,
          orElse: () => null,
        );
    expect(transform, isNull, reason: '未启用时不应产生任何位移');

    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
  });
}
