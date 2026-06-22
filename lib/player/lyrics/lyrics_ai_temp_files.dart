import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String kLyricsAiTempDirectoryName = 'vynody_lyrics_ai';

Future<Directory> getLyricsAiTempDirectory() async {
  final baseDir = await getTemporaryDirectory();
  final tempDir = Directory(
    '${baseDir.path}${Platform.pathSeparator}$kLyricsAiTempDirectoryName',
  );
  if (!await tempDir.exists()) {
    await tempDir.create(recursive: true);
  }
  return tempDir;
}

Future<void> cleanupLyricsAiTempArtifacts() async {
  final baseDir = await getTemporaryDirectory();
  await _deleteLegacyTempMp3Files(baseDir);

  final tempDir = Directory(
    '${baseDir.path}${Platform.pathSeparator}$kLyricsAiTempDirectoryName',
  );
  try {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  } catch (_) {}
}

Future<void> _deleteLegacyTempMp3Files(Directory baseDir) async {
  try {
    await for (final entity in baseDir.list(recursive: false, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (p.extension(entity.path).toLowerCase() != '.mp3') {
        continue;
      }
      try {
        await entity.delete();
      } catch (_) {}
    }
  } catch (_) {}
}
