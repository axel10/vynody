import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'music_file_utils.dart';
import 'scanner_scan_support.dart';

class ScannerDirectoryScanner {
  ScannerDirectoryScanner({
    required void Function(ScanProgressState scanState, String filePath)
    emitScanProgress,
  }) : _emitScanProgress = emitScanProgress;

  final void Function(ScanProgressState scanState, String filePath)
  _emitScanProgress;

  Future<List<String>> discoverMusicFiles(
    String path,
    ScanProgressState scanState, {
    bool Function()? shouldCancel,
  }) async {
    debugPrint('[ScannerDirectoryScanner] discoverMusicFiles start path=$path');
    try {
      final discoveredPaths = await _discoverMusicFilesWithIsolate(
        path,
        scanState,
        shouldCancel: shouldCancel,
      );
      debugPrint(
        '[ScannerDirectoryScanner] discoverMusicFiles finished via isolate '
        'path=$path count=${discoveredPaths.length}',
      );
      return discoveredPaths;
    } catch (e, st) {
      debugPrint(
        '[ScannerDirectoryScanner] isolate discovery failed for $path: $e\n$st',
      );
      final discoveredPaths = await _discoverMusicFilesInline(
        path,
        scanState,
        shouldCancel: shouldCancel,
      );
      debugPrint(
        '[ScannerDirectoryScanner] discoverMusicFiles finished via inline '
        'path=$path count=${discoveredPaths.length}',
      );
      return discoveredPaths;
    }
  }

  Future<List<String>> _discoverMusicFilesWithIsolate(
    String path,
    ScanProgressState scanState, {
    bool Function()? shouldCancel,
  }) async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    final cancelPort = ReceivePort();
    final discoveredPaths = <String>[];

    Isolate? isolate;
    Timer? cancelTimer;
    try {
      isolate = await Isolate.spawn<_DirectoryDiscoveryRequest>(
        _discoverMusicFilesIsolateEntry,
        _DirectoryDiscoveryRequest(
          rootPath: path,
          replyPort: receivePort.sendPort,
          cancelPort: cancelPort.sendPort,
        ),
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
        errorsAreFatal: true,
      );

      final completer = Completer<List<String>>();
      late final StreamSubscription receiveSub;
      late final StreamSubscription errorSub;
      late final StreamSubscription exitSub;
      late final StreamSubscription cancelSub;
      var finished = false;
      var cancelRequested = false;
      SendPort? isolateCancelPort;

      void completeSuccess() {
        if (finished) return;
        finished = true;
        completer.complete(discoveredPaths);
      }

      void completeError(Object error, [StackTrace? st]) {
        if (finished) return;
        finished = true;
        completer.completeError(error, st);
      }

      cancelSub = cancelPort.listen((message) {
        if (message is SendPort) {
          isolateCancelPort = message;
        }
      });

      receiveSub = receivePort.listen((message) {
        if (message is! Map) {
          return;
        }
        if ((shouldCancel?.call() ?? false) && !cancelRequested) {
          cancelRequested = true;
          isolateCancelPort?.send(true);
        }
        final type = message['type'];
        if (type == _DirectoryDiscoveryMessage.batchType) {
          final rawPaths = message['paths'];
          if (rawPaths is! List) {
            return;
          }
          final batch = rawPaths.whereType<String>().toList(growable: false);
          if (batch.isEmpty) {
            return;
          }
          discoveredPaths.addAll(batch);
          scanState.discoveredCount += batch.length;
          _emitScanProgress(scanState, batch.last);
          return;
        }
        if (type == _DirectoryDiscoveryMessage.doneType) {
          completeSuccess();
        }
      });

      errorSub = errorPort.listen((message) {
        if (message is List && message.isNotEmpty) {
          final error = message.first;
          final stackTrace = message.length > 1 && message[1] is String
              ? StackTrace.fromString(message[1] as String)
              : null;
          completeError(
            error is Object ? error : Exception(error.toString()),
            stackTrace,
          );
          return;
        }
        completeError(Exception('Directory discovery isolate failed.'));
      });

      exitSub = exitPort.listen((_) {
        if (!finished) {
          completeError(Exception('Directory discovery isolate exited early.'));
        }
      });

      if (shouldCancel != null) {
        cancelTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
          if (finished || cancelRequested) {
            return;
          }
          if (shouldCancel()) {
            cancelRequested = true;
            isolateCancelPort?.send(true);
          }
        });
      }

      try {
        return await completer.future;
      } finally {
        cancelTimer?.cancel();
        await cancelSub.cancel();
        await receiveSub.cancel();
        await errorSub.cancel();
        await exitSub.cancel();
      }
    } finally {
      receivePort.close();
      errorPort.close();
      exitPort.close();
      cancelPort.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }

  Future<List<String>> _discoverMusicFilesInline(
    String path,
    ScanProgressState scanState, {
    bool Function()? shouldCancel,
  }) async {
    final rootDir = Directory(path);
    if (!await rootDir.exists()) {
      debugPrint(
        '[ScannerDirectoryScanner] inline discovery skipped missing path=$path',
      );
      return const <String>[];
    }

    const yieldEvery = 256;
    final pendingDirectories = ListQueue<String>()..add(path);
    final discoveredPaths = <String>[];
    var processedEntries = 0;

    while (pendingDirectories.isNotEmpty) {
      if (shouldCancel?.call() ?? false) {
        debugPrint(
          '[ScannerDirectoryScanner] inline discovery cancelled before next '
          'directory path=$path discovered=${discoveredPaths.length}',
        );
        break;
      }
      final currentPath = pendingDirectories.removeFirst();
      final dir = Directory(currentPath);
      try {
        await for (final entity in dir.list(followLinks: false)) {
          if (shouldCancel?.call() ?? false) {
            debugPrint(
              '[ScannerDirectoryScanner] inline discovery cancelled during '
              'listing root=$path current=$currentPath '
              'discovered=${discoveredPaths.length}',
            );
            return discoveredPaths;
          }
          if (entity is Directory) {
            if (p.basename(entity.path).startsWith('.')) {
              continue;
            }
            pendingDirectories.add(entity.path);
          } else if (entity is File &&
              MusicFileUtils.isMusicFilePath(entity.path)) {
            final filePath = entity.path;
            discoveredPaths.add(filePath);
            scanState.discoveredCount++;
            _emitScanProgress(scanState, filePath);
          }

          processedEntries++;
          if (processedEntries % yieldEvery == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
      } catch (e, st) {
        debugPrint(
          '[ScannerDirectoryScanner] inline discovery list error '
          'root=$path current=$currentPath: $e\n$st',
        );
      }
    }

    return discoveredPaths;
  }
}

class _DirectoryDiscoveryRequest {
  const _DirectoryDiscoveryRequest({
    required this.rootPath,
    required this.replyPort,
    required this.cancelPort,
  });

  final String rootPath;
  final SendPort replyPort;
  final SendPort cancelPort;
}

class _DirectoryDiscoveryMessage {
  static const String batchType = 'batch';
  static const String doneType = 'done';
}

Future<void> _discoverMusicFilesIsolateEntry(
  _DirectoryDiscoveryRequest request,
) async {
  final cancelReceivePort = ReceivePort();
  request.cancelPort.send(cancelReceivePort.sendPort);
  var cancelled = false;
  late final StreamSubscription cancelSub;
  cancelSub = cancelReceivePort.listen((_) {
    cancelled = true;
  });

  final rootDir = Directory(request.rootPath);
  if (!await rootDir.exists()) {
    debugPrint(
      '[ScannerDirectoryScanner] isolate discovery skipped missing '
      'path=${request.rootPath}',
    );
    await cancelSub.cancel();
    cancelReceivePort.close();
    request.replyPort.send(const {'type': _DirectoryDiscoveryMessage.doneType});
    return;
  }

  const batchSize = 128;
  final pendingDirectories = ListQueue<String>()..add(request.rootPath);
  final batch = <String>[];

  while (pendingDirectories.isNotEmpty && !cancelled) {
    final currentPath = pendingDirectories.removeFirst();
    final dir = Directory(currentPath);
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (cancelled) {
          break;
        }
        if (entity is Directory) {
          if (p.basename(entity.path).startsWith('.')) {
            continue;
          }
          pendingDirectories.add(entity.path);
        } else if (entity is File &&
            MusicFileUtils.isMusicFilePath(entity.path)) {
          batch.add(entity.path);
          if (batch.length >= batchSize) {
            request.replyPort.send({
              'type': _DirectoryDiscoveryMessage.batchType,
              'paths': List<String>.from(batch),
            });
            batch.clear();
          }
        }
      }
    } catch (e, st) {
      debugPrint(
        '[ScannerDirectoryScanner] isolate discovery list error '
        'root=${request.rootPath} current=$currentPath: $e\n$st',
      );
    }
  }

  if (batch.isNotEmpty) {
    request.replyPort.send({
      'type': _DirectoryDiscoveryMessage.batchType,
      'paths': List<String>.from(batch),
    });
  }
  await cancelSub.cancel();
  cancelReceivePort.close();
  if (cancelled) {
    debugPrint(
      '[ScannerDirectoryScanner] isolate discovery cancelled '
      'path=${request.rootPath}',
    );
  }
  request.replyPort.send(const {'type': _DirectoryDiscoveryMessage.doneType});
}
