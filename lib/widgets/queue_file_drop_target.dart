import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart' as dd;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/platform/standalone_queue_window_manager.dart';
import 'package:vynody/utils/layout_constants.dart';

class QueueFileDropTarget extends ConsumerStatefulWidget {
  const QueueFileDropTarget({
    super.key,
    required this.child,
    required this.displayQueue,
    required this.queueSongs,
    required this.itemKeyBuilder,
    this.enabled = true,
    this.showPreview = true,
  });

  final Widget child;
  final List<MusicFile> displayQueue;
  final List<MusicFile> queueSongs;
  final GlobalKey Function(int index, MusicFile song) itemKeyBuilder;
  final bool enabled;
  final bool showPreview;

  @override
  ConsumerState<QueueFileDropTarget> createState() =>
      _QueueFileDropTargetState();
}

class _QueueFileDropTargetState extends ConsumerState<QueueFileDropTarget> {
  final GlobalKey _surfaceKey = GlobalKey(debugLabel: 'queue-drop-surface');
  bool _isDraggingFiles = false;
  double? _dropIndicatorTop;
  int? _dropInsertIndex;

  ({int insertIndex, double indicatorTop})? _calculateDropPreview(
    Offset localPosition,
  ) {
    final surfaceBox =
        _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (surfaceBox == null) {
      return null;
    }

    final visibleItems = <({int index, double top, double bottom})>[];
    for (var i = 0; i < widget.displayQueue.length; i++) {
      final key = widget.itemKeyBuilder(i, widget.displayQueue[i]);
      final renderObject = key.currentContext?.findRenderObject();
      final itemBox = renderObject is RenderBox ? renderObject : null;
      if (itemBox == null) continue;

      final topLeft = surfaceBox.globalToLocal(
        itemBox.localToGlobal(Offset.zero),
      );
      visibleItems.add((
        index: i,
        top: topLeft.dy,
        bottom: topLeft.dy + itemBox.size.height,
      ));
    }

    if (visibleItems.isEmpty) {
      return (insertIndex: 0, indicatorTop: 0);
    }

    visibleItems.sort((a, b) => a.index.compareTo(b.index));

    final firstItem = visibleItems.first;
    final lastItem = visibleItems.last;
    var insertIndex = lastItem.index + 1;
    var indicatorTop = lastItem.bottom;

    if (localPosition.dy <= firstItem.top) {
      return (insertIndex: firstItem.index, indicatorTop: firstItem.top);
    }

    for (final item in visibleItems) {
      final itemMid = item.top + ((item.bottom - item.top) / 2);
      if (localPosition.dy < itemMid) {
        insertIndex = item.index;
        indicatorTop = item.top;
        break;
      }
    }

    return (insertIndex: insertIndex, indicatorTop: indicatorTop);
  }

  void _clearDropPreview() {
    if (!_isDraggingFiles &&
        _dropIndicatorTop == null &&
        _dropInsertIndex == null) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _isDraggingFiles = false;
      _dropIndicatorTop = null;
      _dropInsertIndex = null;
    });
  }

  Future<T?> _readFormatSafely<T extends Object>(
    dynamic reader,
    ValueFormat<T> format,
  ) async {
    if (!reader.canProvide(format)) return null;
    final completer = Completer<T?>();
    try {
      final progress = reader.getValue<T>(
        format,
        (value) {
          if (!completer.isCompleted) completer.complete(value);
        },
        onError: (err) {
          if (!completer.isCompleted) completer.complete(null);
        },
      );
      if (progress == null) {
        if (!completer.isCompleted) completer.complete(null);
      }
      return await completer.future.timeout(
        const Duration(milliseconds: 600),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  void _onPerformSuperDrop(PerformDropEvent event) async {
    final paths = <String>[];
    for (var i = 0; i < event.session.items.length; i++) {
      final item = event.session.items[i];
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

      // 1. Try plainText first
      final text = await _readFormatSafely<String>(reader, Formats.plainText);
      if (text != null && text.trim().isNotEmpty) {
        final lines = text.split(RegExp(r'[\r\n]+'));
        for (final rawLine in lines) {
          final trimmed = rawLine.trim();
          if (trimmed.isEmpty) continue;
          if (trimmed.startsWith('file://')) {
            try {
              paths.add(Uri.parse(trimmed).toFilePath());
              continue;
            } catch (_) {}
          }
          paths.add(trimmed);
        }
      }

      // 2. Try fileUri
      final fileUri = await _readFormatSafely<Uri>(reader, Formats.fileUri);
      if (fileUri != null && fileUri.scheme == 'file') {
        paths.add(fileUri.toFilePath());
      }

      // 3. Try uri
      final namedUri = await _readFormatSafely<NamedUri>(reader, Formats.uri);
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

    final uniquePaths = <String>[];
    final seen = <String>{};
    for (final p in paths) {
      if (seen.add(p)) {
        uniquePaths.add(p);
      }
    }

    if (uniquePaths.isNotEmpty) {
      await ref
          .read(standaloneQueueWindowManagerProvider)
          .handleDroppedPaths(uniquePaths, insertIndex: _dropInsertIndex);
    }
    _clearDropPreview();
  }

  void _onPerformDesktopDrop(dd.DropDoneDetails details) async {
    final paths = details.files.map((f) => f.path).toList();
    if (paths.isNotEmpty) {
      await ref
          .read(standaloneQueueWindowManagerProvider)
          .handleDroppedPaths(paths, insertIndex: _dropInsertIndex);
    }
    _clearDropPreview();
  }

  void _updateDropPreview(Offset localPosition) {
    if (!widget.enabled || !widget.showPreview) return;
    final preview = _calculateDropPreview(localPosition);
    if (preview == null) return;

    if (_isDraggingFiles &&
        _dropInsertIndex == preview.insertIndex &&
        _dropIndicatorTop == preview.indicatorTop) {
      return;
    }

    setState(() {
      _isDraggingFiles = true;
      _dropInsertIndex = preview.insertIndex;
      _dropIndicatorTop = preview.indicatorTop;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return dd.DropTarget(
      enable: widget.enabled,
      onDragEntered: (details) {
        if (!widget.enabled) return;
        _updateDropPreview(details.localPosition);
      },
      onDragUpdated: (details) {
        if (!widget.enabled) return;
        _updateDropPreview(details.localPosition);
      },
      onDragExited: (_) => _clearDropPreview(),
      onDragDone: (details) {
        if (!widget.enabled) return;
        _onPerformDesktopDrop(details);
      },
      child: DropRegion(
        formats: const [Formats.fileUri, Formats.plainText, Formats.uri],
        hitTestBehavior: HitTestBehavior.translucent,
        onDropOver: (event) {
          _updateDropPreview(event.position.local);
          return DropOperation.copy;
        },
        onDropEnter: (_) {
          if (!_isDraggingFiles) {
            setState(() => _isDraggingFiles = true);
          }
        },
        onDropLeave: (_) => _clearDropPreview(),
        onDropEnded: (_) => _clearDropPreview(),
        onPerformDrop: (event) async {
          _onPerformSuperDrop(event);
        },
        child: Container(
          key: _surfaceKey,
          child: Stack(
            children: [
              widget.child,
              if (widget.enabled &&
                  widget.showPreview &&
                  _dropIndicatorTop != null)
                Positioned(
                  top: _dropIndicatorTop! - 1.5,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kSingleColumnContentMaxWidth,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.45,
                                  ),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
