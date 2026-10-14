import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/scanner/ios_path_manager.dart';

void main() {
  group('IosPathManager classification & resolution tests', () {
    const currentDoc = '/private/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555/Documents';
    const currentLib = '/private/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555/Library';
    const externalRoot = '/private/var/mobile/Containers/Shared/AppGroup/GROUP-UUID/File Provider Storage/Music';

    setUp(() {
      IosPathManager.configure(
        docDir: currentDoc,
        libDir: currentLib,
        externalRoots: [externalRoot],
        historicalSandboxUuids: ['OLD-UUID-9999'],
      );
    });

    test('classifies File Provider Storage correctly and never rewrites it', () {
      const fileProviderSong =
          '/private/var/mobile/Containers/Shared/AppGroup/AAAA-BBBB/File Provider Storage/Documents/song.mp3';

      expect(
        IosPathManager.classify(fileProviderSong),
        equals(IosPathKind.fileProviderStorage),
      );

      // Resolving must NEVER rewrite File Provider Storage to Vynody's sandbox Documents
      final resolved = IosPathManager.resolveSandboxPath(fileProviderSong);
      expect(resolved, equals(fileProviderSong));
    });

    test('classifies internal Documents and heals stale UUID', () {
      const staleInternalSong =
          '/private/var/mobile/Containers/Data/Application/OLD-UUID-9999/Documents/Artist/Album/song.flac';

      expect(
        IosPathManager.classify(staleInternalSong),
        equals(IosPathKind.internalDocuments),
      );

      final resolved = IosPathManager.resolveSandboxPath(staleInternalSong);
      expect(
        resolved,
        equals('$currentDoc/Artist/Album/song.flac'),
      );
    });

    test('classifies thumbnails and resolves to current Library', () {
      const staleThumb =
          '/private/var/mobile/Containers/Data/Application/OLD-UUID/Library/thumbnails/hash123.jpg';

      expect(
        IosPathManager.classify(staleThumb),
        equals(IosPathKind.internalLibrary),
      );

      final resolved = IosPathManager.resolveSandboxPath(staleThumb);
      expect(
        resolved,
        equals('$currentLib/thumbnails/hash123.jpg'),
      );
    });

    test('respects registered external roots without rewriting', () {
      const externalSong = '$externalRoot/song.mp3';

      expect(
        IosPathManager.classify(externalSong),
        equals(IosPathKind.fileProviderStorage),
      );

      final resolved = IosPathManager.resolveSandboxPath(externalSong);
      expect(resolved, equals(externalSong));
    });

    test('ignores non-file URIs', () {
      const webdavUri = 'http://192.168.1.100:8080/music.mp3';
      expect(
        IosPathManager.classify(webdavUri),
        equals(IosPathKind.nonFileUri),
      );
      expect(
        IosPathManager.resolveSandboxPath(webdavUri),
        equals(webdavUri),
      );
    });

    test('classifies unknown container UUID as externalAppContainer and never rewrites', () {
      const unknownSong =
          '/private/var/mobile/Containers/Data/Application/UNKNOWN-APP-UUID/Documents/track.mp3';

      expect(
        IosPathManager.classify(unknownSong),
        equals(IosPathKind.externalAppContainer),
      );

      final resolved = IosPathManager.resolveSandboxPath(unknownSong);
      expect(resolved, equals(unknownSong));
    });

    test('dynamically added historical UUIDs are recognized and resolved', () {
      const newlyDiscoveredSong =
          '/var/mobile/Containers/Data/Application/DISCOVERED-UUID-5555/Documents/song.m4a';

      // Before registering: unknown container, treated as external
      expect(
        IosPathManager.classify(newlyDiscoveredSong),
        equals(IosPathKind.externalAppContainer),
      );
      expect(
        IosPathManager.resolveSandboxPath(newlyDiscoveredSong),
        equals(newlyDiscoveredSong),
      );

      // Register historical UUID
      IosPathManager.addHistoricalSandboxUuids(['DISCOVERED-UUID-5555']);

      // After registering: internalDocuments, resolved to currentDoc
      expect(
        IosPathManager.classify(newlyDiscoveredSong),
        equals(IosPathKind.internalDocuments),
      );
      expect(
        IosPathManager.resolveSandboxPath(newlyDiscoveredSong),
        equals('$currentDoc/song.m4a'),
      );
    });

    test('supports Simulator container paths with historical UUIDs', () {
      const simSong =
          '/Users/test/Library/Developer/CoreSimulator/Devices/DEV-1/data/Containers/Data/Application/OLD-UUID-9999/Documents/album/track.mp3';

      expect(
        IosPathManager.classify(simSong),
        equals(IosPathKind.internalDocuments),
      );
      expect(
        IosPathManager.resolveSandboxPath(simSong),
        equals('$currentDoc/album/track.mp3'),
      );
    });
  });
}
