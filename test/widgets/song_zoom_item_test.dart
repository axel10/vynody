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
}
