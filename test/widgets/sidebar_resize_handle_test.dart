import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/platform/right_queue_drawer_controller.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'package:vynody/widgets/sidebar_resize_handle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SidebarResizeHandle and Width Providers Tests', () {
    late SettingsService settingsService;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsService = SettingsService(prefs);
      container = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settingsService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    testWidgets('SidebarResizeHandle displays and triggers double-tap', (
      tester,
    ) async {
      bool doubleTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SidebarResizeHandle(
                isLeft: true,
                onDoubleTap: () => doubleTapped = true,
              ),
            ),
          ),
        ),
      );

      final handleFinder = find.byType(SidebarResizeHandle);
      expect(handleFinder, findsOneWidget);

      await tester.tap(handleFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(handleFinder);
      await tester.pumpAndSettle();

      expect(doubleTapped, isTrue);
    });

    test('RightQueueDrawerWidthNotifier setWidth clamps within min and max', () {
      final notifier = container.read(rightQueueDrawerWidthProvider.notifier);

      expect(container.read(rightQueueDrawerWidthProvider), equals(kDefaultRightQueueDrawerWidth));

      // 尝试设置过小的值
      notifier.setWidth(100.0);
      expect(container.read(rightQueueDrawerWidthProvider), equals(kMinRightQueueDrawerWidth));
      expect(settingsService.rightQueueDrawerWidth, equals(kMinRightQueueDrawerWidth));

      // 尝试设置过大的值
      notifier.setWidth(1200.0);
      expect(container.read(rightQueueDrawerWidthProvider), equals(kMaxRightQueueDrawerWidth));
      expect(settingsService.rightQueueDrawerWidth, equals(kMaxRightQueueDrawerWidth));

      // 重置回默认值
      notifier.reset();
      expect(container.read(rightQueueDrawerWidthProvider), equals(kDefaultRightQueueDrawerWidth));
      expect(settingsService.rightQueueDrawerWidth, equals(kDefaultRightQueueDrawerWidth));
    });

    test('sidebarRailWidthProvider responds to windowWidth and custom width', () {
      // 窗口小于 900 时强制折叠到 80
      expect(
        container.read(sidebarRailWidthProvider(800.0)),
        equals(kSidebarRailWidthCollapsed),
      );

      // 窗口 >= 900 时默认展开态 216
      expect(
        container.read(sidebarRailWidthProvider(1200.0)),
        equals(kDefaultSidebarRailWidthExtended),
      );

      // 设置自定义展开宽度
      settingsService.sidebarRailCustomWidth = 260.0;
      expect(
        container.read(sidebarRailWidthProvider(1200.0)),
        equals(260.0),
      );

      // 尝试设置小于最小宽度（216.0 原数值）的值，应被 clamp 在 216.0
      settingsService.sidebarRailCustomWidth = 150.0;
      expect(
        container.read(sidebarRailWidthProvider(1200.0)),
        equals(kMinSidebarRailWidthExtended),
      );

      // 尝试设置大于最大宽度（360.0）的值，应被 clamp 在 360.0
      settingsService.sidebarRailCustomWidth = 500.0;
      expect(
        container.read(sidebarRailWidthProvider(1200.0)),
        equals(kMaxSidebarRailWidthExtended),
      );
    });
  });
}
