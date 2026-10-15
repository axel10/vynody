import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/utils/stream_utils.dart';

void main() {
  group('StreamRateLimitExtension.throttleLeadingAndTrailing', () {
    test('emits first event immediately, throttles subsequent events, and emits trailing event', () async {
      final controller = StreamController<int>();
      final emitted = <int>[];

      final sub = controller.stream
          .throttleLeadingAndTrailing(const Duration(milliseconds: 100))
          .listen(emitted.add);

      // 1. First event should emit immediately
      controller.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(emitted, [1]);

      // 2. Events arriving rapidly within 100ms
      controller.add(2);
      controller.add(3);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(emitted, [1]); // Still only 1

      controller.add(4);
      // Wait for the trailing timer (100ms) to fire
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(emitted, [1, 4]);

      // 3. After idle (>100ms since last emit), new event should emit immediately again
      await Future<void>.delayed(const Duration(milliseconds: 120));
      controller.add(5);
      await Future<void>.delayed(Duration.zero);
      expect(emitted, [1, 4, 5]);

      await sub.cancel();
      await controller.close();
    });

    test('emits pending event when source stream closes', () async {
      final controller = StreamController<int>();
      final emitted = <int>[];

      final sub = controller.stream
          .throttleLeadingAndTrailing(const Duration(milliseconds: 100))
          .listen(emitted.add);

      controller.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(emitted, [1]);

      controller.add(2);
      await controller.close();
      await Future<void>.delayed(Duration.zero);

      // Pending event 2 should be delivered on stream close
      expect(emitted, [1, 2]);

      await sub.cancel();
    });
  });
}
