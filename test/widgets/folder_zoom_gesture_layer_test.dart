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

  testWidgets('queue 记忆域限制在列表4档，到达 largeList 不会继续推进到网格', (tester) async {
    settings.queueZoomScale = kFolderZoomTierLargeList;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          home: Scaffold(
            body: FolderZoomGestureLayer(
              scope: LibraryZoomScope.queue,
              child: ListView.builder(
                controller: controller,
                itemCount: 10,
                itemBuilder: (context, index) => Text('item $index'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(ListView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // 依然限制在 largeList，不能进入 smallGrid
    expect(settings.queueZoomScale, kFolderZoomTierLargeList);
  });

  testWidgets('双指捏合只张开一点点（未达阈值）时条目跟手变化，松手后退回原档位', (tester) async {
    FolderZoomLayoutMetrics? capturedMetrics;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          home: Scaffold(
            body: FolderZoomGestureLayer(
              child: CustomScrollView(
                slivers: [
                  Consumer(
                    builder: (context, ref, child) {
                      final scale = ref.watch(
                        settingsServiceProvider.select(
                          (s) => s.folderZoomScale,
                        ),
                      );
                      return FolderZoomSliverBuilder(
                        zoomScale: scale,
                        width: 400,
                        builder: (context, metrics) {
                          capturedMetrics = metrics;
                          return SliverToBoxAdapter(
                            child: SizedBox(
                              height: metrics.animatedListExtent,
                              child: const Text('content'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 初始状态：StandardList 行高为 80
    expect(capturedMetrics!.animatedListExtent, closeTo(80.0, 0.01));
    expect(settings.folderZoomScale, kFolderZoomTierStandardList);

    final center = tester.getCenter(find.text('content'));
    // 触控板微捏合：scale = 1.05（仅放大 5%，小于 11% 的 50% 阈值）
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 1.05),
    );
    await tester.pump();

    // 跟手变化：行高在 80 到 104 之间插值增大（大约 85 左右）
    expect(capturedMetrics!.animatedListExtent, greaterThan(80.0));
    expect(capturedMetrics!.animatedListExtent, lessThan(95.0));

    // 松手结算：因为未超过阈值，回弹退回
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();

    // 档位未变，行高完全恢复为 80.0
    expect(settings.folderZoomScale, kFolderZoomTierStandardList);
    expect(capturedMetrics!.animatedListExtent, closeTo(80.0, 0.01));
  });

  testWidgets('双指捏合微缩小（未达阈值）松手退回，超过阈值缩小确认减一档', (tester) async {
    // 初始档位为 LargeList（行高 104）
    settings.folderZoomScale = kFolderZoomTierLargeList;
    FolderZoomLayoutMetrics? capturedMetrics;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          home: Scaffold(
            body: FolderZoomGestureLayer(
              child: CustomScrollView(
                slivers: [
                  Consumer(
                    builder: (context, ref, child) {
                      final scale = ref.watch(
                        settingsServiceProvider.select(
                          (s) => s.folderZoomScale,
                        ),
                      );
                      return FolderZoomSliverBuilder(
                        zoomScale: scale,
                        width: 400,
                        builder: (context, metrics) {
                          capturedMetrics = metrics;
                          return SliverToBoxAdapter(
                            child: SizedBox(
                              height: metrics.animatedListExtent,
                              child: const Text('content'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(capturedMetrics!.animatedListExtent, closeTo(104.0, 0.01));

    final center = tester.getCenter(find.text('content'));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    pointer.hover(center);

    // 1. 微缩小：scale = 0.96（缩小 4%，未达到 10% 阈值）
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 0.96),
    );
    await tester.pump();

    // 条目实时变小了一点点（在 80 到 104 之间）
    expect(capturedMetrics!.animatedListExtent, lessThan(104.0));
    expect(capturedMetrics!.animatedListExtent, greaterThan(95.0));

    // 松手：未达阈值退回 LargeList
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();
    expect(settings.folderZoomScale, kFolderZoomTierLargeList);
    expect(capturedMetrics!.animatedListExtent, closeTo(104.0, 0.01));

    // 2. 较大幅度缩小：scale = 0.50（缩小 50%，捏合过半，超过 40% 阈值）
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 0.50),
    );
    await tester.pump();

    // 条目实时显著变小
    expect(capturedMetrics!.animatedListExtent, lessThan(95.0));

    // 松手：超过阈值减一个档位，平滑吸附到 StandardList
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();
    expect(settings.folderZoomScale, kFolderZoomTierStandardList);
    expect(capturedMetrics!.animatedListExtent, closeTo(80.0, 0.01));
  });

  testWidgets('同一作用域内包含多个 FolderZoomSliverBuilder 时，手势换档均静默对齐无二次动画', (tester) async {
    int builder1Count = 0;
    int builder2Count = 0;
    FolderZoomLayoutMetrics? metrics1;
    FolderZoomLayoutMetrics? metrics2;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          home: Scaffold(
            body: FolderZoomGestureLayer(
              child: CustomScrollView(
                slivers: [
                  Consumer(
                    builder: (context, ref, child) {
                      final scale = ref.watch(
                        settingsServiceProvider.select((s) => s.folderZoomScale),
                      );
                      return FolderZoomSliverBuilder(
                        zoomScale: scale,
                        width: 400,
                        builder: (context, m) {
                          builder1Count++;
                          metrics1 = m;
                          return SliverToBoxAdapter(
                            child: SizedBox(
                              height: m.animatedListExtent,
                              child: const Text('list 1'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  Consumer(
                    builder: (context, ref, child) {
                      final scale = ref.watch(
                        settingsServiceProvider.select((s) => s.folderZoomScale),
                      );
                      return FolderZoomSliverBuilder(
                        zoomScale: scale,
                        width: 400,
                        builder: (context, m) {
                          builder2Count++;
                          metrics2 = m;
                          return SliverToBoxAdapter(
                            child: SizedBox(
                              height: m.animatedListExtent,
                              child: const Text('list 2'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.text('list 1'));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    pointer.hover(center);

    // 捏合放大超过平缓阈值（scale = 1.40）
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 1.40),
    );
    await tester.pump();

    // 松手结算
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();

    // 两个列表都必须精准同步到达 LargeList (104.0)
    expect(settings.folderZoomScale, kFolderZoomTierLargeList);
    expect(metrics1!.animatedListExtent, closeTo(104.0, 0.01));
    expect(metrics2!.animatedListExtent, closeTo(104.0, 0.01));

    // 记录换档安定后的 build 次数
    final b1Stable = builder1Count;
    final b2Stable = builder2Count;

    // 前进 50ms，验证没有多余的动画在后台继续 tick 重绘
    await tester.pump(const Duration(milliseconds: 50));
    expect(builder1Count, b1Stable);
    expect(builder2Count, b2Stable);
  });

  testWidgets('双指超过换档阈值后若有微小回缩，滞后区间确保稳稳换档不跳回', (tester) async {
    FolderZoomLayoutMetrics? capturedMetrics;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          home: Scaffold(
            body: FolderZoomGestureLayer(
              child: CustomScrollView(
                slivers: [
                  Consumer(
                    builder: (context, ref, child) {
                      final scale = ref.watch(
                        settingsServiceProvider.select((s) => s.folderZoomScale),
                      );
                      return FolderZoomSliverBuilder(
                        zoomScale: scale,
                        width: 400,
                        builder: (context, m) {
                          capturedMetrics = m;
                          return SliverToBoxAdapter(
                            child: SizedBox(
                              height: m.animatedListExtent,
                              child: const Text('content'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.text('content'));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    pointer.hover(center);

    await tester.sendEventToBinding(pointer.panZoomStart(center));
    // 先张开 50%（scale = 1.50，进度 50%，已超过 40% 的触发阈值，换档意图已确认）
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 1.50),
    );
    await tester.pump();

    // 手指松手瞬间发生肌肉微收缩，scale 微落到 1.25（进度落到 25%，在 20%~40% 滞后区间内）
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 1.25),
    );
    await tester.pump();

    // 松手：滞后保护生效，稳稳吸附并确认换档，绝不误弹回！
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();

    expect(settings.folderZoomScale, kFolderZoomTierLargeList);
    expect(capturedMetrics!.animatedListExtent, closeTo(104.0, 0.01));
  });

  testWidgets('对齐 Poweramp 物理模型：双指移动到两倍时放大一档，完全捏合时缩小一档', (tester) async {
    FolderZoomLayoutMetrics? capturedMetrics;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          home: Scaffold(
            body: FolderZoomGestureLayer(
              child: CustomScrollView(
                slivers: [
                  Consumer(
                    builder: (context, ref, child) {
                      final scale = ref.watch(
                        settingsServiceProvider.select((s) => s.folderZoomScale),
                      );
                      return FolderZoomSliverBuilder(
                        zoomScale: scale,
                        width: 400,
                        builder: (context, m) {
                          capturedMetrics = m;
                          return SliverToBoxAdapter(
                            child: SizedBox(
                              height: m.animatedListExtent,
                              child: const Text('touch content'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(capturedMetrics!.animatedListExtent, closeTo(80.0, 0.01));

    final center = tester.getCenter(find.text('touch content'));
    // 初始双指间距 100 像素
    final left = await tester.startGesture(center - const Offset(50, 0));
    final right = await tester.startGesture(center + const Offset(50, 0));
    await tester.pump();

    // 双指各微动 10 像素（双指间距从 100 增加到 120 像素，scale = 1.20）：
    await left.moveBy(const Offset(-10, 0));
    await right.moveBy(const Offset(10, 0));
    await tester.pump();

    // 进度 t = scale - 1.0 = 0.20，行高从 80 生长到 80 + 0.20 * 24 = 84.8 像素
    expect(capturedMetrics!.animatedListExtent, closeTo(84.8, 0.5));

    // 松手：未达 40% 阈值，退回 80.0
    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    expect(settings.folderZoomScale, kFolderZoomTierStandardList);
    expect(capturedMetrics!.animatedListExtent, closeTo(80.0, 0.01));
  });

  testWidgets('文字大小在手势缩放途中随动画进程平滑线性插值', (tester) async {
    FolderZoomLayoutMetrics? capturedMetrics;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          home: Scaffold(
            body: FolderZoomGestureLayer(
              child: CustomScrollView(
                slivers: [
                  Consumer(
                    builder: (context, ref, child) {
                      final scale = ref.watch(
                        settingsServiceProvider.select((s) => s.folderZoomScale),
                      );
                      return FolderZoomSliverBuilder(
                        zoomScale: scale,
                        width: 400,
                        builder: (context, m) {
                          capturedMetrics = m;
                          return SliverToBoxAdapter(
                            child: SizedBox(
                              height: 100,
                              child: Text(
                                'Title',
                                style: TextStyle(
                                  fontSize: m.animatedTitleFontSize,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 初始档位为 standardList，测试默认 800x600 横屏下为 15.5
    expect(capturedMetrics!.animatedTitleFontSize, closeTo(15.5, 0.01));

    final center = tester.getCenter(find.text('Title'));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    pointer.hover(center);

    // 触控板捏合放大：从 standardList (15.5) 向 largeList (16.5) 放大
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    // scale = 1.50 -> progress = 0.50 (正好处于正中间)
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 1.50),
    );
    await tester.pump();

    // 验证字号平滑线性过渡到 15.5 + (16.5 - 15.5) * 0.5 = 16.0
    expect(capturedMetrics!.animatedTitleFontSize, closeTo(16.0, 0.01));

    // 松手结算完成换档
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();

    // 换档完成到达 largeList：16.5
    expect(settings.folderZoomScale, kFolderZoomTierLargeList);
    expect(capturedMetrics!.animatedTitleFontSize, closeTo(16.5, 0.01));
  });

  testWidgets('触控板双指滚动（scale 恒为 1）不进入捏合态，画面零重建', (tester) async {
    int buildCount = 0;
    FolderZoomLayoutMetrics? capturedMetrics;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          home: Scaffold(
            body: FolderZoomGestureLayer(
              child: CustomScrollView(
                slivers: [
                  Consumer(
                    builder: (context, ref, child) {
                      final scale = ref.watch(
                        settingsServiceProvider.select((s) => s.folderZoomScale),
                      );
                      return FolderZoomSliverBuilder(
                        zoomScale: scale,
                        width: 400,
                        builder: (context, m) {
                          buildCount++;
                          capturedMetrics = m;
                          return SliverToBoxAdapter(
                            child: SizedBox(
                              height: 100,
                              child: Text('scroll content', style: TextStyle(fontSize: m.animatedTitleFontSize)),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final baseline = buildCount;

    final center = tester.getCenter(find.text('scroll content'));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    pointer.hover(center);

    // 触控板的双指滚动走的是同一套 panZoom 事件，只有 scale 区分捏合与滚动。
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    for (var i = 0; i < 10; i++) {
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(center, pan: const Offset(0, 24)),
      );
      await tester.pump();
    }
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();

    // 滚动不该把整屏可见条目拖进捏合分支重建，也不该多挂 200ms 的吸附动画。
    expect(
      buildCount,
      baseline,
      reason: '纯滚动的 panZoom 事件不应触发 FolderZoomSliverBuilder 重建',
    );
    expect(settings.folderZoomScale, kFolderZoomTierStandardList);
    expect(capturedMetrics!.animatedListExtent, closeTo(80.0, 0.01));
  });

  testWidgets('跨「列表↔网格」时内容侧按滞回翻转，不会在中点来回跳', (tester) async {
    // 从 largeList 捏合放大，目标是 smallGrid：这是唯一会发生
    // 「列表内容 ↔ 网格内容」交接的跨类换档。
    settings.folderZoomScale = kFolderZoomTierLargeList;
    FolderZoomLayoutMetrics? capturedMetrics;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          home: Scaffold(
            body: FolderZoomGestureLayer(
              child: CustomScrollView(
                slivers: [
                  Consumer(
                    builder: (context, ref, child) {
                      final scale = ref.watch(
                        settingsServiceProvider.select((s) => s.folderZoomScale),
                      );
                      return FolderZoomSliverBuilder(
                        zoomScale: scale,
                        width: 400,
                        builder: (context, m) {
                          capturedMetrics = m;
                          return SliverToBoxAdapter(
                            child: SizedBox(
                              height: 100,
                              child: Text(
                                'handoff',
                                style: TextStyle(
                                  fontSize: m.animatedTitleFontSize,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 起始就是列表档，内容侧必须是列表。
    expect(capturedMetrics!.renderAsGrid, isFalse);
    expect(capturedMetrics!.contentReveal, 1.0);

    final center = tester.getCenter(find.text('handoff'));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.panZoomStart(center));

    // 越过中点但没到滞回上界：仍是列表侧（这一帧以前会翻转）。
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 1.52),
    );
    await tester.pump();
    expect(capturedMetrics!.gridMorph, closeTo(0.52, 0.01));
    expect(
      capturedMetrics!.renderAsGrid,
      isFalse,
      reason: '滞回区内应保持上一侧，不能一过 0.5 就翻转',
    );
    // 交接点附近内容压暗，盖住两套布局的结构突变。
    expect(capturedMetrics!.contentReveal, lessThan(1.0));

    // 越过上界才切网格。
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 1.62),
    );
    await tester.pump();
    expect(capturedMetrics!.renderAsGrid, isTrue);

    // 回缩到滞回区内部（0.48）：继续留在网格侧，不来回跳。
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 1.48),
    );
    await tester.pump();
    expect(
      capturedMetrics!.renderAsGrid,
      isTrue,
      reason: '滞回区内不应回退到列表侧',
    );

    // 低于下界才回列表侧。
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, scale: 1.40),
    );
    await tester.pump();
    expect(capturedMetrics!.renderAsGrid, isFalse);

    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();
  });
}
