import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/widgets/remote_server_slivers.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

TextButton _buttonFor(WidgetTester tester, IconData icon) {
  return tester.widget<TextButton>(
    find
        .ancestor(
          of: find.byIcon(icon),
          matching: find.byType(TextButton),
        )
        .first,
  );
}

CloudServerSelectionPanel _panel({
  required int selectedCount,
  VoidCallback? onDelete,
  VoidCallback? onEdit,
}) {
  return CloudServerSelectionPanel(
    selectedCount: selectedCount,
    totalCount: 4,
    onSelectAll: () {},
    onDelete: onDelete,
    onEdit: onEdit,
    onCancel: () {},
  );
}

void main() {
  testWidgets('编辑按钮只在选中 1 条时可点', (tester) async {
    Future<void> pump({
      required int selectedCount,
      VoidCallback? onEdit,
    }) async {
      await tester.pumpWidget(_wrap(_panel(
        selectedCount: selectedCount,
        onDelete: selectedCount > 0 ? () {} : null,
        onEdit: onEdit,
      )));
      await tester.pump();
    }

    await pump(selectedCount: 0);
    expect(_buttonFor(tester, Icons.edit_rounded).onPressed, isNull);

    await pump(selectedCount: 2);
    expect(_buttonFor(tester, Icons.edit_rounded).onPressed, isNull);

    await pump(selectedCount: 1, onEdit: () {});
    expect(_buttonFor(tester, Icons.edit_rounded).onPressed, isNotNull);
  });

  testWidgets('删除按钮仅在有选中时可点，全选与退出始终可点', (tester) async {
    await tester.pumpWidget(_wrap(_panel(selectedCount: 0)));
    await tester.pump();
    expect(_buttonFor(tester, Icons.delete_outline_rounded).onPressed, isNull);
    expect(
      _buttonFor(tester, Icons.select_all_rounded).onPressed,
      isNotNull,
    );
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.pumpWidget(_wrap(_panel(
      selectedCount: 2,
      onDelete: () {},
    )));
    await tester.pump();
    expect(
      _buttonFor(tester, Icons.delete_outline_rounded).onPressed,
      isNotNull,
    );
  });
}
