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
      version: 4,
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
            themeColorsBlob BLOB
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
