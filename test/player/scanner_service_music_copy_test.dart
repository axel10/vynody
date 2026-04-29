import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibe_flow/models/music_folder.dart';
import 'package:vibe_flow/player/metadata_database.dart';
import 'package:vibe_flow/player/scanner_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScannerService', () {
    late Directory supportDirectory;

    setUpAll(() async {
      supportDirectory = await Directory.systemTemp.createTemp(
        'scanner_service_music_copy_test_',
      );
      PathProviderPlatform.instance = _TestPathProviderPlatform(
        supportPath: supportDirectory.path,
      );
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await MetadataDatabase().clearAll();
    });

    tearDownAll(() async {
      if (await supportDirectory.exists()) {
        await supportDirectory.delete(recursive: true);
      }
    });

    test(
      'should keep current folder and show copied song after incremental sync',
      () async {
        const rootPath = '/Users/axel10/Music';
        final rootDirectory = Directory(rootPath);
        if (!await rootDirectory.exists()) {
          return;
        }

        final scanner = ScannerService(
          autoInitialize: false,
          incrementalBatchWindow: const Duration(milliseconds: 80),
        );
        final notifications = <DateTime>[];
        scanner.addListener(() {
          notifications.add(DateTime.now());
        });

        File? copiedFile;
        try {
          final addResult = await scanner.addRootPath(rootPath);
          expect(addResult.status, RootPathAddStatus.added);

          await _waitUntil(
            () =>
                !scanner.isScanning &&
                _firstFolderWithFiles(scanner.rootFolders) != null,
            reason: 'waiting for initial root scan to finish',
          );
          await _pumpEventQueue();

          final targetFolder = _firstFolderWithFiles(scanner.rootFolders);
          expect(targetFolder, isNotNull);

          final currentFolder = targetFolder!;
          final sourceSong = currentFolder.files.first;
          final initialFileCount = currentFolder.files.length;
          final initialNotificationCount = notifications.length;

          scanner.setNavigationState(currentFolder, <MusicFolder>[]);
          expect(scanner.navigationCurrentFolder?.path, currentFolder.path);

          copiedFile = await _copySongWithinSameDirectory(sourceSong.path);

          await _waitUntil(
            () {
              final refreshed = scanner.navigationCurrentFolder;
              if (refreshed == null) {
                return false;
              }
              return refreshed.path == currentFolder.path &&
                  refreshed.files.any((file) => file.path == copiedFile!.path) &&
                  refreshed.files.length == initialFileCount + 1;
            },
            reason: 'waiting for copied song to appear in current folder',
          );

          expect(scanner.navigationCurrentFolder, isNotNull);
          expect(scanner.navigationCurrentFolder!.path, currentFolder.path);
          expect(
            scanner.navigationCurrentFolder!.files.any(
              (file) => file.path == copiedFile!.path,
            ),
            isTrue,
          );
          expect(
            scanner.navigationCurrentFolder!.files.length,
            initialFileCount + 1,
          );
          expect(notifications.length, greaterThan(initialNotificationCount));
        } finally {
          if (copiedFile != null && await copiedFile.exists()) {
            await copiedFile.delete();
          }
          scanner.dispose();
        }
      },
      skip: !Platform.environment.containsKey(
        'RUN_SCANNER_SERVICE_MUSIC_COPY_TEST',
      ),
    );
  });
}

MusicFolder? _firstFolderWithFiles(Iterable<MusicFolder> folders) {
  for (final folder in folders) {
    if (folder.files.isNotEmpty) {
      return folder;
    }
    final nested = _firstFolderWithFiles(folder.subFolders);
    if (nested != null) {
      return nested;
    }
  }
  return null;
}

Future<File> _copySongWithinSameDirectory(String sourcePath) async {
  final sourceFile = File(sourcePath);
  final directory = sourceFile.parent.path;
  final baseName = p.basenameWithoutExtension(sourcePath);
  final extension = p.extension(sourcePath);
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final destinationPath = p.join(
    directory,
    '${baseName}__scanner_copy_test__$timestamp$extension',
  );
  return sourceFile.copy(destinationPath);
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 45),
  Duration pollInterval = const Duration(milliseconds: 200),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(pollInterval);
  }
  fail('Timed out while $reason');
}

Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

class _TestPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _TestPathProviderPlatform({required this.supportPath});

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => supportPath;

  @override
  Future<String?> getTemporaryPath() async => supportPath;

  @override
  Future<String?> getLibraryPath() async => supportPath;
}
