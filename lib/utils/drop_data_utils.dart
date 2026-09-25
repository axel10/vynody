import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/models/music_file.dart';

/// Centralized utility for extracting file paths from SuperDragAndDrop events and sessions.
class DropDataUtils {
  const DropDataUtils._();

  /// Reads a specific format from a [DataReader] with error handling and timeout.
  static Future<T?> readFormatSafely<T extends Object>(
    dynamic reader,
    ValueFormat<T> format, {
    Duration timeout = const Duration(milliseconds: 600),
  }) async {
    if (reader == null || !reader.canProvide(format)) return null;
    final completer = Completer<T?>();
    try {
      final progress = reader.getValue<T>(
        format,
        (value) {
          if (!completer.isCompleted) completer.complete(value);
        },
        onError: (err) {
          debugPrint('[DropDataUtils] Error reading format $format: $err');
          if (!completer.isCompleted) completer.complete(null);
        },
      );
      if (progress == null && !completer.isCompleted) {
        completer.complete(null);
      }
      return await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Extracts all valid, deduplicated paths from a [PerformDropEvent].
  static Future<List<String>> extractPathsFromDrop(
    PerformDropEvent event, {
    Duration itemTimeout = const Duration(milliseconds: 600),
  }) async {
    final paths = <String>[];

    for (var i = 0; i < event.session.items.length; i++) {
      final item = event.session.items[i];

      // 1. Fast in-memory extraction (localData)
      if (item.localData is MusicFile) {
        paths.add((item.localData as MusicFile).path);
        continue;
      }
      if (item.localData is Map) {
        final map = item.localData as Map;
        if (map['paths'] is List) {
          final list = map['paths'] as List;
          for (final p in list) {
            if (p != null) paths.add(p.toString());
          }
          continue;
        }
        if (map['path'] != null) {
          paths.add(map['path'] as String);
          continue;
        }
      }

      final reader = item.dataReader;
      if (reader == null) continue;

      bool extracted = false;

      // 2. Try plainText first (supports multi-line batch paths from other windows/apps)
      final text = await readFormatSafely<String>(
        reader,
        Formats.plainText,
        timeout: itemTimeout,
      );
      if (text != null && text.trim().isNotEmpty) {
        final lines = text.split(RegExp(r'[\r\n]+'));
        for (final rawLine in lines) {
          final trimmed = rawLine.trim();
          if (trimmed.isEmpty) continue;
          if (trimmed.startsWith('file://')) {
            try {
              paths.add(Uri.parse(trimmed).toFilePath());
              extracted = true;
              continue;
            } catch (_) {}
          }
          paths.add(trimmed);
          extracted = true;
        }
      }

      if (extracted) continue;

      // 3. Try fileUri
      final fileUri = await readFormatSafely<Uri>(
        reader,
        Formats.fileUri,
        timeout: itemTimeout,
      );
      if (fileUri != null && fileUri.scheme == 'file') {
        paths.add(fileUri.toFilePath());
        continue;
      }

      // 4. Try uri
      final namedUri = await readFormatSafely<NamedUri>(
        reader,
        Formats.uri,
        timeout: itemTimeout,
      );
      if (namedUri != null) {
        final uri = namedUri.uri;
        if (uri.scheme == 'file') {
          try {
            paths.add(uri.toFilePath());
          } catch (_) {
            paths.add(uri.toString());
          }
        } else {
          paths.add(uri.toString());
        }
      }
    }

    // Deduplicate and decode paths
    final uniquePaths = <String>[];
    final seen = <String>{};
    for (final p in paths) {
      String decoded = p;
      try {
        decoded = Uri.decodeFull(p);
      } catch (_) {}
      if (seen.add(decoded)) {
        uniquePaths.add(decoded);
      }
    }

    return uniquePaths;
  }
}
