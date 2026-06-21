import 'package:flutter/foundation.dart';

import 'package:vynody/models/music_folder.dart';

class ScannerNavigationState extends ChangeNotifier {
  MusicFolder? _currentFolder;
  final List<MusicFolder> _history = [];
  final Map<String, double> _scrollOffsets = {};

  MusicFolder? get currentFolder => _currentFolder;

  List<MusicFolder> get history => List.unmodifiable(_history);

  void setState(MusicFolder? current, List<MusicFolder> history) {
    _currentFolder = current;
    _history
      ..clear()
      ..addAll(history);
    notifyListeners();
  }

  void pushHistory(MusicFolder folder) {
    _history.add(folder);
    notifyListeners();
  }

  MusicFolder? popHistory() {
    if (_history.isEmpty) return null;
    final folder = _history.removeLast();
    notifyListeners();
    return folder;
  }

  double getScrollOffset(String? path) {
    return _scrollOffsets[path ?? 'root'] ?? 0.0;
  }

  void setScrollOffset(String? path, double offset) {
    _scrollOffsets[path ?? 'root'] = offset;
  }

  void clearScrollOffsets() {
    _scrollOffsets.clear();
  }
}
