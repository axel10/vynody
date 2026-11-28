import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/audio/loudness_normalization.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:vynody/player/scanner/scanner_metadata_store.dart';
import 'package:vynody/player/scanner/scanner_scan_pipeline.dart';

void main() {
  test(
    'buildScannedMetadataFromBatchResult preserves existing loudness fields',
    () {
      final pipeline = ScannerScanPipeline(
        normalizePath: (path) => path,
        pathLookupKey: (path) => path,
        metadataStore: ScannerMetadataStore(
          rootFolders: () => const [],
          systemMediaFolder: () => null,
          notifyListeners: () {},
          scheduleMetadataNotify: () {},
          onMetadataMutated: () {},
          onAlbumMetadataMutated: () {},
          notifySongMissingState: (_, _) {},
          normalizePath: (path) => path,
          pathsEqual: (a, b) => a == b,
        ),
      );

      const existing = SongMetadata(
        path: '/music/track.flac',
        title: 'Old Title',
        album: 'Album',
        artist: 'Artist',
        trackLufs: -9.5,
        trackPeak: 0.92,
        albumLufs: -10.1,
        albumPeak: 0.95,
        loudnessSource: LoudnessSource.analyzedEbuR128,
        loudnessAnalyzedAt: 1700000000000,
      );

      const scanned = ScannedFileMetadata(
        path: '/music/track.flac',
        title: 'New Title',
        album: 'Album',
        artist: 'Artist',
        duration: 180000,
      );

      final result = pipeline.buildScannedMetadataFromBatchResult(
        '/music/track.flac',
        scanned,
        existing: existing,
      );

      expect(result.title, 'New Title');
      expect(result.trackLufs, -9.5);
      expect(result.trackPeak, 0.92);
      expect(result.albumLufs, -10.1);
      expect(result.albumPeak, 0.95);
      expect(result.loudnessSource, LoudnessSource.analyzedEbuR128);
      expect(result.loudnessAnalyzedAt, 1700000000000);
    },
  );
}
