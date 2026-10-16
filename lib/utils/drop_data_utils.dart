import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

/// Centralized utility for extracting file paths from SuperDragAndDrop events and sessions.
class DropDataUtils {
  const DropDataUtils._();

  /// Indicates whether the current platform supports desktop native drag-and-drop.
  /// Automatically disabled in unit/widget test environments (`FLUTTER_TEST`).
  static bool get isPlatformSupported =>
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Number of in-app drag sessions (initiated via `DragSource`) still alive.
  static int _activeInternalDrags = 0;

  /// How long the internal-drag flag stays raised after a session completes.
  ///
  /// The native session can report completion marginally before the drop
  /// handler runs; this grace window bridges that gap without ever flipping the
  /// flag back to `false` while a drag is still in flight.
  static const _postDragGrace = Duration(milliseconds: 350);

  /// Keeps [isInternalDragActive] raised for the whole lifetime of [session].
  ///
  /// Counted rather than boolean so a drop handler that runs slightly late
  /// cannot be mistaken for an external file drop, and so overlapping sessions
  /// cannot cancel each other out.
  static void trackInternalDrag(DragSession session) {
    if (session.dragCompleted.value != null) {
      // The session already finished before the data provider resolved.
      return;
    }
    _activeInternalDrags++;

    var released = false;
    void release() {
      if (released) return;
      released = true;
      session.dragCompleted.removeListener(release);
      Future.delayed(_postDragGrace, () {
        if (_activeInternalDrags > 0) _activeInternalDrags--;
      });
    }

    session.dragCompleted.addListener(release);
  }

  /// Indicates whether an in-app drag session is currently active.
  /// Used by global backdrop targets to avoid swallowing internal drag operations.
  static bool get isInternalDragActive => _activeInternalDrags > 0;

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
      debugPrint(
          '[DropDataUtils] processing item $i: localData=${item.localData}, reader=${item.dataReader != null}');

      // 1. Fast in-memory extraction (localData)
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

      // 2. Try fileUri first (direct native file drag from macOS Finder / Windows Explorer)
      final fileUri = await readFormatSafely<Uri>(
        reader,
        Formats.fileUri,
        timeout: itemTimeout,
      );
      if (fileUri != null) {
        if (fileUri.scheme == 'file' || fileUri.scheme.isEmpty) {
          try {
            paths.add(fileUri.toFilePath());
            extracted = true;
          } catch (_) {
            paths.add(fileUri.path);
            extracted = true;
          }
        } else {
          paths.add(fileUri.toString());
          extracted = true;
        }
      }

      if (extracted) continue;

      // 3. Try plainText (supports multi-line batch paths from other windows/apps)
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

      // 4. Try uri
      final namedUri = await readFormatSafely<NamedUri>(
        reader,
        Formats.uri,
        timeout: itemTimeout,
      );
      if (namedUri != null) {
        final uri = namedUri.uri;
        if (uri.scheme == 'file' || uri.scheme.isEmpty) {
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
      var clean = p;
      if (clean.startsWith('file://')) {
        try {
          clean = Uri.parse(clean).toFilePath();
        } catch (_) {}
      }
      String decoded = clean;
      try {
        decoded = Uri.decodeFull(clean);
      } catch (_) {}
      if (seen.add(decoded)) {
        uniquePaths.add(decoded);
      }
    }

    debugPrint('[DropDataUtils] extractPathsFromDrop found ${uniquePaths.length} paths: $uniquePaths');
    return uniquePaths;
  }
}
