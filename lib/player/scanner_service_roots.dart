import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_file_utils.dart';
import 'scanner_path_utils.dart';

class ScannerServiceRoots {
  ScannerServiceRoots({
    required bool Function() isDisposed,
    required void Function(FileSystemEvent event) onFileEvent,
    required void Function(String path, bool isMissing) notifySongMissingState,
  }) : _isDisposed = isDisposed,
       _onFileEvent = onFileEvent,
       _notifySongMissingState = notifySongMissingState;

  final bool Function() _isDisposed;
  final void Function(FileSystemEvent event) _onFileEvent;
  final void Function(String path, bool isMissing) _notifySongMissingState;

  final List<String> _rootPaths = [];
  final Map<String, StreamSubscription<FileSystemEvent>>
  _rootWatchSubscriptions = {};

  List<String> get rootPaths => List.unmodifiable(_rootPaths);

  Future<List<String>> loadRootPaths({
    Future<bool> Function(String path)? hasPersistentAccess,
    Future<void> Function(String path)? forgetPersistentAccess,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList('root_paths') ?? [];
    final normalizedPaths = ScannerPathUtils.normalizeDeclaredRootPaths(paths);

    final removedPaths = <String>[];
    final retainedPaths = <String>[];
    for (final path in normalizedPaths) {
      var keepPath = true;
      if (hasPersistentAccess != null) {
        try {
          keepPath = await hasPersistentAccess(path);
        } catch (e) {
          debugPrint('Persistent access check failed for $path: $e');
          keepPath = false;
        }
      }

      if (keepPath) {
        retainedPaths.add(path);
        continue;
      }

      removedPaths.add(path);
      if (forgetPersistentAccess != null) {
        try {
          await forgetPersistentAccess(path);
        } catch (e) {
          debugPrint('Persistent access cleanup failed for $path: $e');
        }
      }
    }

    _rootPaths
      ..clear()
      ..addAll(retainedPaths);
    if (removedPaths.isNotEmpty) {
      await saveRootPaths();
    }
    await refreshRootWatchers();
    return removedPaths;
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
    debugPrint(
      '[ScannerServiceRoots] refreshRootWatchers desiredRoots=$desiredRoots',
    );
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
      try {
        if (!directory.existsSync()) {
          debugPrint(
            '[ScannerServiceRoots] skip watcher for missing root=$root',
          );
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

                if (event is FileSystemMoveEvent) {
                  final destination = event.destination?.trim() ?? '';
                  if (destination.isNotEmpty &&
                      MusicFileUtils.isMusicFilePath(destination)) {
                    _notifySongMissingState(destination, false);
                    _onFileEvent(FileSystemCreateEvent(destination, false));
                  }
                }

                if (event.isDirectory) {
                  if ((event.type & FileSystemEvent.delete) != 0 ||
                      (event.type & FileSystemEvent.move) != 0) {
                    _onFileEvent(event);
                  }
                  return;
                }

                if (event.path.trim().isNotEmpty &&
                    MusicFileUtils.isMusicFilePath(event.path)) {
                  _onFileEvent(event);
                }
              },
              onError: (err) {
                debugPrint('Root watcher error for $root: $err');
              },
            );
        debugPrint('[ScannerServiceRoots] watcher attached root=$root');
      } catch (e, st) {
        debugPrint(
          '[ScannerServiceRoots] failed to attach watcher root=$root: $e\n$st',
        );
      }
    }
  }

  void dispose() {
    for (final subscription in _rootWatchSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _rootWatchSubscriptions.clear();
  }
}
