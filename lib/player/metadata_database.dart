import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

part 'metadata_database.freezed.dart';

@freezed
abstract class SongMetadata with _$SongMetadata {
  const SongMetadata._();

  const factory SongMetadata({
    int? id,
    required String path,
    required String title,
    required String album,
    required String artist,
    int? duration,
    String? artworkPath,
    String? thumbnailPath,
    int? artworkWidth,
    int? artworkHeight,
    int? trackNumber,
    Uint8List? themeColorsBlob,
    Uint8List? waveformBlob,
    int? lastModifiedTime,
    int? createdAt,
    List<String>? genres,
  }) = _SongMetadata;

  /// Check if this metadata has been modified since creation
  bool get isModified {
    if (createdAt == null || lastModifiedTime == null) return false;
    return lastModifiedTime! > createdAt!;
  }

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'title': title,
      'album': album,
      'artist': artist,
      'duration': duration,
      'artworkPath': artworkPath,
      'thumbnailPath': thumbnailPath,
      'artworkWidth': artworkWidth,
      'artworkHeight': artworkHeight,
      'trackNumber': trackNumber,
      'themeColorsBlob': themeColorsBlob,
      'waveformBlob': waveformBlob,
      'lastModifiedTime': lastModifiedTime,
      'createdAt': createdAt,
      'genres': genres != null ? jsonEncode(genres) : null,
    };
  }

  factory SongMetadata.fromMap(Map<String, dynamic> map) {
    List<String>? genres;
    if (map['genres'] != null) {
      final decoded = jsonDecode(map['genres'] as String);
      if (decoded is List) {
        genres = decoded.cast<String>();
      }
    }
    return SongMetadata(
      id: map['id'],
      path: map['path'],
      title: map['title'] ?? 'Unknown',
      album: map['album'] ?? 'Unknown',
      artist: map['artist'] ?? 'Unknown',
      duration: map['duration'],
      artworkPath: map['artworkPath'],
      thumbnailPath: map['thumbnailPath'],
      artworkWidth: map['artworkWidth'],
      artworkHeight: map['artworkHeight'],
      trackNumber: map['trackNumber'],
      themeColorsBlob: map['themeColorsBlob'] as Uint8List?,
      waveformBlob: map['waveformBlob'] as Uint8List?,
      lastModifiedTime: map['lastModifiedTime'],
      createdAt: map['createdAt'],
      genres: genres,
    );
  }
}

class LyricsCacheRecord {
  // SQLite 自增主键，只用于数据库内部标识。
  final int? id;
  // 本次歌词查询的缓存键，由歌曲路径、标题、歌手、专辑、时长组合生成。
  final String cacheKey;
  // 缓存来源，例如 get、search、none、gemini_generate、gemini_timeline。
  final String source;
  // 是否为同步歌词。
  final bool isSynced;
  // 原始带时间轴歌词文本。
  final String? syncedLyrics;
  // 已解析好的逐行时间轴数据，便于直接恢复渲染。
  final List<Map<String, dynamic>> syncedLines;
  // 手动调整后的整体时间轴偏移，单位毫秒。
  final int timelineOffsetMillis;
  // 最近更新时间，毫秒时间戳。
  final int updatedAtMillis;

  const LyricsCacheRecord({
    this.id,
    required this.cacheKey,
    required this.source,
    required this.isSynced,
    this.syncedLyrics,
    required this.syncedLines,
    required this.timelineOffsetMillis,
    required this.updatedAtMillis,
  });

  Map<String, dynamic> toMap() {
    return {
      'cacheKey': cacheKey,
      'source': source,
      'isSynced': isSynced ? 1 : 0,
      'syncedLyrics': syncedLyrics,
      'syncedLinesJson': jsonEncode(syncedLines),
      'timelineOffsetMillis': timelineOffsetMillis,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  factory LyricsCacheRecord.fromMap(Map<String, dynamic> map) {
    final syncedLinesJson = map['syncedLinesJson'] as String?;
    final decodedLines = syncedLinesJson == null || syncedLinesJson.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(syncedLinesJson) as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

    return LyricsCacheRecord(
      id: map['id'] as int?,
      cacheKey: map['cacheKey'] as String,
      source: map['source'] as String? ?? 'search',
      isSynced: (map['isSynced'] as int? ?? 0) == 1,
      syncedLyrics: map['syncedLyrics'] as String?,
      syncedLines: decodedLines,
      timelineOffsetMillis: (map['timelineOffsetMillis'] as int?) ?? 0,
      updatedAtMillis:
          (map['updatedAtMillis'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class LyricsTranslationCacheRecord {
  final int? id;
  final String cacheKey;
  final String languageCode;
  final String translatedText;
  final List<String> translatedLines;
  final String? provider;
  final int updatedAtMillis;

  const LyricsTranslationCacheRecord({
    this.id,
    required this.cacheKey,
    required this.languageCode,
    required this.translatedText,
    required this.translatedLines,
    this.provider,
    required this.updatedAtMillis,
  });

  Map<String, dynamic> toMap() {
    return {
      'cacheKey': cacheKey,
      'languageCode': languageCode,
      'translatedText': translatedText,
      'translatedLinesJson': jsonEncode(translatedLines),
      'provider': provider,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  factory LyricsTranslationCacheRecord.fromMap(Map<String, dynamic> map) {
    final rawLines = map['translatedLinesJson'] as String?;
    final decodedLines = rawLines == null || rawLines.isEmpty
        ? <String>[]
        : (jsonDecode(rawLines) as List)
              .map((item) => item?.toString() ?? '')
              .toList(growable: false);

    return LyricsTranslationCacheRecord(
      id: map['id'] as int?,
      cacheKey: map['cacheKey'] as String? ?? '',
      languageCode: map['languageCode'] as String? ?? 'zh',
      translatedText: map['translatedText'] as String? ?? '',
      translatedLines: decodedLines,
      provider: map['provider'] as String?,
      updatedAtMillis:
          (map['updatedAtMillis'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class AcoustIDCacheRecord {
  final int? id;
  final String fingerprint;
  final int durationSeconds;
  final String resultsJson;
  final int updatedAtMillis;

  const AcoustIDCacheRecord({
    this.id,
    required this.fingerprint,
    required this.durationSeconds,
    required this.resultsJson,
    required this.updatedAtMillis,
  });

  Map<String, dynamic> toMap() {
    return {
      'fingerprint': fingerprint,
      'durationSeconds': durationSeconds,
      'resultsJson': resultsJson,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  factory AcoustIDCacheRecord.fromMap(Map<String, dynamic> map) {
    return AcoustIDCacheRecord(
      id: map['id'] as int?,
      fingerprint: map['fingerprint'] as String? ?? '',
      durationSeconds: (map['durationSeconds'] as int?) ?? 0,
      resultsJson: map['resultsJson'] as String? ?? '[]',
      updatedAtMillis:
          (map['updatedAtMillis'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class ReleaseCoverCacheRecord {
  final int? id;
  final String releaseId;
  final String? largeUrl;
  final String? thumbnailUrl;
  final int updatedAtMillis;

  const ReleaseCoverCacheRecord({
    this.id,
    required this.releaseId,
    this.largeUrl,
    this.thumbnailUrl,
    required this.updatedAtMillis,
  });

  Map<String, dynamic> toMap() {
    return {
      'releaseId': releaseId,
      'largeUrl': largeUrl,
      'thumbnailUrl': thumbnailUrl,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  factory ReleaseCoverCacheRecord.fromMap(Map<String, dynamic> map) {
    return ReleaseCoverCacheRecord(
      id: map['id'] as int?,
      releaseId: map['releaseId'] as String? ?? '',
      largeUrl: map['largeUrl'] as String?,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      updatedAtMillis:
          (map['updatedAtMillis'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class MetadataDatabase {
  static Database? _database;
  static final MetadataDatabase _instance = MetadataDatabase._internal();

  factory MetadataDatabase() => _instance;

  MetadataDatabase._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final directory = await getApplicationSupportDirectory();
    final path = p.join(directory.path, 'metadata.db');

    return await openDatabase(
      path,
      version: 17,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE songs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT UNIQUE,
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
            lastModifiedTime INTEGER,
            createdAt INTEGER,
            genres TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE lyrics_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cacheKey TEXT UNIQUE,
            source TEXT,
            isSynced INTEGER,
            syncedLyrics TEXT,
            syncedLinesJson TEXT,
            timelineOffsetMillis INTEGER,
            updatedAtMillis INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE acoustid_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fingerprint TEXT UNIQUE,
            durationSeconds INTEGER,
            resultsJson TEXT,
            updatedAtMillis INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE release_cover_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            releaseId TEXT UNIQUE,
            largeUrl TEXT,
            thumbnailUrl TEXT,
            updatedAtMillis INTEGER
          )
        ''');

        await db.execute('''
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          if (!await _columnExists(db, 'songs', 'artworkWidth')) {
            await db.execute(
              'ALTER TABLE songs ADD COLUMN artworkWidth INTEGER',
            );
          }
          if (!await _columnExists(db, 'songs', 'artworkHeight')) {
            await db.execute(
              'ALTER TABLE songs ADD COLUMN artworkHeight INTEGER',
            );
          }
        }
        if (oldVersion < 3) {
          if (!await _columnExists(db, 'songs', 'trackNumber')) {
            await db.execute(
              'ALTER TABLE songs ADD COLUMN trackNumber INTEGER',
            );
          }
        }
        if (oldVersion < 4) {
          if (!await _columnExists(db, 'songs', 'themeColorsBlob')) {
            await db.execute(
              'ALTER TABLE songs ADD COLUMN themeColorsBlob BLOB',
            );
          }
        }
        if (oldVersion < 5) {
          if (!await _columnExists(db, 'songs', 'waveformBlob')) {
            await db.execute('ALTER TABLE songs ADD COLUMN waveformBlob BLOB');
          }
        }
        if (oldVersion < 6) {
          await db.execute('''
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
        if (oldVersion < 7) {
          if (!await _columnExists(db, 'songs', 'thumbnailPath')) {
            await db.execute('ALTER TABLE songs ADD COLUMN thumbnailPath TEXT');
          }
        }
        if (oldVersion < 8) {
          if (!await _columnExists(db, 'songs', 'lastModifiedTime')) {
            await db.execute(
              'ALTER TABLE songs ADD COLUMN lastModifiedTime INTEGER',
            );
          }
        }
        if (oldVersion < 9) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS acoustid_cache (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              fingerprint TEXT UNIQUE,
              durationSeconds INTEGER,
              resultsJson TEXT,
              updatedAtMillis INTEGER
            )
          ''');
        }
        if (oldVersion < 10) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS release_cover_cache (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              releaseId TEXT UNIQUE,
              largeUrl TEXT,
              thumbnailUrl TEXT,
              updatedAtMillis INTEGER
            )
          ''');
        }
        if (oldVersion < 11) {
          if (!await _columnExists(db, 'songs', 'genres')) {
            await db.execute('ALTER TABLE songs ADD COLUMN genres TEXT');
          }
        }
        if (oldVersion < 12) {
          if (!await _columnExists(db, 'songs', 'createdAt')) {
            await db.execute('ALTER TABLE songs ADD COLUMN createdAt INTEGER');
          }
        }
        if (oldVersion < 13) {
          await db.execute('''
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
        if (oldVersion < 14) {
          if (!await _columnExists(db, 'lyrics_cache', 'cacheKey')) {
            await db.execute(
              'ALTER TABLE lyrics_cache ADD COLUMN cacheKey TEXT',
            );
          }
        }
        if (oldVersion < 15) {
          await db.execute('DROP TABLE IF EXISTS lyrics_translation_cache');
          await db.execute('''
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
        if (oldVersion < 16) {
          await db.execute('DROP TABLE IF EXISTS acoustid_cache');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS acoustid_cache (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              fingerprint TEXT UNIQUE,
              durationSeconds INTEGER,
              resultsJson TEXT,
              updatedAtMillis INTEGER
            )
          ''');
        }
        if (oldVersion < 17) {
          if (!await _columnExists(
            db,
            'lyrics_cache',
            'timelineOffsetMillis',
          )) {
            await db.execute(
              'ALTER TABLE lyrics_cache ADD COLUMN timelineOffsetMillis INTEGER',
            );
          }
        }
      },
    );
  }

  Future<bool> _columnExists(
    DatabaseExecutor db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }

  Future<void> insertOrUpdateSong(SongMetadata song) async {
    final db = await database;
    await db.insert(
      'songs',
      song.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertOrUpdateLyricsCache(LyricsCacheRecord record) async {
    final db = await database;
    await db.insert(
      'lyrics_cache',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<LyricsCacheRecord?> getLyricsCache(String cacheKey) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'lyrics_cache',
      where: 'cacheKey = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return LyricsCacheRecord.fromMap(maps.first);
    }
    return null;
  }

  Future<void> insertOrUpdateLyricsTranslationCache(
    LyricsTranslationCacheRecord record,
  ) async {
    final db = await database;
    final normalizedCacheKey = record.cacheKey.trim();
    if (normalizedCacheKey.isNotEmpty) {
      await db.delete(
        'lyrics_translation_cache',
        where: 'cacheKey = ? AND languageCode = ?',
        whereArgs: [normalizedCacheKey, record.languageCode],
      );
    }
    await db.insert(
      'lyrics_translation_cache',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<LyricsTranslationCacheRecord>> getLyricsTranslationCaches(
    String cacheKey,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'lyrics_translation_cache',
      where: 'cacheKey = ?',
      whereArgs: [cacheKey],
      orderBy: 'updatedAtMillis DESC',
    );
    return maps.map(LyricsTranslationCacheRecord.fromMap).toList();
  }

  Future<void> insertOrUpdateAcoustIDCache(AcoustIDCacheRecord record) async {
    final db = await database;
    await db.insert(
      'acoustid_cache',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AcoustIDCacheRecord?> getAcoustIDCache(String fingerprint) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'acoustid_cache',
      where: 'fingerprint = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return AcoustIDCacheRecord.fromMap(maps.first);
    }
    return null;
  }

  Future<void> insertOrUpdateReleaseCoverCache(
    ReleaseCoverCacheRecord record,
  ) async {
    final db = await database;
    await db.insert(
      'release_cover_cache',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ReleaseCoverCacheRecord?> getReleaseCoverCache(
    String releaseId,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'release_cover_cache',
      where: 'releaseId = ?',
      whereArgs: [releaseId],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return ReleaseCoverCacheRecord.fromMap(maps.first);
    }
    return null;
  }

  Future<SongMetadata?> getSongMetadata(String path) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'songs',
      where: 'path = ?',
      whereArgs: [path],
    );

    if (maps.isNotEmpty) {
      return SongMetadata.fromMap(maps.first);
    }
    return null;
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('songs');
  }

  Future<void> clearLyricsCache() async {
    final db = await database;
    await db.delete('lyrics_cache');
  }

  Future<void> clearLyricsCacheByKey(String cacheKey) async {
    final normalizedCacheKey = cacheKey.trim();
    if (normalizedCacheKey.isEmpty) return;

    final db = await database;
    await db.delete(
      'lyrics_cache',
      where: 'cacheKey = ?',
      whereArgs: [normalizedCacheKey],
    );
  }

  Future<void> clearLyricsTranslationCache() async {
    final db = await database;
    await db.delete('lyrics_translation_cache');
  }

  Future<void> clearLyricsTranslationCacheByKey(String cacheKey) async {
    final normalizedCacheKey = cacheKey.trim();
    if (normalizedCacheKey.isEmpty) return;

    final db = await database;
    await db.delete(
      'lyrics_translation_cache',
      where: 'cacheKey = ?',
      whereArgs: [normalizedCacheKey],
    );
  }
}
