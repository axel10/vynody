import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/dialogs/manual_lyrics_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/widgets/app_bottom_sheet.dart';

void main() {
  testWidgets('showManualLyricsDialog renders AppAdaptiveSheet and returns edited lyrics on confirm',
      (tester) async {
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showManualLyricsDialog(
                    context,
                    initialLyrics: 'Initial line',
                  );
                },
                child: const Text('Open Manual Lyrics'),
              );
            },
          ),
        ),
      ),
    );

    // Tap to open the dialog
    await tester.tap(find.text('Open Manual Lyrics'));
    await tester.pumpAndSettle();

    // Verify AppAdaptiveSheet is rendered
    expect(find.byType(AppAdaptiveSheet), findsOneWidget);

    // Verify TextField with initial text
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);
    expect(find.text('Initial line'), findsOneWidget);

    // Enter new lyrics
    await tester.enterText(textFieldFinder, 'Line 1\nLine 2\nLine 3');
    await tester.pumpAndSettle();

    // Tap confirm button
    final confirmButton = find.byType(FilledButton);
    expect(confirmButton, findsOneWidget);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    // Verify sheet is closed and result returned
    expect(find.byType(AppAdaptiveSheet), findsNothing);
    expect(result, equals('Line 1\nLine 2\nLine 3'));
  });

  testWidgets('showManualLyricsDialog returns null on cancel',
      (tester) async {
    String? result = 'not-null';

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showManualLyricsDialog(
                    context,
                    initialLyrics: '',
                  );
                },
                child: const Text('Open Manual Lyrics'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Manual Lyrics'));
    await tester.pumpAndSettle();

    expect(find.byType(AppAdaptiveSheet), findsOneWidget);

    // Tap cancel button
    final cancelButton = find.widgetWithText(TextButton, 'Cancel');
    expect(cancelButton, findsOneWidget);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    expect(find.byType(AppAdaptiveSheet), findsNothing);
    expect(result, isNull);
  });
}
