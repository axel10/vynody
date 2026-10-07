part of 'metadata_database.dart';

@DriftDatabase(
  tables: [
    Songs,
    SongRoots,
    SongPlayHistories,
    LyricsCaches,
    AcoustidCaches,
    ReleaseCoverCaches,
    LyricsTranslationCaches,
    ArtistCaches,
    ArtistImageCaches,
    ArtworkCaches,
    RemoteSongs,
    FolderCovers,
    RemoteLibraryCaches,
    LyricsHistories,
  ],
)
class MetadataDriftDatabase extends _$MetadataDriftDatabase {
  MetadataDriftDatabase._() : super(_openConnection());

  static final MetadataDriftDatabase instance = MetadataDriftDatabase._();

  @override
  int get schemaVersion => 40;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA busy_timeout = 5000');

      if (Platform.isIOS) {
        await _ensureIosDirectories();
        // Schedule non-blocking background sandbox path healing after database is opened
        Future.delayed(const Duration(seconds: 1), () {
          unawaited(_healIosSandboxPathsInBackground());
        });
      }

      final migrator = createMigrator();
      for (final table in allTables) {
        final exists = await _tableExists(table.actualTableName);
        if (!exists) {
          debugPrint(
            '[Database] Table ${table.actualTableName} is missing, recreating...',
          );
          await migrator.createTable(table as TableInfo<Table, dynamic>);
        }
      }

      await _repairLegacyLyricsCacheRows();
      await _repairLegacyArtistCacheRows();

      // Clean up sourceFlags (remove external flag 4 if combined with rootScan or systemMedia)
      if (await _columnExists('songs', 'sourceFlags')) {
        await customStatement('''
          UPDATE songs
          SET sourceFlags = sourceFlags - 4
          WHERE sourceFlags IS NOT NULL
            AND (sourceFlags & 3) != 0
            AND (sourceFlags & 4) != 0
        ''');
      }
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
      if (from < 27) {
        if (await _columnExists('songs', 'isSoftDeleted')) {
          final rows = await customSelect(
            '''
            SELECT thumbnailPath
            FROM songs
            WHERE isSoftDeleted = 1
              AND deletedAt IS NULL
            ''',
            readsFrom: {songs},
          ).get();
          final deletedAtMillis = DateTime.now().millisecondsSinceEpoch;
          await customStatement('''
            UPDATE songs
            SET deletedAt = $deletedAtMillis,
                thumbnailPath = NULL
            WHERE isSoftDeleted = 1
              AND deletedAt IS NULL
          ''');
          await _deleteThumbnailFiles(
            rows.map((row) => row.read<String?>('thumbnailPath')),
          );
        }
      }
      if (from < 28) {
        await _addColumnIfMissing(m, 'songs', 'isAppModified', 'INTEGER');
        await m.database.customStatement('''
          UPDATE songs
          SET isAppModified = 0
          WHERE isAppModified IS NULL
        ''');
      }
      if (from < 29) {
        await m.database.customStatement('ALTER TABLE lyrics_cache RENAME TO lyrics_cache_old;');
        await m.database.customStatement('''
          CREATE TABLE lyrics_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cacheKey TEXT NOT NULL,
            source TEXT NOT NULL,
            languageCode TEXT NOT NULL DEFAULT '',
            isSynced INTEGER NOT NULL,
            syncedLyrics TEXT,
            syncedLinesJson TEXT NOT NULL,
            timelineOffsetMillis INTEGER NOT NULL,
            updatedAtMillis INTEGER NOT NULL,
            UNIQUE(cacheKey, source, languageCode)
          )
        ''');
        await m.database.customStatement('''
          INSERT INTO lyrics_cache (
            id, cacheKey, source, languageCode, isSynced, syncedLyrics,
            syncedLinesJson, timelineOffsetMillis, updatedAtMillis
          )
          SELECT 
            id, cacheKey, source, '', isSynced, syncedLyrics,
            syncedLinesJson, timelineOffsetMillis, updatedAtMillis
          FROM lyrics_cache_old;
        ''');
        await m.database.customStatement('DROP TABLE lyrics_cache_old;');
      }
      if (from < 30) {
        await _addColumnIfMissing(m, 'songs', 'mediaId', 'INTEGER');
      }
      if (from < 32) {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS remote_songs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            serverId TEXT NOT NULL,
            remoteId TEXT NOT NULL,
            virtualUri TEXT NOT NULL,
            title TEXT,
            album TEXT,
            artist TEXT,
            duration INTEGER,
            artworkPath TEXT,
            thumbnailPath TEXT,
            artworkWidth INTEGER,
            artworkHeight INTEGER,
            trackNumber INTEGER,
            themeColorsBlob BLOB,
            waveformBlob BLOB,
            coverArtId TEXT,
            suffix TEXT,
            bitRate INTEGER,
            cachedFilePath TEXT,
            createdAt INTEGER,
            updatedAt INTEGER,
            deletedAt INTEGER,
            UNIQUE(virtualUri)
          )
        ''');
        await m.database.customStatement('''
          CREATE INDEX IF NOT EXISTS idx_remote_songs_server_id
          ON remote_songs(serverId)
        ''');
      }
      if (from < 33) {
        await _addColumnIfMissing(m, 'songs', 'albumArtist', 'TEXT');
        await _addColumnIfMissing(m, 'remote_songs', 'albumArtist', 'TEXT');
      }
      if (from < 34) {
        final migrator = createMigrator();
        final exists = await _tableExists(folderCovers.actualTableName);
        if (!exists) {
          await migrator.createTable(folderCovers);
        }
      }
      if (from < 35) {
        await _addColumnIfMissing(m, 'songs', 'hasArtwork', 'INTEGER');
      }
      if (from < 36) {
        final migrator = createMigrator();
        final exists = await _tableExists(remoteLibraryCaches.actualTableName);
        if (!exists) {
          await migrator.createTable(remoteLibraryCaches);
        }
      }
      if (from < 37) {
        await _addColumnIfMissing(m, 'songs', 'bitrate', 'INTEGER');
        await _addColumnIfMissing(m, 'songs', 'sampleRate', 'INTEGER');
        await _addColumnIfMissing(m, 'songs', 'channels', 'INTEGER');
        await _addColumnIfMissing(m, 'songs', 'bitDepth', 'INTEGER');
        await _addColumnIfMissing(m, 'songs', 'format', 'TEXT');
        await _addColumnIfMissing(m, 'songs', 'codec', 'TEXT');
      }
      if (from < 38) {
        final exists = await _tableExists(lyricsHistories.actualTableName);
        if (!exists) {
          await m.createTable(lyricsHistories);
        }
      }
      if (from < 40) {
        await _migrateLyricsCacheToPathKey(m);
      }
    },
  );

  static String _legacyNormalizeText(String? value) {
    if (value == null) return '';
    var text = value.toLowerCase().trim();
    if (text.isEmpty) return '';

    text = text.replaceAll(RegExp(r'[\u2013\u2014]'), '-');
    text = text.replaceAll(RegExp(r'[\(\[\{（【][^\)\]\}）】]*[\)\]\}）】]'), ' ');
    text = text.replaceAll(RegExp(r'\b(feat|ft|featuring)\b.*$'), ' ');
    text = text.replaceAll(
      RegExp(
        r'\b(live|remaster(?:ed)?|radio edit|album version|instrumental|karaoke|mono|stereo|official audio|edit)\b',
      ),
      ' ',
    );
    text = text.replaceAll(RegExp(r'[\p{P}\p{S}]+', unicode: true), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  static String _legacyNormalizeForKey(String? value) {
    return _legacyNormalizeText(value).replaceAll(' ', '_');
  }

  Future<void> _migrateLyricsCacheToPathKey(Migrator m) async {
    final exists = await _tableExists('lyrics_cache');
    if (!exists) return;

    // 0. 从 songs 表中构建旧缓存键前缀到真实规范化路径的映射表
    final legacyKeyToRealPath = <String, String>{};
    if (await _tableExists('songs')) {
      final songRows = await customSelect('SELECT path FROM songs WHERE path IS NOT NULL').get();
      for (final row in songRows) {
        final path = row.data['path'] as String?;
        if (path == null || path.trim().isEmpty) continue;
        final normPath = ScannerPathUtils.normalizePath(path);
        if (normPath.isEmpty) continue;

        final legacyKey = _legacyNormalizeForKey(path);
        if (legacyKey.isNotEmpty) {
          legacyKeyToRealPath[legacyKey] = normPath;
        }
      }
    }

    String resolveNormalizedKey(String rawKey) {
      if (rawKey.isEmpty) return '';
      final parts = rawKey.split('|');
      final firstPart = parts.first.trim();
      if (firstPart.isEmpty) return '';

      // 1) 优先检查是否命中 songs 表还原出的真实物理路径
      final mappedPath = legacyKeyToRealPath[firstPart];
      if (mappedPath != null && mappedPath.isNotEmpty) {
        return mappedPath;
      }

      // 2) 如果本身就是 URI 或物理路径格式，直接规范化
      return ScannerPathUtils.normalizeLyricCacheKey(firstPart);
    }

    // 1. 读取旧表所有数据并在内存中按规范化路径规整去重
    final rows = await customSelect('SELECT * FROM lyrics_cache').get();

    int getSourcePriority(String? s) {
      switch (s) {
        case 'manual_adjust':
          return 7;
        case 'external':
          return 6;
        case 'embedded':
          return 5;
        case 'ai_timeline':
          return 4;
        case 'ai_karaoke':
          return 3;
        case 'ai_generate':
          return 2;
        case 'ai':
          return 1;
        case 'lrclib':
          return 0;
        default:
          return -1;
      }
    }

    final bestByPath = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final data = Map<String, dynamic>.from(row.data);
      final rawKey = (data['cacheKey'] as String?) ?? '';
      final normKey = resolveNormalizedKey(rawKey);
      if (normKey.isEmpty) continue;

      data['cacheKey'] = normKey;
      final existing = bestByPath[normKey];
      if (existing == null) {
        bestByPath[normKey] = data;
      } else {
        final curPrio = getSourcePriority(data['source'] as String?);
        final existPrio = getSourcePriority(existing['source'] as String?);
        if (curPrio > existPrio) {
          bestByPath[normKey] = data;
        } else if (curPrio == existPrio) {
          final curTime = (data['updatedAtMillis'] as int?) ?? 0;
          final existTime = (existing['updatedAtMillis'] as int?) ?? 0;
          if (curTime > existTime) {
            bestByPath[normKey] = data;
          }
        }
      }
    }

    // 2. 创建新表并批量插入最佳记录
    await customStatement('DROP TABLE IF EXISTS lyrics_cache_new');
    await customStatement('''
      CREATE TABLE lyrics_cache_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cacheKey TEXT NOT NULL,
        source TEXT NOT NULL,
        languageCode TEXT NOT NULL DEFAULT '',
        isSynced INTEGER NOT NULL,
        syncedLyrics TEXT,
        syncedLinesJson TEXT NOT NULL,
        timelineOffsetMillis INTEGER NOT NULL,
        updatedAtMillis INTEGER NOT NULL,
        UNIQUE(cacheKey)
      )
    ''');

    for (final entry in bestByPath.values) {
      await customStatement(
        '''
        INSERT INTO lyrics_cache_new (
          cacheKey, source, languageCode, isSynced, syncedLyrics,
          syncedLinesJson, timelineOffsetMillis, updatedAtMillis
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          entry['cacheKey'],
          entry['source'] ?? 'lrclib',
          entry['languageCode'] ?? '',
          entry['isSynced'] ?? 0,
          entry['syncedLyrics'],
          entry['syncedLinesJson'] ?? '[]',
          entry['timelineOffsetMillis'] ?? 0,
          entry['updatedAtMillis'] ?? DateTime.now().millisecondsSinceEpoch,
        ],
      );
    }

    await customStatement('DROP TABLE lyrics_cache');
    await customStatement('ALTER TABLE lyrics_cache_new RENAME TO lyrics_cache');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_lyrics_cache_key ON lyrics_cache(cacheKey)');

    // 3. 规整 lyrics_history 表
    if (await _tableExists('lyrics_history')) {
      final historyRows = await customSelect('SELECT * FROM lyrics_history').get();
      await customStatement('DROP TABLE IF EXISTS lyrics_history_new');
      await customStatement('''
        CREATE TABLE lyrics_history_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cacheKey TEXT NOT NULL,
          actionType TEXT NOT NULL,
          description TEXT NOT NULL,
          lyrics TEXT NOT NULL,
          translation TEXT,
          timelineOffsetMillis INTEGER NOT NULL DEFAULT 0,
          createdAtMillis INTEGER NOT NULL
        )
      ''');
      for (final row in historyRows) {
        final data = row.data;
        final rawKey = (data['cacheKey'] as String?) ?? '';
        final normKey = resolveNormalizedKey(rawKey);
        if (normKey.isEmpty) continue;
        await customStatement(
          '''
          INSERT INTO lyrics_history_new (
            id, cacheKey, actionType, description, lyrics, translation, timelineOffsetMillis, createdAtMillis
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            data['id'],
            normKey,
            data['actionType'] ?? 'manual_edit',
            data['description'] ?? '',
            data['lyrics'] ?? '',
            data['translation'],
            data['timelineOffsetMillis'] ?? 0,
            data['createdAtMillis'] ?? DateTime.now().millisecondsSinceEpoch,
          ],
        );
      }
      await customStatement('DROP TABLE lyrics_history');
      await customStatement('ALTER TABLE lyrics_history_new RENAME TO lyrics_history');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_lyrics_history_key ON lyrics_history(cacheKey)');
    }

    // 4. 规整 lyrics_translation_cache 表
    if (await _tableExists('lyrics_translation_cache')) {
      final transRows = await customSelect('SELECT * FROM lyrics_translation_cache').get();
      await customStatement('DROP TABLE IF EXISTS lyrics_translation_cache_new');
      await customStatement('''
        CREATE TABLE lyrics_translation_cache_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cacheKey TEXT NOT NULL,
          languageCode TEXT NOT NULL DEFAULT 'zh',
          translatedText TEXT NOT NULL,
          translatedLinesJson TEXT NOT NULL,
          provider TEXT,
          updatedAtMillis INTEGER NOT NULL,
          UNIQUE(cacheKey, languageCode)
        )
      ''');

      final bestTrans = <String, Map<String, dynamic>>{};
      for (final row in transRows) {
        final data = Map<String, dynamic>.from(row.data);
        final rawKey = (data['cacheKey'] as String?) ?? '';
        final normKey = resolveNormalizedKey(rawKey);
        if (normKey.isEmpty) continue;

        data['cacheKey'] = normKey;
        final lang = (data['languageCode'] as String?) ?? 'zh';
        final compoundKey = '$normKey\$$lang';
        final existing = bestTrans[compoundKey];
        if (existing == null) {
          bestTrans[compoundKey] = data;
        } else {
          final curTime = (data['updatedAtMillis'] as int?) ?? 0;
          final existTime = (existing['updatedAtMillis'] as int?) ?? 0;
          if (curTime >= existTime) {
            bestTrans[compoundKey] = data;
          }
        }
      }

      for (final data in bestTrans.values) {
        await customStatement(
          '''
          INSERT INTO lyrics_translation_cache_new (
            id, cacheKey, languageCode, translatedText, translatedLinesJson, provider, updatedAtMillis
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            data['id'],
            data['cacheKey'],
            data['languageCode'] ?? 'zh',
            data['translatedText'] ?? '',
            data['translatedLinesJson'] ?? '[]',
            data['provider'],
            data['updatedAtMillis'] ?? DateTime.now().millisecondsSinceEpoch,
          ],
        );
      }
      await customStatement('DROP TABLE lyrics_translation_cache');
      await customStatement('ALTER TABLE lyrics_translation_cache_new RENAME TO lyrics_translation_cache');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_lyrics_trans_key ON lyrics_translation_cache(cacheKey)');
    }
  }

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

  Future<bool> _tableExists(String table) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable(table)],
    ).get();
    return rows.isNotEmpty;
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

  Future<void> _deleteThumbnailFiles(Iterable<String?> thumbnailPaths) async {
    for (final thumbnailPath in thumbnailPaths) {
      await _deleteThumbnailFile(thumbnailPath);
    }
  }

  Future<void> _deleteThumbnailFile(String? thumbnailPath) async {
    final normalizedPath = thumbnailPath?.trim();
    if (normalizedPath == null || normalizedPath.isEmpty) {
      return;
    }

    try {
      // 避免当同一首歌曲在多个根目录里有副本时，因其中一个副本被清理而导致共用的缩略图文件被删掉。
      // 仅当没有其他有效（未被彻底删除）的歌曲记录引用该缩略图时，才物理删除文件。
      final query = select(songs)
        ..where((t) => t.thumbnailPath.equals(normalizedPath) & t.deletedAt.isNull());
      final count = await query.get().then((rows) => rows.length);
      if (count > 0) {
        return;
      }
    } catch (e) {
      debugPrint('[Database] Failed to query thumbnail reference count: $e');
    }

    try {
      final file = File(normalizedPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint(
        '[Database] Failed to delete thumbnail file $normalizedPath: $e',
      );
    }
  }

  Stream<List<SongMetadata>> watchAllSongMetadata() {
    return customSelect(
      '''
      SELECT *
      FROM songs
      WHERE deletedAt IS NULL
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
      WHERE deletedAt IS NULL
      ORDER BY LOWER(path) ASC
      ''',
      readsFrom: {songs},
    ).get();
    return rows.map(_songFromQueryRow).toList(growable: false);
  }

  Future<List<SongMetadata>> getSongsUnderPath(String rootPath) async {
    final normalized = _normalizePath(rootPath);
    if (normalized.isEmpty) return const [];
    if (normalized == 'system') {
      return getSystemMediaSongs();
    }
    if (normalized.startsWith('system/')) {
      final relativePath = normalized.substring('system/'.length);
      final separator = Platform.isWindows ? '\\' : '/';
      final prefixPattern = relativePath.endsWith(separator) ? '$relativePath%' : '$relativePath$separator%';
      final rows = await customSelect(
        '''
        SELECT *
        FROM songs
        WHERE (sourceFlags & ?) != 0
          AND (path = ? OR path LIKE ? OR path = ? OR path LIKE ?)
          AND deletedAt IS NULL
        ORDER BY LOWER(path) ASC
        ''',
        variables: [
          Variable(SongSourceFlags.systemMedia),
          Variable(relativePath),
          Variable(prefixPattern),
          Variable(normalized),
          Variable('$normalized%'),
        ],
        readsFrom: {songs},
      ).get();
      return rows.map(_songFromQueryRow).toList(growable: false);
    }

    final separator = RemoteMediaResolver.isRemoteUri(normalized)
        ? '/'
        : (Platform.isWindows ? '\\' : '/');
    final prefixPattern = normalized.endsWith(separator) ? '$normalized%' : '$normalized$separator%';
    final sandboxSuffix = _extractIosSandboxSuffix(normalized);

    final List<QueryRow> rows;
    if (sandboxSuffix != null) {
      final legacyPattern = '%/Containers/Data/Application/%$sandboxSuffix%';
      rows = await customSelect(
        '''
        SELECT *
        FROM songs
        WHERE (path = ? OR path LIKE ? OR path LIKE ?)
          AND deletedAt IS NULL
        ORDER BY LOWER(path) ASC
        ''',
        variables: [Variable(normalized), Variable(prefixPattern), Variable(legacyPattern)],
        readsFrom: {songs},
      ).get();
    } else {
      rows = await customSelect(
        '''
        SELECT *
        FROM songs
        WHERE (path = ? OR path LIKE ?)
          AND deletedAt IS NULL
        ORDER BY LOWER(path) ASC
        ''',
        variables: [Variable(normalized), Variable(prefixPattern)],
        readsFrom: {songs},
      ).get();
    }
    return rows.map(_songFromQueryRow).toList(growable: false);
  }

  static String? _extractIosSandboxSuffix(String path) {
    if (!Platform.isIOS && !Platform.isMacOS) return null;
    if (!ScannerPathUtils.isSandboxInternalPath(path)) return null;
    final match = RegExp(
      r'(?:^|/)(?:private/)?var/mobile/Containers/Data/Application/[^/]+(/(?:Documents|Library)(?:/.*)?)$',
    ).firstMatch(path) ?? RegExp(
      r'/Containers/Data/Application/[^/]+(/(?:Documents|Library)(?:/.*)?)$',
    ).firstMatch(path);
    return match?.group(1);
  }

  Future<int> getSongCountUnderPath(String rootPath) async {
    final normalized = _normalizePath(rootPath);
    if (normalized.isEmpty) return 0;
    if (normalized.startsWith('system/')) {
      final relativePath = normalized.substring('system/'.length);
      final separator = Platform.isWindows ? '\\' : '/';
      final prefixPattern = relativePath.endsWith(separator) ? '$relativePath%' : '$relativePath$separator%';
      final row = await customSelect(
        '''
        SELECT COUNT(*) AS c
        FROM songs
        WHERE (sourceFlags & ?) != 0
          AND (path = ? OR path LIKE ? OR path = ? OR path LIKE ?)
          AND deletedAt IS NULL
        ''',
        variables: [
          Variable(SongSourceFlags.systemMedia),
          Variable(relativePath),
          Variable(prefixPattern),
          Variable(normalized),
          Variable('$normalized%'),
        ],
        readsFrom: {songs},
      ).getSingle();
      return row.read<int>('c');
    }

    final separator = RemoteMediaResolver.isRemoteUri(normalized)
        ? '/'
        : (Platform.isWindows ? '\\' : '/');
    final prefixPattern = normalized.endsWith(separator) ? '$normalized%' : '$normalized$separator%';
    final sandboxSuffix = _extractIosSandboxSuffix(normalized);

    final QueryRow row;
    if (sandboxSuffix != null) {
      final legacyPattern = '%/Containers/Data/Application/%$sandboxSuffix%';
      row = await customSelect(
        '''
        SELECT COUNT(*) AS c
        FROM songs
        WHERE (path = ? OR path LIKE ? OR path LIKE ?)
          AND deletedAt IS NULL
        ''',
        variables: [Variable(normalized), Variable(prefixPattern), Variable(legacyPattern)],
        readsFrom: {songs},
      ).getSingle();
    } else {
      row = await customSelect(
        '''
        SELECT COUNT(*) AS c
        FROM songs
        WHERE (path = ? OR path LIKE ?)
          AND deletedAt IS NULL
        ''',
        variables: [Variable(normalized), Variable(prefixPattern)],
        readsFrom: {songs},
      ).getSingle();
    }
    return row.read<int>('c');
  }

  Future<int> getSongDurationUnderPath(String rootPath) async {
    final normalized = _normalizePath(rootPath);
    if (normalized.isEmpty) return 0;
    if (normalized.startsWith('system/')) {
      final relativePath = normalized.substring('system/'.length);
      final separator = Platform.isWindows ? '\\' : '/';
      final prefixPattern = relativePath.endsWith(separator) ? '$relativePath%' : '$relativePath$separator%';
      final row = await customSelect(
        '''
        SELECT SUM(duration) AS s
        FROM songs
        WHERE (sourceFlags & ?) != 0
          AND (path = ? OR path LIKE ? OR path = ? OR path LIKE ?)
          AND deletedAt IS NULL
        ''',
        variables: [
          Variable(SongSourceFlags.systemMedia),
          Variable(relativePath),
          Variable(prefixPattern),
          Variable(normalized),
          Variable('$normalized%'),
        ],
        readsFrom: {songs},
      ).getSingle();
      return row.read<int?>('s') ?? 0;
    }

    final separator = RemoteMediaResolver.isRemoteUri(normalized)
        ? '/'
        : (Platform.isWindows ? '\\' : '/');
    final prefixPattern = normalized.endsWith(separator) ? '$normalized%' : '$normalized$separator%';
    final sandboxSuffix = _extractIosSandboxSuffix(normalized);

    final QueryRow row;
    if (sandboxSuffix != null) {
      final legacyPattern = '%/Containers/Data/Application/%$sandboxSuffix%';
      row = await customSelect(
        '''
        SELECT SUM(duration) AS s
        FROM songs
        WHERE (path = ? OR path LIKE ? OR path LIKE ?)
          AND deletedAt IS NULL
        ''',
        variables: [Variable(normalized), Variable(prefixPattern), Variable(legacyPattern)],
        readsFrom: {songs},
      ).getSingle();
    } else {
      row = await customSelect(
        '''
        SELECT SUM(duration) AS s
        FROM songs
        WHERE (path = ? OR path LIKE ?)
          AND deletedAt IS NULL
        ''',
        variables: [Variable(normalized), Variable(prefixPattern)],
        readsFrom: {songs},
      ).getSingle();
    }
    return row.read<int?>('s') ?? 0;
  }

  Future<SongMetadata?> getRepresentativeSongUnderPath(
    String rootPath, {
    SortCriteria criteria = SortCriteria.filename,
    SortOrder order = SortOrder.ascending,
  }) async {
    final normalized = _normalizePath(rootPath);
    if (normalized.isEmpty) return null;
    return getFolderRepresentativeMetadata(normalized);
  }

  Future<List<SongMetadata>> getSystemMediaSongs() async {
    final rows = await customSelect(
      '''
      SELECT *
      FROM songs
      WHERE (sourceFlags & ?) != 0
        AND deletedAt IS NULL
      ORDER BY path ASC
      ''',
      variables: [Variable(SongSourceFlags.systemMedia)],
      readsFrom: {songs},
    ).get();
    return rows.map(_songFromQueryRow).toList();
  }

  Future<List<SongMetadata>> searchSongs(
    String query, {
    String? folderPath,
  }) async {
    final pattern = '%$query%';
    if (folderPath != null && folderPath.isNotEmpty) {
      final normalizedFolder = _normalizePath(folderPath);
      if (normalizedFolder == 'system') {
        final rows = await customSelect(
          '''
          SELECT *
          FROM songs
          WHERE (sourceFlags & ?) != 0
            AND (title LIKE ? OR artist LIKE ? OR album LIKE ? OR path LIKE ?)
            AND deletedAt IS NULL
          ORDER BY LOWER(path) ASC
          ''',
          variables: [
            Variable(SongSourceFlags.systemMedia),
            Variable(pattern),
            Variable(pattern),
            Variable(pattern),
            Variable(pattern),
          ],
          readsFrom: {songs},
        ).get();
        return rows.map(_songFromQueryRow).toList(growable: false);
      } else if (normalizedFolder.startsWith('system/')) {
        final relativePath = normalizedFolder.substring('system/'.length);
        final separator = Platform.isWindows ? '\\' : '/';
        final prefixPattern = relativePath.endsWith(separator)
            ? '$relativePath%'
            : '$relativePath$separator%';
        final rows = await customSelect(
          '''
          SELECT *
          FROM songs
          WHERE (sourceFlags & ?) != 0
            AND (path = ? OR path LIKE ? OR path = ? OR path LIKE ?)
            AND (title LIKE ? OR artist LIKE ? OR album LIKE ? OR path LIKE ?)
            AND deletedAt IS NULL
          ORDER BY LOWER(path) ASC
          ''',
          variables: [
            Variable(SongSourceFlags.systemMedia),
            Variable(relativePath),
            Variable(prefixPattern),
            Variable(normalizedFolder),
            Variable('$normalizedFolder%'),
            Variable(pattern),
            Variable(pattern),
            Variable(pattern),
            Variable(pattern),
          ],
          readsFrom: {songs},
        ).get();
        return rows.map(_songFromQueryRow).toList(growable: false);
      } else {
        final separator = Platform.isWindows ? '\\' : '/';
        final prefixPattern = normalizedFolder.endsWith(separator)
            ? '$normalizedFolder%'
            : '$normalizedFolder$separator%';
        final rows = await customSelect(
          '''
          SELECT *
          FROM songs
          WHERE (path = ? OR path LIKE ?)
            AND (title LIKE ? OR artist LIKE ? OR album LIKE ? OR path LIKE ?)
            AND deletedAt IS NULL
          ORDER BY LOWER(path) ASC
          ''',
          variables: [
            Variable(normalizedFolder),
            Variable(prefixPattern),
            Variable(pattern),
            Variable(pattern),
            Variable(pattern),
            Variable(pattern),
          ],
          readsFrom: {songs},
        ).get();
        return rows.map(_songFromQueryRow).toList(growable: false);
      }
    }

    final rows = await customSelect(
      '''
      SELECT *
      FROM songs
      WHERE (title LIKE ? OR artist LIKE ? OR album LIKE ? OR path LIKE ?)
        AND deletedAt IS NULL
      ORDER BY LOWER(path) ASC
      ''',
      variables: [
        Variable(pattern),
        Variable(pattern),
        Variable(pattern),
        Variable(pattern),
      ],
      readsFrom: {songs},
    ).get();
    return rows.map(_songFromQueryRow).toList(growable: false);
  }

  Future<List<String>> searchFolderPaths(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final pattern = '%$trimmed%';
    final rows = await customSelect(
      '''
      SELECT DISTINCT path
      FROM songs
      WHERE path LIKE ?
        AND deletedAt IS NULL
      ORDER BY LOWER(path) ASC
      ''',
      variables: [Variable(pattern)],
      readsFrom: {songs},
    ).get();

    final distinctDirs = <String>{};
    final lowercaseQuery = trimmed.toLowerCase();

    for (final row in rows) {
      final filePath = row.read<String>('path');
      var dirPath = p.dirname(filePath);
      while (dirPath.isNotEmpty && dirPath != p.rootPrefix(dirPath)) {
        final dirName = p.basename(dirPath);
        if (dirName.toLowerCase().contains(lowercaseQuery)) {
          distinctDirs.add(dirPath);
        }
        final parent = p.dirname(dirPath);
        if (parent == dirPath) break;
        dirPath = parent;
      }
    }
    return distinctDirs.toList(growable: false);
  }

  Stream<SongMetadata?> watchSongMetadata(String path) {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) {
      return Stream<SongMetadata?>.value(null);
    }
    if (RemoteMediaResolver.isRemoteUri(normalizedPath)) {
      return customSelect(
        '''
        SELECT *
        FROM remote_songs
        WHERE virtualUri = ?
          AND deletedAt IS NULL
        LIMIT 1
        ''',
        variables: [Variable(normalizedPath)],
        readsFrom: {remoteSongs},
      ).watchSingleOrNull().map(
        (row) => row == null ? null : _songFromRemoteRow(row),
      );
    }
    return customSelect(
      '''
      SELECT *
      FROM songs
      WHERE path = ?
        AND deletedAt IS NULL
      LIMIT 1
      ''',
      variables: [Variable(normalizedPath)],
      readsFrom: {songs},
    ).watchSingleOrNull().map(
      (row) => row == null ? null : _songFromQueryRow(row),
    );
  }

  Future<SongMetadata?> getRemoteSongMetadata(String virtualUri) async {
    final normalized = virtualUri.trim();
    if (normalized.isEmpty) return null;
    var row = await customSelect(
      '''
      SELECT *
      FROM remote_songs
      WHERE virtualUri = ?
        AND deletedAt IS NULL
      LIMIT 1
      ''',
      variables: [Variable(normalized)],
      readsFrom: {remoteSongs},
    ).getSingleOrNull();

    if (row == null) {
      String decoded = normalized;
      try {
        decoded = Uri.decodeFull(normalized);
      } catch (_) {}
      final encoded = Uri.encodeFull(normalized);
      final fallbackUri = decoded != normalized ? decoded : encoded;
      if (fallbackUri != normalized) {
        row = await customSelect(
          '''
          SELECT *
          FROM remote_songs
          WHERE virtualUri = ?
            AND deletedAt IS NULL
          LIMIT 1
          ''',
          variables: [Variable(fallbackUri)],
          readsFrom: {remoteSongs},
        ).getSingleOrNull();
      }
    }
    return row == null ? null : _songFromRemoteRow(row);
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
        AND deletedAt IS NULL
      LIMIT 1
      ''',
      variables: [Variable(normalizedPath)],
      readsFrom: {songs},
    ).getSingleOrNull();
    if (row != null) {
      return _songFromQueryRow(row);
    }
    if (RemoteMediaResolver.isRemoteUri(normalizedPath)) {
      return getRemoteSongMetadata(normalizedPath);
    }
    return null;
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

    final localPaths = <String>[];
    final remotePaths = <String>[];
    for (final p in normalizedPaths) {
      if (RemoteMediaResolver.isRemoteUri(p)) {
        remotePaths.add(p);
      } else {
        localPaths.add(p);
      }
    }

    final result = LinkedHashMap<String, SongMetadata>(
      equals: (a, b) => _pathLookupKey(a) == _pathLookupKey(b),
      hashCode: (a) => _pathLookupKey(a).hashCode,
    );
    const batchSize = 500;
    await transaction(() async {
      for (var i = 0; i < localPaths.length; i += batchSize) {
        if (i > 0 && i % 2000 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        final chunk = localPaths.sublist(
          i,
          i + batchSize > localPaths.length
              ? localPaths.length
              : i + batchSize,
        );
        final rows = await customSelect(
          '''
          SELECT *
          FROM songs
          WHERE path IN (${List.filled(chunk.length, '?').join(', ')})
            AND deletedAt IS NULL
          ''',
          variables: chunk.map(Variable.new).toList(growable: false),
          readsFrom: {songs},
        ).get();

        for (final row in rows) {
          final rowPath = row.read<String>('path');
          result[rowPath] = _songFromQueryRow(row);
        }
      }

      for (var i = 0; i < remotePaths.length; i += batchSize) {
        if (i > 0 && i % 2000 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        final chunk = remotePaths.sublist(
          i,
          i + batchSize > remotePaths.length
              ? remotePaths.length
              : i + batchSize,
        );
        final rows = await customSelect(
          '''
          SELECT *
          FROM remote_songs
          WHERE virtualUri IN (${List.filled(chunk.length, '?').join(', ')})
            AND deletedAt IS NULL
          ''',
          variables: chunk.map(Variable.new).toList(growable: false),
          readsFrom: {remoteSongs},
        ).get();

        for (final row in rows) {
          final rowUri = row.read<String>('virtualUri');
          result[rowUri] = _songFromRemoteRow(row);
        }
      }
    });
    return result;
  }

  Future<List<SongMetadata>> findSongsByPathSuffix(String suffix) async {
    final trimmed = suffix.trim();
    if (trimmed.isEmpty) return [];

    // Search by exact suffix or separator + suffix
    final normalized = trimmed.replaceAll('\\', '/');
    final lastComponent = normalized.contains('/') ? normalized.split('/').last : normalized;
    final separator = Platform.isWindows ? r'\' : '/';
    final suffixPattern = '%$separator$trimmed';
    final slashPattern = '%/$normalized';
    final filenamePattern = '%$separator$lastComponent';

    final rows = await customSelect(
      '''
      SELECT *
      FROM songs
      WHERE (path = ? OR path LIKE ? OR path LIKE ? OR path LIKE ?)
        AND deletedAt IS NULL
      LIMIT 10
      ''',
      variables: [
        Variable(trimmed),
        Variable(suffixPattern),
        Variable(slashPattern),
        Variable(filenamePattern),
      ],
      readsFrom: {songs},
    ).get();
    return rows.map(_songFromQueryRow).toList(growable: false);
  }

  Future<List<SongMetadata>> findRemoteSongsByRemoteId(String remoteId) async {
    final cleanRemoteId = remoteId.trim();
    if (cleanRemoteId.isEmpty) return [];
    final withSlash = cleanRemoteId.startsWith('/') ? cleanRemoteId : '/$cleanRemoteId';
    final withoutSlash = cleanRemoteId.startsWith('/') ? cleanRemoteId.substring(1) : cleanRemoteId;
    final lastComponent = cleanRemoteId.contains('/') ? cleanRemoteId.split('/').last : cleanRemoteId;
    final suffixPattern = '%/$lastComponent';

    final rows = await customSelect(
      '''
      SELECT *
      FROM remote_songs
      WHERE (remoteId = ? OR remoteId = ? OR remoteId LIKE ? OR virtualUri LIKE ?)
        AND deletedAt IS NULL
      LIMIT 10
      ''',
      variables: [
        Variable(withSlash),
        Variable(withoutSlash),
        Variable(suffixPattern),
        Variable(suffixPattern),
      ],
      readsFrom: {remoteSongs},
    ).get();
    return rows.map(_songFromRemoteRow).toList(growable: false);
  }

  Future<List<SongMetadata>> findSongsByTitleAndArtist({
    required String title,
    String? artist,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return [];

    final localRows = await customSelect(
      '''
      SELECT *
      FROM songs
      WHERE LOWER(title) = ?
        AND deletedAt IS NULL
      LIMIT 10
      ''',
      variables: [Variable(cleanTitle.toLowerCase())],
      readsFrom: {songs},
    ).get();

    final results = localRows.map(_songFromQueryRow).toList();

    final remoteRows = await customSelect(
      '''
      SELECT *
      FROM remote_songs
      WHERE LOWER(title) = ?
        AND deletedAt IS NULL
      LIMIT 10
      ''',
      variables: [Variable(cleanTitle.toLowerCase())],
      readsFrom: {remoteSongs},
    ).get();

    results.addAll(remoteRows.map(_songFromRemoteRow));

    if (artist != null && artist.trim().isNotEmpty) {
      final cleanArtist = artist.trim().toLowerCase();
      results.sort((a, b) {
        final aArtist = a.artist.toLowerCase();
        final bArtist = b.artist.toLowerCase();
        final aMatches = aArtist.contains(cleanArtist) || cleanArtist.contains(aArtist);
        final bMatches = bArtist.contains(cleanArtist) || cleanArtist.contains(bArtist);
        if (aMatches && !bMatches) return -1;
        if (!aMatches && bMatches) return 1;
        return 0;
      });
    }

    return results;
  }

  Future<void> insertOrUpdateRemoteSong(
    SongMetadata song, {
    String? coverArtId,
    String? suffix,
    int? bitRate,
    String? cachedFilePath,
  }) async {
    final virtualUri = song.path.trim();
    if (virtualUri.isEmpty) return;

    final existing = await (select(remoteSongs)
          ..where((t) => t.virtualUri.equals(virtualUri))
          ..limit(1))
        .getSingleOrNull();

    final companion = _remoteSongCompanion(
      song,
      coverArtId: coverArtId ?? existing?.coverArtId,
      suffix: suffix ?? existing?.suffix,
      bitRate: bitRate ?? existing?.bitRate,
      cachedFilePath: cachedFilePath ?? existing?.cachedFilePath,
    );

    if (existing != null) {
      await (update(remoteSongs)
            ..where((t) => t.virtualUri.equals(existing.virtualUri)))
          .write(companion);
      return;
    }

    await into(remoteSongs).insert(companion);
  }

  Future<void> deleteRemoteSongsByServerId(String serverId) async {
    final cleanServerId = serverId.trim();
    if (cleanServerId.isEmpty) return;
    final lowerServerId = cleanServerId.toLowerCase();

    final rows = await (select(remoteSongs)
          ..where((t) =>
              t.serverId.equals(cleanServerId) |
              t.serverId.equals(lowerServerId)))
        .get();
    await _deleteThumbnailFiles(rows.map((r) => r.thumbnailPath));

    await (delete(remoteSongs)
          ..where((t) =>
              t.serverId.equals(cleanServerId) |
              t.serverId.equals(lowerServerId)))
        .go();
  }

  Future<List<SongMetadata>> getRemoteSongsByServerId(String serverId) async {
    final cleanServerId = serverId.trim();
    if (cleanServerId.isEmpty) return const [];
    final lowerServerId = cleanServerId.toLowerCase();

    final rows = await (select(remoteSongs)
          ..where((t) =>
              (t.serverId.equals(cleanServerId) |
                  t.serverId.equals(lowerServerId)) &
              t.deletedAt.isNull()))
        .get();
    return rows.map(_songFromRemoteTableRow).toList(growable: false);
  }

  Future<void> insertOrUpdateSong(
    SongMetadata song, {
    int? rootScanSessionId,
  }) async {
    final normalizedPath = _normalizePath(song.path);
    if (normalizedPath.isEmpty) return;

    final isIndexedRemote = (song.sourceFlags != null &&
        (song.sourceFlags! & SongSourceFlags.remote) != 0);

    if (RemoteMediaResolver.isRemoteUri(normalizedPath) && !isIndexedRemote) {
      await insertOrUpdateRemoteSong(song.copyWith(path: normalizedPath));
      return;
    }

    final existing =
        await (select(songs)
              ..where((t) => t.path.equals(normalizedPath))
              ..limit(1))
            .getSingleOrNull();
    final mergedSourceFlags = _mergeSourceFlags(
      existing?.sourceFlags,
      song.sourceFlags,
    );

    final updatedSong = song.copyWith(
      path: normalizedPath,
      sourceFlags: mergedSourceFlags,
    );
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
    final dedupedByPath = <String, SongMetadata>{};
    for (final song in songsList) {
      final normalizedPath = _normalizePath(song.path);
      if (normalizedPath.isEmpty) continue;
      dedupedByPath[_pathLookupKey(normalizedPath)] = song.copyWith(
        path: normalizedPath,
      );
    }

    final normalizedSongs = dedupedByPath.values.toList(growable: false);
    if (normalizedSongs.isEmpty) return;
    final existingRows =
        await (select(songs)..where(
              (t) => t.path.isIn(
                normalizedSongs.map((song) => song.path).toList(),
              ),
            ))
            .get();
    final existingByPath = {
      for (final row in existingRows)
        _pathLookupKey(row.path): _songFromTableRow(row),
    };

    await transaction(() async {
      for (final song in normalizedSongs) {
        final existing = existingByPath[_pathLookupKey(song.path)];
        final mergedCompanion = _songCompanion(
          song.copyWith(
            sourceFlags: _mergeSourceFlags(
              existing?.sourceFlags,
              song.sourceFlags,
            ),
          ),
          lastSeenRootScanSessionId: rootScanSessionId,
        );
        await into(songs).insert(
          mergedCompanion,
          onConflict: DoUpdate((old) => mergedCompanion, target: [songs.path]),
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
    int? limit = 500,
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
      ..writeln('  s.isAppModified,')
      ..writeln('  0 AS playCount,')
      ..writeln('  NULL AS lastPlayedAt')
      ..writeln('FROM songs s')
      ..writeln('WHERE s.createdAt IS NOT NULL')
      ..writeln('  AND s.deletedAt IS NULL');

    final variables = <Variable<Object>>[];
    if (startAtMillis != null) {
      buffer.writeln('  AND s.createdAt >= ?');
      variables.add(Variable.withInt(startAtMillis));
    }

    buffer
      ..writeln('ORDER BY s.createdAt DESC,')
      ..writeln("LOWER(COALESCE(s.title, '')) ASC,")
      ..writeln('LOWER(s.path) ASC');

    if (limit != null && limit > 0) {
      buffer.writeln('LIMIT ?');
      variables.add(Variable.withInt(limit));
    }

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
    int? limit = 500,
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
      ..writeln('  s.isAppModified,')
      ..writeln('  COUNT(h.id) AS playCount,')
      ..writeln('  MAX(h.playedAt) AS lastPlayedAt')
      ..writeln('FROM songs s')
      ..writeln('JOIN song_play_history h ON h.songPath = s.path')
      ..writeln('WHERE s.deletedAt IS NULL');

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

    if (limit != null && limit > 0) {
      buffer.writeln('LIMIT ?');
      variables.add(Variable.withInt(limit));
    }

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

  Stream<List<LibraryInsightSongRecord>> watchRecentlyPlayedSongs({
    int? startAtMillis,
    int? limit = 500,
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
      ..writeln('  s.isAppModified,')
      ..writeln('  COUNT(h.id) AS playCount,')
      ..writeln('  MAX(h.playedAt) AS lastPlayedAt')
      ..writeln('FROM songs s')
      ..writeln('JOIN song_play_history h ON h.songPath = s.path')
      ..writeln('WHERE s.deletedAt IS NULL');

    final variables = <Variable<Object>>[];
    if (startAtMillis != null) {
      buffer.writeln('  AND h.playedAt >= ?');
      variables.add(Variable.withInt(startAtMillis));
    }

    buffer
      ..writeln('GROUP BY s.path')
      ..writeln('ORDER BY lastPlayedAt DESC,')
      ..writeln("LOWER(COALESCE(s.title, '')) ASC,")
      ..writeln('LOWER(s.path) ASC');

    if (limit != null && limit > 0) {
      buffer.writeln('LIMIT ?');
      variables.add(Variable.withInt(limit));
    }

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

    final row =
        await (select(songs)
              ..where((t) => t.path.equals(normalizedPath))
              ..limit(1))
            .getSingleOrNull();
    if (row != null) {
      await (update(songs)..where((t) => t.path.equals(normalizedPath))).write(
        SongsCompanion(
          deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
          thumbnailPath: const Value(null),
        ),
      );
      await _deleteThumbnailFile(row.thumbnailPath);
    }

    if (RemoteMediaResolver.isRemoteUri(normalizedPath)) {
      final remoteRow = await (select(remoteSongs)
            ..where((t) => t.virtualUri.equals(normalizedPath))
            ..limit(1))
          .getSingleOrNull();
      if (remoteRow != null) {
        await (update(remoteSongs)
              ..where((t) => t.virtualUri.equals(normalizedPath)))
            .write(
          RemoteSongsCompanion(
            deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
            thumbnailPath: const Value(null),
          ),
        );
        await _deleteThumbnailFile(remoteRow.thumbnailPath);
      }
    }
  }

  Future<void> softDeleteSongsUnderPath(
    String rootPath, {
    int? maxCreatedAt,
  }) async {
    final normalized = _normalizePath(rootPath);
    if (normalized.isEmpty) return;

    final separator = RemoteMediaResolver.isRemoteUri(normalized)
        ? '/'
        : (Platform.isWindows ? '\\' : '/');
    final prefixPattern = normalized.endsWith(separator) ? '$normalized%' : '$normalized$separator%';

    final isRemote = RemoteMediaResolver.isRemoteUri(normalized);
    final now = DateTime.now().millisecondsSinceEpoch;

    final createdAtCondition = maxCreatedAt != null ? ' AND (createdAt IS NULL OR createdAt <= ?)' : '';
    final baseSelectVariables = [
      Variable(normalized),
      Variable(prefixPattern),
      if (maxCreatedAt != null) Variable(maxCreatedAt),
    ];
    final baseUpdateVariables = [
      Variable(now),
      Variable(normalized),
      Variable(prefixPattern),
      if (maxCreatedAt != null) Variable(maxCreatedAt),
    ];

    await transaction(() async {
      // 1. 获取即将被软删除的歌曲的缩略图路径，以便后续清理文件
      final songRows = await customSelect(
        '''
        SELECT thumbnailPath
        FROM songs
        WHERE (path = ? OR path LIKE ?)
          AND deletedAt IS NULL
          $createdAtCondition
        ''',
        variables: baseSelectVariables,
        readsFrom: {songs},
      ).get();

      final List<String?> thumbnailPaths = songRows
          .map((r) => r.read<String?>('thumbnailPath'))
          .where((p) => p != null && p.isNotEmpty)
          .toList();

      // 2. 批量软删除 songs 表
      await customUpdate(
        '''
        UPDATE songs
        SET deletedAt = ?, thumbnailPath = NULL
        WHERE (path = ? OR path LIKE ?)
          AND deletedAt IS NULL
          $createdAtCondition
        ''',
        variables: baseUpdateVariables,
        updates: {songs},
      );

      // 3. 如果是远程歌曲，同时批量软删除 remoteSongs 表
      if (isRemote) {
        final remoteRows = await customSelect(
          '''
          SELECT thumbnailPath
          FROM remote_songs
          WHERE (virtualUri = ? OR virtualUri LIKE ?)
            AND deletedAt IS NULL
            $createdAtCondition
          ''',
          variables: baseSelectVariables,
          readsFrom: {remoteSongs},
        ).get();

        for (final r in remoteRows) {
          final thumb = r.read<String?>('thumbnailPath');
          if (thumb != null && thumb.isNotEmpty) {
            thumbnailPaths.add(thumb);
          }
        }

        await customUpdate(
          '''
          UPDATE remote_songs
          SET deletedAt = ?, thumbnailPath = NULL
          WHERE (virtualUri = ? OR virtualUri LIKE ?)
            AND deletedAt IS NULL
            $createdAtCondition
          ''',
          variables: baseUpdateVariables,
          updates: {remoteSongs},
        );
      }

      // 4. 异步清理磁盘缩略图文件，不阻塞事务提交
      if (thumbnailPaths.isNotEmpty) {
        _deleteThumbnailFiles(thumbnailPaths).ignore();
      }
    });
  }

  Future<void> clearAllSongs() async {
    final rows = await select(songs).get();
    await delete(songs).go();
    await delete(folderCovers).go();
    await _deleteThumbnailFiles(rows.map((row) => row.thumbnailPath));
  }

  Future<void> clearSongsExceptExternal() async {
    final rows =
        await (select(songs)..where(
              (t) =>
                  t.sourceFlags.isNull() |
                  t.sourceFlags
                      .bitwiseAnd(Variable(SongSourceFlags.external))
                      .equals(0),
            ))
            .get();
    await (delete(songs)..where(
          (t) =>
              t.sourceFlags.isNull() |
              t.sourceFlags
                  .bitwiseAnd(Variable(SongSourceFlags.external))
                  .equals(0),
        ))
        .go();
    await _deleteThumbnailFiles(rows.map((row) => row.thumbnailPath));
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
    await transaction(() async {
      for (var start = 0; start < normalizedPaths.length; start += batchSize) {
        if (start > 0 && start % 2000 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
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
              lastSeenRootScanSessionId = ?,
              deletedAt = NULL
          WHERE path IN (${List.filled(chunk.length, '?').join(', ')})
          ''',
          <Object>[sourceMask, sourceMask, scanToken, ...chunk],
        );
      }
    });
    notifyUpdates({TableUpdate.onTable(songs)});
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
    final thumbnailPathsToDelete = <String?>[];
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
          thumbnailPathsToDelete.add(row.thumbnailPath);
          await (delete(songs)..where((t) => t.path.equals(row.path))).go();
        } else {
          await (update(songs)..where((t) => t.path.equals(row.path))).write(
            SongsCompanion(sourceFlags: Value(nextFlags)),
          );
        }
        changedCount++;
      }
    });
    await _deleteThumbnailFiles(thumbnailPathsToDelete);

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
      SELECT path, sourceFlags, lastSeenRootScanSessionId, thumbnailPath
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
    final thumbnailPathsToDelete = <String?>[];
    final deletedAtMillis = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      for (final row in candidateRows) {
        final path = row.read<String>('path');
        final currentFlags = row.read<int?>('sourceFlags') ?? 0;
        final seenToken = row.read<int?>('lastSeenRootScanSessionId');
        final thumbnailPath = row.read<String?>('thumbnailPath');
        if (seenToken == scanToken) {
          continue;
        }

        if (_isWithinAnyRoot(path, normalizedActiveRoots)) {
          await (update(songs)..where((t) => t.path.equals(path))).write(
            SongsCompanion(
              deletedAt: Value(deletedAtMillis),
              thumbnailPath: const Value(null),
            ),
          );
          softDeletedPaths.add(path);
          thumbnailPathsToDelete.add(thumbnailPath);
          continue;
        }

        final nextFlags = currentFlags == 0 ? 0 : currentFlags & ~sourceMask;
        if (nextFlags == 0) {
          thumbnailPathsToDelete.add(thumbnailPath);
          await (delete(songs)..where((t) => t.path.equals(path))).go();
        } else {
          await (update(songs)..where((t) => t.path.equals(path))).write(
            SongsCompanion(
              sourceFlags: Value(nextFlags),
              deletedAt: const Value(null),
            ),
          );
        }
        deletedPaths.add(path);
      }
    });
    await _deleteThumbnailFiles(thumbnailPathsToDelete);

    return RootScanSweepResult(
      deletedPaths: deletedPaths,
      softDeletedPaths: softDeletedPaths,
    );
  }

  Future<void> bindSongToRoot(String songPath, String rootPath) async {
    final normSong = _normalizePath(songPath);
    final normRoot = _normalizePath(rootPath);
    if (normSong.isEmpty || normRoot.isEmpty) return;
    await into(songRoots).insert(
      SongRootsCompanion.insert(
        songPath: normSong,
        rootPath: normRoot,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> bindSongsToRootBatch(
    Iterable<String> songPaths,
    String rootPath,
  ) async {
    final normRoot = _normalizePath(rootPath);
    if (normRoot.isEmpty) return;
    final normalizedSongPaths = songPaths
        .map(_normalizePath)
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (normalizedSongPaths.isEmpty) return;

    const chunkSize = 2500;
    for (var i = 0; i < normalizedSongPaths.length; i += chunkSize) {
      if (i > 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final end = (i + chunkSize < normalizedSongPaths.length)
          ? i + chunkSize
          : normalizedSongPaths.length;
      final chunk = normalizedSongPaths.sublist(i, end);
      await batch((b) {
        b.insertAll(
          songRoots,
          chunk.map(
            (p) => SongRootsCompanion.insert(songPath: p, rootPath: normRoot),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      });
    }
  }

  Future<void> unbindRootPaths(Iterable<String> rootPaths) async {
    final normalizedRoots = rootPaths
        .map(_normalizePath)
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (normalizedRoots.isEmpty) return;

    await (delete(songRoots)
          ..where((t) => t.rootPath.isIn(normalizedRoots)))
        .go();
  }

  Future<RootScanSweepResult> sweepOrphanSongs({int chunkSize = 2000}) async {
    final candidateRows = await customSelect(
      '''
      SELECT s.path, s.sourceFlags, s.thumbnailPath
      FROM songs s
      LEFT JOIN song_roots r ON s.path = r.song_path
      WHERE r.song_path IS NULL
        AND (s.sourceFlags IS NULL OR (s.sourceFlags & ?) = 0)
        AND s.deletedAt IS NULL
      ''',
      variables: [Variable(SongSourceFlags.external)],
      readsFrom: {songs, songRoots},
    ).get();

    if (candidateRows.isEmpty) {
      return const RootScanSweepResult(
        deletedPaths: <String>[],
        softDeletedPaths: <String>[],
      );
    }

    final deletedPaths = <String>[];
    final thumbnailPathsToDelete = <String?>[];

    for (var i = 0; i < candidateRows.length; i += chunkSize) {
      final end = (i + chunkSize < candidateRows.length)
          ? i + chunkSize
          : candidateRows.length;
      final chunk = candidateRows.sublist(i, end);

      await transaction(() async {
        for (final row in chunk) {
          final path = row.read<String>('path');
          final thumbnailPath = row.read<String?>('thumbnailPath');

          await (delete(songs)..where((t) => t.path.equals(path))).go();
          deletedPaths.add(path);
          if (thumbnailPath != null) {
            thumbnailPathsToDelete.add(thumbnailPath);
          }
        }
      });

      await Future<void>.delayed(Duration.zero);
    }

    _deleteThumbnailFiles(thumbnailPathsToDelete).ignore();

    if (deletedPaths.isNotEmpty) {
      for (var i = 0; i < deletedPaths.length; i += chunkSize) {
        final end = (i + chunkSize < deletedPaths.length)
            ? i + chunkSize
            : deletedPaths.length;
        final chunk = deletedPaths.sublist(i, end);
        await (delete(folderCovers)..where((t) => t.songPath.isIn(chunk))).go();
      }
    }

    return RootScanSweepResult(
      deletedPaths: deletedPaths,
      softDeletedPaths: const <String>[],
    );
  }

  Future<void> insertOrUpdateLyricsCache(LyricsCacheRecord record) async {
    final normalizedCacheKey = ScannerPathUtils.normalizeLyricCacheKey(record.cacheKey);
    if (normalizedCacheKey.isEmpty) return;

    await transaction(() async {
      await (delete(lyricsCaches)
            ..where((t) => t.cacheKey.equals(normalizedCacheKey)))
          .go();

      await into(lyricsCaches).insert(
        LyricsCachesCompanion(
          cacheKey: Value(normalizedCacheKey),
          source: Value(record.source.dbValue),
          languageCode: Value(record.languageCode),
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
    });
  }

  Future<LyricsCacheRecord?> getLyricsCache(String cacheKey) async {
    final normalizedCacheKey = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalizedCacheKey.isEmpty) return null;

    final row =
        await (select(lyricsCaches)
              ..where((t) => t.cacheKey.equals(normalizedCacheKey))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _lyricsCacheFromRow(row);
  }

  Stream<LyricsCacheRecord?> watchLyricsCache(String cacheKey) {
    final normalizedCacheKey = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalizedCacheKey.isEmpty) {
      return Stream.value(null);
    }

    return (select(lyricsCaches)
          ..where((t) => t.cacheKey.equals(normalizedCacheKey))
          ..limit(1))
        .watchSingleOrNull()
        .map((row) => row == null ? null : _lyricsCacheFromRow(row));
  }

  Future<List<LyricsCacheRecord>> getLyricsCaches(String cacheKey) async {
    final normalizedCacheKey = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalizedCacheKey.isEmpty) return const [];

    final rows = await (select(lyricsCaches)
          ..where((t) => t.cacheKey.equals(normalizedCacheKey)))
        .get();
    return rows.map(_lyricsCacheFromRow).toList(growable: false);
  }

  Future<List<LyricsCacheRecord>> getLyricsCachesByPrefix(String prefix) async {
    final normalized = ScannerPathUtils.normalizeLyricCacheKey(prefix);
    if (normalized.isEmpty) return const [];

    final rows = await (select(lyricsCaches)
          ..where((t) => t.cacheKey.like('$normalized%'))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAtMillis)]))
        .get();
    return rows.map(_lyricsCacheFromRow).toList(growable: false);
  }

  Stream<List<LyricsCacheRecord>> watchLyricsCaches(String cacheKey) {
    final normalizedCacheKey = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalizedCacheKey.isEmpty) {
      return Stream.value(const []);
    }

    return (select(lyricsCaches)
          ..where((t) => t.cacheKey.equals(normalizedCacheKey)))
        .watch()
        .map((rows) => rows.map(_lyricsCacheFromRow).toList(growable: false));
  }

  Future<void> clearLyricsCache() async {
    await delete(lyricsCaches).go();
  }

  Future<void> clearLyricsCacheByKey(String cacheKey) async {
    final normalizedCacheKey = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalizedCacheKey.isEmpty) return;

    await (delete(
      lyricsCaches,
    )..where((t) => t.cacheKey.equals(normalizedCacheKey))).go();
  }

  Future<int> insertLyricsHistory(LyricsHistoriesCompanion companion) async {
    final key = companion.cacheKey.value;
    final normalizedKey = ScannerPathUtils.normalizeLyricCacheKey(key);
    final finalCompanion = companion.copyWith(cacheKey: Value(normalizedKey));
    return into(lyricsHistories).insert(finalCompanion);
  }

  Future<List<LyricsHistory>> getLyricsHistories(
    String cacheKey, {
    int limit = 30,
  }) async {
    final normalized = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalized.isEmpty) return const [];
    return (select(lyricsHistories)
          ..where((t) => t.cacheKey.equals(normalized))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAtMillis)])
          ..limit(limit))
        .get();
  }

  Future<int> deleteLyricsHistoryById(int id) async {
    return (delete(lyricsHistories)..where((t) => t.id.equals(id))).go();
  }

  Future<void> trimLyricsHistories(String cacheKey, {int maxCount = 30}) async {
    final normalized = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalized.isEmpty) return;

    final all = await (select(lyricsHistories)
          ..where((t) => t.cacheKey.equals(normalized))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAtMillis)]))
        .get();

    if (all.length > maxCount) {
      final toDeleteIds = all.sublist(maxCount).map((e) => e.id).toList();
      await (delete(lyricsHistories)..where((t) => t.id.isIn(toDeleteIds))).go();
    }
  }

  Future<int> clearLyricsHistoriesByKey(String cacheKey) async {
    final normalized = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalized.isEmpty) return 0;
    return (delete(lyricsHistories)..where((t) => t.cacheKey.equals(normalized))).go();
  }

  Future<List<LyricsCacheRecord>> getAllLyricsCaches() async {
    final rows = await select(lyricsCaches).get();
    return rows.map(_lyricsCacheFromRow).toList(growable: false);
  }

  Future<void> insertOrUpdateLyricsTranslationCache(
    LyricsTranslationCacheRecord record,
  ) async {
    final normalizedCacheKey = ScannerPathUtils.normalizeLyricCacheKey(record.cacheKey);
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
    final normalizedCacheKey = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalizedCacheKey.isEmpty) {
      return const <LyricsTranslationCacheRecord>[];
    }

    final rows =
        await (select(lyricsTranslationCaches)
              ..where((t) => t.cacheKey.equals(normalizedCacheKey))
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
    final normalizedCacheKey = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
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
    final normalizedCacheKey = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalizedCacheKey.isEmpty) return;

    await (delete(
      lyricsTranslationCaches,
    )..where((t) => t.cacheKey.equals(normalizedCacheKey))).go();
  }

  Future<List<LyricsTranslationCacheRecord>>
  getAllLyricsTranslationCaches() async {
    final rows = await select(lyricsTranslationCaches).get();
    return rows.map(_lyricsTranslationCacheFromRow).toList(growable: false);
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

  Future<void> insertOrUpdateArtworkCache(ArtworkCacheRecord record) async {
    await into(artworkCaches).insert(
      ArtworkCachesCompanion(
        md5: Value(record.md5),
        artworkPath: Value(record.artworkPath),
        thumbnailPath: Value(record.thumbnailPath),
        artworkWidth: Value(record.artworkWidth),
        artworkHeight: Value(record.artworkHeight),
        themeColorsBlob: Value(record.themeColorsBlob),
        updatedAtMillis: Value(record.updatedAtMillis),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<ArtworkCacheRecord?> getArtworkCache(String md5) async {
    final row = await (select(artworkCaches)
          ..where((t) => t.md5.equals(md5))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _artworkCacheFromRow(row);
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
    final rawPath = row.read<String>('path');
    final rawArtwork = row.read<String?>('artworkPath');
    final rawThumbnail = row.read<String?>('thumbnailPath');

    return SongMetadata(
      id: row.read<int?>('id'),
      mediaId: row.read<int?>('mediaId'),
      path: ScannerPathUtils.resolveIosSandboxPath(rawPath),
      title: row.read<String?>('title') ?? 'Unknown',
      album: row.read<String?>('album') ?? 'Unknown',
      artist: row.read<String?>('artist') ?? 'Unknown',
      albumArtist: row.read<String?>('albumArtist'),
      duration: row.read<int?>('duration'),
      artworkPath: rawArtwork != null
          ? ScannerPathUtils.resolveIosSandboxPath(rawArtwork)
          : null,
      thumbnailPath: rawThumbnail != null
          ? ScannerPathUtils.resolveIosSandboxPath(rawThumbnail)
          : null,
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
      deletedAt: row.read<int?>('deletedAt'),
      genres: _decodeGenres(row.read<String?>('genres')),
      isAppModified: row.read<bool?>('isAppModified') ?? false,
      hasArtwork: row.read<bool?>('hasArtwork'),
      bitrate: row.read<int?>('bitrate'),
      sampleRate: row.read<int?>('sampleRate'),
      channels: row.read<int?>('channels'),
      bitDepth: row.read<int?>('bitDepth'),
      format: row.read<String?>('format'),
      codec: row.read<String?>('codec'),
    );
  }

  SongMetadata _songFromTableRow(Song row) {
    final resolvedPath = ScannerPathUtils.resolveIosSandboxPath(row.path);
    final resolvedArtwork = row.artworkPath != null
        ? ScannerPathUtils.resolveIosSandboxPath(row.artworkPath!)
        : null;
    final resolvedThumbnail = row.thumbnailPath != null
        ? ScannerPathUtils.resolveIosSandboxPath(row.thumbnailPath!)
        : null;

    if (Platform.isIOS &&
        (resolvedPath != row.path ||
            resolvedArtwork != row.artworkPath ||
            resolvedThumbnail != row.thumbnailPath)) {
      unawaited(customStatement(
        'UPDATE songs SET path = ?, artworkPath = ?, thumbnailPath = ? WHERE id = ?',
        <Object?>[resolvedPath, resolvedArtwork, resolvedThumbnail, row.id],
      ));
    }

    return SongMetadata(
      id: row.id,
      mediaId: row.mediaId,
      path: resolvedPath,
      title: row.title ?? 'Unknown',
      album: row.album ?? 'Unknown',
      artist: row.artist ?? 'Unknown',
      albumArtist: row.albumArtist,
      duration: row.duration,
      artworkPath: resolvedArtwork,
      thumbnailPath: resolvedThumbnail,
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
      deletedAt: row.deletedAt,
      genres: _decodeGenres(row.genres),
      isAppModified: row.isAppModified,
      hasArtwork: row.hasArtwork,
      bitrate: row.bitrate,
      sampleRate: row.sampleRate,
      channels: row.channels,
      bitDepth: row.bitDepth,
      format: row.format,
      codec: row.codec,
    );
  }

  SongsCompanion _songCompanion(
    SongMetadata song, {
    int? lastSeenRootScanSessionId,
  }) {
    return SongsCompanion(
      path: Value(song.path),
      mediaId: Value(song.mediaId),
      title: Value(song.title),
      album: Value(song.album),
      artist: Value(song.artist),
      albumArtist: Value(song.albumArtist),
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
      deletedAt: Value(song.deletedAt),
      genres: Value(song.genres == null ? null : jsonEncode(song.genres)),
      isAppModified: Value(song.isAppModified),
      hasArtwork: Value(song.hasArtwork),
      bitrate: Value(song.bitrate),
      sampleRate: Value(song.sampleRate),
      channels: Value(song.channels),
      bitDepth: Value(song.bitDepth),
      format: Value(song.format),
      codec: Value(song.codec),
      lastSeenRootScanSessionId: lastSeenRootScanSessionId == null
          ? const Value.absent()
          : Value(lastSeenRootScanSessionId),
    );
  }

  static (String serverId, String remoteId) _parseRemoteUri(String uriString) {
    final info = RemoteMediaResolver.parseUri(uriString);
    if (info != null) {
      return (info.serverId, info.trackIdOrPath);
    }
    final uri = Uri.tryParse(uriString);
    if (uri != null) {
      final serverId = uri.host;
      final remoteId = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.join('/')
          : uri.path;
      return (serverId, remoteId);
    }
    return ('', uriString);
  }

  RemoteSongsCompanion _remoteSongCompanion(
    SongMetadata song, {
    String? coverArtId,
    String? suffix,
    int? bitRate,
    String? cachedFilePath,
  }) {
    final (serverId, remoteId) = _parseRemoteUri(song.path);
    final now = DateTime.now().millisecondsSinceEpoch;
    return RemoteSongsCompanion(
      id: song.id != null ? Value(song.id!) : const Value.absent(),
      serverId: Value(serverId),
      remoteId: Value(remoteId),
      virtualUri: Value(song.path),
      title: Value(song.title),
      album: Value(song.album),
      artist: Value(song.artist),
      albumArtist: Value(song.albumArtist),
      duration: Value(song.duration),
      artworkPath: Value(song.artworkPath),
      thumbnailPath: Value(song.thumbnailPath),
      artworkWidth: Value(song.artworkWidth),
      artworkHeight: Value(song.artworkHeight),
      trackNumber: Value(song.trackNumber),
      themeColorsBlob: Value(song.themeColorsBlob),
      waveformBlob: Value(song.waveformBlob),
      coverArtId: Value(coverArtId),
      suffix: Value(suffix),
      bitRate: Value(bitRate),
      cachedFilePath: Value(cachedFilePath),
      createdAt: Value(song.createdAt ?? now),
      updatedAt: Value(now),
      deletedAt: Value(song.deletedAt),
    );
  }

  SongMetadata _songFromRemoteRow(QueryRow row) {
    return SongMetadata(
      id: row.read<int?>('id'),
      path: row.read<String>('virtualUri'),
      title: row.read<String?>('title') ?? 'Unknown',
      album: row.read<String?>('album') ?? 'Unknown',
      artist: row.read<String?>('artist') ?? 'Unknown',
      albumArtist: row.read<String?>('albumArtist'),
      duration: row.read<int?>('duration'),
      artworkPath: row.read<String?>('artworkPath'),
      thumbnailPath: row.read<String?>('thumbnailPath'),
      artworkWidth: row.read<int?>('artworkWidth'),
      artworkHeight: row.read<int?>('artworkHeight'),
      trackNumber: row.read<int?>('trackNumber'),
      themeColorsBlob: row.read<Uint8List?>('themeColorsBlob'),
      waveformBlob: row.read<Uint8List?>('waveformBlob'),
      createdAt: row.read<int?>('createdAt'),
      deletedAt: row.read<int?>('deletedAt'),
    );
  }

  SongMetadata _songFromRemoteTableRow(RemoteSong row) {
    return SongMetadata(
      id: row.id,
      path: row.virtualUri,
      title: row.title ?? 'Unknown',
      album: row.album ?? 'Unknown',
      artist: row.artist ?? 'Unknown',
      albumArtist: row.albumArtist,
      duration: row.duration,
      artworkPath: row.artworkPath,
      thumbnailPath: row.thumbnailPath,
      artworkWidth: row.artworkWidth,
      artworkHeight: row.artworkHeight,
      trackNumber: row.trackNumber,
      themeColorsBlob: row.themeColorsBlob,
      waveformBlob: row.waveformBlob,
      createdAt: row.createdAt,
      deletedAt: row.deletedAt,
    );
  }

  LyricsCacheRecord _lyricsCacheFromRow(LyricsCache row) {
    return LyricsCacheRecord(
      id: row.id,
      cacheKey: row.cacheKey,
      source: LyricsCacheSource.fromDbValue(row.source),
      languageCode: row.languageCode,
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

  ArtworkCacheRecord _artworkCacheFromRow(ArtworkCache row) {
    return ArtworkCacheRecord(
      id: row.id,
      md5: row.md5,
      artworkPath: row.artworkPath,
      thumbnailPath: row.thumbnailPath,
      artworkWidth: row.artworkWidth,
      artworkHeight: row.artworkHeight,
      themeColorsBlob: row.themeColorsBlob,
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
    final lines = decodedValue
        .whereType<Map>()
        .map((item) => LyricLine.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    return LrcUtils.refineWordDurations(lines);
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
    final rawPath = row.read<String>('path');
    final rawArtwork = row.read<String?>('artworkPath');
    final rawThumbnail = row.read<String?>('thumbnailPath');

    final resolvedPath = ScannerPathUtils.resolveIosSandboxPath(rawPath);
    final resolvedArtwork = rawArtwork != null
        ? ScannerPathUtils.resolveIosSandboxPath(rawArtwork)
        : null;
    final resolvedThumbnail = rawThumbnail != null
        ? ScannerPathUtils.resolveIosSandboxPath(rawThumbnail)
        : null;

    if (Platform.isIOS &&
        (resolvedPath != rawPath ||
            resolvedArtwork != rawArtwork ||
            resolvedThumbnail != rawThumbnail)) {
      final id = row.read<int?>('id');
      if (id != null) {
        unawaited(customStatement(
          'UPDATE songs SET path = ?, artworkPath = ?, thumbnailPath = ? WHERE id = ?',
          <Object?>[resolvedPath, resolvedArtwork, resolvedThumbnail, id],
        ));
      }
    }

    return LibraryInsightSongRecord(
      song: SongMetadata(
        id: row.read<int?>('id'),
        path: resolvedPath,
        title: row.read<String?>('title') ?? 'Unknown',
        album: row.read<String?>('album') ?? 'Unknown',
        artist: row.read<String?>('artist') ?? 'Unknown',
        duration: row.read<int?>('duration'),
        artworkPath: resolvedArtwork,
        thumbnailPath: resolvedThumbnail,
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
        isAppModified: row.read<bool?>('isAppModified') ?? false,
        hasArtwork: row.read<bool?>('hasArtwork'),
      ),
      playCount: row.read<int>('playCount'),
      lastPlayedAt: row.read<int?>('lastPlayedAt'),
    );
  }

  Future<void> _ensureIosDirectories() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final currentSandbox = p.dirname(docDir.path);

      ScannerPathUtils.setIosSandboxDirs(
        docDir: docDir.path,
        libDir: p.join(currentSandbox, 'Library', 'Application Support'),
      );

      // Ensure the sharing directory is created so it's never grayed out in the files app!
      final sharingFolderPath = p.join(docDir.path, 'Vynody Music');
      final dir = Directory(sharingFolderPath);
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
          debugPrint(
            '[PathMigration] Created Vynody Music directory at: $sharingFolderPath',
          );
        } catch (e) {
          debugPrint(
            '[PathMigration] Failed to create Vynody Music directory: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('[PathMigration] Failed to ensure iOS directories: $e');
    }
  }

  Future<void> _healIosSandboxPathsInBackground() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final currentSandbox = p.dirname(docDir.path);

      final prefs = await SharedPreferences.getInstance();
      final lastKnownSandbox = prefs.getString('last_known_sandbox_path');

      String? oldSandboxPrefix;
      if (lastKnownSandbox != null) {
        if (lastKnownSandbox != currentSandbox) {
          oldSandboxPrefix = lastKnownSandbox;
        }
      } else {
        // If not found in SharedPreferences, check if there's any song with an old sandbox prefix
        try {
          final regExp = RegExp(r'^(.*)/Containers/Data/Application/([^/]+)');
          final row = await customSelect(
            "SELECT path FROM songs WHERE path LIKE '%/Containers/Data/Application/%' LIMIT 1",
          ).getSingleOrNull();
          if (row != null) {
            final path = row.read<String>('path');
            final match = regExp.firstMatch(path);
            if (match != null) {
              final oldPrefix = match.group(0);
              if (oldPrefix != null && oldPrefix != currentSandbox) {
                oldSandboxPrefix = oldPrefix;
              }
            }
          }
        } catch (e) {
          debugPrint(
            '[PathMigration] Failed to check database for old sandbox prefix: $e',
          );
        }
      }

      // If no old sandbox prefix detected, we're up to date
      if (oldSandboxPrefix == null || oldSandboxPrefix == currentSandbox) {
        await prefs.setString('last_known_sandbox_path', currentSandbox);
        return;
      }

      final oldPrefix = oldSandboxPrefix;
      final oldPrefixNoPrivate = oldPrefix.replaceFirst(RegExp(r'^/private'), '');
      final oldPrefixWithPrivate = oldPrefixNoPrivate.startsWith('/')
          ? '/private$oldPrefixNoPrivate'
          : '/private/$oldPrefixNoPrivate';

      final currentSandboxNoPrivate = currentSandbox.replaceFirst(RegExp(r'^/private'), '');
      final currentSandboxWithPrivate = currentSandboxNoPrivate.startsWith('/')
          ? '/private$currentSandboxNoPrivate'
          : '/private/$currentSandboxNoPrivate';

      debugPrint('[PathMigration] (Background) Healing sandbox UUID paths on iOS.');
      debugPrint('[PathMigration] (Background) Old sandbox: $oldPrefix');
      debugPrint('[PathMigration] (Background) Current sandbox: $currentSandbox');

      // 1. Update SQLite tables in background
      for (final pair in [
        (oldPrefixWithPrivate, currentSandboxWithPrivate),
        (oldPrefixNoPrivate, currentSandboxNoPrivate),
      ]) {
        await customStatement(
          'UPDATE songs SET path = REPLACE(path, ?, ?), '
          'artworkPath = REPLACE(artworkPath, ?, ?), '
          'thumbnailPath = REPLACE(thumbnailPath, ?, ?) '
          'WHERE path LIKE ? OR artworkPath LIKE ? OR thumbnailPath LIKE ?',
          <Object>[
            pair.$1,
            pair.$2,
            pair.$1,
            pair.$2,
            pair.$1,
            pair.$2,
            '%${pair.$1}%',
            '%${pair.$1}%',
            '%${pair.$1}%',
          ],
        );

        await customStatement(
          'UPDATE song_play_history SET songPath = REPLACE(songPath, ?, ?) '
          'WHERE songPath LIKE ?',
          <Object>[pair.$1, pair.$2, '%${pair.$1}%'],
        );

        await customStatement(
          'UPDATE lyrics_cache SET cacheKey = REPLACE(cacheKey, ?, ?) '
          'WHERE cacheKey LIKE ?',
          <Object>[pair.$1, pair.$2, '%${pair.$1}%'],
        );

        await customStatement(
          'UPDATE lyrics_translation_cache SET cacheKey = REPLACE(cacheKey, ?, ?) '
          'WHERE cacheKey LIKE ?',
          <Object>[pair.$1, pair.$2, '%${pair.$1}%'],
        );

        await customStatement(
          'UPDATE artist_image_cache SET imagePath = REPLACE(imagePath, ?, ?) '
          'WHERE imagePath LIKE ?',
          <Object>[pair.$1, pair.$2, '%${pair.$1}%'],
        );

        await customStatement(
          'UPDATE folder_covers SET folderPath = REPLACE(folderPath, ?, ?), '
          'songPath = REPLACE(songPath, ?, ?) '
          'WHERE folderPath LIKE ? OR songPath LIKE ?',
          <Object>[
            pair.$1,
            pair.$2,
            pair.$1,
            pair.$2,
            '%${pair.$1}%',
            '%${pair.$1}%',
          ],
        );
      }

      // 2. Migrate playlists.json in background
      try {
        final playlistsFile = File(
          p.join(currentSandbox, 'Library', 'Application Support', 'playlists.json'),
        );
        String? playlistsJson;
        if (await playlistsFile.exists()) {
          playlistsJson = await playlistsFile.readAsString();
        } else {
          playlistsJson = prefs.getString('playlists');
        }
        if (playlistsJson != null && playlistsJson.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(playlistsJson);
          bool changed = false;
          for (final playlist in jsonList) {
            if (playlist is Map<String, dynamic>) {
              final songs = playlist['songs'];
              if (songs is List) {
                for (final song in songs) {
                  if (song is Map<String, dynamic>) {
                    final path = song['path'];
                    if (path is String && path.contains(oldPrefix)) {
                      song['path'] = path.replaceAll(
                        oldPrefix,
                        currentSandbox,
                      );
                      changed = true;
                    }
                    final thumbnailPath = song['thumbnailPath'];
                    if (thumbnailPath is String &&
                        thumbnailPath.contains(oldPrefix)) {
                      song['thumbnailPath'] = thumbnailPath.replaceAll(
                        oldPrefix,
                        currentSandbox,
                      );
                      changed = true;
                    }
                  }
                }
              }
            }
          }
          if (changed || !await playlistsFile.exists()) {
            final parent = playlistsFile.parent;
            if (!parent.existsSync()) {
              await parent.create(recursive: true);
            }
            final tmpFile = File('${playlistsFile.path}.tmp');
            await tmpFile.writeAsString(jsonEncode(jsonList), flush: true);
            if (await playlistsFile.exists()) {
              await playlistsFile.delete();
            }
            await tmpFile.rename(playlistsFile.path);
            debugPrint('[PathMigration] (Background) Migrated playlists file.');
          }
          if (prefs.containsKey('playlists')) {
            await prefs.remove('playlists');
          }
        }
      } catch (e) {
        debugPrint(
          '[PathMigration] Failed to migrate playlists: $e',
        );
      }

      // 3. Migrate playback_session.json in background
      try {
        final sessionFile = File(
          p.join(currentSandbox, 'Library', 'Application Support', 'playback_session.json'),
        );
        String? rawSession;
        if (await sessionFile.exists()) {
          rawSession = await sessionFile.readAsString();
        } else {
          rawSession = prefs.getString('playback_session_v1');
        }
        if (rawSession != null && rawSession.trim().isNotEmpty) {
          final decoded = jsonDecode(rawSession);
          if (decoded is Map<String, dynamic>) {
            bool changed = false;
            final queue = decoded['queue'];
            if (queue is List) {
              for (final song in queue) {
                if (song is Map<String, dynamic>) {
                  final path = song['path'];
                  if (path is String && path.contains(oldPrefix)) {
                    song['path'] = path.replaceAll(oldPrefix, currentSandbox);
                    changed = true;
                  }
                  final thumbnailPath = song['thumbnailPath'];
                  if (thumbnailPath is String &&
                      thumbnailPath.contains(oldPrefix)) {
                    song['thumbnailPath'] = thumbnailPath.replaceAll(
                      oldPrefix,
                      currentSandbox,
                    );
                    changed = true;
                  }
                }
              }
            }
            if (changed || !await sessionFile.exists()) {
              final parent = sessionFile.parent;
              if (!parent.existsSync()) {
                await parent.create(recursive: true);
              }
              final tmpFile = File('${sessionFile.path}.tmp');
              await tmpFile.writeAsString(jsonEncode(decoded), flush: true);
              if (await sessionFile.exists()) {
                await sessionFile.delete();
              }
              await tmpFile.rename(sessionFile.path);
              debugPrint('[PathMigration] (Background) Migrated playback_session file.');
            }
            if (prefs.containsKey('playback_session_v1')) {
              await prefs.remove('playback_session_v1');
            }
          }
        }
      } catch (e) {
        debugPrint(
          '[PathMigration] Failed to migrate playback_session: $e',
        );
      }

      // Always save the current sandbox path
      await prefs.setString('last_known_sandbox_path', currentSandbox);
      debugPrint('[PathMigration] (Background) Path healing completed.');
    } catch (e, st) {
      debugPrint(
        '[PathMigration] Error running background iOS sandbox path healing: $e\n$st',
      );
    }
  }
}

class Songs extends Table {
  @override
  String get tableName => 'songs';

  IntColumn get id => integer().autoIncrement().named('id')();
  IntColumn get mediaId => integer().nullable().named('mediaId')();
  TextColumn get path => text().named('path')();
  TextColumn get title => text().nullable().named('title')();
  TextColumn get album => text().nullable().named('album')();
  TextColumn get artist => text().nullable().named('artist')();
  TextColumn get albumArtist => text().nullable().named('albumArtist')();
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
  IntColumn get deletedAt => integer().nullable().named('deletedAt')();
  TextColumn get genres => text().nullable().named('genres')();
  BoolColumn get isAppModified =>
      boolean().withDefault(const Constant(false)).named('isAppModified')();
  BoolColumn get hasArtwork =>
      boolean().nullable().named('hasArtwork')();
  IntColumn get bitrate => integer().nullable().named('bitrate')();
  IntColumn get sampleRate => integer().nullable().named('sampleRate')();
  IntColumn get channels => integer().nullable().named('channels')();
  IntColumn get bitDepth => integer().nullable().named('bitDepth')();
  TextColumn get format => text().nullable().named('format')();
  TextColumn get codec => text().nullable().named('codec')();
  IntColumn get lastSeenRootScanSessionId =>
      integer().nullable().named('lastSeenRootScanSessionId')();

  @override
  List<String> get customConstraints => const ['UNIQUE(path)'];
}

class SongRoots extends Table {
  @override
  String get tableName => 'song_roots';

  TextColumn get songPath => text().named('song_path')();
  TextColumn get rootPath => text().named('root_path')();

  @override
  Set<Column> get primaryKey => {songPath, rootPath};
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
  TextColumn get languageCode => text().withDefault(const Constant('')).named('languageCode')();
  BoolColumn get isSynced => boolean().named('isSynced')();
  TextColumn get syncedLyrics => text().nullable().named('syncedLyrics')();
  TextColumn get syncedLinesJson => text().named('syncedLinesJson')();
  IntColumn get timelineOffsetMillis =>
      integer().named('timelineOffsetMillis')();
  IntColumn get updatedAtMillis => integer().named('updatedAtMillis')();

  @override
  List<String> get customConstraints => const ['UNIQUE(cacheKey)'];
}

class LyricsHistories extends Table {
  @override
  String get tableName => 'lyrics_history';

  IntColumn get id => integer().autoIncrement().named('id')();
  TextColumn get cacheKey => text().named('cacheKey')();
  TextColumn get actionType => text().named('actionType')();
  TextColumn get description => text().named('description')();
  TextColumn get lyrics => text().named('lyrics')();
  TextColumn get translation => text().nullable().named('translation')();
  IntColumn get timelineOffsetMillis =>
      integer().withDefault(const Constant(0)).named('timelineOffsetMillis')();
  IntColumn get createdAtMillis => integer().named('createdAtMillis')();
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

class ArtworkCaches extends Table {
  @override
  String get tableName => 'artwork_cache';

  IntColumn get id => integer().autoIncrement().named('id')();
  TextColumn get md5 => text().named('md5')();
  TextColumn get artworkPath => text().nullable().named('artworkPath')();
  TextColumn get thumbnailPath => text().nullable().named('thumbnailPath')();
  IntColumn get artworkWidth => integer().nullable().named('artworkWidth')();
  IntColumn get artworkHeight => integer().nullable().named('artworkHeight')();
  BlobColumn get themeColorsBlob => blob().nullable().named('themeColorsBlob')();
  IntColumn get updatedAtMillis => integer().named('updatedAtMillis')();

  @override
  List<String> get customConstraints => const ['UNIQUE(md5)'];
}

class RemoteSongs extends Table {
  @override
  String get tableName => 'remote_songs';

  IntColumn get id => integer().autoIncrement().named('id')();
  TextColumn get serverId => text().named('serverId')();
  TextColumn get remoteId => text().named('remoteId')();
  TextColumn get virtualUri => text().named('virtualUri')();
  TextColumn get title => text().nullable().named('title')();
  TextColumn get album => text().nullable().named('album')();
  TextColumn get artist => text().nullable().named('artist')();
  TextColumn get albumArtist => text().nullable().named('albumArtist')();
  IntColumn get duration => integer().nullable().named('duration')();
  TextColumn get artworkPath => text().nullable().named('artworkPath')();
  TextColumn get thumbnailPath => text().nullable().named('thumbnailPath')();
  IntColumn get artworkWidth => integer().nullable().named('artworkWidth')();
  IntColumn get artworkHeight => integer().nullable().named('artworkHeight')();
  IntColumn get trackNumber => integer().nullable().named('trackNumber')();
  BlobColumn get themeColorsBlob =>
      blob().nullable().named('themeColorsBlob')();
  BlobColumn get waveformBlob => blob().nullable().named('waveformBlob')();
  TextColumn get coverArtId => text().nullable().named('coverArtId')();
  TextColumn get suffix => text().nullable().named('suffix')();
  IntColumn get bitRate => integer().nullable().named('bitRate')();
  TextColumn get cachedFilePath => text().nullable().named('cachedFilePath')();
  IntColumn get createdAt => integer().nullable().named('createdAt')();
  IntColumn get updatedAt => integer().nullable().named('updatedAt')();
  IntColumn get deletedAt => integer().nullable().named('deletedAt')();

  @override
  List<String> get customConstraints => const ['UNIQUE(virtualUri)'];
}

class FolderCovers extends Table {
  @override
  String get tableName => 'folder_covers';

  TextColumn get folderPath => text().named('folderPath')();
  TextColumn get songPath => text().named('songPath')();
  IntColumn get updatedAtMillis => integer().named('updatedAtMillis')();

  @override
  Set<Column> get primaryKey => {folderPath};
}

class RemoteLibraryCaches extends Table {
  @override
  String get tableName => 'remote_library_caches';

  TextColumn get serverId => text().named('serverId')();
  TextColumn get category => text().named('category')(); // 'songs', 'albums', 'artists', 'playlists', 'starred_songs'
  TextColumn get dataJson => text().named('dataJson')();
  IntColumn get count => integer().nullable().named('count')();
  IntColumn get updatedAtMillis => integer().named('updatedAtMillis')();

  @override
  Set<Column> get primaryKey => {serverId, category};
}

extension MetadataRemoteLibraryCachesOps on MetadataDriftDatabase {
  Future<void> saveRemoteLibraryCache({
    required String serverId,
    required String category,
    required String dataJson,
    int? count,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanServerId = serverId.trim();
    if (cleanServerId.isEmpty) return;

    await into(remoteLibraryCaches).insertOnConflictUpdate(
      RemoteLibraryCachesCompanion(
        serverId: Value(cleanServerId),
        category: Value(category),
        dataJson: Value(dataJson),
        count: Value(count),
        updatedAtMillis: Value(now),
      ),
    );
  }

  Future<({String dataJson, int? count, int updatedAtMillis})?> getRemoteLibraryCache({
    required String serverId,
    required String category,
  }) async {
    final cleanServerId = serverId.trim();
    if (cleanServerId.isEmpty) return null;

    final row = await (select(remoteLibraryCaches)
          ..where((t) =>
              t.serverId.equals(cleanServerId) & t.category.equals(category))
          ..limit(1))
        .getSingleOrNull();

    if (row == null) return null;
    return (
      dataJson: row.dataJson,
      count: row.count,
      updatedAtMillis: row.updatedAtMillis,
    );
  }

  Future<void> clearRemoteLibraryCache({
    required String serverId,
    String? category,
  }) async {
    final cleanServerId = serverId.trim();
    if (cleanServerId.isEmpty) return;

    if (category != null) {
      await (delete(remoteLibraryCaches)
            ..where((t) =>
                t.serverId.equals(cleanServerId) & t.category.equals(category)))
          .go();
    } else {
      await (delete(remoteLibraryCaches)
            ..where((t) => t.serverId.equals(cleanServerId)))
          .go();
    }
  }
}

extension MetadataFolderCoversOps on MetadataDriftDatabase {
  Future<void> batchUpsertFolderCovers(Map<String, String> covers) async {
    if (covers.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await batch((b) {
      for (final entry in covers.entries) {
        b.insert(
          folderCovers,
          FolderCoversCompanion(
            folderPath: Value(_normalizePath(entry.key)),
            songPath: Value(_normalizePath(entry.value)),
            updatedAtMillis: Value(now),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> upsertFolderCover(String folderPath, String songPath) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(folderCovers).insert(
      FolderCoversCompanion(
        folderPath: Value(_normalizePath(folderPath)),
        songPath: Value(_normalizePath(songPath)),
        updatedAtMillis: Value(now),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<Map<String, String>> getAllFolderCovers() async {
    final rows = await select(folderCovers).get();
    final result = <String, String>{};
    for (final row in rows) {
      result[row.folderPath] = row.songPath;
    }
    return result;
  }

  Future<Map<String, SongMetadata>> getAllFolderRepresentativeMetadata() async {
    final query = select(folderCovers).join([
      innerJoin(songs, songs.path.equalsExp(folderCovers.songPath)),
    ])..where(songs.deletedAt.isNull());

    final rows = await query.get();
    final result = <String, SongMetadata>{};
    for (final row in rows) {
      final coverRow = row.readTable(folderCovers);
      final songRow = row.readTable(songs);
      final resolvedFolder = ScannerPathUtils.resolveIosSandboxPath(coverRow.folderPath);
      result[resolvedFolder] = _songFromTableRow(songRow);
    }
    return result;
  }

  Future<SongMetadata?> getFolderRepresentativeMetadata(String folderPath) async {
    final normalized = _normalizePath(folderPath);
    if (normalized.isEmpty) return null;
    final resolvedFolder = _normalizePath(ScannerPathUtils.resolveIosSandboxPath(folderPath));
    final sandboxSuffix = MetadataDriftDatabase._extractIosSandboxSuffix(normalized);

    Expression<bool> whereClause =
        folderCovers.folderPath.equals(normalized) |
        folderCovers.folderPath.equals(resolvedFolder);
    if (sandboxSuffix != null) {
      whereClause = whereClause |
          folderCovers.folderPath.like('%/Containers/Data/Application/%$sandboxSuffix');
    }
    whereClause = whereClause & songs.deletedAt.isNull();

    final query = select(folderCovers).join([
      innerJoin(songs, songs.path.equalsExp(folderCovers.songPath)),
    ])..where(whereClause);

    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return _songFromTableRow(row.readTable(songs));
  }

  Future<void> removeFolderCoversForPaths(Iterable<String> folderPaths) async {
    final normalized = folderPaths.map(_normalizePath).toSet();
    if (normalized.isEmpty) return;
    await (delete(folderCovers)..where((tbl) => tbl.folderPath.isIn(normalized))).go();
  }

  Future<void> removeFolderCoversUnderRoots(Iterable<String> rootPaths) async {
    final normalizedRoots =
        rootPaths.map(_normalizePath).where((p) => p.isNotEmpty).toList();
    if (normalizedRoots.isEmpty) return;

    for (final root in normalizedRoots) {
      final separator = Platform.isWindows ? '\\' : '/';
      final prefixPattern =
          root.endsWith(separator) ? '$root%' : '$root$separator%';
      await (delete(folderCovers)
            ..where(
              (tbl) =>
                  tbl.folderPath.equals(root) |
                  tbl.folderPath.like(prefixPattern),
            ))
          .go();
    }
  }
}

void _setupSqliteInIsolate([Object? db]) {}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    _setupSqliteInIsolate();
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'metadata.db'));
    return NativeDatabase.createInBackground(
      file,
      isolateSetup: _setupSqliteInIsolate,
      setup: _setupSqliteInIsolate,
    );
  });
}

String _normalizeArtistCacheKey(String queryKey) {
  return queryKey.trim().toLowerCase();
}
