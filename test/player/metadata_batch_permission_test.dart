import 'dart:io';

import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';

void main() {
  group('Batch write permissions', () {
    test('TagLibFile.requestWritePermissions returns empty map for empty list',
        () async {
      final result = await TagLibFile.requestWritePermissions(const <String>[]);
      expect(result, isEmpty);
    });

    test('TagLibFile.requestWritePermissions maps paths to themselves off-Android',
        () async {
      if (Platform.isAndroid) return;
      final paths = <String>['/music/a.mp3', '/music/b.flac'];
      final result = await TagLibFile.requestWritePermissions(paths);
      expect(result, <String, String?>{
        '/music/a.mp3': '/music/a.mp3',
        '/music/b.flac': '/music/b.flac',
      });
    });

    test('MetadataHelper.requestBatchWritePermissions returns empty map for empty or non-Android',
        () async {
      final emptyResult = await MetadataHelper.requestBatchWritePermissions(
        const <({String filePath, String? fallbackMediaUri})>[],
      );
      expect(emptyResult, isEmpty);

      if (!Platform.isAndroid) {
        final result = await MetadataHelper.requestBatchWritePermissions(
          const <({String filePath, String? fallbackMediaUri})>[
            (filePath: '/music/a.mp3', fallbackMediaUri: null),
            (filePath: '/music/b.flac', fallbackMediaUri: 'content://media/1'),
          ],
        );
        expect(result, isEmpty);
      }
    });
  });
}
