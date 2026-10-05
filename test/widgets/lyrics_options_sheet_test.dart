import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/dialogs/lyrics_options_sheet.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/widgets/app_bottom_sheet.dart';

void main() {
  testWidgets('showLyricsOptionsSheet renders options in AppAdaptiveSheet and returns selected value',
      (tester) async {
    String? selectedResult;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  selectedResult = await showLyricsOptionsSheet(
                    context,
                    title: 'Lyrics Options',
                    subtitle: 'Test Song',
                    groups: [
                      LyricsOptionGroup(
                        title: 'Basic',
                        items: [
                          const LyricsOptionItem(
                            value: 'fill_lyrics',
                            label: 'Enter Lyrics',
                            icon: Icons.edit_note_rounded,
                          ),
                          const LyricsOptionItem(
                            value: 'disabled_item',
                            label: 'Disabled Action',
                            icon: Icons.block,
                            enabled: false,
                          ),
                        ],
                      ),
                      LyricsOptionGroup(
                        title: 'Advanced',
                        items: [
                          const LyricsOptionItem(
                            value: 'generate',
                            label: 'Generate Lyrics',
                            icon: Icons.auto_awesome_rounded,
                          ),
                        ],
                      ),
                    ],
                  );
                },
                child: const Text('Open Sheet'),
              );
            },
          ),
        ),
      ),
    );

    // Tap to open
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Verify AppAdaptiveSheet is rendered with title and items
    expect(find.byType(AppAdaptiveSheet), findsOneWidget);
    expect(find.text('Lyrics Options'), findsOneWidget);
    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('Enter Lyrics'), findsOneWidget);
    expect(find.text('Disabled Action'), findsOneWidget);
    expect(find.text('Generate Lyrics'), findsOneWidget);

    // Tap disabled item - should NOT pop or set result
    await tester.tap(find.text('Disabled Action'));
    await tester.pumpAndSettle();
    expect(find.byType(AppAdaptiveSheet), findsOneWidget);
    expect(selectedResult, isNull);

    // Tap enabled item 'Generate Lyrics'
    await tester.tap(find.text('Generate Lyrics'));
    await tester.pumpAndSettle();

    // Verify sheet closed and returned selected item value
    expect(find.byType(AppAdaptiveSheet), findsNothing);
    expect(selectedResult, equals('generate'));
  });
}
