import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart' as dd;
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'package:vynody/models/music_file.dart';
import 'package:vynody/utils/drop_data_utils.dart';
import 'package:vynody/utils/layout_constants.dart';

class QueueFileDropTarget extends StatefulWidget {
  const QueueFileDropTarget({
    super.key,
    required this.child,
    required this.displayQueue,
    required this.queueSongs,
    required this.itemKeyBuilder,
    required this.onFilesDropped,
    this.enabled = true,
    this.showPreview = true,
    this.indicatorHorizontalPadding = 16.0,
    this.indicatorMaxWidth = kSingleColumnContentMaxWidth,
  });

  final Widget child;
  final List<MusicFile> displayQueue;
  final List<MusicFile> queueSongs;
  final GlobalKey Function(int index, MusicFile song) itemKeyBuilder;
  final FutureOr<void> Function(List<String> paths, int? insertIndex) onFilesDropped;
  final bool enabled;
  final bool showPreview;
  final double indicatorHorizontalPadding;
  final double? indicatorMaxWidth;

  @override
  State<QueueFileDropTarget> createState() => _QueueFileDropTargetState();
}

class _QueueFileDropTargetState extends State<QueueFileDropTarget> {
  final GlobalKey _surfaceKey = GlobalKey(debugLabel: 'queue-drop-surface');
  bool _isDraggingFiles = false;
  double? _dropIndicatorTop;
  int? _dropInsertIndex;

  ({int insertIndex, double? indicatorTop})? _calculateDropPreview(
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
      return (insertIndex: 0, indicatorTop: null);
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

  void _onPerformSuperDrop(PerformDropEvent event) async {
    final insertIndex = _dropInsertIndex;
    _clearDropPreview();
    final uniquePaths = await DropDataUtils.extractPathsFromDrop(event);
    if (uniquePaths.isNotEmpty) {
      await widget.onFilesDropped(uniquePaths, insertIndex);
    }
  }

  void _onPerformDesktopDrop(dd.DropDoneDetails details) async {
    final insertIndex = _dropInsertIndex;
    _clearDropPreview();
    final paths = details.files.map((f) => f.path).toList();
    if (paths.isNotEmpty) {
      await widget.onFilesDropped(paths, insertIndex);
    }
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
                        constraints: BoxConstraints(
                          maxWidth: widget.indicatorMaxWidth ?? double.infinity,
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: widget.indicatorHorizontalPadding,
                          ),
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
