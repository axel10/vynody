import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/app_top_nav_bar.dart';

void main() {
  group('AppTopNavBar', () {
    testWidgets('triggers onTitleTap when title is tapped', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTopNavBar(
              title: 'Albums',
              onTitleTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Albums'), findsOneWidget);
      await tester.tap(find.text('Albums'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('renders normally without onTitleTap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppTopNavBar(
              title: 'Artists',
            ),
          ),
        ),
      );

      expect(find.text('Artists'), findsOneWidget);
    });
  });
}
