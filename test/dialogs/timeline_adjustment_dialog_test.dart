import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/dialogs/timeline_adjustment_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';

void main() {
  testWidgets('最大范围输入框会收窄滑块并钳制当前偏移', (tester) async {
    double? previewed;
    Duration? committed;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showTimelineAdjustmentDialog(
                    context,
                    initialTimelineOffsetSeconds: 12.5,
                    onPreviewChanged: (value) => previewed = value,
                    onCommit: (value) async => committed = value,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 初始偏移 12.5s 超出默认 20s 以内 → 默认范围仍是 20。
    final rangeField = find.byType(TextField);
    expect(rangeField, findsOneWidget);
    expect(tester.widget<TextField>(rangeField).controller!.text, '20');

    await tester.enterText(rangeField, '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(rangeField).controller!.text, '5');
    expect(previewed, 5.0);
    expect(committed, const Duration(seconds: 5));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('关闭弹窗后不再访问已释放的 FocusNode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showTimelineAdjustmentDialog(
                    context,
                    initialTimelineOffsetSeconds: 0,
                    onPreviewChanged: (_) {},
                    onCommit: (_) async {},
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 输入框保持焦点时直接点关闭，退出转场里 TextField 仍在树上。
    await tester.enterText(find.byType(TextField), '30');
    await tester.pump();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('输入框允许超过默认 20 秒的范围', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showTimelineAdjustmentDialog(
                    context,
                    initialTimelineOffsetSeconds: 0,
                    onPreviewChanged: (_) {},
                    onCommit: (_) async {},
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final rangeField = find.byType(TextField);
    await tester.enterText(rangeField, '90');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(rangeField).controller!.text, '90');
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.max, 90.0);
    expect(slider.min, -90.0);

    await tester.pumpWidget(const SizedBox());
  });
}
