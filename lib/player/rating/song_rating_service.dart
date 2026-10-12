import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';

/// Service responsible for managing song ratings (0-5 stars).
///
/// Distinguishes between:
/// 1. Scanned file-tag ratings (stored in `songs.fileRating`, extracted by TagLib)
/// 2. User-assigned ratings (stored in `song_ratings` table, preserved across rescans)
///
/// Priority: User rating overrides file tag rating. If a user explicitly clears
/// a rating on a file-rated track, user rating = 0 suppresses the file rating.
class SongRatingService extends ChangeNotifier {
  final MetadataDatabase _database;
  final Map<String, int> _userRatings = {};
  final Map<String, int> _fileRatings = {};
  StreamSubscription<Map<String, int>>? _fileRatingsSubscription;
  bool _isInitialized = false;
  bool _disposed = false;

  SongRatingService({MetadataDatabase? database})
      : _database = database ?? MetadataDatabase() {
    _init();
  }

  @override
  void dispose() {
    _disposed = true;
    _fileRatingsSubscription?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  String _normalizeKey(String path) {
    if (path.isEmpty) return '';
    final resolved = ScannerPathUtils.resolveIosSandboxPath(path);
    return p.normalize(resolved);
  }

  Future<void> _init() async {
    if (_isInitialized) return;
    try {
      final dbUserRatings = await _database.getAllSongRatings();
      for (final entry in dbUserRatings.entries) {
        if (entry.value >= 0 && entry.value <= 5) {
          final key = _normalizeKey(entry.key);
          if (key.isNotEmpty) _userRatings[key] = entry.value;
          _userRatings[entry.key] = entry.value;
          _userRatings[entry.key.replaceAll('\\', '/')] = entry.value;
        }
      }

      final dbFileRatings = await _database.getAllFileRatings();
      for (final entry in dbFileRatings.entries) {
        if (entry.value > 0 && entry.value <= 5) {
          final key = _normalizeKey(entry.key);
          if (key.isNotEmpty) _fileRatings[key] = entry.value;
          _fileRatings[entry.key] = entry.value;
          _fileRatings[entry.key.replaceAll('\\', '/')] = entry.value;
        }
      }

      _fileRatingsSubscription = _database.watchAllFileRatings().listen((fileRatings) {
        if (_disposed) return;
        _fileRatings.clear();
        for (final entry in fileRatings.entries) {
          if (entry.value > 0 && entry.value <= 5) {
            final key = _normalizeKey(entry.key);
            if (key.isNotEmpty) _fileRatings[key] = entry.value;
            _fileRatings[entry.key] = entry.value;
            _fileRatings[entry.key.replaceAll('\\', '/')] = entry.value;
          }
        }
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[SongRatingService] Error loading ratings from SQLite: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Get user-assigned rating if set (0 = explicitly cleared, 1-5 = stars), or null if not set.
  int? getUserRating(String path) {
    if (path.isEmpty || _userRatings.isEmpty) return null;
    final direct = _userRatings[path];
    if (direct != null) return direct;
    final normalizedSlash = _userRatings[path.replaceAll('\\', '/')];
    if (normalizedSlash != null) return normalizedSlash;
    final key = _normalizeKey(path);
    return _userRatings[key];
  }

  /// Get file-tag rating if present (1-5 = stars), or null if unrated in tag.
  int? getFileRating(String path) {
    if (path.isEmpty || _fileRatings.isEmpty) return null;
    final direct = _fileRatings[path];
    if (direct != null) return direct;
    final normalizedSlash = _fileRatings[path.replaceAll('\\', '/')];
    if (normalizedSlash != null) return normalizedSlash;
    final key = _normalizeKey(path);
    return _fileRatings[key];
  }

  /// Get effective rating for a song (0 = unrated, 1-5 = stars).
  /// User manual rating has precedence over file metadata rating.
  int getRating(String path) {
    final user = getUserRating(path);
    if (user != null) return user;
    final file = getFileRating(path);
    if (file != null) return file;
    return 0;
  }

  /// Whether the effective rating comes explicitly from user manual action.
  bool isUserRated(String path) {
    final user = getUserRating(path);
    return user != null && user > 0;
  }

  /// Whether the effective rating comes from file tag metadata (user hasn't overridden).
  bool isFileRated(String path) {
    final user = getUserRating(path);
    if (user != null) return false;
    final file = getFileRating(path);
    return file != null && file > 0;
  }

  /// Sets or clears user rating for a given song path.
  /// 0 clears the rating (suppresses any file tag rating). Values 1-5 set star rating.
  Future<void> setRating(String path, int rating) async {
    if (path.isEmpty) return;
    final key = _normalizeKey(path);
    final clampedRating = rating.clamp(0, 5);

    final currentUser = getUserRating(path);
    if (currentUser == clampedRating) return;

    if (key.isNotEmpty) _userRatings[key] = clampedRating;
    _userRatings[path] = clampedRating;
    _userRatings[path.replaceAll('\\', '/')] = clampedRating;

    notifyListeners();

    try {
      final dbKey = key.isNotEmpty ? key : path;
      await _database.setSongRating(dbKey, clampedRating);
    } catch (e) {
      debugPrint('[SongRatingService] Error saving rating to SQLite: $e');
    }
  }

  /// Resets user override, reverting to the file tag rating if available.
  Future<void> resetToTagRating(String path) async {
    if (path.isEmpty) return;
    final key = _normalizeKey(path);
    _userRatings.remove(key);
    _userRatings.remove(path);
    _userRatings.remove(path.replaceAll('\\', '/'));

    notifyListeners();

    try {
      final dbKey = key.isNotEmpty ? key : path;
      await _database.deleteSongRating(dbKey);
    } catch (e) {
      debugPrint('[SongRatingService] Error resetting user rating in SQLite: $e');
    }
  }

  /// Combined map of all effectively rated songs (rating > 0).
  Map<String, int> get allRatings {
    final map = <String, int>{};
    for (final entry in _fileRatings.entries) {
      if (entry.value > 0 && entry.value <= 5) {
        map[entry.key] = entry.value;
      }
    }
    for (final entry in _userRatings.entries) {
      if (entry.value > 0 && entry.value <= 5) {
        map[entry.key] = entry.value;
      } else if (entry.value == 0) {
        map.remove(entry.key);
      }
    }
    return Map.unmodifiable(map);
  }
}

final songRatingServiceProvider = ChangeNotifierProvider<SongRatingService>((ref) {
  return SongRatingService();
});

final songRatingProvider = Provider.family<int, String>((ref, path) {
  final service = ref.watch(songRatingServiceProvider);
  return service.getRating(path);
});

final isSongFileRatedProvider = Provider.family<bool, String>((ref, path) {
  final service = ref.watch(songRatingServiceProvider);
  return service.isFileRated(path);
});
