import 'package:flutter/foundation.dart';

import 'package:vibe_flow/models/music_folder.dart';

class ScannerNavigationState extends ChangeNotifier {
  MusicFolder? _currentFolder;
  final List<MusicFolder> _history = [];

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
}
