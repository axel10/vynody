import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';
import 'package:vynody/widgets/folder_zoom_gesture_layer.dart';

void main() {
  late SettingsService settings;
  late ScrollController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'folder_zoom_scale': 0.2});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
    settings.folderZoomScale = kFolderZoomTierStandardList;
    controller = ScrollController();
  });

  tearDown(() {
    controller.dispose();
  });

  Widget buildHarness() {
    return ProviderScope(
      overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
      child: MaterialApp(
        home: Scaffold(
          body: FolderZoomGestureLayer(
            child: ListView.builder(
              controller: controller,
              itemCount: 100,
              itemBuilder: (context, index) => SizedBox(
                height: 60,
                child: Text('item $index'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Ctrl + 滚轮向上滚动推进一档，且列表不滚动', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(ListView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(controller.offset, 0.0);
    expect(settings.folderZoomScale, kFolderZoomTierLargeList);
  });

  testWidgets('Ctrl + 滚轮向下滚动后退一档', (tester) async {
    settings.folderZoomScale = kFolderZoomTierLargeList;
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(ListView)));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(controller.offset, 0.0);
    expect(settings.folderZoomScale, kFolderZoomTierStandardList);
  });

  testWidgets('不按 Ctrl 时滚轮照常滚动列表，档位不变', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(ListView)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0.0));
    expect(settings.folderZoomScale, kFolderZoomTierStandardList);
  });

  testWidgets('同一格滚轮被拆成多笔事件时只换一档', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(ListView)));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    // macOS 的平滑滚动会把一个物理格拆成好几笔 8~16ms 的事件。
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(
        pointer.scroll(
          const Offset(0, -12),
          timeStamp: Duration(milliseconds: 16 * i),
        ),
      );
    }
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(controller.offset, 0.0);
    // 五笔事件属于同一次滚动：只进一档，不会「一下子两档」。
    expect(settings.folderZoomScale, kFolderZoomTierLargeList);
  });

  testWidgets('静默后的下一次滚动重新换一档', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(ListView)));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      pointer.scroll(const Offset(0, -30), timeStamp: Duration.zero),
    );
    await tester.sendEventToBinding(
      pointer.scroll(
        const Offset(0, -30),
        timeStamp: const Duration(milliseconds: 200),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    // 两笔事件间隔 200ms，是两次独立滚动：各换一档。
    expect(settings.folderZoomScale, kFolderZoomTierSmallGrid);
  });

  testWidgets('反方向滚动不必等静默，立刻退档', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(ListView)));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      pointer.scroll(const Offset(0, -30), timeStamp: Duration.zero),
    );
    await tester.sendEventToBinding(
      pointer.scroll(
        const Offset(0, 30),
        timeStamp: const Duration(milliseconds: 16),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(settings.folderZoomScale, kFolderZoomTierStandardList);
  });

  testWidgets('触控板双指捏合放大', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(ListView));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 1.5),
    );
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();

    expect(controller.offset, 0.0);
    // 一次捏合只换一档（标准列表 → 大图列表），不会因为张开幅度大就连跳。
    expect(settings.folderZoomScale, kFolderZoomTierLargeList);
  });

  testWidgets('触屏一次双指张开只换一档', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(ListView));
    final left = await tester.startGesture(center - const Offset(40, 0));
    final right = await tester.startGesture(center + const Offset(40, 0));
    await tester.pump();

    // 跨度 80 -> 200，比例 2.5；即使张得很大也只走一档。
    for (var i = 0; i < 4; i++) {
      await left.moveBy(const Offset(-15, 0));
      await right.moveBy(const Offset(15, 0));
      await tester.pump();
    }
    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    expect(controller.offset, 0.0);
    expect(settings.folderZoomScale, kFolderZoomTierLargeList);
  });

  testWidgets('第二次捏合才会再换一档', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(ListView));

    Future<void> pinch({required bool spread}) async {
      final left = await tester.startGesture(center - const Offset(40, 0));
      final right = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await left.moveBy(Offset(spread ? -15 : 15, 0));
        await right.moveBy(Offset(spread ? 15 : -15, 0));
        await tester.pump();
      }
      await left.up();
      await right.up();
      await tester.pumpAndSettle();
    }

    await pinch(spread: true);
    expect(settings.folderZoomScale, kFolderZoomTierLargeList);

    await pinch(spread: true);
    expect(settings.folderZoomScale, kFolderZoomTierSmallGrid);

    await pinch(spread: false);
    expect(settings.folderZoomScale, kFolderZoomTierLargeList);
  });

  testWidgets('第一根手指先滑动、第二根后落下，仍能捏合换档', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(ListView));
    final left = await tester.startGesture(center - const Offset(40, 0));
    // 单指先滑动一段，拖拽识别器很可能已经赢下第一根手指。
    await left.moveBy(const Offset(0, 40));
    await tester.pump();

    final right = await tester.startGesture(center + const Offset(40, 0));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await left.moveBy(const Offset(-15, 0));
      await right.moveBy(const Offset(15, 0));
      await tester.pump();
    }
    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    expect(settings.folderZoomScale, kFolderZoomTierLargeList);
  });
}
