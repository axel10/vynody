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

      const oldThumbPath = '/private/var/mobile/Containers/Data/Application/OLD-UUID-9999/Library/Application Support/thumbnails/abc12345.jpg';
      final resolvedThumb = ScannerPathUtils.resolveIosSandboxPath(oldThumbPath);
      expect(resolvedThumb, '/var/mobile/Containers/Data/Application/NEW-UUID-1234/Library/Application Support/thumbnails/abc12345.jpg');
    });

    test('isSandboxInternalPath correctly detects sandbox paths', () {
      expect(
        ScannerPathUtils.isSandboxInternalPath(
          '/var/mobile/Containers/Data/Application/ANY-UUID/Documents/vynody',
        ),
        isTrue,
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
  });
}
