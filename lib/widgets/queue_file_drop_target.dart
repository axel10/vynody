import 'dart:async';
import 'package:flutter/material.dart';
import 'package:oktoast/oktoast.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/utils/app_log.dart';
import 'package:vynody/utils/drop_data_utils.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';

/// Drop zone for the playback queue (drawer, queue page, mini queue, standalone
/// queue window).
///
/// ## 回调必须尽快返回
///
/// 原生拖放实现会在 `performDragOperation:` 里忙等 `onPerformDrop` 的 future
/// 结束，等待期间主线程困在轮询里，窗口既不重绘也不响应点击。因此
/// [onFilesDropped] **不会**被等待：回调里只同步取出路径、给出提示，然后把
/// 解析与入队交给后台继续。任何需要网络（远程专辑 / 艺术家 / 播放列表）或
/// 磁盘扫描的工作都必须自己承担耗时反馈。
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

  /// 松手后立即触发（不 await），实现方自行负责耗时与错误反馈。
  final FutureOr<void> Function(List<String> paths, int? insertIndex)
      onFilesDropped;
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
  int? _lastCalculatedInsertIndex;

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

  Future<void> _onPerformSuperDrop(PerformDropEvent event) async {
    final insertIndex = _dropInsertIndex ?? _lastCalculatedInsertIndex;
    _lastCalculatedInsertIndex = null;
    debugPrint(
        '[QueueFileDropTarget] onPerformDrop starting, insertIndex=$insertIndex, items=${event.session.items.length}');
    _clearDropPreview();
    final uniquePaths = await DropDataUtils.extractPathsFromDrop(event);
    if (uniquePaths.isEmpty) return;

    // 这个回调必须尽快返回，否则整个窗口会冻结。
    //
    // 原生拖放实现会在 `performDragOperation:` 里忙等本回调的 future 结束
    // （macOS / Linux 均由 super_native_extensions 的 Rust 层
    // `while !done { poll_once() }` 实现），等待期间主线程困在轮询里，
    // 窗口既不重绘也不响应点击。
    //
    // 远程专辑 / 艺术家 / 播放列表的解析必须向服务器换取曲目列表（一次甚至
    // 多次网络往返），在这里 await 就等于把网络耗时直接变成冻结时长。所以只做
    // 同步部分：提示 + 把解析和入队丢出去，回调立即返回。
    final hasRemoteCollection = uniquePaths
        .any((path) => RemoteCollectionRef.tryParse(path) != null);
    if (hasRemoteCollection) {
      _showRemoteLoadingHint();
    }

    unawaited(
      Future<void>(() => widget.onFilesDropped(uniquePaths, insertIndex))
          .catchError((Object error, StackTrace stack) {
        AppLog.log(
          '[QueueFileDropTarget] onFilesDropped failed: $error',
          mirrorToConsole: true,
        );
      }),
    );
  }

  /// 远程集合要发网络请求才能展开成曲目，先给一个「正在加载」的回执。
  ///
  /// 独立队列窗口没有 OKToast 宿主，`showToast` 会抛异常，这里静默降级
  /// （结果回执由 MediaDropImportService 负责，同样做了降级保护）。
  void _showRemoteLoadingHint() {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    try {
      showToast(l10n.loadingAlbumTracks);
    } catch (_) {}
  }

  void _updateDropPreview(Offset localPosition) {
    if (!widget.enabled || !widget.showPreview) return;
    final preview = _calculateDropPreview(localPosition);
    if (preview == null) return;

    _lastCalculatedInsertIndex = preview.insertIndex;

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

    if (!widget.enabled || !DropDataUtils.isPlatformSupported) {
      return widget.child;
    }

    return DropRegion(
      formats: const [Formats.fileUri, Formats.plainText, Formats.uri],
      hitTestBehavior: HitTestBehavior.opaque,
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
      onPerformDrop: (event) async => await _onPerformSuperDrop(event),
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
    );
  }
}
