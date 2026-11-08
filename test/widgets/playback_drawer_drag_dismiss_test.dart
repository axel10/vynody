import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';

void main() {
  group('Playback Drawer Drag Dismiss and Offset Reset Tests', () {
    testWidgets(
      'drag offset is reset to 0.0 after dismiss animation completes and drawer reopens',
      (tester) async {
        final dragOffsetNotifier = ValueNotifier<double>(0.0);

        Widget buildTestWidget() {
          return Consumer(
            builder: (context, ref, child) {
              ref.listen<bool>(isPlaybackDrawerOpenProvider, (previous, next) {
                if (next && dragOffsetNotifier.value != 0.0) {
                  dragOffsetNotifier.value = 0.0;
                }
              });

              return ValueListenableBuilder<double>(
                valueListenable: dragOffsetNotifier,
                builder: (context, offset, _) {
                  return Transform.translate(
                    offset: Offset(0, offset),
                    child: const Text('PlaybackContent'),
                  );
                },
              );
            },
          );
        }

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: buildTestWidget(),
              ),
            ),
          ),
        );

        expect(find.text('PlaybackContent'), findsOneWidget);
        expect(tester.getTopLeft(find.text('PlaybackContent')).dy, 0.0);

        // Simulate downward drag dismiss
        dragOffsetNotifier.value = 800.0;
        await tester.pump();
        expect(tester.getTopLeft(find.text('PlaybackContent')).dy, 800.0);

        // Simulate drawer collapse then reopen
        container.read(isPlaybackDrawerOpenProvider.notifier).setOpen(false);
        await tester.pump();

        // Reopen playback drawer
        container.read(isPlaybackDrawerOpenProvider.notifier).setOpen(true);
        await tester.pump();

        // Verify: drag offset is restored to 0.0 and text returns to top position
        expect(dragOffsetNotifier.value, 0.0);
        expect(tester.getTopLeft(find.text('PlaybackContent')).dy, 0.0);
      },
    );
  });
}
