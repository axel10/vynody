import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/remote_queue_metadata_enricher.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_storage.dart';

class _TestPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPathProviderPlatform(this.supportPath);
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getTemporaryPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MetadataDatabase db;
  late RemoteServer webdavServer;
  late RemoteServer smbServer;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('remote_queue_enricher_test_');
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir.path);
    db = MetadataDatabase();
    await db.ensureOpen();
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    await db.clearAll();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    webdavServer = RemoteServer(
      id: 'wd_srv',
      name: 'WebDAV',
      type: RemoteServerType.webdav,
      url: 'https://dav.example.com',
      username: 'u',
      createdAt: DateTime(2026),
    );
    smbServer = RemoteServer(
      id: 'smb_srv',
      name: 'SMB',
      type: RemoteServerType.smb,
      url: 'smb://192.168.1.10',
      username: 'u',
      createdAt: DateTime(2026),
    );
    final storage = RemoteServerStorage(prefs: prefs);
    await storage.saveServers([webdavServer, smbServer]);
    await storage.savePassword('wd_srv', 'pw1');
    await storage.savePassword('smb_srv', 'pw2');
  });

  Future<RemoteServerStorage> loadStorage() async {
    final prefs = await SharedPreferences.getInstance();
    return RemoteServerStorage(prefs: prefs);
  }

  group('RemoteQueueMetadataEnricher', () {
    test('only enqueues WebDAV/SMB audio paths and deduplicates identical URIs', () async {
      final fetchedPaths = <String>[];
      final updatesByPath = <String, Map<String, dynamic>>{};

      final enricher = RemoteQueueMetadataEnricher(
        db: db,
        storageGetter: loadStorage,
        onMetadata: (path, updates) => updatesByPath[path] = updates,
        metadataFetcher: ({
          required file,
          required server,
          required password,
          required sourceFlags,
        }) async {
          fetchedPaths.add('${server.id}:${file.path}');
          return SongMetadata(
            path: '${server.type.name}://${server.id}${file.path}',
            title: 'Fetched ${file.name}',
            album: 'Album',
            artist: 'Artist',
            duration: 180000,
          );
        },
      );

      enricher.enqueue([
        const MusicFile(path: '/local/song.mp3', name: 'song.mp3'),
        const MusicFile(path: 'subsonic://s1/track1', name: 'track1'),
        const MusicFile(path: 'jellyfin://j1/track2', name: 'track2'),
        const MusicFile(path: 'webdav://wd_srv/docs/readme.txt', name: 'readme.txt'),
        const MusicFile(path: 'webdav://wd_srv/Music/a.flac', name: 'a.flac'),
        const MusicFile(path: 'webdav://wd_srv/Music/a.flac', name: 'a.flac'),
        const MusicFile(path: 'smb://smb_srv/share/b.mp3', name: 'b.mp3'),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fetchedPaths, unorderedEquals([
        'wd_srv:/Music/a.flac',
        'smb_srv:share/b.mp3',
      ]));
      expect(updatesByPath['webdav://wd_srv/Music/a.flac']?['title'], 'Fetched a.flac');
      expect(updatesByPath['smb://smb_srv/share/b.mp3']?['title'], 'Fetched b.mp3');
      enricher.dispose();
    });

    test('uses DB cache when metadataTextScanned >= 0 and retries when < 0', () async {
      const cachedPath = 'webdav://wd_srv/Music/cached.flac';
      const retryPath = 'webdav://wd_srv/Music/retry.flac';

      await db.insertOrUpdateSong(
        const SongMetadata(
          path: cachedPath,
          title: 'Cached Title',
          album: 'Cached Album',
          artist: 'Cached Artist',
          duration: 210000,
          sourceFlags: SongSourceFlags.remote,
          metadataTextScanned: 1700000000,
        ),
      );
      await db.insertOrUpdateSong(
        const SongMetadata(
          path: retryPath,
          title: 'Unknown',
          album: 'Unknown',
          artist: 'Unknown',
          sourceFlags: SongSourceFlags.remote,
          metadataTextScanned: -1,
        ),
      );

      final fetched = <String>[];
      final updates = <String, Map<String, dynamic>>{};

      final enricher = RemoteQueueMetadataEnricher(
        db: db,
        storageGetter: loadStorage,
        onMetadata: (path, u) => updates[path] = u,
        metadataFetcher: ({
          required file,
          required server,
          required password,
          required sourceFlags,
        }) async {
          fetched.add(file.path);
          return const SongMetadata(
            path: retryPath,
            title: 'Retried Title',
            album: 'Retried Album',
            artist: 'Retried Artist',
            duration: 195000,
          );
        },
      );

      enricher.enqueue([
        const MusicFile(path: cachedPath, name: 'cached.flac'),
        const MusicFile(path: retryPath, name: 'retry.flac'),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fetched, ['/Music/retry.flac']);
      expect(updates[cachedPath]?['title'], 'Cached Title');
      expect(updates[retryPath]?['title'], 'Retried Title');
      enricher.dispose();
    });

    test('enforces max concurrency limit and stops callbacks after dispose', () async {
      var inFlight = 0;
      var maxObservedInFlight = 0;
      final gates = <Completer<void>>[];
      final callbackPaths = <String>[];

      final enricher = RemoteQueueMetadataEnricher(
        db: db,
        storageGetter: loadStorage,
        onMetadata: (path, _) => callbackPaths.add(path),
        concurrency: 2,
        metadataFetcher: ({
          required file,
          required server,
          required password,
          required sourceFlags,
        }) async {
          inFlight++;
          if (inFlight > maxObservedInFlight) {
            maxObservedInFlight = inFlight;
          }
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          inFlight--;
          return SongMetadata(
            path: 'webdav://${server.id}${file.path}',
            title: file.name,
            album: 'A',
            artist: 'B',
          );
        },
      );

      enricher.enqueue([
        for (var i = 0; i < 5; i++)
          MusicFile(path: 'webdav://wd_srv/Music/$i.mp3', name: '$i.mp3'),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(gates, hasLength(2));
      expect(maxObservedInFlight, 2);

      // Complete first batch of 2.
      for (final g in gates.toList()) {
        g.complete();
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(callbackPaths, hasLength(2));
      expect(gates, hasLength(4));
      expect(maxObservedInFlight, 2);

      // Dispose before releasing remaining in-flight batch.
      enricher.dispose();
      for (final g in gates.skip(2)) {
        g.complete();
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Neither the in-flight tasks nor the 5th queued item should emit after dispose.
      expect(callbackPaths, hasLength(2));
      expect(gates, hasLength(4));
    });
  });
}
