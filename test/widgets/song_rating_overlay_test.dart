import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/player/rating/song_rating_service.dart';
import 'package:vynody/widgets/playback/song_rating_overlay.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  _FakePathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SongRatingService ratingService;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rating_widget_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    ratingService = SongRatingService();
  });

  Widget buildTestWidget(String songPath) {
    return ProviderScope(
      overrides: [
        songRatingServiceProvider.overrideWith((ref) => ratingService),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SongRatingOverlay(songPath: songPath),
          ),
        ),
      ),
    );
  }

  testWidgets('SongRatingOverlay displays outline star when unrated', (tester) async {
    await tester.pumpWidget(buildTestWidget('/music/test_song.mp3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('SongRatingOverlay displays filled star and rating number when rated', (tester) async {
    await tester.runAsync(() async {
      await ratingService.setRating('/music/test_song.mp3', 4);
    });

    await tester.pumpWidget(buildTestWidget('/music/test_song.mp3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });
}
