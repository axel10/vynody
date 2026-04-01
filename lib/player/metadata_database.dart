import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SongMetadata {
  final int? id;
  final String path;
  final String title;
  final String album;
  final String artist;
  final int? duration;
  final String? artworkPath;
  final int? artworkWidth;
  final int? artworkHeight;
  final int? trackNumber;
  final Uint8List? themeColorsBlob;
  final Uint8List? waveformBlob;

  SongMetadata({
    this.id,
    required this.path,
    required this.title,
    required this.album,
    required this.artist,
    this.duration,
    this.artworkPath,
    this.artworkWidth,
    this.artworkHeight,
    this.trackNumber,
    this.themeColorsBlob,
    this.waveformBlob,
  });

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'title': title,
      'album': album,
      'artist': artist,
      'duration': duration,
      'artworkPath': artworkPath,
      'artworkWidth': artworkWidth,
      'artworkHeight': artworkHeight,
      'trackNumber': trackNumber,
      'themeColorsBlob': themeColorsBlob,
      'waveformBlob': waveformBlob,
    };
  }

  factory SongMetadata.fromMap(Map<String, dynamic> map) {
    return SongMetadata(
      id: map['id'],
      path: map['path'],
      title: map['title'] ?? 'Unknown',
      album: map['album'] ?? 'Unknown',
      artist: map['artist'] ?? 'Unknown',
      duration: map['duration'],
      artworkPath: map['artworkPath'],
      artworkWidth: map['artworkWidth'],
      artworkHeight: map['artworkHeight'],
      trackNumber: map['trackNumber'],
      themeColorsBlob: map['themeColorsBlob'] as Uint8List?,
      waveformBlob: map['waveformBlob'] as Uint8List?,
    );
  }

  SongMetadata copyWith({
    int? id,
    String? path,
    String? title,
    String? album,
    String? artist,
    int? duration,
    String? artworkPath,
    int? artworkWidth,
    int? artworkHeight,
    int? trackNumber,
    Uint8List? themeColorsBlob,
    Uint8List? waveformBlob,
  }) {
    return SongMetadata(
      id: id ?? this.id,
      path: path ?? this.path,
      title: title ?? this.title,
      album: album ?? this.album,
      artist: artist ?? this.artist,
      duration: duration ?? this.duration,
      artworkPath: artworkPath ?? this.artworkPath,
      artworkWidth: artworkWidth ?? this.artworkWidth,
      artworkHeight: artworkHeight ?? this.artworkHeight,
      trackNumber: trackNumber ?? this.trackNumber,
      themeColorsBlob: themeColorsBlob ?? this.themeColorsBlob,
      waveformBlob: waveformBlob ?? this.waveformBlob,
    );
  }
}

class LyricsCacheRecord {
  final int? id;
  final String cacheKey;
  final String filePath;
  final String title;
  final String? artist;
  final String? album;
  final int? duration;
  final String source;
  final int? trackId;
  final double score;
  final bool isSynced;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;
  final List<Map<String, dynamic>> syncedLines;
  final Map<String, dynamic>? rawJson;
  final int updatedAtMillis;

  const LyricsCacheRecord({
    this.id,
    required this.cacheKey,
    required this.filePath,
    required this.title,
    this.artist,
    this.album,
    this.duration,
    required this.source,
    this.trackId,
    required this.score,
    required this.isSynced,
    required this.instrumental,
    this.plainLyrics,
    this.syncedLyrics,
    required this.syncedLines,
    this.rawJson,
    required this.updatedAtMillis,
  });

  Map<String, dynamic> toMap() {
    return {
      'cacheKey': cacheKey,
      'filePath': filePath,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'source': source,
      'trackId': trackId,
      'score': score,
      'isSynced': isSynced ? 1 : 0,
      'instrumental': instrumental ? 1 : 0,
      'plainLyrics': plainLyrics,
      'syncedLyrics': syncedLyrics,
      'syncedLinesJson': jsonEncode(syncedLines),
      'rawJson': rawJson == null ? null : jsonEncode(rawJson),
      'updatedAtMillis': updatedAtMillis,
    };
  }

  factory LyricsCacheRecord.fromMap(Map<String, dynamic> map) {
    final syncedLinesJson = map['syncedLinesJson'] as String?;
    final rawJson = map['rawJson'] as String?;
    final decodedLines = syncedLinesJson == null || syncedLinesJson.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(syncedLinesJson) as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

    return LyricsCacheRecord(
      id: map['id'] as int?,
      cacheKey: map['cacheKey'] as String,
      filePath: map['filePath'] as String? ?? '',
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      duration: map['duration'] as int?,
      source: map['source'] as String? ?? 'search',
      trackId: map['trackId'] as int?,
      score: (map['score'] as num?)?.toDouble() ?? 0.0,
      isSynced: (map['isSynced'] as int? ?? 0) == 1,
      instrumental: (map['instrumental'] as int? ?? 0) == 1,
      plainLyrics: map['plainLyrics'] as String?,
      syncedLyrics: map['syncedLyrics'] as String?,
      syncedLines: decodedLines,
      rawJson: rawJson == null || rawJson.isEmpty
          ? null
          : Map<String, dynamic>.from(jsonDecode(rawJson) as Map),
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
      version: 6,
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
            artworkWidth INTEGER,
            artworkHeight INTEGER,
            trackNumber INTEGER,
            themeColorsBlob BLOB,
            waveformBlob BLOB
          )
        ''');
        await db.execute('''
          CREATE TABLE lyrics_cache (
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
}
