import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/drag/drag_preview_card.dart';

void main() {
  testWidgets('AppDraggablePreviewCard handles tight constraints without overflow',
      (tester) async {
    // Under tight constraints (like 111.6px, which leaves ~37.6px for subtitle Row),
    // it should not throw RenderFlex overflow error.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 111.6,
            child: AppDraggablePreviewCard(
              title: 'Very Long Title Here',
              subtitle: 'Sub title details',
              badgeText: '12 首歌曲',
              isBatch: false,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Very Long Title Here'), findsOneWidget);
    expect(find.text('12 首歌曲'), findsOneWidget);
  });
}
