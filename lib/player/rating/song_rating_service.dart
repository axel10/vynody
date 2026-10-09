import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';

/// Service responsible for managing song ratings (0-5 stars) independently
/// from the scan cache database to ensure ratings persist across library rescans and index rebuilds.
class SongRatingService extends ChangeNotifier {
  static const String _ratingsFileName = 'ratings.json';
  final Map<String, int> _ratings = {};
  bool _isInitialized = false;
  bool _isSaving = false;
  bool _needsSaveAgain = false;
  bool _disposed = false;

  SongRatingService() {
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

  static Future<File> get _ratingsFile async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _ratingsFileName));
  }

  String _normalizeKey(String path) {
    if (path.isEmpty) return '';
    final resolved = ScannerPathUtils.resolveIosSandboxPath(path);
    return p.normalize(resolved);
  }

  Future<void> _init() async {
    if (_isInitialized) return;
    try {
      final file = await _ratingsFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            final rawMap = decoded['ratings'] is Map<String, dynamic>
                ? decoded['ratings'] as Map<String, dynamic>
                : decoded;
            for (final entry in rawMap.entries) {
              final val = entry.value;
              if (val is int && val > 0 && val <= 5) {
                _ratings[_normalizeKey(entry.key)] = val;
              } else if (val is num && val > 0 && val <= 5) {
                _ratings[_normalizeKey(entry.key)] = val.toInt();
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[SongRatingService] Error loading ratings: $e');
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
    await _scheduleSave();
  }

  Future<void> _scheduleSave() async {
    if (_disposed) return;
    if (_isSaving) {
      _needsSaveAgain = true;
      return;
    }
    _isSaving = true;
    try {
      final file = await _ratingsFile;
      final parent = file.parent;
      if (!parent.existsSync()) {
        await parent.create(recursive: true);
      }

      final payload = {
        'version': 1,
        'ratings': _ratings,
      };
      final jsonStr = jsonEncode(payload);

      final tmpFile = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await tmpFile.writeAsString(jsonStr, flush: true);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (await tmpFile.exists()) {
        await tmpFile.rename(file.path);
      }
    } catch (e) {
      debugPrint('[SongRatingService] Error saving ratings: $e');
    } finally {
      _isSaving = false;
      if (_needsSaveAgain) {
        _needsSaveAgain = false;
        await _scheduleSave();
      }
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
