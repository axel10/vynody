import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/media_drop_import_service.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/player/scanner/scanner_service.dart';

class _TestPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPathProviderPlatform(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

class _FakeAudioService extends Fake implements AudioService {
  final List<List<String>> registeredPathBatches = [];
  final List<List<MusicFile>> appendedBatches = [];
  final List<({int index, List<MusicFile> songs})> insertedCalls = [];
  final List<({String path, String name})> playedFiles = [];

  @override
  Future<void> registerPersistentAccessForPaths(Iterable<String> paths) async {
    registeredPathBatches.add(paths.toList());
  }

  @override
  Future<void> appendToQueue(List<MusicFile> songs) async {
    appendedBatches.add(List.of(songs));
  }

  @override
  Future<void> insertIntoQueueAt(int index, List<MusicFile> songs) async {
    insertedCalls.add((index: index, songs: List.of(songs)));
  }

  @override
  Future<void> playFile(
    String path,
    String name, {
    int? id,
    String? mediaUri,
    bool append = false,
    int? insertIndex,
  }) async {
    playedFiles.add((path: path, name: name));
  }
}

class _FakeScannerService extends Fake
    with ChangeNotifier
    implements ScannerService {
  final Map<String, SongMetadata> _metadataMap = {};

  @override
  Map<String, SongMetadata> get metadataMap => _metadataMap;
}

class _FakePlaylistService extends Fake
    with ChangeNotifier
    implements PlaylistService {
  final List<({String playlistId, List<MusicFile> songs})> addedCalls = [];

  @override
  Future<void> addSongsToPlaylist(
    String playlistId,
    List<MusicFile> songs,
  ) async {
    addedCalls.add((playlistId: playlistId, songs: List.of(songs)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;
  late Directory musicDir;
  late MetadataDatabase db;
  late _FakeAudioService fakeAudio;
  late _FakeScannerService fakeScanner;
  late _FakePlaylistService fakePlaylist;
  late ProviderContainer container;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('media_drop_support_');
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
    musicDir = await Directory.systemTemp.createTemp('media_drop_music_');
    fakeAudio = _FakeAudioService();
    fakeScanner = _FakeScannerService();
    fakePlaylist = _FakePlaylistService();

    container = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(fakeAudio),
        scannerServiceProvider.overrideWith((ref) => fakeScanner),
        playlistServiceProvider.overrideWith((ref) => fakePlaylist),
      ],
    );
    await container.read(remoteServersProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await db.clearAll();
    try {
      if (await musicDir.exists()) {
        await musicDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('MediaDropImportService', () {
    test('decodes file:// URIs with spaces, deduplicates, and filters non-audio files', () async {
      final spacedPath = p.join(musicDir.path, 'track one.mp3');
      final textPath = p.join(musicDir.path, 'readme.txt');
      await File(spacedPath).writeAsBytes(const <int>[1, 2, 3]);
      await File(textPath).writeAsString('ignore');

      fakeScanner.metadataMap[spacedPath] = SongMetadata(
        path: spacedPath,
        title: 'Track One',
        album: 'Single',
        artist: 'Scanner Artist',
        duration: 123000,
      );

      final fileUri = Uri.file(spacedPath).toString();
      expect(fileUri, contains('%20'));

      final service = container.read(mediaDropImportServiceProvider);
      final resolved = await service.resolvePathsToMusicFiles([
        fileUri,
        spacedPath,
        textPath,
        '',
      ]);

      expect(resolved, hasLength(1));
      expect(resolved.single.path, spacedPath);
      expect(resolved.single.title, 'Track One');
      expect(resolved.single.artist, 'Scanner Artist');
      expect(resolved.single.durationMillis, 123000);
    });

    test('recursively scans directories, skips hidden entries, and enriches from DB + scanner map', () async {
      final rootVisible = p.join(musicDir.path, 'db_song.flac');
      final subDir = Directory(p.join(musicDir.path, 'sub'))..createSync();
      final subVisible = p.join(subDir.path, 'scanner_song.m4a');
      final hiddenFile = p.join(musicDir.path, '.hidden.mp3');
      final hiddenDir = Directory(p.join(musicDir.path, '.Trash'))..createSync();
      final insideHiddenDir = p.join(hiddenDir.path, 'deleted.wav');
      final coverImage = p.join(musicDir.path, 'cover.jpg');

      await File(rootVisible).writeAsBytes(const <int>[0]);
      await File(subVisible).writeAsBytes(const <int>[0]);
      await File(hiddenFile).writeAsBytes(const <int>[0]);
      await File(insideHiddenDir).writeAsBytes(const <int>[0]);
      await File(coverImage).writeAsBytes(const <int>[0]);

      await db.insertOrUpdateSong(
        SongMetadata(
          path: rootVisible,
          title: 'From Database',
          album: 'DB Album',
          artist: 'DB Artist',
          duration: 245000,
          trackNumber: 3,
        ),
      );

      fakeScanner.metadataMap[subVisible] = SongMetadata(
        path: subVisible,
        title: 'From Scanner',
        album: 'Scanner Album',
        artist: 'Scanner Artist',
        duration: 180000,
        trackNumber: 7,
      );

      final service = container.read(mediaDropImportServiceProvider);
      final resolved = await service.resolvePathsToMusicFiles([musicDir.path]);

      expect(resolved, hasLength(2));
      final byPath = {for (final s in resolved) s.path: s};
      expect(byPath.keys, containsAll([rootVisible, subVisible]));
      expect(byPath.keys, isNot(contains(hiddenFile)));
      expect(byPath.keys, isNot(contains(insideHiddenDir)));
      expect(byPath.keys, isNot(contains(coverImage)));

      final dbSong = byPath[rootVisible]!;
      expect(dbSong.title, 'From Database');
      expect(dbSong.artist, 'DB Artist');
      expect(dbSong.album, 'DB Album');
      expect(dbSong.durationMillis, 245000);
      expect(dbSong.trackNumber, 3);

      final scanSong = byPath[subVisible]!;
      expect(scanSong.title, 'From Scanner');
      expect(scanSong.artist, 'Scanner Artist');
      expect(scanSong.album, 'Scanner Album');
      expect(scanSong.durationMillis, 180000);
      expect(scanSong.trackNumber, 7);
    });

    test('handleDroppedPaths appends and plays first track when insertIndex is null and playNow is true', () async {
      final pathA = p.join(musicDir.path, 'a.mp3');
      final pathB = p.join(musicDir.path, 'b.mp3');
      await File(pathA).writeAsBytes(const <int>[0]);
      await File(pathB).writeAsBytes(const <int>[0]);

      fakeScanner.metadataMap[pathA] = SongMetadata(
        path: pathA,
        title: 'Alpha',
        album: 'Alb',
        artist: 'Art',
      );
      fakeScanner.metadataMap[pathB] = SongMetadata(
        path: pathB,
        title: 'Beta',
        album: 'Alb',
        artist: 'Art',
      );

      final service = container.read(mediaDropImportServiceProvider);
      final dropped = await service.handleDroppedPaths(
        [pathA, pathB],
        playNow: true,
      );

      expect(dropped.map((e) => e.path), [pathA, pathB]);
      expect(fakeAudio.registeredPathBatches, [
        [pathA, pathB],
      ]);
      expect(fakeAudio.appendedBatches, hasLength(1));
      expect(fakeAudio.appendedBatches.single.map((e) => e.path), [pathA, pathB]);
      expect(fakeAudio.insertedCalls, isEmpty);
      expect(fakeAudio.playedFiles, [(path: pathA, name: 'a.mp3')]);
    });

    test('handleDroppedPaths inserts at explicit insertIndex without appending or playing', () async {
      final pathA = p.join(musicDir.path, 'insert.flac');
      await File(pathA).writeAsBytes(const <int>[0]);
      fakeScanner.metadataMap[pathA] = SongMetadata(
        path: pathA,
        title: 'Inserted',
        album: 'Alb',
        artist: 'Art',
      );

      final service = container.read(mediaDropImportServiceProvider);
      final dropped = await service.handleDroppedPaths(
        [pathA],
        insertIndex: 2,
        playNow: false,
      );

      expect(dropped, hasLength(1));
      expect(fakeAudio.insertedCalls, hasLength(1));
      expect(fakeAudio.insertedCalls.single.index, 2);
      expect(fakeAudio.insertedCalls.single.songs.single.path, pathA);
      expect(fakeAudio.appendedBatches, isEmpty);
      expect(fakeAudio.playedFiles, isEmpty);
    });

    test('addPathsToPlaylist resolves dropped paths and forwards them to PlaylistService', () async {
      final pathA = p.join(musicDir.path, 'playlist_song.mp3');
      await File(pathA).writeAsBytes(const <int>[0]);
      fakeScanner.metadataMap[pathA] = SongMetadata(
        path: pathA,
        title: 'For Playlist',
        album: 'Alb',
        artist: 'Art',
      );

      final service = container.read(mediaDropImportServiceProvider);
      final added = await service.addPathsToPlaylist('playlist-42', [pathA]);

      expect(added, hasLength(1));
      expect(added.single.path, pathA);
      expect(fakePlaylist.addedCalls, hasLength(1));
      expect(fakePlaylist.addedCalls.single.playlistId, 'playlist-42');
      expect(fakePlaylist.addedCalls.single.songs.single.path, pathA);
    });
  });
}
