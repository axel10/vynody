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

    test('fileRating fallback and user override behavior', () async {
      final db = MetadataDatabase();
      const songPath = '/music/tagged_song.mp3';

      // 1. Insert a song with fileRating = 4 into songs table
      await db.insertOrUpdateSong(
        const SongMetadata(
          path: songPath,
          title: 'Tagged Song',
          album: 'Tagged Album',
          artist: 'Tagged Artist',
          fileRating: 4,
        ),
      );

      final service = SongRatingService();
      await Future.delayed(const Duration(milliseconds: 100));

      // Effective rating falls back to fileRating (4)
      expect(service.getRating(songPath), equals(4));
      expect(service.getFileRating(songPath), equals(4));
      expect(service.getUserRating(songPath), isNull);
      expect(service.isFileRated(songPath), isTrue);
      expect(service.isUserRated(songPath), isFalse);

      // 2. User overrides with 5 stars
      await service.setRating(songPath, 5);
      expect(service.getRating(songPath), equals(5));
      expect(service.getUserRating(songPath), equals(5));
      expect(service.getFileRating(songPath), equals(4));
      expect(service.isFileRated(songPath), isFalse);
      expect(service.isUserRated(songPath), isTrue);

      // 3. User unrates (clears rating to 0) -> suppresses file rating (effective rating is 0)
      await service.setRating(songPath, 0);
      expect(service.getRating(songPath), equals(0));
      expect(service.getUserRating(songPath), equals(0));
      expect(service.getFileRating(songPath), equals(4));
      expect(service.isFileRated(songPath), isFalse);
      expect(service.isUserRated(songPath), isFalse);

      // 4. User resets to tag rating -> reverts back to file rating 4
      await service.resetToTagRating(songPath);
      expect(service.getRating(songPath), equals(4));
      expect(service.getUserRating(songPath), isNull);
      expect(service.isFileRated(songPath), isTrue);
      expect(service.isUserRated(songPath), isFalse);
    });
  });
}
