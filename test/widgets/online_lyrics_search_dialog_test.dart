import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/dialogs/online_lyrics_search_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/widgets/app_bottom_sheet.dart';

void main() {
  testWidgets('showOnlineLyricsSearchDialog renders AppAdaptiveSheet and returns selected track',
      (tester) async {
    final lyricsService = LyricsService();
    const mockTrack = LyricTrack(
      id: 123,
      trackName: 'Test Song',
      artistName: 'Test Artist',
      albumName: 'Test Album',
      duration: 180.0,
      syncedLyrics: '[00:01.00]Line 1\n[00:05.00]Line 2',
    );

    LyricTrack? selectedResult;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  selectedResult = await showOnlineLyricsSearchDialog(
                    context: context,
                    queryTitle: 'Test Song',
                    queryArtist: 'Test Artist',
                    lyricsService: lyricsService,
                    searchTracks: ({
                      required title,
                      artist,
                      album,
                      q,
                      cancelToken,
                    }) async {
                      return [mockTrack];
                    },
                  );
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      ),
    );

    // Tap to open the adaptive dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify AppAdaptiveSheet is rendered
    expect(find.byType(AppAdaptiveSheet), findsOneWidget);

    // Verify search input field exists
    expect(find.byType(TextField), findsOneWidget);

    // Verify track details are displayed in the list item
    final trackItem = find.widgetWithText(InkWell, 'Test Song');
    expect(trackItem, findsOneWidget);

    // Verify lyrics detail button and tap it
    final infoButton = find.byIcon(Icons.info_outline);
    expect(infoButton, findsOneWidget);
    await tester.tap(infoButton);
    await tester.pumpAndSettle();

    // Verify detail sheet is shown with duration and synced info
    expect(find.byType(AppAdaptiveSheet), findsNWidgets(2));
    expect(find.textContaining('Line 1'), findsOneWidget);

    // Close detail sheet
    final closeDetailButton = find.descendant(
      of: find.byType(AppAdaptiveSheet).last,
      matching: find.byIcon(Icons.close),
    );
    await tester.tap(closeDetailButton);
    await tester.pumpAndSettle();

    // Tap on the track item to select it
    await tester.tap(trackItem);
    await tester.pumpAndSettle();

    // Verify dialog closed and track was returned
    expect(find.byType(AppAdaptiveSheet), findsNothing);
    expect(selectedResult?.id, equals(mockTrack.id));
    expect(selectedResult?.trackName, equals(mockTrack.trackName));
  });
}
