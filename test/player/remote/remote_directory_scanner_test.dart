import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/clients/webdav_client.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/services/remote_directory_scanner.dart';
import 'package:vynody/player/remote/services/remote_scan_root.dart';
import 'package:vynody/player/scanner/scanner_service.dart';

class _TestPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPathProviderPlatform(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

class _FakeRemoteDirectoryClient implements RemoteDirectoryClient {
  _FakeRemoteDirectoryClient(this.tree);

  final Map<String, List<WebDavFile>> tree;
  final List<String> listedDirs = [];
  Completer<void>? beforeListGate;

  @override
  Future<List<WebDavFile>> listFiles(String path) async {
    listedDirs.add(path);
    if (beforeListGate != null && !beforeListGate!.isCompleted) {
      await beforeListGate!.future;
    }
    return tree[path] ?? const [];
  }
}

class _FakeAudioService extends Fake implements AudioService {
  final List<List<String>> purgedRootPathBatches = [];

  @override
  Future<void> purgeSongsFromQueue({
    Iterable<String>? paths,
    Iterable<String>? rootPaths,
  }) async {
    purgedRootPathBatches.add((rootPaths ?? const <String>[]).toList());
  }
}

class _FakeScannerService extends Fake
    with ChangeNotifier
    implements ScannerService {
  final List<List<RemoteScanRoot>> setRemoteRootsCalls = [];

  @override
  void setRemoteRoots(Iterable<RemoteScanRoot> roots) {
    setRemoteRootsCalls.add(List.of(roots));
  }
}

class _BlockingRemoveRootsNotifier extends RemoteScanRootsNotifier {
  Completer<void>? removeGate;
  bool removeEntered = false;

  @override
  Future<void> removeRoot(String rootId) async {
    removeEntered = true;
    if (removeGate != null && !removeGate!.isCompleted) {
      await removeGate!.future;
    }
    await super.removeRoot(rootId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;
  late MetadataDatabase db;
  late _FakeAudioService fakeAudio;
  late _FakeScannerService fakeScanner;

  final server = RemoteServer(
    id: 'srv_webdav_1',
    name: 'NAS Music',
    type: RemoteServerType.webdav,
    url: 'https://nas.example.com/dav',
    username: 'alice',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  RemoteScanRoot makeRoot([String remotePath = '/Music']) => RemoteScanRoot(
        id: RemoteScanRoot.generateId(server.id, remotePath),
        serverId: server.id,
        serverType: server.type,
        serverName: server.name,
        remotePath: remotePath,
        virtualUri: RemoteScanRoot.generateVirtualUri(server, remotePath),
        addedAt: 1700000000000,
      );

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('remote_scanner_test_');
    PathProviderPlatform.instance = _TestPathProviderPlatform(supportDir.path);
    db = MetadataDatabase();
    await db.ensureOpen();
  });

  tearDownAll(() async {
    try {
      if (await supportDir.exists()) {
        await supportDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await db.clearAll();
    fakeAudio = _FakeAudioService();
    fakeScanner = _FakeScannerService();
  });

  tearDown(() async {
    await db.clearAll();
  });

  group('RemoteDirectoryScanner', () {
    test('scanRoot traverses subdirectories once and guards against cyclic folder links', () async {
      final root = makeRoot('/Music');
      final client = _FakeRemoteDirectoryClient({
        '/Music': [
          const WebDavFile(
            path: '/Music/root.flac',
            name: 'root.flac',
            isDirectory: false,
            contentLength: 1024,
          ),
          const WebDavFile(
            path: '/Music/Album',
            name: 'Album',
            isDirectory: true,
            contentLength: 0,
          ),
          const WebDavFile(
            path: '/Music/cover.jpg',
            name: 'cover.jpg',
            isDirectory: false,
            contentLength: 512,
          ),
        ],
        '/Music/Album': [
          const WebDavFile(
            path: '/Music/Album/track.mp3',
            name: 'track.mp3',
            isDirectory: false,
            contentLength: 2048,
          ),
          // Cyclic directory entry pointing back to /Music
          const WebDavFile(
            path: '/Music',
            name: 'back_to_root',
            isDirectory: true,
            contentLength: 0,
          ),
        ],
      });

      final extractedPaths = <String>[];
      final progresses = <RemoteScanProgress>[];

      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(fakeAudio),
          scannerServiceProvider.overrideWith((ref) => fakeScanner),
          remoteDirectoryScannerProvider.overrideWith(
            (ref) => RemoteDirectoryScanner(
              ref,
              database: db,
              clientFactory: (_, _) => client,
              batchMetadataProcessor: ({
                required files,
                required server,
                required password,
                concurrency = 3,
                isCancelled,
                onFileStart,
                onMetadataLoaded,
              }) async {
                for (final f in files) {
                  extractedPaths.add(f.path);
                  onFileStart?.call(f);
                  final uri = 'webdav://${server.id}${f.path}';
                  final meta = SongMetadata(
                    path: uri,
                    title: f.name,
                    album: 'NAS Album',
                    artist: 'NAS Artist',
                    sourceFlags: SongSourceFlags.remote,
                    lastModifiedTime: f.lastModified?.millisecondsSinceEpoch ?? 0,
                  );
                  await db.insertOrUpdateSong(meta);
                  onMetadataLoaded?.call(uri, meta, f);
                }
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(remoteScanRootsProvider.future);
      await container.read(remoteScanRootsProvider.notifier).addRoot(root);

      final scanner = container.read(remoteDirectoryScannerProvider);
      final count = await scanner.scanRoot(
        server: server,
        password: 'pw',
        root: root,
        onProgress: progresses.add,
      );

      expect(count, 2);
      expect(client.listedDirs, ['/Music', '/Music/Album']);
      expect(extractedPaths, ['/Music/root.flac', '/Music/Album/track.mp3']);

      final indexed = await db.getSongsUnderPath(root.virtualUri);
      expect(
        indexed.map((s) => s.path).toSet(),
        {
          'webdav://srv_webdav_1/Music/root.flac',
          'webdav://srv_webdav_1/Music/Album/track.mp3',
        },
      );
      expect(fakeScanner.setRemoteRootsCalls.last.single.songCount, 2);
      expect(progresses.last.isScanning, isFalse);
    });

    test('scanRoot incrementally filters unchanged songs, re-extracts Unknown/changed, and deletes stale DB rows', () async {
      final root = makeRoot('/Music');
      const unchangedMtime = 1700000100000;
      const oldMtime = 1700000200000;
      const newMtime = 1700000300000;

      // Seed existing DB state under root.virtualUri
      await db.insertOrUpdateSong(
        const SongMetadata(
          path: 'webdav://srv_webdav_1/Music/unchanged.flac',
          title: 'Known Track',
          album: 'Album',
          artist: 'Artist',
          lastModifiedTime: unchangedMtime,
          sourceFlags: SongSourceFlags.remote,
        ),
      );
      await db.insertOrUpdateSong(
        const SongMetadata(
          path: 'webdav://srv_webdav_1/Music/changed.flac',
          title: 'Outdated Title',
          album: 'Album',
          artist: 'Artist',
          lastModifiedTime: oldMtime,
          sourceFlags: SongSourceFlags.remote,
        ),
      );
      await db.insertOrUpdateSong(
        const SongMetadata(
          path: 'webdav://srv_webdav_1/Music/unknown_meta.mp3',
          title: 'Unknown',
          album: 'Album',
          artist: 'Artist',
          lastModifiedTime: unchangedMtime,
          sourceFlags: SongSourceFlags.remote,
        ),
      );
      await db.insertOrUpdateSong(
        const SongMetadata(
          path: 'webdav://srv_webdav_1/Music/removed_from_server.flac',
          title: 'Gone',
          album: 'Album',
          artist: 'Artist',
          lastModifiedTime: unchangedMtime,
          sourceFlags: SongSourceFlags.remote,
        ),
      );

      final client = _FakeRemoteDirectoryClient({
        '/Music': [
          WebDavFile(
            path: '/Music/unchanged.flac',
            name: 'unchanged.flac',
            isDirectory: false,
            contentLength: 1000,
            lastModified: DateTime.fromMillisecondsSinceEpoch(unchangedMtime),
          ),
          WebDavFile(
            path: '/Music/changed.flac',
            name: 'changed.flac',
            isDirectory: false,
            contentLength: 1000,
            lastModified: DateTime.fromMillisecondsSinceEpoch(newMtime),
          ),
          WebDavFile(
            path: '/Music/unknown_meta.mp3',
            name: 'unknown_meta.mp3',
            isDirectory: false,
            contentLength: 1000,
            lastModified: DateTime.fromMillisecondsSinceEpoch(unchangedMtime),
          ),
          WebDavFile(
            path: '/Music/brand_new.flac',
            name: 'brand_new.flac',
            isDirectory: false,
            contentLength: 1000,
            lastModified: DateTime.fromMillisecondsSinceEpoch(newMtime),
          ),
        ],
      });

      final extractedFiles = <String>[];
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(fakeAudio),
          scannerServiceProvider.overrideWith((ref) => fakeScanner),
          remoteDirectoryScannerProvider.overrideWith(
            (ref) => RemoteDirectoryScanner(
              ref,
              database: db,
              clientFactory: (_, _) => client,
              batchMetadataProcessor: ({
                required files,
                required server,
                required password,
                concurrency = 3,
                isCancelled,
                onFileStart,
                onMetadataLoaded,
              }) async {
                for (final f in files) {
                  extractedFiles.add(f.path);
                  final uri = 'webdav://${server.id}${f.path}';
                  final meta = SongMetadata(
                    path: uri,
                    title: 'Extracted ${f.name}',
                    album: 'Album',
                    artist: 'Artist',
                    sourceFlags: SongSourceFlags.remote,
                    lastModifiedTime: f.lastModified?.millisecondsSinceEpoch ?? 0,
                  );
                  await db.insertOrUpdateSong(meta);
                  onMetadataLoaded?.call(uri, meta, f);
                }
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(remoteScanRootsProvider.future);
      await container.read(remoteScanRootsProvider.notifier).addRoot(root);

      final count = await container.read(remoteDirectoryScannerProvider).scanRoot(
            server: server,
            password: 'pw',
            root: root,
          );

      expect(count, 4);
      expect(
        extractedFiles.toSet(),
        {
          '/Music/changed.flac',
          '/Music/unknown_meta.mp3',
          '/Music/brand_new.flac',
        },
      );
      expect(extractedFiles, isNot(contains('/Music/unchanged.flac')));

      final indexed = await db.getSongsUnderPath(root.virtualUri);
      final byPath = {for (final s in indexed) s.path: s};
      expect(byPath.keys, hasLength(4));
      expect(
        byPath['webdav://srv_webdav_1/Music/removed_from_server.flac'],
        isNull,
      );
      expect(
        byPath['webdav://srv_webdav_1/Music/unchanged.flac']?.title,
        'Known Track',
      );
      expect(
        byPath['webdav://srv_webdav_1/Music/changed.flac']?.title,
        'Extracted changed.flac',
      );
    });

    test('removeRootFromDatabase soft-deletes songs, purges queue, and serializes concurrent scanRoot via activeDeletions lock', () async {
      final root = makeRoot('/Music');
      await db.insertOrUpdateSong(
        const SongMetadata(
          path: 'webdav://srv_webdav_1/Music/song.flac',
          title: 'Indexed Song',
          album: 'Album',
          artist: 'Artist',
          sourceFlags: SongSourceFlags.remote,
        ),
      );

      final removeGate = Completer<void>();
      final rootsNotifier = _BlockingRemoveRootsNotifier()
        ..removeGate = removeGate;

      final client = _FakeRemoteDirectoryClient({
        '/Music': [
          const WebDavFile(
            path: '/Music/song.flac',
            name: 'song.flac',
            isDirectory: false,
            contentLength: 1000,
          ),
        ],
      });

      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(fakeAudio),
          scannerServiceProvider.overrideWith((ref) => fakeScanner),
          remoteScanRootsProvider.overrideWith(() => rootsNotifier),
          remoteDirectoryScannerProvider.overrideWith(
            (ref) => RemoteDirectoryScanner(
              ref,
              database: db,
              clientFactory: (_, _) => client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(remoteScanRootsProvider.future);
      await container.read(remoteScanRootsProvider.notifier).addRoot(root);

      final scanner = container.read(remoteDirectoryScannerProvider);

      // Start deletion; it will pause inside rootsNotifier.removeRoot
      final deleteFuture = scanner.removeRootFromDatabase(root);
      while (!rootsNotifier.removeEntered) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // Trigger concurrent scanRoot while deletion is still active
      var scanFinished = false;
      final scanFuture = scanner
          .scanRoot(server: server, password: 'pw', root: root)
          .then((value) {
        scanFinished = true;
        return value;
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(scanFinished, isFalse);
      expect(client.listedDirs, isEmpty);

      // Allow deletion to complete
      removeGate.complete();
      await deleteFuture;
      final scanResult = await scanFuture;

      expect(scanFinished, isTrue);
      // After deletion finishes, root is no longer registered, so scan aborts cleanly with 0
      expect(scanResult, 0);
      expect(client.listedDirs, isEmpty);
      expect(await db.getSongsUnderPath(root.virtualUri), isEmpty);
      expect(fakeAudio.purgedRootPathBatches, [
        [root.virtualUri],
      ]);
      expect(fakeScanner.setRemoteRootsCalls.last, isEmpty);
    });
  });
}
