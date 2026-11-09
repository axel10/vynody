import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/widgets/generic_selection_panel.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('GenericSelectionPanel renders title, cancel and executes action', (tester) async {
    bool cancelCalled = false;
    bool actionCalled = false;

    await tester.pumpWidget(
      _wrap(
        GenericSelectionPanel(
          title: '已选 2 项',
          onCancel: () => cancelCalled = true,
          actions: [
            SelectionActionItem(
              icon: Icons.edit_rounded,
              label: '编辑',
              onPressed: () => actionCalled = true,
            ),
            SelectionActionItem(
              icon: Icons.delete_outline_rounded,
              label: '删除',
              onPressed: null,
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已选 2 项'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    // Cancel callback
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(cancelCalled, isTrue);

    // Enabled action callback
    await tester.tap(find.text('编辑'));
    expect(actionCalled, isTrue);

    // Disabled action
    final deleteButton = tester.widget<TextButton>(
      find.ancestor(of: find.text('删除'), matching: find.byType(TextButton)).first,
    );
    expect(deleteButton.onPressed, isNull);
  });

  testWidgets('GenericSelectionPanel shows scrollbar when actions exceed 2 rows', (tester) async {
    final manyActions = List.generate(
      12,
      (i) => SelectionActionItem(
        icon: Icons.star,
        label: 'Action $i',
        onPressed: () {},
      ),
    );

    await tester.pumpWidget(
      _wrap(
        GenericSelectionPanel(
          title: '批量操作',
          onCancel: () {},
          actions: manyActions,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
