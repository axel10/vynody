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

  testWidgets('收起态下在新页面从顶部下滑：顶部缓冲区不再把 Dock 展开', (tester) async {
    await pumpHost(tester);
    container.read(floatingDockCollapsedProvider.notifier).setCollapsed(true);
    helper.reset(ref);

    // 新页面停在顶部，手指继续往下滑：pixels 依次 10 → 30 → 80
    scrollTo(tester, pixels: 10, dy: 10);
    expect(
      container.read(floatingDockCollapsedProvider),
      isTrue,
      reason: '上一版对 pixels <= 20 的每一帧都无条件展开，这里会先展开再收起',
    );

    scrollTo(tester, pixels: 30, dy: 20);
    scrollTo(tester, pixels: 80, dy: 50);
    expect(container.read(floatingDockCollapsedProvider), isTrue);
  });

  testWidgets('收起态下从下方滚回顶部：仍然按边沿触发展开', (tester) async {
    await pumpHost(tester);
    container.read(floatingDockCollapsedProvider.notifier).setCollapsed(true);
    helper.reset(ref);

    scrollTo(tester, pixels: 120, dy: 40);
    expect(container.read(floatingDockCollapsedProvider), isTrue);

    scrollTo(tester, pixels: 10, dy: -110);
    expect(
      container.read(floatingDockCollapsedProvider),
      isFalse,
      reason: '越过 20px 边界回到顶部时应完整展开',
    );
  });

  testWidgets('切页重置后累计距离归零，不会与上一页的滚动叠加', (tester) async {
    await pumpHost(tester);
    helper.reset(ref);

    // 第一页向下滚 60px，未达 72px 阈值，Dock 仍是展开态
    scrollTo(tester, pixels: 60, dy: 60);
    expect(container.read(floatingDockCollapsedProvider), isFalse);

    // 切页：清掉上一页的累计与半收起进度
    helper.reset(ref);

    // 新页面在列表中段只下滑 15px。旧版会把 60 + 15 累加成 75 直接收起
    scrollTo(tester, pixels: 115, dy: 15);
    expect(
      container.read(floatingDockCollapsedProvider),
      isFalse,
      reason: '阈值累计不应跨页面继承',
    );

    // 清掉防抖 Timer，避免测试结束时仍有 pending timer
    helper.reset(ref);
  });

  testWidgets('切换列表（进子目录/返回）后跨列表的 pixels 跳变不触发边沿展开', (tester) async {
    await pumpHost(tester);
    container.read(floatingDockCollapsedProvider.notifier).setCollapsed(true);
    helper.reset(ref);

    // 列表 A（目录页，max=1863）滚到 107，Dock 保持收起
    scrollTo(tester, pixels: 107, dy: 7, maxScrollExtent: 1863);
    expect(container.read(floatingDockCollapsedProvider), isTrue);

    // 进入子目录：新 Scrollable（max=603）第一条通知 px=0。
    // run.log 实测：旧实现拿列表 A 的 107 当 prev，107>20 && 0<=20 误判为
    // 「从下方滚回顶部」→ 展开，随后下滑满阈值又收起，即「先展开再收起」。
    final otherScrollableContext = tester.element(
      find.byType(MaterialApp),
    );
    scrollTo(
      tester,
      pixels: 0,
      dy: 0,
      maxScrollExtent: 603,
      scrollableContext: otherScrollableContext,
    );
    expect(
      container.read(floatingDockCollapsedProvider),
      isTrue,
      reason: '换列表后的第一条通知不应被当作滚回顶部',
    );

    // 同一新列表内从下方滚回顶部：边沿展开仍然生效
    scrollTo(
      tester,
      pixels: 120,
      dy: 10,
      maxScrollExtent: 603,
      scrollableContext: otherScrollableContext,
    );
    scrollTo(
      tester,
      pixels: 10,
      dy: -110,
      maxScrollExtent: 603,
      scrollableContext: otherScrollableContext,
    );
    expect(
      container.read(floatingDockCollapsedProvider),
      isFalse,
      reason: '同一列表内滚回顶部仍应展开',
    );

    helper.reset(ref);
  });
}
