import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/platform/right_queue_drawer_controller.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/layout_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('drawer width → window width rule', () {
    test('window width always keeps room for the minimum content width', () {
      expect(minWindowWidthForDrawer(kDefaultRightQueueDrawerWidth), 740.0);
      expect(minWindowWidthForDrawer(kMinRightQueueDrawerWidth), 680.0);
      expect(minWindowWidthForDrawer(kMaxRightQueueDrawerWidth), 1000.0);
      // 抽屉打开时的窗口最小宽度必须与公式一致，不能是另一个独立常量。
      expect(
        kDrawerOpenMinWindowSize.width,
        minWindowWidthForDrawer(kDefaultRightQueueDrawerWidth),
      );
      expect(kMinMainContentWidth, kDefaultRegularMinWindowSize.width);
    });
  });

  group('RightQueueDrawerNotifier Tests', () {
    test('initial state is false (closed) when no settings provided', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final isOpen = container.read(rightQueueDrawerProvider);
      expect(isOpen, isFalse);
    });

    test('open and close update drawer state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(rightQueueDrawerProvider.notifier);

      await notifier.open();
      expect(container.read(rightQueueDrawerProvider), isTrue);

      await notifier.close();
      expect(container.read(rightQueueDrawerProvider), isFalse);
    });

    test('toggle flips drawer state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(rightQueueDrawerProvider.notifier);

      await notifier.toggle();
      expect(container.read(rightQueueDrawerProvider), isTrue);

      await notifier.toggle();
      expect(container.read(rightQueueDrawerProvider), isFalse);
    });

    test('restores and persists state with SettingsService', () async {
      SharedPreferences.setMockInitialValues({
        'right_queue_drawer_open': true,
      });
      final settingsService = await SettingsService.init();

      final container = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settingsService),
        ],
      );
      addTearDown(container.dispose);

      // Initial state restored from settings
      expect(container.read(rightQueueDrawerProvider), isTrue);

      final notifier = container.read(rightQueueDrawerProvider.notifier);
      await notifier.close();

      expect(container.read(rightQueueDrawerProvider), isFalse);
      expect(settingsService.isRightQueueDrawerOpen, isFalse);

      await notifier.open();
      expect(container.read(rightQueueDrawerProvider), isTrue);
      expect(settingsService.isRightQueueDrawerOpen, isTrue);
    });
  });
}
