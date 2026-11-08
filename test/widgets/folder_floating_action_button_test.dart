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
}
