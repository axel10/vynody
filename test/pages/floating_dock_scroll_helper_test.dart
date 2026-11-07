import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;
  late WidgetRef ref;
  late ProviderContainer container;
  late FloatingDockScrollHelper helper;

  setUp(() async {
    FloatingDockScrollHelper.traceEnabled = false;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
    settings.enableFloatingDockScrollCollapse = true;
    helper = FloatingDockScrollHelper();
  });

  tearDown(() {
    helper.dispose();
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((r) => settings)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const SizedBox(key: ValueKey('host'));
            },
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('host'))),
    );
  }

  void scrollTo(
    WidgetTester tester, {
    required double pixels,
    required double dy,
    double maxScrollExtent = 2000,
    BuildContext? scrollableContext,
  }) {
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: maxScrollExtent,
          pixels: pixels,
          viewportDimension: 800,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1.0,
        ),
        context: scrollableContext ??
            tester.element(find.byKey(const ValueKey('host'))),
        scrollDelta: dy,
      ),
      ref,
    );
  }

  testWidgets('向下滚动时位移随滚动增加（滚多少移出多少），直至最大上限', (tester) async {
    await pumpHost(tester);
    helper.reset(ref);

    expect(container.read(floatingDockScrollOffsetProvider), 0.0);

    // 向下滚动 30px (dy = 30)
    scrollTo(tester, pixels: 30, dy: 30);
    expect(container.read(floatingDockScrollOffsetProvider), 30.0);

    // 继续向下滚动 50px (dy = 50)
    scrollTo(tester, pixels: 80, dy: 50);
    expect(container.read(floatingDockScrollOffsetProvider), 80.0);

    // 大幅向下滚动，位移达到最大上限 maxScrollOffset (220.0)
    scrollTo(tester, pixels: 400, dy: 320);
    expect(
      container.read(floatingDockScrollOffsetProvider),
      FloatingDockScrollHelper.maxScrollOffset,
    );
  });

  testWidgets('向上滚动时位移随滚动减少，滚多少移回多少，直至原位', (tester) async {
    await pumpHost(tester);
    helper.reset(ref);

    // 先向下滚动 150px
    scrollTo(tester, pixels: 150, dy: 150);
    expect(container.read(floatingDockScrollOffsetProvider), 150.0);

    // 向上滚动 40px (dy = -40)
    scrollTo(tester, pixels: 110, dy: -40);
    expect(container.read(floatingDockScrollOffsetProvider), 110.0);

    // 继续向上滚动 120px，超过剩余位移，clamp 到 0.0（原位）
    scrollTo(tester, pixels: 50, dy: -120);
    expect(container.read(floatingDockScrollOffsetProvider), 0.0);
  });

  testWidgets('方案 B：停在哪就在哪，滚动停止时不自动吸附', (tester) async {
    await pumpHost(tester);
    helper.reset(ref);

    // 向下滚动 75px
    scrollTo(tester, pixels: 75, dy: 75);
    expect(container.read(floatingDockScrollOffsetProvider), 75.0);

    // 触发 ScrollEndNotification，位移依然保持 75px 不变
    helper.handleScrollNotification(
      ScrollEndNotification(
        metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 2000,
          pixels: 75,
          viewportDimension: 800,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1.0,
        ),
        context: tester.element(find.byKey(const ValueKey('host'))),
      ),
      ref,
    );

    expect(container.read(floatingDockScrollOffsetProvider), 75.0);
  });

  testWidgets('列表回到顶部（pixels <= 0）时无条件复位回原位', (tester) async {
    await pumpHost(tester);
    helper.reset(ref);

    // 滚到中段，位移为 100px
    scrollTo(tester, pixels: 200, dy: 100);
    expect(container.read(floatingDockScrollOffsetProvider), 100.0);

    // 滚回到最顶部（pixels = 0）
    scrollTo(tester, pixels: 0, dy: -200);
    expect(container.read(floatingDockScrollOffsetProvider), 0.0);
  });

  testWidgets('切页或 reset 时位移复位回 0.0', (tester) async {
    await pumpHost(tester);
    helper.reset(ref);

    scrollTo(tester, pixels: 100, dy: 100);
    expect(container.read(floatingDockScrollOffsetProvider), 100.0);

    helper.reset(ref);
    expect(container.read(floatingDockScrollOffsetProvider), 0.0);
  });

  testWidgets('滚动到列表底部填充区域时Dock随滚动展开，滚到最低时正好位于原位', (tester) async {
    await pumpHost(tester);
    helper.reset(ref);

    const maxScroll = 1000.0;
    const maxOffset = FloatingDockScrollHelper.maxScrollOffset; // 220.0

    // 1. 在列表中段向下滚动，Dock 完全移出 (offset = 220)
    scrollTo(tester, pixels: 500, dy: 300, maxScrollExtent: maxScroll);
    expect(container.read(floatingDockScrollOffsetProvider), maxOffset);

    // 2. 滚入底部填充区域 (例如 pixels = 880，离底部还差 120px)
    // Dock 应该向上浮现展开，offset 变为 120px
    scrollTo(tester, pixels: 880, dy: 380, maxScrollExtent: maxScroll);
    expect(container.read(floatingDockScrollOffsetProvider), 120.0);

    // 3. 继续向下滚动到 pixels = 960 (离底部还差 40px)
    // Dock 继续向上展开，offset 变为 40px
    scrollTo(tester, pixels: 960, dy: 80, maxScrollExtent: maxScroll);
    expect(container.read(floatingDockScrollOffsetProvider), 40.0);

    // 4. 滚到最底端 (pixels = 1000)
    // Dock 正好完全处于原位 (offset = 0)
    scrollTo(tester, pixels: 1000, dy: 40, maxScrollExtent: maxScroll);
    expect(container.read(floatingDockScrollOffsetProvider), 0.0);

    // 5. 底部弹性越界 overscroll (pixels = 1050)
    // Dock 依然稳稳停在原位 (offset = 0)
    scrollTo(tester, pixels: 1050, dy: 50, maxScrollExtent: maxScroll);
    expect(container.read(floatingDockScrollOffsetProvider), 0.0);
  });

  testWidgets('关闭设置开关后，滚动不再产生位移，始终保持 0.0', (tester) async {
    await pumpHost(tester);
    settings.enableFloatingDockScrollCollapse = false;
    helper.reset(ref);

    scrollTo(tester, pixels: 100, dy: 100);
    expect(container.read(floatingDockScrollOffsetProvider), 0.0);
  });
}
