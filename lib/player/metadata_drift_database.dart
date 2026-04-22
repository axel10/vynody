part of 'metadata_database.dart';

@DriftDatabase(
  tables: [
    Songs,
    LyricsCaches,
    AcoustidCaches,
    ReleaseCoverCaches,
    LyricsTranslationCaches,
  ],
)
class MetadataDriftDatabase extends _$MetadataDriftDatabase {
  MetadataDriftDatabase._() : super(_openConnection());

  static final MetadataDriftDatabase instance = MetadataDriftDatabase._();

  @override
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA busy_timeout = 5000');
    },
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _addColumnIfMissing(m, 'songs', 'artworkWidth', 'INTEGER');
        await _addColumnIfMissing(m, 'songs', 'artworkHeight', 'INTEGER');
      }
      if (from < 3) {
        await _addColumnIfMissing(m, 'songs', 'trackNumber', 'INTEGER');
      }
      if (from < 4) {
        await _addColumnIfMissing(m, 'songs', 'themeColorsBlob', 'BLOB');
      }
      if (from < 5) {
        await _addColumnIfMissing(m, 'songs', 'waveformBlob', 'BLOB');
      }
      if (from < 6) {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS lyrics_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cacheKey TEXT UNIQUE,
            filePath TEXT,
            title TEXT,
            artist TEXT,
            album TEXT,
            duration INTEGER,
            source TEXT,
            trackId INTEGER,
            score REAL,
            isSynced INTEGER,
            instrumental INTEGER,
            plainLyrics TEXT,
            syncedLyrics TEXT,
            syncedLinesJson TEXT,
            rawJson TEXT,
            updatedAtMillis INTEGER
          )
        ''');
      }
      if (from < 7) {
        await _addColumnIfMissing(m, 'songs', 'thumbnailPath', 'TEXT');
      }
      if (from < 8) {
        await _addColumnIfMissing(m, 'songs', 'lastModifiedTime', 'INTEGER');
      }
      if (from < 9) {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS acoustid_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fingerprint TEXT UNIQUE,
            durationSeconds INTEGER,
            resultsJson TEXT,
            updatedAtMillis INTEGER
          )
        ''');
      }
      if (from < 10) {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS release_cover_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            releaseId TEXT UNIQUE,
            largeUrl TEXT,
            thumbnailUrl TEXT,
            updatedAtMillis INTEGER
          )
        ''');
      }
      if (from < 11) {
        await _addColumnIfMissing(m, 'songs', 'genres', 'TEXT');
      }
      if (from < 12) {
        await _addColumnIfMissing(m, 'songs', 'createdAt', 'INTEGER');
      }
      if (from < 13) {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS lyrics_translation_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cacheKey TEXT,
            languageCode TEXT,
            translatedText TEXT,
            translatedLinesJson TEXT,
            provider TEXT,
            updatedAtMillis INTEGER,
            UNIQUE(cacheKey, languageCode)
          )
        ''');
      }
      if (from < 14) {
        await _addColumnIfMissing(m, 'lyrics_cache', 'cacheKey', 'TEXT');
      }
      if (from < 15) {
        await m.database.customStatement('DROP TABLE IF EXISTS lyrics_translation_cache');
        await m.database.customStatement('''
          CREATE TABLE lyrics_translation_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cacheKey TEXT,
            languageCode TEXT,
            translatedText TEXT,
            translatedLinesJson TEXT,
            provider TEXT,
            updatedAtMillis INTEGER,
            UNIQUE(cacheKey, languageCode)
          )
        ''');
      }
      if (from < 16) {
        await m.database.customStatement('DROP TABLE IF EXISTS acoustid_cache');
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS acoustid_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fingerprint TEXT UNIQUE,
            durationSeconds INTEGER,
            resultsJson TEXT,
            updatedAtMillis INTEGER
          )
        ''');
      }
      if (from < 17) {
        await _addColumnIfMissing(
          m,
          'lyrics_cache',
          'timelineOffsetMillis',
          'INTEGER',
        );
      }
      if (from < 18) {
        await _addColumnIfMissing(
          m,
          'songs',
          'metadataTextScanned',
          'INTEGER',
        );
        await _addColumnIfMissing(
          m,
          'songs',
          'metadataImgScanned',
          'INTEGER',
        );
      }
      if (from < 19) {
        await _addColumnIfMissing(m, 'songs', 'sourceFlags', 'INTEGER');
      }
    },
  );

  Future<void> _addColumnIfMissing(
    Migrator m,
    String table,
    String column,
    String sqlType,
  ) async {
    if (await _columnExists(table, column)) {
      return;
    }
    await m.database.customStatement(
      'ALTER TABLE $table ADD COLUMN $column $sqlType',
    );
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.data['name'] == column);
  }

  Stream<List<SongMetadata>> watchAllSongMetadata() {
    return (select(songs)
          ..orderBy([(t) => OrderingTerm(expression: t.path, mode: OrderingMode.asc)]))
        .watch()
        .map((rows) => rows.map(_songFromRow).toList(growable: false));
  }

  Future<List<SongMetadata>> getAllSongMetadata() async {
    final rows = await (select(songs)
          ..orderBy([(t) => OrderingTerm(expression: t.path, mode: OrderingMode.asc)]))
        .get();
    return rows.map(_songFromRow).toList(growable: false);
  }

  Stream<SongMetadata?> watchSongMetadata(String path) {
    return (select(songs)..where((t) => t.path.equals(path))..limit(1))
        .watchSingleOrNull()
        .map(_songOrNullFromRow);
  }

  Future<SongMetadata?> getSongMetadata(String path) async {
    final row = await (select(songs)..where((t) => t.path.equals(path))..limit(1))
        .getSingleOrNull();
    return _songOrNullFromRow(row);
  }

  Future<Map<String, SongMetadata>> getSongMetadataByPaths(
    Iterable<String> paths,
  ) async {
    final normalizedPaths = paths
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedPaths.isEmpty) {
      return {};
    }

    final rows = await (select(songs)
          ..where((t) => t.path.isIn(normalizedPaths)))
        .get();
    return {
      for (final row in rows) _pathLookupKey(row.path): _songFromRow(row),
    };
  }

  Future<void> insertOrUpdateSong(SongMetadata song) async {
    final mergedSourceFlags = _mergeSourceFlags(
      (await getSongMetadata(song.path))?.sourceFlags,
      song.sourceFlags,
    );

    await into(songs).insertOnConflictUpdate(
      _songCompanion(song.copyWith(sourceFlags: mergedSourceFlags)),
    );
  }

  Future<void> deleteSongByPath(String path) async {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) return;

    await (delete(songs)..where((t) => t.path.equals(normalizedPath))).go();
  }

  Future<void> clearAllSongs() async {
    await delete(songs).go();
  }

  Future<void> clearWaveformCache() async {
    await customStatement(
      'UPDATE songs SET waveformBlob = NULL WHERE waveformBlob IS NOT NULL',
    );
  }

  Future<int> syncSongSourcePresence({
    required int sourceMask,
    required Iterable<String> presentPaths,
    Iterable<String>? scopeRoots,
  }) async {
    final normalizedPresentPaths = presentPaths
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .map((path) => Platform.isWindows ? path.toLowerCase() : path)
        .toSet();
    final normalizedScopeRoots = scopeRoots == null
        ? const <String>[]
        : scopeRoots
            .map(_normalizePath)
            .where((path) => path.isNotEmpty)
            .toList(growable: false);

    var changedCount = 0;
    await transaction(() async {
      final rows = await select(songs).get();
      for (final row in rows) {
        final normalizedPath = _normalizePath(row.path);
        if (normalizedScopeRoots.isNotEmpty &&
            !_isWithinAnyRoot(normalizedPath, normalizedScopeRoots)) {
          continue;
        }

        final normalizedLookup = Platform.isWindows
            ? normalizedPath.toLowerCase()
            : normalizedPath;
        final currentFlags = row.sourceFlags ?? 0;
        final shouldHaveSource = normalizedPresentPaths.contains(
          normalizedLookup,
        );
        final hasSource = currentFlags == 0
            ? true
            : (currentFlags & sourceMask) != 0;

        int? nextFlags;
        if (shouldHaveSource) {
          nextFlags = currentFlags | sourceMask;
        } else if (hasSource) {
          nextFlags = currentFlags & ~sourceMask;
        }

        if (nextFlags == null || nextFlags == currentFlags) {
          continue;
        }

        if (nextFlags == 0) {
          await (delete(songs)..where((t) => t.path.equals(row.path))).go();
        } else {
          await (update(songs)..where((t) => t.path.equals(row.path))).write(
            SongsCompanion(sourceFlags: Value(nextFlags)),
          );
        }
        changedCount++;
      }
    });

    return changedCount;
  }

  Future<void> insertOrUpdateLyricsCache(LyricsCacheRecord record) async {
    await into(lyricsCaches).insertOnConflictUpdate(
      LyricsCachesCompanion(
        cacheKey: Value(record.cacheKey.trim()),
        source: Value(record.source.dbValue),
        isSynced: Value(record.isSynced),
        syncedLyrics: Value(record.syncedLyrics),
        syncedLinesJson: Value(
          jsonEncode(
            record.syncedLines.map((line) => line.toJson()).toList(growable: false),
          ),
        ),
        timelineOffsetMillis: Value(record.timelineOffsetMillis),
        updatedAtMillis: Value(record.updatedAtMillis),
      ),
    );
  }

  Future<LyricsCacheRecord?> getLyricsCache(String cacheKey) async {
    final row = await (select(lyricsCaches)
          ..where((t) => t.cacheKey.equals(cacheKey))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _lyricsCacheFromRow(row);
  }

  Future<void> clearLyricsCache() async {
    await delete(lyricsCaches).go();
  }

  Future<void> clearLyricsCacheByKey(String cacheKey) async {
    final normalizedCacheKey = cacheKey.trim();
    if (normalizedCacheKey.isEmpty) return;

    await (delete(lyricsCaches)
          ..where((t) => t.cacheKey.equals(normalizedCacheKey)))
        .go();
  }

  Future<void> insertOrUpdateLyricsTranslationCache(
    LyricsTranslationCacheRecord record,
  ) async {
    final normalizedCacheKey = record.cacheKey.trim();
    if (normalizedCacheKey.isNotEmpty) {
        await (delete(lyricsTranslationCaches)
              ..where(
                (t) =>
                    t.cacheKey.equals(normalizedCacheKey) &
                    t.languageCode.equals(record.languageCode),
              ))
          .go();
    }

    await into(lyricsTranslationCaches).insertOnConflictUpdate(
      LyricsTranslationCachesCompanion(
        cacheKey: Value(normalizedCacheKey),
        languageCode: Value(record.languageCode),
        translatedText: Value(record.translatedText),
        translatedLinesJson: Value(jsonEncode(record.translatedLines)),
        provider: Value(record.provider),
        updatedAtMillis: Value(record.updatedAtMillis),
      ),
    );
  }

  Future<List<LyricsTranslationCacheRecord>> getLyricsTranslationCaches(
    String cacheKey,
  ) async {
    final rows = await (select(lyricsTranslationCaches)
          ..where((t) => t.cacheKey.equals(cacheKey))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.updatedAtMillis,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
    return rows.map(_lyricsTranslationCacheFromRow).toList(growable: false);
  }

  Future<void> clearLyricsTranslationCache() async {
    await delete(lyricsTranslationCaches).go();
  }

  Future<void> clearLyricsTranslationCacheByKey(String cacheKey) async {
    final normalizedCacheKey = cacheKey.trim();
    if (normalizedCacheKey.isEmpty) return;

    await (delete(lyricsTranslationCaches)
          ..where((t) => t.cacheKey.equals(normalizedCacheKey)))
        .go();
  }

  Future<void> insertOrUpdateAcoustIDCache(
    AcoustIDCacheRecord record,
  ) async {
    await into(acoustidCaches).insertOnConflictUpdate(
      AcoustidCachesCompanion(
        fingerprint: Value(record.fingerprint),
        durationSeconds: Value(record.durationSeconds),
        resultsJson: Value(record.resultsJson),
        updatedAtMillis: Value(record.updatedAtMillis),
      ),
    );
  }

  Future<AcoustIDCacheRecord?> getAcoustIDCache(String fingerprint) async {
    final row = await (select(acoustidCaches)
          ..where((t) => t.fingerprint.equals(fingerprint))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _acoustidCacheFromRow(row);
  }

  Future<void> insertOrUpdateReleaseCoverCache(
    ReleaseCoverCacheRecord record,
  ) async {
    await into(releaseCoverCaches).insertOnConflictUpdate(
      ReleaseCoverCachesCompanion(
        releaseId: Value(record.releaseId),
        largeUrl: Value(record.largeUrl),
        thumbnailUrl: Value(record.thumbnailUrl),
        updatedAtMillis: Value(record.updatedAtMillis),
      ),
    );
  }

  Future<ReleaseCoverCacheRecord?> getReleaseCoverCache(String releaseId) async {
    final row = await (select(releaseCoverCaches)
          ..where((t) => t.releaseId.equals(releaseId))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _releaseCoverCacheFromRow(row);
  }

  List<String> get songPaths => const [];

  SongMetadata _songFromRow(Song row) {
    return SongMetadata(
      id: row.id,
      path: row.path,
      title: row.title ?? 'Unknown',
      album: row.album ?? 'Unknown',
      artist: row.artist ?? 'Unknown',
      duration: row.duration,
      artworkPath: row.artworkPath,
      thumbnailPath: row.thumbnailPath,
      artworkWidth: row.artworkWidth,
      artworkHeight: row.artworkHeight,
      trackNumber: row.trackNumber,
      sourceFlags: row.sourceFlags,
      themeColorsBlob: row.themeColorsBlob,
      waveformBlob: row.waveformBlob,
      lastModifiedTime: row.lastModifiedTime,
      metadataTextScanned: row.metadataTextScanned,
      metadataImgScanned: row.metadataImgScanned,
      createdAt: row.createdAt,
      genres: _decodeGenres(row.genres),
    );
  }

  SongMetadata? _songOrNullFromRow(Song? row) {
    return row == null ? null : _songFromRow(row);
  }

  SongsCompanion _songCompanion(SongMetadata song) {
    return SongsCompanion(
      path: Value(song.path),
      title: Value(song.title),
      album: Value(song.album),
      artist: Value(song.artist),
      duration: Value(song.duration),
      artworkPath: Value(song.artworkPath),
      thumbnailPath: Value(song.thumbnailPath),
      artworkWidth: Value(song.artworkWidth),
      artworkHeight: Value(song.artworkHeight),
      trackNumber: Value(song.trackNumber),
      sourceFlags: Value(song.sourceFlags),
      themeColorsBlob: Value(song.themeColorsBlob),
      waveformBlob: Value(song.waveformBlob),
      lastModifiedTime: Value(song.lastModifiedTime),
      metadataTextScanned: Value(song.metadataTextScanned),
      metadataImgScanned: Value(song.metadataImgScanned),
      createdAt: Value(song.createdAt),
      genres: Value(
        song.genres == null ? null : jsonEncode(song.genres),
      ),
    );
  }

  LyricsCacheRecord _lyricsCacheFromRow(LyricsCache row) {
    return LyricsCacheRecord(
      id: row.id,
      cacheKey: row.cacheKey,
      source: LyricsCacheSource.fromDbValue(row.source),
      isSynced: row.isSynced,
      syncedLyrics: row.syncedLyrics,
      syncedLines: _decodeSyncedLines(row.syncedLinesJson),
      timelineOffsetMillis: row.timelineOffsetMillis,
      updatedAtMillis: row.updatedAtMillis,
    );
  }

  AcoustIDCacheRecord _acoustidCacheFromRow(AcoustidCache row) {
    return AcoustIDCacheRecord(
      id: row.id,
      fingerprint: row.fingerprint,
      durationSeconds: row.durationSeconds,
      resultsJson: row.resultsJson,
      updatedAtMillis: row.updatedAtMillis,
    );
  }

  ReleaseCoverCacheRecord _releaseCoverCacheFromRow(ReleaseCoverCache row) {
    return ReleaseCoverCacheRecord(
      id: row.id,
      releaseId: row.releaseId,
      largeUrl: row.largeUrl,
      thumbnailUrl: row.thumbnailUrl,
      updatedAtMillis: row.updatedAtMillis,
    );
  }

  LyricsTranslationCacheRecord _lyricsTranslationCacheFromRow(
    LyricsTranslationCache row,
  ) {
    return LyricsTranslationCacheRecord(
      id: row.id,
      cacheKey: row.cacheKey,
      languageCode: row.languageCode,
      translatedText: row.translatedText,
      translatedLines: _decodeTranslatedLines(row.translatedLinesJson),
      provider: row.provider,
      updatedAtMillis: row.updatedAtMillis,
    );
  }

  List<LyricLine> _decodeSyncedLines(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) {
      return const <LyricLine>[];
    }
    final decodedValue = jsonDecode(rawValue);
    if (decodedValue is! List) return const <LyricLine>[];
    return decodedValue
        .whereType<Map>()
        .map((item) => LyricLine.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  List<String> _decodeTranslatedLines(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) {
      return const <String>[];
    }
    final decodedValue = jsonDecode(rawValue);
    if (decodedValue is! List) return const <String>[];
    return decodedValue
        .map((item) => item?.toString() ?? '')
        .toList(growable: false);
  }

  List<String>? _decodeGenres(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) return null;
    final decoded = jsonDecode(rawValue);
    if (decoded is! List) return null;
    return decoded.map((item) => item?.toString() ?? '').toList(growable: false);
  }
}

class Songs extends Table {
  @override
  String get tableName => 'songs';

  IntColumn get id => integer().autoIncrement().named('id')();
  TextColumn get path => text().named('path')();
  TextColumn get title => text().nullable().named('title')();
  TextColumn get album => text().nullable().named('album')();
  TextColumn get artist => text().nullable().named('artist')();
  IntColumn get duration => integer().nullable().named('duration')();
  TextColumn get artworkPath => text().nullable().named('artworkPath')();
  TextColumn get thumbnailPath => text().nullable().named('thumbnailPath')();
  IntColumn get artworkWidth => integer().nullable().named('artworkWidth')();
  IntColumn get artworkHeight => integer().nullable().named('artworkHeight')();
  IntColumn get trackNumber => integer().nullable().named('trackNumber')();
  IntColumn get sourceFlags => integer().nullable().named('sourceFlags')();
  BlobColumn get themeColorsBlob => blob().nullable().named('themeColorsBlob')();
  BlobColumn get waveformBlob => blob().nullable().named('waveformBlob')();
  IntColumn get lastModifiedTime => integer().nullable().named('lastModifiedTime')();
  IntColumn get metadataTextScanned => integer().nullable().named('metadataTextScanned')();
  IntColumn get metadataImgScanned => integer().nullable().named('metadataImgScanned')();
  IntColumn get createdAt => integer().nullable().named('createdAt')();
  TextColumn get genres => text().nullable().named('genres')();

  @override
  List<String> get customConstraints => const ['UNIQUE(path)'];
}

class LyricsCaches extends Table {
  @override
  String get tableName => 'lyrics_cache';

  IntColumn get id => integer().autoIncrement().named('id')();
  TextColumn get cacheKey => text().named('cacheKey')();
  TextColumn get source => text().named('source')();
  BoolColumn get isSynced => boolean().named('isSynced')();
  TextColumn get syncedLyrics => text().nullable().named('syncedLyrics')();
  TextColumn get syncedLinesJson => text().named('syncedLinesJson')();
  IntColumn get timelineOffsetMillis => integer().named('timelineOffsetMillis')();
  IntColumn get updatedAtMillis => integer().named('updatedAtMillis')();

  @override
  List<String> get customConstraints => const ['UNIQUE(cacheKey)'];
}

class AcoustidCaches extends Table {
  @override
  String get tableName => 'acoustid_cache';

  IntColumn get id => integer().autoIncrement().named('id')();
  TextColumn get fingerprint => text().named('fingerprint')();
  IntColumn get durationSeconds => integer().named('durationSeconds')();
  TextColumn get resultsJson => text().named('resultsJson')();
  IntColumn get updatedAtMillis => integer().named('updatedAtMillis')();

  @override
  List<String> get customConstraints => const ['UNIQUE(fingerprint)'];
}

class ReleaseCoverCaches extends Table {
  @override
  String get tableName => 'release_cover_cache';

  IntColumn get id => integer().autoIncrement().named('id')();
  TextColumn get releaseId => text().named('releaseId')();
  TextColumn get largeUrl => text().nullable().named('largeUrl')();
  TextColumn get thumbnailUrl => text().nullable().named('thumbnailUrl')();
  IntColumn get updatedAtMillis => integer().named('updatedAtMillis')();

  @override
  List<String> get customConstraints => const ['UNIQUE(releaseId)'];
}

class LyricsTranslationCaches extends Table {
  @override
  String get tableName => 'lyrics_translation_cache';

  IntColumn get id => integer().autoIncrement().named('id')();
  TextColumn get cacheKey => text().named('cacheKey')();
  TextColumn get languageCode => text().named('languageCode')();
  TextColumn get translatedText => text().named('translatedText')();
  TextColumn get translatedLinesJson => text().named('translatedLinesJson')();
  TextColumn get provider => text().nullable().named('provider')();
  IntColumn get updatedAtMillis => integer().named('updatedAtMillis')();

  @override
  List<String> get customConstraints => const [
    'UNIQUE(cacheKey, languageCode)',
  ];
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'metadata.db'));
    return NativeDatabase(file);
  });
}
