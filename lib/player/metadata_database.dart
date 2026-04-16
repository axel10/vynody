import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'lyrics_cache_models.dart';
export 'lyrics_cache_models.dart';

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
    int? metadataTextScanned,
    int? metadataImgScanned,
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
      'metadataTextScanned': metadataTextScanned,
      'metadataImgScanned': metadataImgScanned,
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
      metadataTextScanned: map['metadataTextScanned'],
      metadataImgScanned: map['metadataImgScanned'],
      createdAt: map['createdAt'],
      genres: genres,
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
  static Future<void> _dbQueue = Future<void>.value();

  factory MetadataDatabase() => _instance;

  MetadataDatabase._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final directory = await getApplicationSupportDirectory();
    final path = p.join(directory.path, 'metadata.db');

    final factory = Platform.isWindows || Platform.isLinux || Platform.isMacOS
        ? databaseFactoryFfi
        : databaseFactory;

    return await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 18,
        onConfigure: (db) async {
          await db.execute('PRAGMA busy_timeout = 5000');
        },
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
            metadataTextScanned INTEGER,
            metadataImgScanned INTEGER,
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
              await db.execute(
                'ALTER TABLE songs ADD COLUMN waveformBlob BLOB',
              );
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
              await db.execute(
                'ALTER TABLE songs ADD COLUMN thumbnailPath TEXT',
              );
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
              await db.execute(
                'ALTER TABLE songs ADD COLUMN createdAt INTEGER',
              );
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
          if (oldVersion < 18) {
            if (!await _columnExists(
              db,
              'songs',
              'metadataTextScanned',
            )) {
              await db.execute(
                'ALTER TABLE songs ADD COLUMN metadataTextScanned INTEGER',
              );
            }
            if (!await _columnExists(
              db,
              'songs',
              'metadataImgScanned',
            )) {
              await db.execute(
                'ALTER TABLE songs ADD COLUMN metadataImgScanned INTEGER',
              );
            }
          }
        },
      ),
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

  Future<T> _withDbLock<T>(Future<T> Function(Database db) action) async {
    final completer = Completer<T>();
    final previous = _dbQueue;
    _dbQueue = previous.then((_) async {
      try {
        final db = await database;
        final result = await action(db);
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    });
    return completer.future;
  }

  Future<void> insertOrUpdateSong(SongMetadata song) async {
    await _withDbLock((db) {
      return db.insert(
        'songs',
        song.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> insertOrUpdateLyricsCache(LyricsCacheRecord record) async {
    await _withDbLock((db) {
      return db.insert(
        'lyrics_cache',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<LyricsCacheRecord?> getLyricsCache(String cacheKey) async {
    return _withDbLock((db) async {
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
    });
  }

  Future<void> insertOrUpdateLyricsTranslationCache(
    LyricsTranslationCacheRecord record,
  ) async {
    await _withDbLock((db) async {
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
    });
  }

  Future<List<LyricsTranslationCacheRecord>> getLyricsTranslationCaches(
    String cacheKey,
  ) async {
    return _withDbLock((db) async {
      final List<Map<String, dynamic>> maps = await db.query(
        'lyrics_translation_cache',
        where: 'cacheKey = ?',
        whereArgs: [cacheKey],
        orderBy: 'updatedAtMillis DESC',
      );
      return maps.map(LyricsTranslationCacheRecord.fromMap).toList();
    });
  }

  Future<void> insertOrUpdateAcoustIDCache(AcoustIDCacheRecord record) async {
    await _withDbLock((db) {
      return db.insert(
        'acoustid_cache',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<AcoustIDCacheRecord?> getAcoustIDCache(String fingerprint) async {
    return _withDbLock((db) async {
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
    });
  }

  Future<void> insertOrUpdateReleaseCoverCache(
    ReleaseCoverCacheRecord record,
  ) async {
    await _withDbLock((db) {
      return db.insert(
        'release_cover_cache',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<ReleaseCoverCacheRecord?> getReleaseCoverCache(
    String releaseId,
  ) async {
    return _withDbLock((db) async {
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
    });
  }

  Future<SongMetadata?> getSongMetadata(String path) async {
    return _withDbLock((db) async {
      final List<Map<String, dynamic>> maps = await db.query(
        'songs',
        where: 'path = ?',
        whereArgs: [path],
      );

      if (maps.isNotEmpty) {
        return SongMetadata.fromMap(maps.first);
      }
      return null;
    });
  }

  Future<Map<String, SongMetadata>> getSongMetadataByPaths(
    Iterable<String> paths,
  ) async {
    final normalizedPaths = <String>[];
    final seen = <String>{};

    for (final path in paths) {
      final normalized = _normalizePath(path);
      if (normalized.isEmpty) continue;

      final lookupKey = _pathLookupKey(normalized);
      if (seen.add(lookupKey)) {
        normalizedPaths.add(normalized);
      }
    }

    if (normalizedPaths.isEmpty) {
      return {};
    }

    return _withDbLock((db) async {
      final result = <String, SongMetadata>{};

      const batchSize = 300;
      for (var start = 0; start < normalizedPaths.length; start += batchSize) {
        final end = start + batchSize < normalizedPaths.length
            ? start + batchSize
            : normalizedPaths.length;
        final chunk = normalizedPaths.sublist(start, end);
        final placeholders = List.filled(chunk.length, '?').join(', ');
        final rows = await db.query(
          'songs',
          where: 'path IN ($placeholders)',
          whereArgs: chunk,
        );

        for (final row in rows) {
          final metadata = SongMetadata.fromMap(row);
          result[_pathLookupKey(metadata.path)] = metadata;
        }
      }

      return result;
    });
  }

  Future<int> deleteSongsMissingFromPaths({
    required Iterable<String> scopeRoots,
    required Iterable<String> presentPaths,
  }) async {
    final normalizedPresentPaths = presentPaths
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .map((path) => Platform.isWindows ? path.toLowerCase() : path)
        .toSet();
    final normalizedScopeRoots = scopeRoots
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toList();

    if (normalizedScopeRoots.isEmpty) return 0;

    return _withDbLock((db) async {
      final rows = await db.query('songs', columns: ['path']);
      final missingPaths = <String>[];

      for (final row in rows) {
        final path = row['path'] as String?;
        if (path == null || path.isEmpty) continue;
        final normalizedPath = _normalizePath(path);
        final normalizedLookup = Platform.isWindows
            ? normalizedPath.toLowerCase()
            : normalizedPath;
        if (normalizedPresentPaths.contains(normalizedLookup)) continue;
        if (!_isWithinAnyRoot(normalizedPath, normalizedScopeRoots)) continue;
        missingPaths.add(normalizedPath);
      }

      if (missingPaths.isEmpty) return 0;

      final batch = db.batch();
      for (final path in missingPaths) {
        batch.delete('songs', where: 'path = ?', whereArgs: [path]);
      }
      await batch.commit(noResult: true);
      return missingPaths.length;
    });
  }

  Future<void> clearAll() async {
    await _withDbLock((db) => db.delete('songs'));
  }

  Future<void> clearWaveformCache() async {
    await _withDbLock((db) {
      return db.rawUpdate(
        'UPDATE songs SET waveformBlob = NULL WHERE waveformBlob IS NOT NULL',
      );
    });
  }

  Future<void> clearLyricsCache() async {
    await _withDbLock((db) => db.delete('lyrics_cache'));
  }

  Future<void> clearLyricsCacheByKey(String cacheKey) async {
    final normalizedCacheKey = cacheKey.trim();
    if (normalizedCacheKey.isEmpty) return;

    await _withDbLock((db) {
      return db.delete(
        'lyrics_cache',
        where: 'cacheKey = ?',
        whereArgs: [normalizedCacheKey],
      );
    });
  }

  Future<void> clearLyricsTranslationCache() async {
    await _withDbLock((db) => db.delete('lyrics_translation_cache'));
  }

  Future<void> clearLyricsTranslationCacheByKey(String cacheKey) async {
    final normalizedCacheKey = cacheKey.trim();
    if (normalizedCacheKey.isEmpty) return;

    await _withDbLock((db) {
      return db.delete(
        'lyrics_translation_cache',
        where: 'cacheKey = ?',
        whereArgs: [normalizedCacheKey],
      );
    });
  }

  String _normalizePath(String path) {
    var normalized = p.normalize(path.trim());
    if (Platform.isWindows) {
      normalized = normalized.replaceAll('/', r'\');
      if (normalized.length > 3 && normalized.endsWith(r'\')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
    } else if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _pathLookupKey(String path) {
    final normalized = _normalizePath(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  bool _pathsEqual(String left, String right) {
    final normalizedLeft = _normalizePath(left);
    final normalizedRight = _normalizePath(right);
    if (Platform.isWindows) {
      return normalizedLeft.toLowerCase() == normalizedRight.toLowerCase();
    }
    return normalizedLeft == normalizedRight;
  }

  bool _isWithinAnyRoot(String path, List<String> roots) {
    for (final root in roots) {
      if (_pathsEqual(path, root)) return true;
      if (Platform.isWindows) {
        if (p.isWithin(root.toLowerCase(), path.toLowerCase())) return true;
      } else if (p.isWithin(root, path)) {
        return true;
      }
    }
    return false;
  }
}
