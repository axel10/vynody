import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/rating/song_rating_service.dart';

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

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rating_test_');
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
    await MetadataDatabase().clearAllSongRatings();
  });

  group('SongRatingService Tests', () {
    test('default rating is 0 for unrated song', () {
      final service = SongRatingService();
      expect(service.getRating('/music/song1.mp3'), equals(0));
    });

    test('setRating updates rating and persists', () async {
      final service = SongRatingService();
      await service.setRating('/music/song1.mp3', 4);
      expect(service.getRating('/music/song1.mp3'), equals(4));

      // Create a second service instance to verify persistence
      final service2 = SongRatingService();
      // Allow async db loading
      await Future.delayed(const Duration(milliseconds: 100));
      expect(service2.getRating('/music/song1.mp3'), equals(4));
    });

    test('setting rating to 0 clears the rating', () async {
      final service = SongRatingService();
      await service.setRating('/music/song1.mp3', 5);
      expect(service.getRating('/music/song1.mp3'), equals(5));

      await service.setRating('/music/song1.mp3', 0);
      expect(service.getRating('/music/song1.mp3'), equals(0));

      final service2 = SongRatingService();
      await Future.delayed(const Duration(milliseconds: 100));
      expect(service2.getRating('/music/song1.mp3'), equals(0));
    });

    test('ratings are clamped between 0 and 5', () async {
      final service = SongRatingService();
      await service.setRating('/music/song2.mp3', 10);
      expect(service.getRating('/music/song2.mp3'), equals(5));

      await service.setRating('/music/song3.mp3', -2);
      expect(service.getRating('/music/song3.mp3'), equals(0));
    });
  });
}
