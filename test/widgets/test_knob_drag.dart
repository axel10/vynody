import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Test Knob drag continuous', (tester) async {
    int vStart = 0, vUpdate = 0, vEnd = 0, vCancel = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 100),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) => vStart++,
                  onVerticalDragUpdate: (_) => vUpdate++,
                  onVerticalDragEnd: (_) => vEnd++,
                  onVerticalDragCancel: () => vCancel++,
                  child: Container(
                    key: const ValueKey('knob'),
                    width: 64,
                    height: 64,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('knob'))));
    for (int i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    print('vStart: $vStart, vUpdate: $vUpdate, vEnd: $vEnd, vCancel: $vCancel');
  });
}
