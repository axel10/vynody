import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/folder_floating_action_button.dart';

void main() {
  testWidgets('FolderFloatingActionButton handles visible state and interactions',
      (tester) async {
    bool tapped = false;
    final visibleNotifier = ValueNotifier<bool>(false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visibleNotifier,
            builder: (context, visible, _) {
              return FolderFloatingActionButton(
                visible: visible,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    tapped = true;
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    // Initial state: visible == false
    final ignorePointerFinder = find.descendant(
      of: find.byType(FolderFloatingActionButton),
      matching: find.byType(IgnorePointer),
    );
    expect(ignorePointerFinder, findsOneWidget);
    final ignorePointer = tester.widget<IgnorePointer>(ignorePointerFinder);
    expect(ignorePointer.ignoring, isTrue);

    // Try tapping when hidden
    await tester.tap(find.byType(IconButton), warnIfMissed: false);
    await tester.pump();
    expect(tapped, isFalse);

    // Change to visible == true
    visibleNotifier.value = true;
    await tester.pumpAndSettle();

    final activeIgnorePointer = tester.widget<IgnorePointer>(ignorePointerFinder);
    expect(activeIgnorePointer.ignoring, isFalse);

    // Tap should now trigger callback
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(tapped, isTrue);

    // Switch back to hidden
    visibleNotifier.value = false;
    await tester.pumpAndSettle();

    final hiddenIgnorePointer = tester.widget<IgnorePointer>(ignorePointerFinder);
    expect(hiddenIgnorePointer.ignoring, isTrue);
  });

  testWidgets(
      'ValueNotifier FAB visibility toggle isolates rebuild from surrounding page',
      (tester) async {
    int outerBuildCount = 0;
    final showFabNotifier = ValueNotifier<bool>(false);
    final scrollController = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              outerBuildCount++;
              return Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      final shouldShow = notification.metrics.pixels > 70.0;
                      if (shouldShow != showFabNotifier.value) {
                        showFabNotifier.value = shouldShow;
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: 50,
                      itemBuilder: (_, index) => SizedBox(
                        height: 50,
                        child: Text('Item $index'),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: showFabNotifier,
                      builder: (context, visible, child) {
                        return FolderFloatingActionButton(
                          visible: visible,
                          child: child!,
                        );
                      },
                      child: const Icon(Icons.more_vert),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(outerBuildCount, equals(1));
    expect(showFabNotifier.value, isFalse);

    // Scroll past 70px threshold
    scrollController.jumpTo(100);
    await tester.pumpAndSettle();

    expect(showFabNotifier.value, isTrue);
    // Outer widget must NOT rebuild on threshold crossing
    expect(outerBuildCount, equals(1));

    // Scroll back above 70px threshold (towards top)
    scrollController.jumpTo(20);
    await tester.pumpAndSettle();

    expect(showFabNotifier.value, isFalse);
    // Outer widget still must NOT rebuild
    expect(outerBuildCount, equals(1));

    showFabNotifier.dispose();
    scrollController.dispose();
  });
}
