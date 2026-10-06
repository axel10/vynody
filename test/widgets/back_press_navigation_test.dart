import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/widgets/library_selection_scope.dart';
import 'package:vynody/widgets/app_bottom_sheet.dart';

void main() {
  group('Back Press Navigation and Modal Dismissal Tests', () {
    testWidgets('Modal route on root navigator is dismissed without popping the base page', (tester) async {
      final rootNavKey = GlobalKey<NavigatorState>();
      bool basePagePopped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: rootNavKey,
            home: StatefulBuilder(
              builder: (context, setState) {
                return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) async {
                    if (didPop) return;
                    // Exact logic added to MainLayout._handleBackPressed:
                    final mainModalRoute = ModalRoute.of(context);
                    final rootNav = Navigator.of(context, rootNavigator: true);
                    if (mainModalRoute != null && !mainModalRoute.isCurrent) {
                      await rootNav.maybePop();
                      return;
                    }
                    basePagePopped = true;
                  },
                  child: Scaffold(
                    body: Builder(
                      builder: (childCtx) {
                        return Center(
                          child: ElevatedButton(
                            onPressed: () {
                              showAppAdaptiveModal<void>(
                                context: childCtx,
                                useRootNavigator: true,
                                builder: (_) => const SizedBox(
                                  height: 200,
                                  child: Text('ModalContent'),
                                ),
                              );
                            },
                            child: const Text('OpenModal'),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open the AdaptiveSheet modal
      await tester.tap(find.text('OpenModal'));
      await tester.pumpAndSettle();
      expect(find.text('ModalContent'), findsOneWidget);

      // Trigger system back button (simulating Android physical/gesture back)
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Verify: The modal was dismissed, and the base page was NOT popped!
      expect(find.text('ModalContent'), findsNothing);
      expect(basePagePopped, isFalse);
    });

    testWidgets('Standard Dialog on root navigator is dismissed without popping the base page', (tester) async {
      final rootNavKey = GlobalKey<NavigatorState>();
      bool basePagePopped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: rootNavKey,
            home: StatefulBuilder(
              builder: (context, setState) {
                return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) async {
                    if (didPop) return;
                    // Exact logic added to MainLayout._handleBackPressed:
                    final mainModalRoute = ModalRoute.of(context);
                    final rootNav = Navigator.of(context, rootNavigator: true);
                    if (mainModalRoute != null && !mainModalRoute.isCurrent) {
                      await rootNav.maybePop();
                      return;
                    }
                    basePagePopped = true;
                  },
                  child: Scaffold(
                    body: Builder(
                      builder: (childCtx) {
                        return Center(
                          child: ElevatedButton(
                            onPressed: () {
                              showDialog<void>(
                                context: childCtx,
                                builder: (_) => const AlertDialog(
                                  title: Text('DialogTitle'),
                                ),
                              );
                            },
                            child: const Text('OpenDialog'),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open dialog
      await tester.tap(find.text('OpenDialog'));
      await tester.pumpAndSettle();
      expect(find.text('DialogTitle'), findsOneWidget);

      // Trigger system back button
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Verify: Dialog dismissed, base page untouched
      expect(find.text('DialogTitle'), findsNothing);
      expect(basePagePopped, isFalse);
    });

    testWidgets('Library selection state clears on back press before closing page', (tester) async {
      late WidgetRef capturedRef;
      bool pageClosed = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        // Aligned with LibraryPage.handleBackPressed:
                        final selectionState = ref.read(librarySelectionStateProvider);
                        if (selectionState.isActive &&
                            selectionState.scope != LibrarySelectionScope.none) {
                          ref.read(librarySelectionStateProvider.notifier).clear();
                          return;
                        }
                        pageClosed = true;
                      },
                      child: const Text('BackButton'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter selection mode
      capturedRef.read(librarySelectionStateProvider.notifier).enter(
        LibrarySelectionScope.playlist,
        initialKey: 'p1',
      );
      await tester.pumpAndSettle();
      expect(capturedRef.read(isLibrarySelectionActiveProvider), isTrue);

      // First back press: clears selection, does not close page
      await tester.tap(find.text('BackButton'));
      await tester.pumpAndSettle();
      expect(capturedRef.read(isLibrarySelectionActiveProvider), isFalse);
      expect(pageClosed, isFalse);

      // Second back press: now that selection is cleared, page close is triggered
      await tester.tap(find.text('BackButton'));
      await tester.pumpAndSettle();
      expect(pageClosed, isTrue);
    });
  });
}
