import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';
import 'package:vynody/widgets/song_zoom_item.dart';

void main() {
  testWidgets('SongZoomItem renders without overflow across all zoom tiers', (tester) async {
    const song = MusicFile(
      name: 'test_song.flac',
      path: '/music/test_song.flac',
      title: 'Very Long Song Display Name That Might Challenge Layout Width And Height',
      artist: 'Talented Artist Name',
      album: 'Fabulous Album Title 2026',
      durationMillis: 235000,
    );

    // Test a range of zoom scales including transition boundaries and tight screen widths
    final testScales = [0.0, 0.1, 0.2, 0.35, 0.4, 0.5, 0.6, 0.75, 0.8, 0.95, 1.0];

    for (final scale in testScales) {
      final metrics = FolderZoomLayoutMetrics(
        targetZoomScale: scale,
        animatedZoomScale: scale,
        gridMorph: isFolderZoomGrid(scale) ? 1.0 : 0.0,
        compactMorph: isFolderZoomCompactList(scale) ? 1.0 : 0.0,
        animatedGridCols: 3.0,
        animatedGridTextHeight: 58.0,
        animatedListExtent: getFolderListTileExtent(scale),
        targetCardWidth: 140.0,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 140, // typical narrow grid card width
                height: 200,
                child: SongZoomItem(
                  song: song,
                  metrics: metrics,
                  isCurrent: true,
                  isPlaying: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Ensure no flutter exceptions or overflows occurred
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('SongZoomItem renders in landscape mode across all zoom tiers', (tester) async {
    const song = MusicFile(
      name: 'test_song.flac',
      path: '/music/test_song.flac',
      title: 'Landscape Song Display Name',
      artist: 'Talented Artist Name',
      album: 'Fabulous Album Title 2026',
      durationMillis: 235000,
    );

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final testScales = [0.0, 0.1, 0.2, 0.35, 0.4, 0.5, 0.6, 0.75, 0.8, 0.95, 1.0];

    for (final scale in testScales) {
      final metrics = FolderZoomLayoutMetrics(
        targetZoomScale: scale,
        animatedZoomScale: scale,
        gridMorph: isFolderZoomGrid(scale) ? 1.0 : 0.0,
        compactMorph: isFolderZoomCompactList(scale) ? 1.0 : 0.0,
        animatedGridCols: 5.0,
        animatedGridTextHeight: 58.0,
        animatedListExtent: getFolderListTileExtent(scale),
        targetCardWidth: 200.0,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 100,
                child: SongZoomItem(
                  song: song,
                  metrics: metrics,
                  isCurrent: true,
                  isPlaying: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('SongZoomItem displays separate table columns in landscape list mode', (tester) async {
    const song = MusicFile(
      name: 'test_song.flac',
      path: '/music/test_song.flac',
      title: 'Song Title',
      artist: 'Artist One',
      album: 'Special Album',
      trackNumber: 7,
      durationMillis: 185000,
    );

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const metrics = FolderZoomLayoutMetrics(
      targetZoomScale: 0.35,
      animatedZoomScale: 0.35,
      gridMorph: 0.0,
      compactMorph: 0.0,
      animatedGridCols: 4.0,
      animatedGridTextHeight: 58.0,
      animatedListExtent: 80.0,
      targetCardWidth: 200.0,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(
              width: 1200,
              height: 80,
              child: SongZoomItem(
                song: song,
                metrics: metrics,
                isCurrent: false,
                isPlaying: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify track number column is to the left of format column
    final trackX = tester.getTopLeft(find.text('07')).dx;
    final formatX = tester.getTopLeft(find.text('FLAC')).dx;
    final durationX = tester.getTopLeft(find.text('3:05')).dx;
    expect(trackX < formatX, isTrue, reason: 'Track number must be to the left of format');
    expect(formatX < durationX, isTrue, reason: 'Format must be to the left of duration');

    // Verify title and artist (artist alone without " - Special Album")
    expect(find.text('Song Title'), findsOneWidget);
    expect(find.text('Artist One'), findsOneWidget);
    expect(find.text('Artist One - Special Album'), findsNothing);

    // Verify separate album column
    expect(find.text('Special Album'), findsOneWidget);

    // Verify format column badge
    expect(find.text('FLAC'), findsOneWidget);

    // Verify duration column (3:05)
    expect(find.text('3:05'), findsOneWidget);

    // Test with missing trackNumber -> track column is empty
    const songNoTrack = MusicFile(
      name: 'test_song2.flac',
      path: '/music/test_song2.flac',
      title: 'Song Without Track',
      artist: 'Artist Two',
      album: 'Album Two',
      trackNumber: null,
      durationMillis: 120000,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(
              width: 1200,
              height: 80,
              child: SongZoomItem(
                song: songNoTrack,
                metrics: metrics,
                isCurrent: false,
                isPlaying: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Song Without Track'), findsOneWidget);
    expect(find.text('Artist Two'), findsOneWidget);
    expect(find.text('Album Two'), findsOneWidget);
    expect(find.text('2:00'), findsOneWidget);
  });
}
