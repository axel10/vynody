import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/theaudiodb_artist_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TheAudioDbArtistService', () {
    late Directory supportDirectory;

    setUpAll(() async {
      supportDirectory = await Directory.systemTemp.createTemp(
        'theaudiodb_artist_service_test_',
      );
      PathProviderPlatform.instance = _TestPathProviderPlatform(
        supportPath: supportDirectory.path,
      );
    });

    setUp(() async {
      await MetadataDatabase().clearAll();
    });

    tearDownAll(() async {
      try {
        if (await supportDirectory.exists()) {
          await supportDirectory.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('returns null for unknown artist or empty name', () async {
      final service = TheAudioDbArtistService.instance;

      const unknownArtist = ArtistSummary(
        queryKey: 'unknown artist',
        name: 'Unknown Artist',
        songs: <MusicFile>[],
        representativeSong: MusicFile(path: '/dummy.mp3', name: 'dummy'),
        songCount: 0,
      );

      final result = await service.fetchAndCacheArtistImage(unknownArtist);
      expect(result, isNull);
    });

    test('returns existing cachedImagePath if file exists', () async {
      final dummyFile = File(p.join(supportDirectory.path, 'dummy_artist.jpg'));
      await dummyFile.writeAsString('fake-image-bytes');

      final service = TheAudioDbArtistService.instance;

      final artist = ArtistSummary(
        queryKey: 'coldplay',
        name: 'Coldplay',
        songs: const <MusicFile>[],
        representativeSong: const MusicFile(path: '/dummy.mp3', name: 'dummy'),
        songCount: 1,
        cachedImagePath: dummyFile.path,
      );

      final result = await service.fetchAndCacheArtistImage(artist);
      expect(result, equals(dummyFile.path));
    });

    test('returns existing DB artistImageCache if record exists and file on disk', () async {
      final db = MetadataDatabase();
      final dummyFile = File(p.join(supportDirectory.path, 'db_cached_artist.jpg'));
      await dummyFile.writeAsString('fake-db-image-bytes');

      await db.insertOrUpdateArtistImageCache(
        ArtistImageCacheRecord(
          artistId: 'coldplay',
          imagePath: dummyFile.path,
          sourceUrl: 'https://example.com/thumb.jpg',
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final service = TheAudioDbArtistService(database: db);

      const artist = ArtistSummary(
        queryKey: 'coldplay',
        name: 'Coldplay',
        songs: <MusicFile>[],
        representativeSong: MusicFile(path: '/dummy.mp3', name: 'dummy'),
        songCount: 1,
      );

      final result = await service.fetchAndCacheArtistImage(artist);
      expect(result, equals(dummyFile.path));
    });
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPathProviderPlatform({required this.supportPath});

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}
