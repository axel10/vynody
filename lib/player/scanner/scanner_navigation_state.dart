import 'package:flutter/foundation.dart';

import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';

class ScannerNavigationState extends ChangeNotifier {
  MusicFolder? _currentFolder;
  final List<MusicFolder> _history = [];
  final Map<String, double> _scrollOffsets = {};

  MusicFolder? get currentFolder => _currentFolder;

  List<MusicFolder> get history => List.unmodifiable(_history);

  /// 历史深度。供上层做结构指纹计算，避免为了取长度而复制整个列表。
  int get historyLength => _history.length;

  void setState(MusicFolder? current, List<MusicFolder> history) {
    _currentFolder = current;
    _history
      ..clear()
      ..addAll(history);
    _pruneInactiveOffsets();
    notifyListeners();
  }

  void pushHistory(MusicFolder folder) {
    _history.add(folder);
    notifyListeners();
  }

  MusicFolder? popHistory() {
    if (_history.isEmpty) return null;
    final folder = _history.removeLast();
    _pruneInactiveOffsets();
    notifyListeners();
    return folder;
  }

  void _pruneInactiveOffsets() {
    final activePaths = <String>{
      'root',
      if (_currentFolder != null) _currentFolder!.path,
      for (final f in _history) f.path,
    };
    _scrollOffsets.removeWhere((path, _) {
      if (path == 'root') return false;
      return !activePaths.any((active) => ScannerPathUtils.pathsEqual(active, path));
    });
  }

  double getScrollOffset(String? path) {
    final targetPath = path ?? 'root';
    return _scrollOffsets[targetPath] ?? 0.0;
  }

  void setScrollOffset(String? path, double offset) {
    final targetPath = path ?? 'root';
    if (targetPath != 'root') {
      final isCurrent = _currentFolder != null &&
          ScannerPathUtils.pathsEqual(_currentFolder!.path, targetPath);
      final isInHistory =
          _history.any((f) => ScannerPathUtils.pathsEqual(f.path, targetPath));
      if (!isCurrent && !isInHistory) {
        return;
      }
    }
    _scrollOffsets[targetPath] = offset;
  }

  void clearScrollOffsets() {
    _scrollOffsets.clear();
  }
}
