import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/platform/right_queue_drawer_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RightQueueDrawerNotifier Tests', () {
    test('initial state is false (closed)', () {
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
  });
}
