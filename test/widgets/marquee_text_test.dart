import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/marquee_text.dart';

void main() {
  group('MarqueeText', () {
    Widget buildTestApp({
      required double width,
      required String text,
      double fontSize = 16,
      Duration scrollDelay = const Duration(milliseconds: 200),
      double velocity = 100.0,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: Align(
                alignment: Alignment.centerLeft,
                child: MarqueeText(
                  text: text,
                  style: TextStyle(fontSize: fontSize),
                  scrollDelay: scrollDelay,
                  velocity: velocity,
                ),
              ),
            ),
          ),
        ),
      );
    }

    ScrollableState findMarqueeScrollable(WidgetTester tester) {
      return tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(MarqueeText),
          matching: find.byType(Scrollable),
        ),
      );
    }

    testWidgets('does not scroll when text fits within container', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(width: 400, text: 'Short Title'),
      );

      // Wait past debounce (500ms) + scrollDelay (200ms) + animation time.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 500));

      final scrollable = findMarqueeScrollable(tester);
      expect(scrollable.position.maxScrollExtent, 0.0);
      expect(scrollable.position.pixels, 0.0);
    });

    testWidgets(
      'stops and resets when container widens so text fits completely',
      (tester) async {
        const text = 'Long Track Title Text';

        // 1. Start in a narrow container where text overflows.
        await tester.pumpWidget(buildTestApp(width: 150, text: text));

        // Debounce (500ms) -> measure -> scrollDelay (200ms) -> start scrolling.
        await tester.pump(const Duration(milliseconds: 550));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 300));

        final scrollable = findMarqueeScrollable(tester);
        expect(scrollable.position.maxScrollExtent, greaterThan(50.0));
        expect(scrollable.position.pixels, greaterThan(0.0));

        // 2. Widen container so text fits completely (within 800px test viewport).
        await tester.pumpWidget(buildTestApp(width: 500, text: text));
        await tester.pump();

        expect(scrollable.position.maxScrollExtent, 0.0);
        expect(scrollable.position.pixels, 0.0);

        // Wait past debounce and multiple scroll cycles; offset must stay 0.
        await tester.pump(const Duration(milliseconds: 600));
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
          expect(scrollable.position.pixels, 0.0);
        }
      },
    );

    testWidgets(
      'stops and resets when font size shrinks so text fits completely',
      (tester) async {
        const text = 'Track Title Text';

        // 1. Large font overflows.
        await tester.pumpWidget(
          buildTestApp(width: 240, text: text, fontSize: 28),
        );

        await tester.pump(const Duration(milliseconds: 550));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 300));

        final scrollable = findMarqueeScrollable(tester);
        expect(scrollable.position.maxScrollExtent, greaterThan(10.0));
        expect(scrollable.position.pixels, greaterThan(0.0));

        // 2. Shrink font so text fits completely.
        await tester.pumpWidget(
          buildTestApp(width: 240, text: text, fontSize: 10),
        );
        await tester.pump();

        expect(scrollable.position.maxScrollExtent, 0.0);
        expect(scrollable.position.pixels, 0.0);

        await tester.pump(const Duration(milliseconds: 600));
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
          expect(scrollable.position.pixels, 0.0);
        }
      },
    );
  });
}
