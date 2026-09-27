import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_sorting.dart';

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

  Future<List<SongMetadata>> getSongsUnderPath(String rootPath) {
    return _database.getSongsUnderPath(rootPath);
  }

  Future<int> getSongCountUnderPath(String rootPath) {
    return _database.getSongCountUnderPath(rootPath);
  }

  Future<int> getSongDurationUnderPath(String rootPath) {
    return _database.getSongDurationUnderPath(rootPath);
  }

  Future<SongMetadata?> getRepresentativeSongUnderPath(
    String rootPath, {
    SortCriteria criteria = SortCriteria.filename,
    SortOrder order = SortOrder.ascending,
  }) {
    return _database.getRepresentativeSongUnderPath(
      rootPath,
      criteria: criteria,
      order: order,
    );
  }

  Future<void> batchUpsertFolderCovers(Map<String, String> covers) {
    return _database.batchUpsertFolderCovers(covers);
  }

  Future<void> upsertFolderCover(String folderPath, String songPath) {
    return _database.upsertFolderCover(folderPath, songPath);
  }

  Future<Map<String, String>> getAllFolderCovers() {
    return _database.getAllFolderCovers();
  }

  Future<Map<String, SongMetadata>> getAllFolderRepresentativeMetadata() {
    return _database.getAllFolderRepresentativeMetadata();
  }

  Future<SongMetadata?> getFolderRepresentativeMetadata(String folderPath) {
    return _database.getFolderRepresentativeMetadata(folderPath);
  }

  Future<void> removeFolderCoversForPaths(Iterable<String> folderPaths) {
    return _database.removeFolderCoversForPaths(folderPaths);
  }

  Future<void> removeFolderCoversUnderRoots(Iterable<String> rootPaths) {
    return _database.removeFolderCoversUnderRoots(rootPaths);
  }

  Future<List<SongMetadata>> getSystemMediaSongs() {
    return _database.getSystemMediaSongs();
  }

  Future<List<SongMetadata>> searchSongs(String query, {String? folderPath}) {
    return _database.searchSongs(query, folderPath: folderPath);
  }

  Future<List<String>> searchFolderPaths(String query) {
    return _database.searchFolderPaths(query);
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

  Future<void> bindSongsToRootBatch(
    Iterable<String> songPaths,
    String rootPath,
  ) {
    return _database.bindSongsToRootBatch(songPaths, rootPath);
  }

  Future<void> unbindRootPaths(Iterable<String> rootPaths) {
    return _database.unbindRootPaths(rootPaths);
  }

  Future<RootScanSweepResult> sweepOrphanSongs({int chunkSize = 2000}) {
    return _database.sweepOrphanSongs(chunkSize: chunkSize);
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
