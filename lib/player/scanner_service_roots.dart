import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_file_utils.dart';
import 'scanner_path_utils.dart';

class ScannerServiceRoots {
  ScannerServiceRoots({
    required bool Function() isScanning,
    required bool Function() isDisposed,
    required Future<void> Function() requestScan,
    required void Function(String path, bool isMissing) notifySongMissingState,
  }) : _isScanning = isScanning,
       _isDisposed = isDisposed,
       _requestScan = requestScan,
       _notifySongMissingState = notifySongMissingState;

  final bool Function() _isScanning;
  final bool Function() _isDisposed;
  final Future<void> Function() _requestScan;
  final void Function(String path, bool isMissing) _notifySongMissingState;

  final List<String> _rootPaths = [];
  final Map<String, StreamSubscription<FileSystemEvent>>
  _rootWatchSubscriptions = {};

  Timer? _rootRescanTimer;
  bool _rootRescanPending = false;

  List<String> get rootPaths => List.unmodifiable(_rootPaths);

  Future<void> loadRootPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList('root_paths') ?? [];
    final normalizedPaths = ScannerPathUtils.normalizeDeclaredRootPaths(paths);
    _rootPaths
      ..clear()
      ..addAll(normalizedPaths);
    await refreshRootWatchers();
  }

  Future<void> saveRootPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('root_paths', _rootPaths);
  }

  Future<void> setRootPaths(Iterable<String> paths) async {
    final normalizedRoots = ScannerPathUtils.normalizeDeclaredRootPaths(paths);
    _rootPaths
      ..clear()
      ..addAll(normalizedRoots);
    await saveRootPaths();
    await refreshRootWatchers();
  }

  Future<void> refreshRootWatchers() async {
    if (_isDisposed()) return;

    final desiredRoots = ScannerPathUtils.computeScanRoots(_rootPaths);
    final desiredKeys = desiredRoots
        .map(ScannerPathUtils.pathLookupKey)
        .toSet();

    final existingKeys = _rootWatchSubscriptions.keys.toSet();
    final unchanged =
        existingKeys.length == desiredKeys.length &&
        existingKeys.containsAll(desiredKeys);
    if (unchanged) {
      return;
    }

    for (final subscription in _rootWatchSubscriptions.values) {
      await subscription.cancel();
    }
    _rootWatchSubscriptions.clear();

    for (final root in desiredRoots) {
      final directory = Directory(root);
      if (!directory.existsSync()) {
        continue;
      }

      final key = ScannerPathUtils.pathLookupKey(root);
      _rootWatchSubscriptions[key] = directory
          .watch(recursive: true)
          .listen(
            (event) {
              if ((event.type & FileSystemEvent.delete) != 0 ||
                  (event.type & FileSystemEvent.move) != 0) {
                if (MusicFileUtils.isMusicFilePath(event.path)) {
                  _notifySongMissingState(event.path, true);
                }
              } else if ((event.type & FileSystemEvent.create) != 0 &&
                  MusicFileUtils.isMusicFilePath(event.path)) {
                _notifySongMissingState(event.path, false);
              }

              if (shouldRescanForEvent(event)) {
                requestRootRescan();
              }
            },
            onError: (err) {
              debugPrint('Root watcher error for $root: $err');
            },
          );
    }
  }

  bool shouldRescanForEvent(FileSystemEvent event) {
    final path = event.path.trim();
    if (path.isEmpty) return false;
    if (event.isDirectory) {
      return true;
    }
    if ((event.type & FileSystemEvent.create) != 0 ||
        (event.type & FileSystemEvent.delete) != 0 ||
        (event.type & FileSystemEvent.move) != 0) {
      return true;
    }
    return MusicFileUtils.isMusicFilePath(path);
  }

  void requestRootRescan() {
    if (_isDisposed()) return;
    _rootRescanPending = true;
    _scheduleRootRescan();
  }

  void schedulePendingRootRescan() {
    if (_isDisposed() || !_rootRescanPending) return;
    _scheduleRootRescan();
  }

  void _scheduleRootRescan() {
    if (_isDisposed()) return;
    if (_isScanning()) {
      return;
    }
    if (_rootRescanTimer?.isActive ?? false) {
      return;
    }

    _rootRescanTimer = Timer(const Duration(seconds: 1), () {
      _rootRescanTimer = null;
      if (_isDisposed() || !_rootRescanPending || _isScanning()) {
        return;
      }

      _rootRescanPending = false;
      unawaited(_requestScan());
    });
  }

  bool isShortcutRoot(String path) {
    return ScannerPathUtils.isShortcutRoot(
      path: path,
      declaredRootPaths: _rootPaths,
    );
  }

  void dispose() {
    _rootRescanTimer?.cancel();
    for (final subscription in _rootWatchSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _rootWatchSubscriptions.clear();
  }
}
