import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/library_selection_scope.dart';
import 'package:vynody/widgets/marquee/marquee_selection_region.dart';

Widget _tile(String key, double height) {
  return MarqueeSelectableItem(
    selectionKey: key,
    child: SizedBox(
      height: height,
      child: const ColoredBox(color: Color(0xFF223344)),
    ),
  );
}

/// 三个 40px 高的条目 + 下方大片空白，模拟专辑分组列表。
Widget _harness() {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: MarqueeSelectionRegion(
          scope: LibrarySelectionScope.library,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tile('a', 40),
              _tile('b', 40),
              _tile('c', 40),
              const Spacer(),
            ],
          ),
        ),
      ),
    ),
  );
}

LibrarySelectionState _readSelection(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MarqueeSelectionRegion)),
    listen: false,
  );
  return container.read(librarySelectionStateProvider);
}

void main() {
  testWidgets('从空白处按住左键向上拖动会框选命中的条目', (tester) async {
    await tester.pumpWidget(_harness());

    final gesture = await tester.startGesture(
      const Offset(400, 400),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.moveTo(const Offset(400, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final selection = _readSelection(tester);
    expect(selection.scope, LibrarySelectionScope.library);
    expect(selection.isActive, isTrue);
    expect(selection.selectedKeys, equals(<String>{'a', 'b', 'c'}));
  });

  testWidgets('框选只覆盖矩形内的条目', (tester) async {
    await tester.pumpWidget(_harness());

    // 从空白处拖到 y=100：只盖住最后一条（80-120），不碰上面的 b。
    final gesture = await tester.startGesture(
      const Offset(400, 400),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.moveTo(const Offset(400, 100));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(_readSelection(tester).selectedKeys, <String>{'c'});
  });

  testWidgets('拖动距离低于阈值不触发框选', (tester) async {
    await tester.pumpWidget(_harness());

    final gesture = await tester.startGesture(
      const Offset(400, 400),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.moveTo(const Offset(402, 402));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(_readSelection(tester).selectedKeys, isEmpty);
  });

  testWidgets('在条目上直接拖动不进入框选（保留原生拖拽）', (tester) async {
    await tester.pumpWidget(_harness());

    final gesture = await tester.startGesture(
      const Offset(400, 20),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.moveTo(const Offset(400, 110));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(_readSelection(tester).selectedKeys, isEmpty);
  });

  testWidgets('按住 Alt 从条目上拖动会强制框选', (tester) async {
    await tester.pumpWidget(_harness());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);

    final gesture = await tester.startGesture(
      const Offset(400, 20),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.moveTo(const Offset(400, 110));
    await tester.pump();

    expect(
      MarqueeSelectionRuntime.suppressNativeDrag,
      isTrue,
      reason: 'Alt 拖动期间必须让原生拖拽让路',
    );

    await gesture.up();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(_readSelection(tester).selectedKeys, <String>{'a', 'b', 'c'});
  });

  testWidgets('按住 Ctrl 框选是追加而不是替换', (tester) async {
    await tester.pumpWidget(_harness());

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MarqueeSelectionRegion)),
      listen: false,
    );
    container
        .read(librarySelectionStateProvider.notifier)
        .setSelection(<String>{'a'}, scope: LibrarySelectionScope.library);
    await tester.pump();

    // Ctrl 起手，从空白处只框住最后一条。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final gesture = await tester.startGesture(
      const Offset(400, 400),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.moveTo(const Offset(400, 100));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(_readSelection(tester).selectedKeys, containsAll(<String>['a', 'c']));
  });

  testWidgets('框选从未命中任何条目时不清空已有选择', (tester) async {
    await tester.pumpWidget(_harness());

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MarqueeSelectionRegion)),
      listen: false,
    );
    container
        .read(librarySelectionStateProvider.notifier)
        .setSelection(<String>{'b'}, scope: LibrarySelectionScope.library);
    await tester.pump();

    // 全程留在下方空白区域，没框到任何条目。
    final gesture = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.moveTo(const Offset(700, 500));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(_readSelection(tester).selectedKeys, <String>{'b'});
  });

  testWidgets('没有框选区域的条目保持纯透传', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarqueeSelectableItem(
            selectionKey: 'a',
            child: SizedBox(height: 40, child: ColoredBox(color: Color(0xFF223344))),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(MarqueeSelectableItem), findsOneWidget);
  });
}
