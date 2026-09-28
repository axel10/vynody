import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/platform/right_queue_drawer_controller.dart';
import 'package:vynody/player/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
