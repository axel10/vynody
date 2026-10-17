import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/widgets/album_grid_card.dart';
import 'package:vynody/widgets/folder_grid_card.dart';
import 'package:vynody/widgets/song_grid_card.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

import 'widgets/helpers/screenshot_paths.dart';

void main() {
  testWidgets('grid compare shot', (tester) async {
    await ScreenshotPaths.loadCrossPlatformTestFonts();

    tester.view.physicalSize = const Size(760, 460);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const covers = [
      'test_covers/cover_01.jpg',
      'test_covers/cover_02.jpg',
      'test_covers/cover_03.jpg',
      'test_covers/cover_04.jpg',
    ];

    MusicFile songFor(int i) => MusicFile(
          id: i,
          path: '/music/track_$i.mp3',
          name: 'track_$i.mp3',
          title: '歌曲 $i',
          artist: '艺人 $i',
          album: '专辑 $i',
          durationMillis: 200000,
          thumbnailPath: File(covers[i]).absolute.path,
          artworkPath: File(covers[i]).absolute.path,
        );

    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scannerServiceProvider
              .overrideWith((ref) => ScannerService(autoInitialize: false)),
        ],
        child: RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.light,
              colorSchemeSeed: const Color(0xFF6750A4),
            ),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                final isPortrait =
                    MediaQuery.of(context).orientation == Orientation.portrait;
                const itemWidth = 200.0;
                final textHeight = calculateAlbumGridTextHeight(
                  context,
                  isPortrait: isPortrait,
                );
                final itemHeight = itemWidth + textHeight;

                Widget box(Widget child) => SizedBox(
                      width: itemWidth,
                      height: itemHeight,
                      child: child,
                    );

                return ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            box(FolderGridCard(
                              folder: MusicFolder(
                                path: '/music/folder_1',
                                name: '文件夹 1',
                              ),
                              songsCount: 12,
                              representativeSong: songFor(0),
                              enableHero: false,
                            )),
                            const SizedBox(width: 16),
                            box(SongGridCard(
                              song: songFor(1),
                              isCurrent: false,
                              isPlaying: false,
                            )),
                            const SizedBox(width: 16),
                            box(AlbumGridCard(
                              cover: SongThumbnail.fromSong(
                                songFor(2),
                                size: 200,
                                width: double.infinity,
                                height: double.infinity,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              title: '专辑 2',
                              subtitle: '艺人 2',
                            )),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final widget = element.widget as Image;
        try {
          await precacheImage(widget.image, element);
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump(const Duration(milliseconds: 300));

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/grid_compare_song.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
