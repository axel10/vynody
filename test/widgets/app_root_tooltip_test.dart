import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/app_root_tooltip.dart';

void main() {
  testWidgets('AppRootTooltip displays message on hover and hides on mouse exit', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppRootTooltip(
              message: '返回上一层',
              waitDuration: const Duration(milliseconds: 50),
              child: const IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: null,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('返回上一层'), findsNothing);

    // Hover over the icon button
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(IconButton)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('返回上一层'), findsOneWidget);

    // Mouse exit
    await gesture.moveTo(Offset.zero);
    await tester.pump();

    expect(find.text('返回上一层'), findsNothing);
  });

  testWidgets('AppRootTooltip renders on root Overlay above nested Navigator siblings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              // Bottom layer: nested Navigator (like LibraryPage)
              Positioned.fill(
                child: Navigator(
                  onGenerateRoute: (settings) => MaterialPageRoute(
                    builder: (context) => Scaffold(
                      body: Padding(
                        padding: const EdgeInsets.only(left: 80.0),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: AppRootTooltip(
                            message: '返回上一层',
                            waitDuration: const Duration(milliseconds: 50),
                            child: const IconButton(
                              icon: Icon(Icons.arrow_back),
                              onPressed: null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Top layer: Rail bar (like SlidingNavigationRail)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 80,
                child: Container(
                  key: const ValueKey('mock_rail'),
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Trigger hover
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(IconButton)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('返回上一层'), findsOneWidget);

    // Verify tooltip is in the root Overlay, not within the nested Navigator
    final rootOverlay = tester.widget<Overlay>(find.byType(Overlay).first);
    expect(rootOverlay, isNotNull);
  });
}
