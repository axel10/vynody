import 'dart:async';

import 'metadata_database.dart';

class ScanProgress {
  final String filePath;
  final int discoveredCount;
  final int preprocessedCount;
  final int completedCount;

  const ScanProgress({
    required this.filePath,
    required this.discoveredCount,
    required this.preprocessedCount,
    required this.completedCount,
  });
}

class ScanProgressState {
  ScanProgressState({
    int metadataConcurrency = 4,
    required int Function(String a, String b) comparePaths,
  }) : metadataRunner = OrderedTaskRunner(
         metadataConcurrency,
         comparePaths: comparePaths,
       );

  int discoveredCount = 0;
  int preprocessedCount = 0;
  int completedCount = 0;
  final OrderedTaskRunner metadataRunner;
  final List<Future<void>> pendingMetadataTasks = [];
  final List<String> pendingMetadataPaths = [];
}

class OrderedTaskRunner {
  OrderedTaskRunner(int maxConcurrent, {required this.comparePaths})
    : maxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent;

  final int maxConcurrent;
  final int Function(String a, String b) comparePaths;
  int _running = 0;
  int _sequence = 0;
  final List<QueuedTask<dynamic>> _queue = [];

  Future<T> run<T>(String path, Future<T> Function() task) {
    final completer = Completer<T>();
    _queue.add(
      QueuedTask<T>(
        path: path,
        sequence: _sequence++,
        completer: completer,
        task: task,
      ),
    );
    _pump();
    return completer.future;
  }

  void _pump() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final nextIndex = _selectNextIndex();
      final next = _queue.removeAt(nextIndex);
      _running++;
      unawaited(_execute(next));
    }
  }

  int _selectNextIndex() {
    var bestIndex = 0;
    for (var i = 1; i < _queue.length; i++) {
      final candidate = _queue[i];
      final best = _queue[bestIndex];
      final pathCompare = comparePaths(candidate.path, best.path);
      if (pathCompare < 0 ||
          (pathCompare == 0 && candidate.sequence < best.sequence)) {
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<void> _execute<T>(QueuedTask<T> entry) async {
    try {
      final result = await entry.task();
      if (!entry.completer.isCompleted) {
        entry.completer.complete(result);
      }
    } catch (e, st) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(e, st);
      }
    } finally {
      _running--;
      _pump();
    }
  }
}

class QueuedTask<T> {
  QueuedTask({
    required this.path,
    required this.sequence,
    required this.completer,
    required this.task,
  });

  final String path;
  final int sequence;
  final Completer<T> completer;
  final Future<T> Function() task;
}

enum ScanFileStage { full, imageOnly, unchanged }

class ScanFileClassification {
  ScanFileClassification({
    required this.existingMetadataByPath,
    required this.stageByPath,
  });

  final Map<String, SongMetadata> existingMetadataByPath;
  final Map<String, ScanFileStage> stageByPath;

  List<String> pathsFor(ScanFileStage stage) {
    return stageByPath.entries
        .where((entry) => entry.value == stage)
        .map((entry) => entry.key)
        .toList(growable: false);
  }
}

class ScanPreprocessResult {
  const ScanPreprocessResult({
    required this.keptPaths,
    required this.artworkPendingPaths,
  });

  final List<String> keptPaths;
  final List<String> artworkPendingPaths;
}
