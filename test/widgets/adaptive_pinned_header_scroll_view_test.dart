import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/adaptive_pinned_header_scroll_view.dart';

void main() {
  testWidgets('AdaptivePinnedHeaderScrollView pins header in landscape', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final controller = ScrollController();
    addTearDown(() => controller.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(1200, 800),
            ),
            child: AdaptivePinnedHeaderScrollView(
              controller: controller,
              header: Container(
                key: const ValueKey('test_header'),
                height: 60,
                color: Colors.blue,
                child: const Text('Header Title'),
              ),
              slivers: [
                SliverList.builder(
                  itemCount: 50,
                  itemBuilder: (context, index) => SizedBox(
                    height: 50,
                    child: Text('Item $index'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Column and Expanded structure in landscape
    expect(find.byType(Column), findsOneWidget);
    expect(find.byType(Expanded), findsOneWidget);

    final initialHeaderPos = tester.getTopLeft(find.byKey(const ValueKey('test_header')));

    // Scroll down 200 pixels
    controller.jumpTo(200);
    await tester.pumpAndSettle();

    final scrolledHeaderPos = tester.getTopLeft(find.byKey(const ValueKey('test_header')));

    // Header position must remain pinned and unchanged
    expect(scrolledHeaderPos.dy, equals(initialHeaderPos.dy));
    expect(controller.offset, equals(200.0));
  });

  testWidgets('AdaptivePinnedHeaderScrollView scrolls header away in portrait', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final controller = ScrollController();
    addTearDown(() => controller.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
            ),
            child: AdaptivePinnedHeaderScrollView(
              controller: controller,
              header: Container(
                key: const ValueKey('test_header'),
                height: 60,
                color: Colors.blue,
                child: const Text('Header Title'),
              ),
              slivers: [
                SliverList.builder(
                  itemCount: 50,
                  itemBuilder: (context, index) => SizedBox(
                    height: 50,
                    child: Text('Item $index'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // In portrait, header should be inside CustomScrollView slivers, no Column/Expanded structure
    expect(find.byType(Column), findsNothing);

    final initialHeaderPos = tester.getTopLeft(find.byKey(const ValueKey('test_header')));

    // Scroll down 30 pixels (header height is 60, so it remains partially visible)
    controller.jumpTo(30);
    await tester.pumpAndSettle();

    // Header should have scrolled up by 30px
    final scrolledHeaderPos = tester.getTopLeft(find.byKey(const ValueKey('test_header')));
    expect(scrolledHeaderPos.dy, equals(initialHeaderPos.dy - 30));

    // Scroll down 100 pixels (header should now be completely scrolled offscreen and unmounted)
    controller.jumpTo(100);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test_header')), findsNothing);
  });
}
