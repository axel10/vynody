import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/widgets/library_selection_panel.dart';

void main() {
  final sampleSong = MusicFile(
    path: 'subsonic://server-1/track-1',
    name: 'Song 1',
    title: 'Song 1',
    artist: 'Artist 1',
    album: 'Album 1',
  );

  Widget createTestWidget({
    VoidCallback? onAddToFavorites,
    VoidCallback? onAddToCloudFavorites,
    VoidCallback? onDownload,
    VoidCallback? onDelete,
  }) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: LibrarySelectionPanel(
            selectedSongs: [sampleSong],
            allSongs: [sampleSong],
            onToggleSelectAll: () {},
            onCancel: () {},
            onAddToFavorites: onAddToFavorites,
            onAddToCloudFavorites: onAddToCloudFavorites,
            onDownload: onDownload,
            onDelete: onDelete,
          ),
        ),
      ),
    );
  }

  testWidgets('LibrarySelectionPanel renders local and cloud favorites and scrolls beyond 2 rows',
      (tester) async {
    bool localFavCalled = false;
    bool cloudFavCalled = false;

    await tester.pumpWidget(
      createTestWidget(
        onAddToFavorites: () => localFavCalled = true,
        onAddToCloudFavorites: () => cloudFavCalled = true,
        onDownload: () {},
        onDelete: () {},
      ),
    );
    await tester.pumpAndSettle();

    // Verify "本地收藏" and "云端收藏" are present
    expect(find.text('本地收藏'), findsOneWidget);
    expect(find.text('云端收藏'), findsOneWidget);

    // Tap local favorites
    await tester.tap(find.text('本地收藏'));
    expect(localFavCalled, isTrue);

    // Tap cloud favorites
    await tester.tap(find.text('云端收藏'));
    expect(cloudFavCalled, isTrue);

    // Verify SingleChildScrollView and Scrollbar exist
    final scrollViewFinder = find.byType(SingleChildScrollView);
    expect(scrollViewFinder, findsOneWidget);

    final scrollbarFinder = find.byType(Scrollbar);
    expect(scrollbarFinder, findsOneWidget);

    // Action area maxHeight is constrained to 2 rows (124.0 px)
    final constrainedBoxes = tester.widgetList<ConstrainedBox>(
      find.descendant(
        of: find.byType(LibrarySelectionPanel),
        matching: find.byType(ConstrainedBox),
      ),
    );
    final actionBox = constrainedBoxes.firstWhere(
      (b) => b.constraints.maxHeight == 124.0,
    );
    expect(actionBox.constraints.maxHeight, equals(124.0));
  });

  testWidgets('LibrarySelectionPanel displays addToFavorites when onAddToCloudFavorites is null',
      (tester) async {
    await tester.pumpWidget(
      createTestWidget(
        onAddToFavorites: () {},
        onAddToCloudFavorites: null,
      ),
    );
    await tester.pumpAndSettle();

    // With cloud favorites null, label defaults to "加入收藏"
    expect(find.text('加入收藏'), findsOneWidget);
    expect(find.text('本地收藏'), findsNothing);
    expect(find.text('云端收藏'), findsNothing);
  });
}
