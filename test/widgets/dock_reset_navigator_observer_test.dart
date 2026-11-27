import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/dock_reset_navigator_observer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
    settings.enableFloatingDockScrollCollapse = true;
  });

  testWidgets(
    'DockResetNavigatorObserver resets dock offset with animation on push and pop',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsServiceProvider.overrideWith((r) => settings)],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [DockResetNavigatorObserver()],
            home: const Scaffold(body: Text('home')),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.text('home')),
      );

      // 初始路由构建不应触发动画版本递增
      expect(container.read(floatingDockAnimateResetVersionProvider), 0);
      expect(container.read(floatingDockScrollOffsetProvider), 0.0);

      // 模拟向下滚动导致 Dock 移出屏幕
      container.read(floatingDockScrollOffsetProvider.notifier).setOffset(120.0);
      container
          .read(floatingDockCollapsedProvider.notifier)
          .setCollapsed(true, reason: 'test');
      expect(container.read(floatingDockScrollOffsetProvider), 120.0);
      expect(container.read(floatingDockCollapsedProvider), isTrue);

      // 跳转到新页面（didPush）应触发平滑复位
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('detail')),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(container.read(floatingDockScrollOffsetProvider), 0.0);
      expect(container.read(floatingDockCollapsedProvider), isFalse);
      expect(container.read(floatingDockAnimateResetVersionProvider), 1);

      // 在新页面再次模拟滚动移出
      await tester.pumpAndSettle();
      container.read(floatingDockScrollOffsetProvider.notifier).setOffset(80.0);
      expect(container.read(floatingDockScrollOffsetProvider), 80.0);

      // 返回上一页（didPop）也应触发平滑复位
      navigatorKey.currentState!.pop();
      await tester.pump();
      await tester.pump();

      expect(container.read(floatingDockScrollOffsetProvider), 0.0);
      expect(container.read(floatingDockAnimateResetVersionProvider), 2);
    },
  );

  testWidgets(
    'resetFloatingDockWithContainer skips animation trigger when already at top',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsServiceProvider.overrideWith((r) => settings)],
          child: const MaterialApp(home: Scaffold(body: Text('home'))),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.text('home')),
      );

      expect(container.read(floatingDockScrollOffsetProvider), 0.0);
      resetFloatingDockWithContainer(container, animated: true);
      expect(container.read(floatingDockAnimateResetVersionProvider), 0);
    },
  );
}
