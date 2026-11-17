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

  testWidgets('LibrarySelectionPanel places transcodeAction at the very end',
      (tester) async {
    await tester.pumpWidget(
      createTestWidget(
        onAddToFavorites: () {},
        onAddToCloudFavorites: () {},
        onDownload: () {},
        onDelete: () {},
      ),
    );
    await tester.pumpAndSettle();

    final textButtons = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(LibrarySelectionPanel),
            matching: find.descendant(
              of: find.byType(TextButton),
              matching: find.byType(Text),
            ),
          ),
        )
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    expect(textButtons.last, equals('转码'));
  });

  testWidgets('LibrarySelectionPanel with replaceFavoritesWithSongDetails places transcodeAction at the very end',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: LibrarySelectionPanel(
              selectedSongs: [sampleSong],
              allSongs: [sampleSong],
              replaceFavoritesWithSongDetails: true,
              onToggleSelectAll: () {},
              onCancel: () {},
              onDownload: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textButtons = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(LibrarySelectionPanel),
            matching: find.descendant(
              of: find.byType(TextButton),
              matching: find.byType(Text),
            ),
          ),
        )
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    expect(textButtons.last, equals('转码'));
  });

  testWidgets(
      'LibrarySelectionPanel applies 20pt bottom padding on iOS with 34pt bottom safe area',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 34.0),
            ),
            child: Scaffold(
              body: LibrarySelectionPanel(
                selectedSongs: [sampleSong],
                allSongs: [sampleSong],
                onToggleSelectAll: () {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paddingWidget = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(LibrarySelectionPanel),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(
      paddingWidget.padding,
      equals(const EdgeInsets.fromLTRB(16, 0, 16, 20.0)),
    );
  });

  testWidgets(
      'LibrarySelectionPanel with customActions defaults to 4 columns',
      (tester) async {
    final customActions = [
      SelectionActionItem(icon: Icons.select_all, label: '全选', onPressed: () {}),
      SelectionActionItem(icon: Icons.edit, label: '编辑', onPressed: () {}),
      SelectionActionItem(icon: Icons.delete, label: '删除', onPressed: () {}),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: LibrarySelectionPanel(
              customActions: customActions,
              onCancel: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final genericPanel = tester.widget<GenericSelectionPanel>(
      find.descendant(
        of: find.byType(LibrarySelectionPanel),
        matching: find.byType(GenericSelectionPanel),
      ),
    );
    expect(genericPanel.columns, isNull);

    final expandedWidgets = tester.widgetList<Expanded>(
      find.descendant(
        of: find.byType(Row).last,
        matching: find.byType(Expanded),
      ),
    );
    expect(expandedWidgets.length, 4);
  });

  testWidgets(
      'LibrarySelectionPanel places select-all checkbox in header and auto-checks when all songs selected',
      (tester) async {
    final secondSong = MusicFile(
      path: 'subsonic://server-1/track-2',
      name: 'Song 2',
      title: 'Song 2',
      artist: 'Artist 2',
      album: 'Album 2',
    );
    int toggleCount = 0;

    // 部分选中：复选框未勾选，底部网格没有「全选」按钮
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: LibrarySelectionPanel(
              selectedSongs: [sampleSong],
              allSongs: [sampleSong, secondSong],
              onToggleSelectAll: () => toggleCount++,
              onCancel: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(find.text('全选'), findsOneWidget);
    expect(find.byIcon(Icons.select_all), findsNothing);
    expect(find.byIcon(Icons.deselect), findsNothing);

    await tester.tap(find.text('全选'));
    expect(toggleCount, 1);

    // 全部选中：复选框自动勾选
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: LibrarySelectionPanel(
              selectedSongs: [sampleSong, secondSong],
              allSongs: [sampleSong, secondSong],
              onToggleSelectAll: () => toggleCount++,
              onCancel: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(find.text('全选'), findsOneWidget);
  });
}

