import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/player/scanner/scanner_service_roots.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScannerPathUtils iOS sandbox resolution', () {
    setUp(() {
      ScannerPathUtils.setIosSandboxDirs(
        docDir: '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Documents',
        libDir: '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Library/Application Support',
      );
    });

    test('resolves stale UUID Documents root and subfolders', () {
      const oldDocRoot = '/private/var/mobile/Containers/Data/Application/OLD-UUID-9999/Documents';
      final resolvedRoot = ScannerPathUtils.resolveIosSandboxPath(oldDocRoot);
      expect(resolvedRoot, '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Documents');

      const oldSubFolder = '/var/mobile/Containers/Data/Application/OLD-UUID-9999/Documents/vynody/Music';
      final resolvedSub = ScannerPathUtils.resolveIosSandboxPath(oldSubFolder);
      expect(resolvedSub, '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Documents/vynody/Music');

      const fileProviderPath = '/private/var/mobile/Containers/Shared/AppGroup/GROUP-UUID-5678/File Provider Storage/Documents/MyMusic';
      final resolvedProvider = ScannerPathUtils.resolveIosSandboxPath(fileProviderPath);
      expect(resolvedProvider, '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Documents/MyMusic');

      const oldThumbPath = '/private/var/mobile/Containers/Data/Application/OLD-UUID-9999/Library/Application Support/thumbnails/abc12345.jpg';
      final resolvedThumb = ScannerPathUtils.resolveIosSandboxPath(oldThumbPath);
      expect(resolvedThumb, '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Library/Application Support/thumbnails/abc12345.jpg');

      const simOldDoc = '/Users/john/Library/Developer/CoreSimulator/Devices/DEV-1/data/Containers/Data/Application/OLD-SIM-1/Documents/album/track.m4a';
      final resolvedSimDoc = ScannerPathUtils.resolveIosSandboxPath(simOldDoc);
      expect(resolvedSimDoc, '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Documents/album/track.m4a');

      const nestedCorruptedThumb = '/Users/john/Library/Developer/CoreSimulator/Devices/DEV-1/data/Containers/Data/Application/NEW-1/Library/Application Support/Developer/CoreSimulator/Devices/DEV-1/data/Containers/Data/Application/OLD-1/Library/Application Support/thumbnails/nested_thumb.jpg';
      final resolvedNestedThumb = ScannerPathUtils.resolveIosSandboxPath(nestedCorruptedThumb);
      expect(resolvedNestedThumb, '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Library/Application Support/thumbnails/nested_thumb.jpg');
    });

    test('isSandboxInternalPath correctly detects sandbox paths', () {
      expect(
        ScannerPathUtils.isSandboxInternalPath(
          '/var/mobile/Containers/Data/Application/OTHER-APP-UUID/Documents/vynody',
        ),
        isFalse,
      );
      expect(
        ScannerPathUtils.isSandboxInternalPath(
          '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Documents',
        ),
        isTrue,
      );
      expect(
        ScannerPathUtils.isSandboxInternalPath('/storage/emulated/0/Music'),
        isFalse,
      );
    });

    test('isHiddenOrExcludedPath identifies trash and hidden files/directories correctly', () {
      const root = '/var/mobile/Containers/Data/Application/UUID/Documents/Music';

      // Within root cases
      expect(
        ScannerPathUtils.isHiddenOrExcludedPath(
          '$root/.trash/song.mp3',
          rootPath: root,
        ),
        isTrue,
      );
      expect(
        ScannerPathUtils.isHiddenOrExcludedPath(
          '$root/Rock/.Trash/song.mp3',
          rootPath: root,
        ),
        isTrue,
      );
      expect(
        ScannerPathUtils.isHiddenOrExcludedPath(
          '$root/.hidden_song.mp3',
          rootPath: root,
        ),
        isTrue,
      );
      expect(
        ScannerPathUtils.isHiddenOrExcludedPath(
          '$root/Rock/song.mp3',
          rootPath: root,
        ),
        isFalse,
      );

      // Without rootPath (absolute path check)
      expect(
        ScannerPathUtils.isHiddenOrExcludedPath('/some/path/.trash/file.flac'),
        isTrue,
      );
      expect(
        ScannerPathUtils.isHiddenOrExcludedPath('/some/path/.trashes/file.flac'),
        isTrue,
      );
      expect(
        ScannerPathUtils.isHiddenOrExcludedPath('/some/path/normal/file.flac'),
        isFalse,
      );
    });
  });

  group('ScannerServiceRoots dynamic resolution on load', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ScannerPathUtils.setIosSandboxDirs(
        docDir: '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Documents',
        libDir: '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Library/Application Support',
      );
    });

    test('dynamically updates stale sandbox root paths and protects from purge', () async {
      final prefs = await SharedPreferences.getInstance();
      const oldSandboxPath =
          '/private/var/mobile/Containers/Data/Application/OLD-UUID-9999/Documents/vynody';
      await prefs.setStringList('root_paths', [oldSandboxPath]);

      final roots = ScannerServiceRoots(
        isDisposed: () => false,
        onPathChanged: (_) {},
      );

      // Simulate hasPersistentAccess returning false (e.g. race condition or old check)
      final removed = await roots.loadRootPaths(
        hasPersistentAccess: (path) async => false,
      );

      // It should NOT be removed because it is a protected sandbox internal path
      expect(removed, isEmpty);
      expect(roots.rootPaths, [
        '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Documents/vynody',
      ]);

      // And SharedPreferences should have been updated with the resolved path
      expect(prefs.getStringList('root_paths'), [
        '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Documents/vynody',
      ]);
    });

    test('pathsEqual and normalization matches /private/var and /var on iOS/macOS', () {
      const withPrivate = '/private/var/mobile/Containers/Data/Application/UUID-1234/Documents';
      const withoutPrivate = '/var/mobile/Containers/Data/Application/UUID-1234/Documents';

      expect(ScannerPathUtils.pathsEqual(withPrivate, withoutPrivate), isTrue);
      expect(ScannerPathUtils.pathsEqual(withoutPrivate, withPrivate), isTrue);

      final normalizedList = ScannerPathUtils.normalizeDeclaredRootPaths([withPrivate, withoutPrivate]);
      expect(normalizedList.length, 1);
      expect(normalizedList.first, withoutPrivate);
    });
  });
}

