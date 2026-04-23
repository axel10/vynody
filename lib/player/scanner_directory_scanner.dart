import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

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
    ScanProgressState scanState,
  ) async {
    try {
      return await _discoverMusicFilesWithIsolate(path, scanState);
    } catch (_) {
      return _discoverMusicFilesInline(path, scanState);
    }
  }

  Future<List<String>> _discoverMusicFilesWithIsolate(
    String path,
    ScanProgressState scanState,
  ) async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    final discoveredPaths = <String>[];

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<_DirectoryDiscoveryRequest>(
        _discoverMusicFilesIsolateEntry,
        _DirectoryDiscoveryRequest(
          rootPath: path,
          replyPort: receivePort.sendPort,
        ),
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
        errorsAreFatal: true,
      );

      final completer = Completer<List<String>>();
      late final StreamSubscription receiveSub;
      late final StreamSubscription errorSub;
      late final StreamSubscription exitSub;
      var finished = false;

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

      receiveSub = receivePort.listen((message) {
        if (message is! Map) {
          return;
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
          scanState.pendingMetadataPaths.addAll(batch);
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

      try {
        return await completer.future;
      } finally {
        await receiveSub.cancel();
        await errorSub.cancel();
        await exitSub.cancel();
      }
    } finally {
      receivePort.close();
      errorPort.close();
      exitPort.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }

  Future<List<String>> _discoverMusicFilesInline(
    String path,
    ScanProgressState scanState,
  ) async {
    final rootDir = Directory(path);
    if (!await rootDir.exists()) {
      return const <String>[];
    }

    const yieldEvery = 256;
    final pendingDirectories = ListQueue<String>()..add(path);
    final discoveredPaths = <String>[];
    var processedEntries = 0;

    while (pendingDirectories.isNotEmpty) {
      final currentPath = pendingDirectories.removeFirst();
      final dir = Directory(currentPath);
      try {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is Directory) {
            if (p.basename(entity.path).startsWith('.')) {
              continue;
            }
            pendingDirectories.add(entity.path);
          } else if (entity is File &&
              MusicFileUtils.isMusicFilePath(entity.path)) {
            final filePath = entity.path;
            discoveredPaths.add(filePath);
            scanState.pendingMetadataPaths.add(filePath);
            scanState.discoveredCount++;
            _emitScanProgress(scanState, filePath);
          }

          processedEntries++;
          if (processedEntries % yieldEvery == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
      } catch (_) {
        // Swallow and continue scanning sibling paths; caller handles logging.
      }
    }

    return discoveredPaths;
  }
}

class _DirectoryDiscoveryRequest {
  const _DirectoryDiscoveryRequest({
    required this.rootPath,
    required this.replyPort,
  });

  final String rootPath;
  final SendPort replyPort;
}

class _DirectoryDiscoveryMessage {
  static const String batchType = 'batch';
  static const String doneType = 'done';
}

Future<void> _discoverMusicFilesIsolateEntry(
  _DirectoryDiscoveryRequest request,
) async {
  final rootDir = Directory(request.rootPath);
  if (!await rootDir.exists()) {
    request.replyPort.send(const {'type': _DirectoryDiscoveryMessage.doneType});
    return;
  }

  const batchSize = 128;
  final pendingDirectories = ListQueue<String>()..add(request.rootPath);
  final batch = <String>[];

  while (pendingDirectories.isNotEmpty) {
    final currentPath = pendingDirectories.removeFirst();
    final dir = Directory(currentPath);
    try {
      await for (final entity in dir.list(followLinks: false)) {
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
    } catch (_) {
      // Ignore unreadable directories and continue with siblings.
    }
  }

  if (batch.isNotEmpty) {
    request.replyPort.send({
      'type': _DirectoryDiscoveryMessage.batchType,
      'paths': List<String>.from(batch),
    });
  }
  request.replyPort.send(const {'type': _DirectoryDiscoveryMessage.doneType});
}
