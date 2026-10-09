import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';

/// Service responsible for managing song ratings (0-5 stars) stored in SQLite (song_ratings table)
/// independently from scanned media to ensure ratings persist across library rescans and index rebuilds.
class SongRatingService extends ChangeNotifier {
  final MetadataDatabase _database;
  final Map<String, int> _ratings = {};
  bool _isInitialized = false;
  bool _disposed = false;

  SongRatingService({MetadataDatabase? database})
      : _database = database ?? MetadataDatabase() {
    _init();
  }

  @override
  void dispose() {
    _disposed = true;
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
      final dbRatings = await _database.getAllSongRatings();
      for (final entry in dbRatings.entries) {
        final key = _normalizeKey(entry.key);
        if (key.isNotEmpty && entry.value > 0 && entry.value <= 5) {
          _ratings[key] = entry.value;
        }
      }
    } catch (e) {
      debugPrint('[SongRatingService] Error loading ratings from SQLite: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Get the rating for a given song path (0 = unrated, 1-5 = stars).
  int getRating(String path) {
    if (path.isEmpty) return 0;
    final key = _normalizeKey(path);
    return _ratings[key] ?? 0;
  }

  /// Sets or clears the rating for a given song path.
  /// A rating of 0 or less clears the rating. Values 1-5 set the star rating.
  Future<void> setRating(String path, int rating) async {
    if (path.isEmpty) return;
    final key = _normalizeKey(path);
    final clampedRating = rating.clamp(0, 5);

    final current = _ratings[key] ?? 0;
    if (current == clampedRating) return;

    if (clampedRating == 0) {
      _ratings.remove(key);
    } else {
      _ratings[key] = clampedRating;
    }

    notifyListeners();

    try {
      if (clampedRating == 0) {
        await _database.deleteSongRating(key);
      } else {
        await _database.setSongRating(key, clampedRating);
      }
    } catch (e) {
      debugPrint('[SongRatingService] Error saving rating to SQLite: $e');
    }
  }

  Map<String, int> get allRatings => Map.unmodifiable(_ratings);
}

final songRatingServiceProvider = ChangeNotifierProvider<SongRatingService>((ref) {
  return SongRatingService();
});

final songRatingProvider = Provider.family<int, String>((ref, path) {
  final service = ref.watch(songRatingServiceProvider);
  return service.getRating(path);
});
