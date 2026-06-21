import 'package:vynody/player/metadata/metadata_database.dart';

class ScannerRepository {
  ScannerRepository({MetadataDatabase? database})
    : _database = database ?? MetadataDatabase();

  final MetadataDatabase _database;

  Future<void> ensureOpen() {
    return _database.ensureOpen();
  }

  Stream<List<SongMetadata>> watchAllSongMetadata() {
    return _database.watchAllSongMetadata();
  }

  Future<List<SongMetadata>> getAllSongMetadata() {
    return _database.getAllSongMetadata();
  }

  Future<SongMetadata?> getSongMetadata(String path) {
    return _database.getSongMetadata(path);
  }

  Future<Map<String, SongMetadata>> getSongMetadataByPaths(
    Iterable<String> paths,
  ) {
    return _database.getSongMetadataByPaths(paths);
  }

  Future<void> insertOrUpdateSong(
    SongMetadata song, {
    int? rootScanSessionId,
  }) {
    return _database.insertOrUpdateSong(
      song,
      rootScanSessionId: rootScanSessionId,
    );
  }

  Future<void> insertOrUpdateSongsMerged(
    Iterable<SongMetadata> songs, {
    int? rootScanSessionId,
  }) {
    return _database.insertOrUpdateSongsMerged(
      songs,
      rootScanSessionId: rootScanSessionId,
    );
  }

  Future<void> deleteSongByPath(String path) {
    return _database.deleteSongByPath(path);
  }

  Future<void> syncSongSourcePresence({
    required int sourceMask,
    required Iterable<String> presentPaths,
    Iterable<String>? scopeRoots,
  }) {
    return _database.syncSongSourcePresence(
      sourceMask: sourceMask,
      presentPaths: presentPaths,
      scopeRoots: scopeRoots,
    );
  }

  Future<void> markRootScanSeenWithToken(
    Iterable<String> paths, {
    required int scanToken,
    required int sourceMask,
  }) {
    return _database.markRootScanSeenWithToken(
      paths,
      scanToken: scanToken,
      sourceMask: sourceMask,
    );
  }

  Future<RootScanSweepResult> sweepRootScanState({
    required int scanToken,
    required int sourceMask,
    required Iterable<String> activeRoots,
  }) {
    return _database.sweepRootScanState(
      scanToken: scanToken,
      sourceMask: sourceMask,
      activeRoots: activeRoots,
    );
  }

  Future<void> clearAll() {
    return _database.clearAll();
  }

  Future<void> clearSongsExceptExternal() {
    return _database.clearSongsExceptExternal();
  }

  Future<void> migrateLinuxRootPath(String oldRoot, String newRoot) {
    return _database.migrateLinuxRootPath(oldRoot, newRoot);
  }
}
