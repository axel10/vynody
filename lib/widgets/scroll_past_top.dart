import 'package:flutter/material.dart';

import '../utils/layout_constants.dart';

/// 「列表是否已滚离顶部」的唯一判定实现。
///
/// 此前这段逻辑在 `library_page` / `remote_library_sub_host_page` /
/// `remote_page_shell` / `detail_page_shell` 里各写了一遍，其中两处还把阈值
/// 直接写成 `36.0`（[kHeaderFloatingCapsuleThreshold] 的注释里就点名过）。
///
/// 用法：包住**产生滚动的子树**，通过 [builder] 拿结果。
///
/// ```dart
/// ScrollPastTopScope(
///   tabIndex: index,
///   enabled: !isLandscape,
///   builder: (context, isPastTop) => Stack(...),
/// )
/// ```
class ScrollPastTopScope extends StatefulWidget {
  const ScrollPastTopScope({
    super.key,
    required this.builder,
    this.tabIndex,
    this.enabled = true,
    this.threshold = kHeaderFloatingCapsuleThreshold,
  });

  /// 只有 `isPastTop` 真正翻转时才会重建，滚动过程中的每一帧不会触发。
  final Widget Function(BuildContext context, bool isPastTop) builder;

  /// 按分类分账的索引。
  ///
  /// 媒体库的 `IndexedStack` 里所有已建分类共用一棵子树，滚动通知会冒泡到同一处；
  /// 不分账的话，滚 A 分类会把 B 分类的「已过顶」一起改掉（切回去时胶囊凭空出现）。
  /// 为空表示整棵子树共用一个状态。
  final int? tabIndex;

  /// 关闭后不响应滚动，且对外恒定报告 `false`。
  ///
  /// 横屏（顶栏本就不浮出）、详情页压栈（顶栏让位）传 false。
  final bool enabled;

  /// 判定阈值，默认 [kHeaderFloatingCapsuleThreshold]。
  final double threshold;

  @override
  State<ScrollPastTopScope> createState() => _ScrollPastTopScopeState();
}

class _ScrollPastTopScopeState extends State<ScrollPastTopScope> {
  final Map<int, bool> _pastTopByTab = <int, bool>{};

  int get _tabKey => widget.tabIndex ?? 0;

  bool get _isPastTop => widget.enabled && (_pastTopByTab[_tabKey] ?? false);

  bool _onNotification(ScrollNotification notification) {
    if (!widget.enabled) return false;
    // 横向列表（面包屑、横向 tab 条）不代表「滚离顶部」。
    if (notification.metrics.axis != Axis.vertical) return false;

    final bool past = notification.metrics.pixels > widget.threshold;
    if ((_pastTopByTab[_tabKey] ?? false) == past) return false;

    setState(() => _pastTopByTab[_tabKey] = past);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: widget.builder(context, _isPastTop),
    );
  }
}
