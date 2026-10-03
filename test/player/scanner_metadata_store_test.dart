import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_metadata_store.dart';
import 'package:vynody/player/scanner/scanner_scan_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScannerMetadataStore', () {
    test('removeMetadataForPath removes the song from visible folders', () {
      final rootFolder = MusicFolder(
        path: '/music',
        name: 'music',
        subFolders: [
          MusicFolder(
            path: '/music/album',
            name: 'album',
            files: [
              const MusicFile(
                path: '/music/album/song.mp3',
                name: 'song.mp3',
              ),
            ],
          ),
        ],
      );

      final store = ScannerMetadataStore(
        rootFolders: () => [rootFolder],
        systemMediaFolder: () => null,
        notifyListeners: () {},
        scheduleMetadataNotify: () {},
        onMetadataMutated: () {},
        onAlbumMetadataMutated: () {},
        notifySongMissingState: (_, __) {},
        normalizePath: (path) => path,
        pathsEqual: (left, right) => left == right,
      );

      store.cacheMetadata(
        const SongMetadata(
          path: '/music/album/song.mp3',
          title: 'Song',
          album: 'Album',
          artist: 'Artist',
        ),
      );

      expect(store.metadataMap.containsKey('/music/album/song.mp3'), isTrue);
      expect(rootFolder.subFolders, hasLength(1));
      expect(rootFolder.subFolders.single.files, hasLength(1));

      store.removeMetadataForPath('/music/album/song.mp3');

      expect(store.metadataMap.containsKey('/music/album/song.mp3'), isFalse);
      expect(rootFolder.subFolders, isEmpty);
    });
  });

  group('ScannerScanPipeline', () {
    test('buildScannedMetadataFromBatchResult falls back to existing values on error', () {
      final pipeline = ScannerScanPipeline(
        normalizePath: (p) => p,
        pathLookupKey: (p) => p,
        metadataStore: ScannerMetadataStore(
          rootFolders: () => [],
          systemMediaFolder: () => null,
          notifyListeners: () {},
          scheduleMetadataNotify: () {},
          onMetadataMutated: () {},
          onAlbumMetadataMutated: () {},
          notifySongMissingState: (_, __) {},
          normalizePath: (p) => p,
          pathsEqual: (a, b) => a == b,
        ),
      );

      const existing = SongMetadata(
        path: '/music/song.mp3',
        title: 'Existing Title',
        album: 'Existing Album',
        artist: 'Existing Artist',
        trackNumber: 5,
      );

      final resultWithError = {
        'path': '/music/song.mp3',
        'title': null,
        'album': null,
        'artist': null,
        'duration': null,
        'trackNumber': null,
        'error': 'Failed to read tags',
      };

      final metadata = pipeline.buildScannedMetadataFromBatchResult(
        '/music/song.mp3',
        resultWithError,
        existing: existing,
      );

      expect(metadata.title, equals('Existing Title'));
      expect(metadata.album, equals('Existing Album'));
      expect(metadata.artist, equals('Existing Artist'));
      expect(metadata.trackNumber, equals(5));
    });

    test('buildScannedMetadataFromBatchResult clears tags and does not fall back when no error', () {
      final pipeline = ScannerScanPipeline(
        normalizePath: (p) => p,
        pathLookupKey: (p) => p,
        metadataStore: ScannerMetadataStore(
          rootFolders: () => [],
          systemMediaFolder: () => null,
          notifyListeners: () {},
          scheduleMetadataNotify: () {},
          onMetadataMutated: () {},
          onAlbumMetadataMutated: () {},
          notifySongMissingState: (_, __) {},
          normalizePath: (p) => p,
          pathsEqual: (a, b) => a == b,
        ),
      );

      const existing = SongMetadata(
        path: '/music/song.mp3',
        title: 'Existing Title',
        album: 'Existing Album',
        artist: 'Existing Artist',
        trackNumber: 5,
      );

      final resultEmptyTagsNoError = {
        'path': '/music/song.mp3',
        'title': null,
        'album': null,
        'artist': null,
        'duration': null,
        'trackNumber': null,
        'error': null,
      };

      final metadata = pipeline.buildScannedMetadataFromBatchResult(
        '/music/song.mp3',
        resultEmptyTagsNoError,
        existing: existing,
      );

      expect(metadata.title, equals('song')); // falls back to basename
      expect(metadata.album, equals('Unknown Album'));
      expect(metadata.artist, equals('Unknown Artist'));
      expect(metadata.trackNumber, isNull);
    });

    test('buildScannedMetadataFromBatchResult populates audio details and converts to AudioDetails', () {
      final pipeline = ScannerScanPipeline(
        normalizePath: (p) => p,
        pathLookupKey: (p) => p,
        metadataStore: ScannerMetadataStore(
          rootFolders: () => [],
          systemMediaFolder: () => null,
          notifyListeners: () {},
          scheduleMetadataNotify: () {},
          onMetadataMutated: () {},
          onAlbumMetadataMutated: () {},
          notifySongMissingState: (_, __) {},
          normalizePath: (p) => p,
          pathsEqual: (a, b) => a == b,
        ),
      );

      final batchResult = {
        'path': '/music/song.flac',
        'title': 'High Res Track',
        'album': 'Audiophile Album',
        'artist': 'HiFi Artist',
        'duration': 240000,
        'trackNumber': 1,
        'bitrate': 1411200,
        'sampleRate': 96000,
        'channels': 2,
        'bitDepth': 24,
        'format': 'FLAC',
        'codec': 'flac',
      };

      final metadata = pipeline.buildScannedMetadataFromBatchResult(
        '/music/song.flac',
        batchResult,
      );

      expect(metadata.bitrate, equals(1411200));
      expect(metadata.sampleRate, equals(96000));
      expect(metadata.channels, equals(2));
      expect(metadata.bitDepth, equals(24));
      expect(metadata.format, equals('FLAC'));
      expect(metadata.codec, equals('flac'));

      final musicFile = MusicFile(
        path: metadata.path,
        name: 'song.flac',
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        durationMillis: metadata.duration,
        bitrate: metadata.bitrate,
        sampleRate: metadata.sampleRate,
        channels: metadata.channels,
        bitDepth: metadata.bitDepth,
        format: metadata.format,
        codec: metadata.codec,
      );

      final audioDetails = musicFile.toAudioDetails();
      expect(audioDetails, isNotNull);
      expect(audioDetails!.formatName, equals('FLAC'));
      expect(audioDetails.codecName, equals('flac'));
      expect(audioDetails.sampleRate, equals(96000));
      expect(audioDetails.channels, equals(2));
      expect(audioDetails.bitrate, equals(1411200));
      expect(audioDetails.bitDepth, equals(24));
    });
  });
}

