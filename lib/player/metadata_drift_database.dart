part of 'metadata_database.dart';

@DriftDatabase(
  tables: [
    Songs,
    SongPlayHistories,
    LyricsCaches,
    AcoustidCaches,
    ReleaseCoverCaches,
    LyricsTranslationCaches,
    ArtistCaches,
    ArtistImageCaches,
  ],
)
class MetadataDriftDatabase extends _$MetadataDriftDatabase {
  MetadataDriftDatabase._() : super(_openConnection());

  static final MetadataDriftDatabase instance = MetadataDriftDatabase._();

  @override
  int get schemaVersion => 26;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA busy_timeout = 5000');
      await _repairLegacyLyricsCacheRows();
      await _repairLegacyArtistCacheRows();
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
        await m.database.customStatement(
          'DROP TABLE IF EXISTS lyrics_translation_cache',
        );
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
        await _repairLegacyLyricsCacheRows();
      }
      if (from < 18) {
        await _addColumnIfMissing(m, 'songs', 'metadataTextScanned', 'INTEGER');
        await _addColumnIfMissing(m, 'songs', 'metadataImgScanned', 'INTEGER');
      }
      if (from < 19) {
        await _addColumnIfMissing(m, 'songs', 'sourceFlags', 'INTEGER');
      }
      if (from < 20) {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS artist_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            queryKey TEXT UNIQUE,
            artistId TEXT,
            artistName TEXT,
            sortName TEXT,
            disambiguation TEXT,
            country TEXT,
            imageFileTitle TEXT,
            imageUrl TEXT,
            thumbnailUrl TEXT,
            areaName TEXT,
            beginDate TEXT,
            endDate TEXT,
            tagsJson TEXT,
            rawSearchJson TEXT,
            rawDetailJson TEXT,
            noData INTEGER,
            updatedAtMillis INTEGER
          )
        ''');
      }
      if (from < 21) {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS artist_image_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            artistId TEXT UNIQUE,
            imagePath TEXT,
            sourceUrl TEXT,
            width INTEGER,
            height INTEGER,
            updatedAtMillis INTEGER
          )
        ''');
      }
      if (from < 22) {
        await _addColumnIfMissing(
          m,
          'artist_cache',
          'imageFetchCompleted',
          'INTEGER',
        );
        await m.database.customStatement('''
          UPDATE artist_cache
          SET imageFetchCompleted = 0
          WHERE imageFetchCompleted IS NULL
        ''');
      }
      if (from < 23) {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS song_play_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            songPath TEXT NOT NULL,
            playedAt INTEGER NOT NULL,
            playedDurationMillis INTEGER,
            songDurationMillis INTEGER,
            source TEXT
          )
        ''');
        await m.database.customStatement('''
          CREATE INDEX IF NOT EXISTS idx_song_play_history_song_path_played_at
          ON song_play_history(songPath, playedAt DESC)
        ''');
        await m.database.customStatement('''
          CREATE INDEX IF NOT EXISTS idx_song_play_history_played_at
          ON song_play_history(playedAt DESC)
        ''');
      }
      if (from < 24) {
        await _addColumnIfMissing(
          m,
          'songs',
          'lastSeenRootScanSessionId',
          'INTEGER',
        );
      }
      if (from < 25) {
        await _addColumnIfMissing(
          m,
          'songs',
          'lastSeenRootScanToken',
          'INTEGER',
        );
        await _addColumnIfMissing(m, 'songs', 'missingReason', 'TEXT');
        await _addColumnIfMissing(m, 'songs', 'deletedAt', 'INTEGER');
      }
      if (from < 26) {
        await _addColumnIfMissing(m, 'songs', 'isSoftDeleted', 'INTEGER');
        await m.database.customStatement('''
          UPDATE songs
          SET isSoftDeleted = 0
          WHERE isSoftDeleted IS NULL
        ''');
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

  Future<void> _repairLegacyLyricsCacheRows() async {
    if (!await _columnExists('lyrics_cache', 'timelineOffsetMillis')) {
      return;
    }

    await customStatement('''
      UPDATE lyrics_cache
      SET timelineOffsetMillis = 0
      WHERE timelineOffsetMillis IS NULL
    ''');
  }

  Future<void> _repairLegacyArtistCacheRows() async {
    if (await _columnExists('artist_cache', 'noData')) {
      await customStatement('''
        UPDATE artist_cache
        SET noData = 0
        WHERE noData IS NULL
      ''');
    }

    if (await _columnExists('artist_cache', 'imageFetchCompleted')) {
      await customStatement('''
        UPDATE artist_cache
        SET imageFetchCompleted = 0
        WHERE imageFetchCompleted IS NULL
      ''');
    }
  }

  Stream<List<SongMetadata>> watchAllSongMetadata() {
    return customSelect(
      '''
      SELECT *
      FROM songs
      WHERE COALESCE(isSoftDeleted, 0) = 0
      ORDER BY LOWER(path) ASC
      ''',
      readsFrom: {songs},
    ).watch().map(
      (rows) => rows.map(_songFromQueryRow).toList(growable: false),
    );
  }

  Future<List<SongMetadata>> getAllSongMetadata() async {
    final rows = await customSelect(
      '''
      SELECT *
      FROM songs
      WHERE COALESCE(isSoftDeleted, 0) = 0
      ORDER BY LOWER(path) ASC
      ''',
      readsFrom: {songs},
    ).get();
    return rows.map(_songFromQueryRow).toList(growable: false);
  }

  Stream<SongMetadata?> watchSongMetadata(String path) {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) {
      return Stream<SongMetadata?>.value(null);
    }
    return customSelect(
      '''
      SELECT *
      FROM songs
      WHERE path = ?
        AND COALESCE(isSoftDeleted, 0) = 0
      LIMIT 1
      ''',
      variables: [Variable(normalizedPath)],
      readsFrom: {songs},
    ).watchSingleOrNull().map(
      (row) => row == null ? null : _songFromQueryRow(row),
    );
  }

  Future<SongMetadata?> getSongMetadata(String path) async {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) {
      return null;
    }
    final row = await customSelect(
      '''
      SELECT *
      FROM songs
      WHERE path = ?
        AND COALESCE(isSoftDeleted, 0) = 0
      LIMIT 1
      ''',
      variables: [Variable(normalizedPath)],
      readsFrom: {songs},
    ).getSingleOrNull();
    return row == null ? null : _songFromQueryRow(row);
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

    final rows = await customSelect(
      '''
      SELECT *
      FROM songs
      WHERE path IN (${List.filled(normalizedPaths.length, '?').join(', ')})
        AND COALESCE(isSoftDeleted, 0) = 0
      ''',
      variables: normalizedPaths.map(Variable.new).toList(growable: false),
      readsFrom: {songs},
    ).get();
    return {
      for (final row in rows)
        _pathLookupKey(row.read<String>('path')): _songFromQueryRow(row),
    };
  }

  Future<void> insertOrUpdateSong(
    SongMetadata song, {
    int? rootScanSessionId,
  }) async {
    final existing = await getSongMetadata(song.path);
    final mergedSourceFlags = _mergeSourceFlags(
      existing?.sourceFlags,
      song.sourceFlags,
    );

    final updatedSong = song.copyWith(sourceFlags: mergedSourceFlags);
    final companion = _songCompanion(
      updatedSong,
      lastSeenRootScanSessionId: rootScanSessionId,
    );

    if (existing != null) {
      await (update(
        songs,
      )..where((t) => t.path.equals(existing.path))).write(companion);
      return;
    }

    await into(songs).insert(companion);
  }

  Future<void> insertOrUpdateSongsMerged(
    Iterable<SongMetadata> songsList, {
    int? rootScanSessionId,
  }) async {
    final normalizedSongs = songsList.toList(growable: false);
    if (normalizedSongs.isEmpty) return;
    final existingByPath = await getSongMetadataByPaths(
      normalizedSongs.map((song) => song.path),
    );

    await transaction(() async {
      for (final song in normalizedSongs) {
        final existing = existingByPath[_pathLookupKey(song.path)];
        await into(songs).insertOnConflictUpdate(
          _songCompanion(
            song.copyWith(
              sourceFlags: _mergeSourceFlags(
                existing?.sourceFlags,
                song.sourceFlags,
              ),
            ),
            lastSeenRootScanSessionId: rootScanSessionId,
          ),
        );
      }
    });
  }

  Future<void> recordSongPlayback({
    required String songPath,
    required int playedAt,
    int? playedDurationMillis,
    int? songDurationMillis,
    String? source,
  }) async {
    final normalizedPath = _normalizePath(songPath);
    if (normalizedPath.isEmpty) return;

    await into(songPlayHistories).insert(
      SongPlayHistoriesCompanion.insert(
        songPath: normalizedPath,
        playedAt: playedAt,
        playedDurationMillis: Value(playedDurationMillis),
        songDurationMillis: Value(songDurationMillis),
        source: Value(source?.trim().isEmpty == true ? null : source?.trim()),
      ),
    );
  }

  Stream<List<LibraryInsightSongRecord>> watchRecentlyAddedSongs({
    int? startAtMillis,
  }) {
    final buffer = StringBuffer()
      ..writeln('SELECT')
      ..writeln('  s.id,')
      ..writeln('  s.path,')
      ..writeln('  s.title,')
      ..writeln('  s.album,')
      ..writeln('  s.artist,')
      ..writeln('  s.duration,')
      ..writeln('  s.artworkPath,')
      ..writeln('  s.thumbnailPath,')
      ..writeln('  s.artworkWidth,')
      ..writeln('  s.artworkHeight,')
      ..writeln('  s.trackNumber,')
      ..writeln('  s.sourceFlags,')
      ..writeln('  s.themeColorsBlob,')
      ..writeln('  s.waveformBlob,')
      ..writeln('  s.lastModifiedTime,')
      ..writeln('  s.metadataTextScanned,')
      ..writeln('  s.metadataImgScanned,')
      ..writeln('  s.createdAt,')
      ..writeln('  s.genres,')
      ..writeln('  0 AS playCount,')
      ..writeln('  NULL AS lastPlayedAt')
      ..writeln('FROM songs s')
      ..writeln('WHERE s.createdAt IS NOT NULL')
      ..writeln('  AND COALESCE(s.isSoftDeleted, 0) = 0');

    final variables = <Variable<Object>>[];
    if (startAtMillis != null) {
      buffer.writeln('  AND s.createdAt >= ?');
      variables.add(Variable.withInt(startAtMillis));
    }

    buffer
      ..writeln('ORDER BY s.createdAt DESC,')
      ..writeln("LOWER(COALESCE(s.title, '')) ASC,")
      ..writeln('LOWER(s.path) ASC');

    return customSelect(
      buffer.toString(),
      variables: variables,
      readsFrom: {songs},
    ).watch().map(
      (rows) => rows
          .map((row) => _libraryInsightSongRecordFromRow(row))
          .toList(growable: false),
    );
  }

  Stream<List<LibraryInsightSongRecord>> watchMostPlayedSongs({
    int? startAtMillis,
  }) {
    final buffer = StringBuffer()
      ..writeln('SELECT')
      ..writeln('  s.id,')
      ..writeln('  s.path,')
      ..writeln('  s.title,')
      ..writeln('  s.album,')
      ..writeln('  s.artist,')
      ..writeln('  s.duration,')
      ..writeln('  s.artworkPath,')
      ..writeln('  s.thumbnailPath,')
      ..writeln('  s.artworkWidth,')
      ..writeln('  s.artworkHeight,')
      ..writeln('  s.trackNumber,')
      ..writeln('  s.sourceFlags,')
      ..writeln('  s.themeColorsBlob,')
      ..writeln('  s.waveformBlob,')
      ..writeln('  s.lastModifiedTime,')
      ..writeln('  s.metadataTextScanned,')
      ..writeln('  s.metadataImgScanned,')
      ..writeln('  s.createdAt,')
      ..writeln('  s.genres,')
      ..writeln('  COUNT(h.id) AS playCount,')
      ..writeln('  MAX(h.playedAt) AS lastPlayedAt')
      ..writeln('FROM songs s')
      ..writeln('JOIN song_play_history h ON h.songPath = s.path')
      ..writeln('WHERE COALESCE(s.isSoftDeleted, 0) = 0');

    final variables = <Variable<Object>>[];
    if (startAtMillis != null) {
      buffer.writeln('  AND h.playedAt >= ?');
      variables.add(Variable.withInt(startAtMillis));
    }

    buffer
      ..writeln('GROUP BY s.path')
      ..writeln('ORDER BY playCount DESC,')
      ..writeln('lastPlayedAt DESC,')
      ..writeln("LOWER(COALESCE(s.title, '')) ASC,")
      ..writeln('LOWER(s.path) ASC');

    return customSelect(
      buffer.toString(),
      variables: variables,
      readsFrom: {songs, songPlayHistories},
    ).watch().map(
      (rows) => rows
          .map((row) => _libraryInsightSongRecordFromRow(row))
          .toList(growable: false),
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

  Future<void> markRootScanSeenWithToken(
    Iterable<String> paths, {
    required int scanToken,
    required int sourceMask,
  }) async {
    final normalizedPaths = paths
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedPaths.isEmpty) {
      return;
    }

    const batchSize = 200;
    for (var start = 0; start < normalizedPaths.length; start += batchSize) {
      final end = start + batchSize < normalizedPaths.length
          ? start + batchSize
          : normalizedPaths.length;
      final chunk = normalizedPaths.sublist(start, end);
      await customStatement(
        '''
        UPDATE songs
        SET sourceFlags = CASE
              WHEN sourceFlags IS NULL OR sourceFlags = 0 THEN ?
              ELSE sourceFlags | ?
            END,
            lastSeenRootScanToken = ?,
            isSoftDeleted = 0,
            missingReason = NULL,
            deletedAt = NULL
        WHERE path IN (${List.filled(chunk.length, '?').join(', ')})
        ''',
        <Object>[sourceMask, sourceMask, scanToken, ...chunk],
      );
    }
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

  Future<RootScanSweepResult> sweepRootScanState({
    required int scanToken,
    required int sourceMask,
    required Iterable<String> activeRoots,
  }) async {
    final normalizedActiveRoots = activeRoots
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    final candidateRows = await customSelect(
      '''
      SELECT path, sourceFlags, lastSeenRootScanToken
      FROM songs
      WHERE sourceFlags IS NULL
         OR sourceFlags = 0
         OR (sourceFlags & ?) != 0
      ''',
      variables: [Variable(sourceMask)],
      readsFrom: {songs},
    ).get();

    if (candidateRows.isEmpty) {
      return const RootScanSweepResult(
        deletedPaths: <String>[],
        softDeletedPaths: <String>[],
      );
    }

    final deletedPaths = <String>[];
    final softDeletedPaths = <String>[];
    final deletedAt = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      for (final row in candidateRows) {
        final path = row.read<String>('path');
        final currentFlags = row.read<int?>('sourceFlags') ?? 0;
        final seenToken = row.read<int?>('lastSeenRootScanToken');
        if (seenToken == scanToken) {
          continue;
        }

        if (_isWithinAnyRoot(path, normalizedActiveRoots)) {
          await customStatement(
            '''
            UPDATE songs
            SET isSoftDeleted = 1,
                missingReason = ?,
                deletedAt = ?
            WHERE path = ?
            ''',
            <Object>['missing_on_disk', deletedAt, path],
          );
          softDeletedPaths.add(path);
          continue;
        }

        final nextFlags = currentFlags == 0 ? 0 : currentFlags & ~sourceMask;
        if (nextFlags == 0) {
          await (delete(songs)..where((t) => t.path.equals(path))).go();
        } else {
          await customStatement(
            '''
            UPDATE songs
            SET sourceFlags = ?,
                isSoftDeleted = 0,
                missingReason = NULL,
                deletedAt = NULL
            WHERE path = ?
            ''',
            <Object>[nextFlags, path],
          );
        }
        deletedPaths.add(path);
      }
    });

    return RootScanSweepResult(
      deletedPaths: deletedPaths,
      softDeletedPaths: softDeletedPaths,
    );
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
            record.syncedLines
                .map((line) => line.toJson())
                .toList(growable: false),
          ),
        ),
        timelineOffsetMillis: Value(record.timelineOffsetMillis),
        updatedAtMillis: Value(record.updatedAtMillis),
      ),
    );
  }

  Future<LyricsCacheRecord?> getLyricsCache(String cacheKey) async {
    final row =
        await (select(lyricsCaches)
              ..where((t) => t.cacheKey.equals(cacheKey))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _lyricsCacheFromRow(row);
  }

  Stream<LyricsCacheRecord?> watchLyricsCache(String cacheKey) {
    final normalizedCacheKey = cacheKey.trim();
    if (normalizedCacheKey.isEmpty) {
      return Stream.value(null);
    }

    return (select(lyricsCaches)
          ..where((t) => t.cacheKey.equals(normalizedCacheKey))
          ..limit(1))
        .watchSingleOrNull()
        .map((row) => row == null ? null : _lyricsCacheFromRow(row));
  }

  Future<void> clearLyricsCache() async {
    await delete(lyricsCaches).go();
  }

  Future<void> clearLyricsCacheByKey(String cacheKey) async {
    final normalizedCacheKey = cacheKey.trim();
    if (normalizedCacheKey.isEmpty) return;

    await (delete(
      lyricsCaches,
    )..where((t) => t.cacheKey.equals(normalizedCacheKey))).go();
  }

  Future<void> insertOrUpdateLyricsTranslationCache(
    LyricsTranslationCacheRecord record,
  ) async {
    final normalizedCacheKey = record.cacheKey.trim();
    if (normalizedCacheKey.isNotEmpty) {
      await (delete(lyricsTranslationCaches)..where(
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
    final rows =
        await (select(lyricsTranslationCaches)
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

  Stream<List<LyricsTranslationCacheRecord>> watchLyricsTranslationCaches(
    String cacheKey,
  ) {
    final normalizedCacheKey = cacheKey.trim();
    if (normalizedCacheKey.isEmpty) {
      return Stream.value(const <LyricsTranslationCacheRecord>[]);
    }

    return (select(lyricsTranslationCaches)
          ..where((t) => t.cacheKey.equals(normalizedCacheKey))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.updatedAtMillis,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch()
        .map(
          (rows) =>
              rows.map(_lyricsTranslationCacheFromRow).toList(growable: false),
        );
  }

  Future<void> clearLyricsTranslationCache() async {
    await delete(lyricsTranslationCaches).go();
  }

  Future<void> clearLyricsTranslationCacheByKey(String cacheKey) async {
    final normalizedCacheKey = cacheKey.trim();
    if (normalizedCacheKey.isEmpty) return;

    await (delete(
      lyricsTranslationCaches,
    )..where((t) => t.cacheKey.equals(normalizedCacheKey))).go();
  }

  Future<void> insertOrUpdateAcoustIDCache(AcoustIDCacheRecord record) async {
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
    final row =
        await (select(acoustidCaches)
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

  Future<ReleaseCoverCacheRecord?> getReleaseCoverCache(
    String releaseId,
  ) async {
    final row =
        await (select(releaseCoverCaches)
              ..where((t) => t.releaseId.equals(releaseId))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _releaseCoverCacheFromRow(row);
  }

  Future<void> insertOrUpdateArtistCache(ArtistCacheRecord record) async {
    final normalizedKey = _normalizeArtistCacheKey(record.queryKey);
    final companion = ArtistCachesCompanion(
      queryKey: Value(normalizedKey),
      artistId: Value(record.artistId),
      artistName: Value(record.artistName),
      sortName: Value(record.sortName),
      disambiguation: Value(record.disambiguation),
      country: Value(record.country),
      imageFileTitle: Value(record.imageFileTitle),
      imageUrl: Value(record.imageUrl),
      thumbnailUrl: Value(record.thumbnailUrl),
      areaName: Value(record.areaName),
      beginDate: Value(record.beginDate),
      endDate: Value(record.endDate),
      tagsJson: Value(record.tagsJson),
      rawSearchJson: Value(record.rawSearchJson),
      rawDetailJson: Value(record.rawDetailJson),
      noData: Value(record.noData),
      imageFetchCompleted: Value(record.imageFetchCompleted),
      updatedAtMillis: Value(record.updatedAtMillis),
    );

    final existing = await getArtistCache(normalizedKey);
    if (existing != null) {
      await (update(
        artistCaches,
      )..where((t) => t.queryKey.equals(normalizedKey))).write(companion);
      return;
    }

    await into(artistCaches).insert(companion);
  }

  Future<void> insertOrUpdateArtistImageCache(
    ArtistImageCacheRecord record,
  ) async {
    await into(artistImageCaches).insertOnConflictUpdate(
      ArtistImageCachesCompanion(
        artistId: Value(record.artistId),
        imagePath: Value(record.imagePath),
        sourceUrl: Value(record.sourceUrl),
        width: Value(record.width),
        height: Value(record.height),
        updatedAtMillis: Value(record.updatedAtMillis),
      ),
    );
  }

  Future<ArtistCacheRecord?> getArtistCache(String queryKey) async {
    final normalized = _normalizeArtistCacheKey(queryKey);
    if (normalized.isEmpty) return null;
    final row =
        await (select(artistCaches)
              ..where((t) => t.queryKey.equals(normalized))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _artistCacheFromRow(row);
  }

  Future<ArtistImageCacheRecord?> getArtistImageCache(String artistId) async {
    final normalized = artistId.trim();
    if (normalized.isEmpty) return null;
    final row =
        await (select(artistImageCaches)
              ..where((t) => t.artistId.equals(normalized))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _artistImageCacheFromRow(row);
  }

  Future<Map<String, ArtistImageCacheRecord>> getArtistImageCachesByIds(
    Iterable<String> artistIds,
  ) async {
    final normalizedIds = artistIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) return const {};

    final rows = await (select(
      artistImageCaches,
    )..where((t) => t.artistId.isIn(normalizedIds))).get();
    return {
      for (final row in rows) row.artistId: _artistImageCacheFromRow(row),
    };
  }

  Future<Map<String, ArtistCacheRecord>> getArtistCachesByKeys(
    Iterable<String> queryKeys,
  ) async {
    final normalizedKeys = queryKeys
        .map(_normalizeArtistCacheKey)
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedKeys.isEmpty) return const {};

    final rows = await (select(
      artistCaches,
    )..where((t) => t.queryKey.isIn(normalizedKeys))).get();
    return {for (final row in rows) row.queryKey: _artistCacheFromRow(row)};
  }

  Future<List<ArtistCacheRecord>> getAllArtistCaches() async {
    final rows =
        await (select(artistCaches)..orderBy([
              (t) =>
                  OrderingTerm(expression: t.queryKey, mode: OrderingMode.asc),
            ]))
            .get();
    return rows.map(_artistCacheFromRow).toList(growable: false);
  }

  List<String> get songPaths => const [];

  SongMetadata _songFromQueryRow(QueryRow row) {
    return SongMetadata(
      id: row.read<int?>('id'),
      path: row.read<String>('path'),
      title: row.read<String?>('title') ?? 'Unknown',
      album: row.read<String?>('album') ?? 'Unknown',
      artist: row.read<String?>('artist') ?? 'Unknown',
      duration: row.read<int?>('duration'),
      artworkPath: row.read<String?>('artworkPath'),
      thumbnailPath: row.read<String?>('thumbnailPath'),
      artworkWidth: row.read<int?>('artworkWidth'),
      artworkHeight: row.read<int?>('artworkHeight'),
      trackNumber: row.read<int?>('trackNumber'),
      sourceFlags: row.read<int?>('sourceFlags'),
      themeColorsBlob: row.read<Uint8List?>('themeColorsBlob'),
      waveformBlob: row.read<Uint8List?>('waveformBlob'),
      lastModifiedTime: row.read<int?>('lastModifiedTime'),
      metadataTextScanned: row.read<int?>('metadataTextScanned'),
      metadataImgScanned: row.read<int?>('metadataImgScanned'),
      createdAt: row.read<int?>('createdAt'),
      genres: _decodeGenres(row.read<String?>('genres')),
    );
  }

  SongsCompanion _songCompanion(
    SongMetadata song, {
    int? lastSeenRootScanSessionId,
  }) {
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
      genres: Value(song.genres == null ? null : jsonEncode(song.genres)),
      lastSeenRootScanSessionId: lastSeenRootScanSessionId == null
          ? const Value.absent()
          : Value(lastSeenRootScanSessionId),
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

  ArtistCacheRecord _artistCacheFromRow(ArtistCache row) {
    return ArtistCacheRecord(
      id: row.id,
      queryKey: row.queryKey,
      artistId: row.artistId,
      artistName: row.artistName,
      sortName: row.sortName,
      disambiguation: row.disambiguation,
      country: row.country,
      imageFileTitle: row.imageFileTitle,
      imageUrl: row.imageUrl,
      thumbnailUrl: row.thumbnailUrl,
      areaName: row.areaName,
      beginDate: row.beginDate,
      endDate: row.endDate,
      tagsJson: row.tagsJson,
      rawSearchJson: row.rawSearchJson,
      rawDetailJson: row.rawDetailJson,
      noData: row.noData,
      imageFetchCompleted: row.imageFetchCompleted,
      updatedAtMillis: row.updatedAtMillis,
    );
  }

  ArtistImageCacheRecord _artistImageCacheFromRow(ArtistImageCache row) {
    return ArtistImageCacheRecord(
      id: row.id,
      artistId: row.artistId,
      imagePath: row.imagePath,
      sourceUrl: row.sourceUrl,
      width: row.width,
      height: row.height,
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
    return decoded
        .map((item) => item?.toString() ?? '')
        .toList(growable: false);
  }

  LibraryInsightSongRecord _libraryInsightSongRecordFromRow(QueryRow row) {
    return LibraryInsightSongRecord(
      song: SongMetadata(
        id: row.read<int?>('id'),
        path: row.read<String>('path'),
        title: row.read<String?>('title') ?? 'Unknown',
        album: row.read<String?>('album') ?? 'Unknown',
        artist: row.read<String?>('artist') ?? 'Unknown',
        duration: row.read<int?>('duration'),
        artworkPath: row.read<String?>('artworkPath'),
        thumbnailPath: row.read<String?>('thumbnailPath'),
        artworkWidth: row.read<int?>('artworkWidth'),
        artworkHeight: row.read<int?>('artworkHeight'),
        trackNumber: row.read<int?>('trackNumber'),
        sourceFlags: row.read<int?>('sourceFlags'),
        themeColorsBlob: row.read<Uint8List?>('themeColorsBlob'),
        waveformBlob: row.read<Uint8List?>('waveformBlob'),
        lastModifiedTime: row.read<int?>('lastModifiedTime'),
        metadataTextScanned: row.read<int?>('metadataTextScanned'),
        metadataImgScanned: row.read<int?>('metadataImgScanned'),
        createdAt: row.read<int?>('createdAt'),
        genres: _decodeGenres(row.read<String?>('genres')),
      ),
      playCount: row.read<int>('playCount'),
      lastPlayedAt: row.read<int?>('lastPlayedAt'),
    );
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
  BlobColumn get themeColorsBlob =>
      blob().nullable().named('themeColorsBlob')();
  BlobColumn get waveformBlob => blob().nullable().named('waveformBlob')();
  IntColumn get lastModifiedTime =>
      integer().nullable().named('lastModifiedTime')();
  IntColumn get metadataTextScanned =>
      integer().nullable().named('metadataTextScanned')();
  IntColumn get metadataImgScanned =>
      integer().nullable().named('metadataImgScanned')();
  IntColumn get createdAt => integer().nullable().named('createdAt')();
  TextColumn get genres => text().nullable().named('genres')();
  BoolColumn get isSoftDeleted => boolean().nullable().named('isSoftDeleted')();
  IntColumn get lastSeenRootScanSessionId =>
      integer().nullable().named('lastSeenRootScanSessionId')();

  @override
  List<String> get customConstraints => const ['UNIQUE(path)'];
}

class SongPlayHistories extends Table {
  @override
  String get tableName => 'song_play_history';

  IntColumn get id => integer().autoIncrement().named('id')();
  TextColumn get songPath => text().named('songPath')();
  IntColumn get playedAt => integer().named('playedAt')();
  IntColumn get playedDurationMillis =>
      integer().nullable().named('playedDurationMillis')();
  IntColumn get songDurationMillis =>
      integer().nullable().named('songDurationMillis')();
  TextColumn get source => text().nullable().named('source')();
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
  IntColumn get timelineOffsetMillis =>
      integer().named('timelineOffsetMillis')();
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

class ArtistCaches extends Table {
  @override
  String get tableName => 'artist_cache';

  IntColumn get id => integer().autoIncrement().named('id')();
  TextColumn get queryKey => text().named('queryKey')();
  TextColumn get artistId => text().nullable().named('artistId')();
  TextColumn get artistName => text().nullable().named('artistName')();
  TextColumn get sortName => text().nullable().named('sortName')();
  TextColumn get disambiguation => text().nullable().named('disambiguation')();
  TextColumn get country => text().nullable().named('country')();
  TextColumn get imageFileTitle => text().nullable().named('imageFileTitle')();
  TextColumn get imageUrl => text().nullable().named('imageUrl')();
  TextColumn get thumbnailUrl => text().nullable().named('thumbnailUrl')();
  TextColumn get areaName => text().nullable().named('areaName')();
  TextColumn get beginDate => text().nullable().named('beginDate')();
  TextColumn get endDate => text().nullable().named('endDate')();
  TextColumn get tagsJson => text().nullable().named('tagsJson')();
  TextColumn get rawSearchJson => text().nullable().named('rawSearchJson')();
  TextColumn get rawDetailJson => text().nullable().named('rawDetailJson')();
  BoolColumn get noData => boolean().named('noData')();
  BoolColumn get imageFetchCompleted =>
      boolean().named('imageFetchCompleted')();
  IntColumn get updatedAtMillis => integer().named('updatedAtMillis')();

  @override
  List<String> get customConstraints => const ['UNIQUE(queryKey)'];
}

class ArtistImageCaches extends Table {
  @override
  String get tableName => 'artist_image_cache';

  IntColumn get id => integer().autoIncrement().named('id')();
  TextColumn get artistId => text().named('artistId')();
  TextColumn get imagePath => text().named('imagePath')();
  TextColumn get sourceUrl => text().nullable().named('sourceUrl')();
  IntColumn get width => integer().nullable().named('width')();
  IntColumn get height => integer().nullable().named('height')();
  IntColumn get updatedAtMillis => integer().named('updatedAtMillis')();

  @override
  List<String> get customConstraints => const ['UNIQUE(artistId)'];
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
    return NativeDatabase.createInBackground(file);
  });
}

String _normalizeArtistCacheKey(String queryKey) {
  return queryKey.trim().toLowerCase();
}
