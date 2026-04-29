import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class IncrementalScanBatch {
  const IncrementalScanBatch({
    required this.upsertPaths,
    required this.deletedFilePaths,
    required this.deletedDirectoryPaths,
    required this.hasDirectoryMove,
  });

  final List<String> upsertPaths;
  final List<String> deletedFilePaths;
  final List<String> deletedDirectoryPaths;
  final bool hasDirectoryMove;

  bool get isEmpty =>
      upsertPaths.isEmpty &&
      deletedFilePaths.isEmpty &&
      deletedDirectoryPaths.isEmpty &&
      !hasDirectoryMove;

  bool shouldFallbackToFullRescan({int pathThreshold = 64}) {
    final totalPaths =
        upsertPaths.length +
        deletedFilePaths.length +
        deletedDirectoryPaths.length;
    return hasDirectoryMove || totalPaths >= pathThreshold;
  }
}

class ScannerIncrementalSync {
  ScannerIncrementalSync({
    required this.normalizePath,
    required this.isMusicFilePath,
    required this.onBatchReady,
    this.batchWindow = const Duration(milliseconds: 900),
  });

  final String Function(String path) normalizePath;
  final bool Function(String path) isMusicFilePath;
  final Future<void> Function(IncrementalScanBatch batch) onBatchReady;
  final Duration batchWindow;

  Timer? _timer;
  bool _isDisposed = false;
  bool _hasDirectoryMove = false;
  final Set<String> _upsertPaths = <String>{};
  final Set<String> _deletedFilePaths = <String>{};
  final Set<String> _deletedDirectoryPaths = <String>{};

  void enqueue(FileSystemEvent event) {
    if (_isDisposed) {
      return;
    }

    if (event is FileSystemMoveEvent) {
      _enqueueMove(event);
    } else {
      _enqueueStandardEvent(event);
    }

    _timer?.cancel();
    _timer = Timer(batchWindow, _flush);
  }

  void _enqueueMove(FileSystemMoveEvent event) {
    final sourcePath = normalizePath(event.path);
    final destinationPath = normalizePath(event.destination ?? '');

    if (event.isDirectory) {
      _hasDirectoryMove = true;
      if (sourcePath.isNotEmpty) {
        _deletedDirectoryPaths.add(sourcePath);
      }
      return;
    }

    if (sourcePath.isNotEmpty && isMusicFilePath(sourcePath)) {
      _deletedFilePaths.add(sourcePath);
      _upsertPaths.remove(sourcePath);
    }
    if (destinationPath.isNotEmpty && isMusicFilePath(destinationPath)) {
      _upsertPaths.add(destinationPath);
      _deletedFilePaths.remove(destinationPath);
    }
  }

  void _enqueueStandardEvent(FileSystemEvent event) {
    final path = normalizePath(event.path);
    if (path.isEmpty) {
      return;
    }

    if (event.isDirectory) {
      if ((event.type & FileSystemEvent.delete) != 0) {
        _deletedDirectoryPaths.add(path);
      }
      return;
    }

    if (!isMusicFilePath(path)) {
      return;
    }

    if ((event.type & FileSystemEvent.delete) != 0) {
      _deletedFilePaths.add(path);
      _upsertPaths.remove(path);
      return;
    }

    if ((event.type & FileSystemEvent.create) != 0 ||
        (event.type & FileSystemEvent.modify) != 0) {
      _upsertPaths.add(path);
      _deletedFilePaths.remove(path);
    }
  }

  Future<void> _flush() async {
    _timer = null;
    if (_isDisposed) {
      return;
    }

    final batch = IncrementalScanBatch(
      upsertPaths: _upsertPaths.toList(growable: false),
      deletedFilePaths: _deletedFilePaths.toList(growable: false),
      deletedDirectoryPaths: _deletedDirectoryPaths.toList(growable: false),
      hasDirectoryMove: _hasDirectoryMove,
    );
    _upsertPaths.clear();
    _deletedFilePaths.clear();
    _deletedDirectoryPaths.clear();
    _hasDirectoryMove = false;

    if (batch.isEmpty) {
      return;
    }

    try {
      await onBatchReady(batch);
    } catch (error, stackTrace) {
      debugPrint(
        '[ScannerIncrementalSync] batch processing failed: $error\n$stackTrace',
      );
    }
  }

  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
    _upsertPaths.clear();
    _deletedFilePaths.clear();
    _deletedDirectoryPaths.clear();
  }
}
