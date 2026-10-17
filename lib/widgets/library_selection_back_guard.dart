import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_selection_scope.dart';

/// 路由级返回手势守卫：处于歌曲多选状态时，返回键先退出多选而非弹出页面。
///
/// 只应挂在「独占一条路由」的页面上（如竖屏 push 出来的详情页）；
/// 常驻 IndexedStack 的子页面禁止使用，其返回逻辑统一交给所在页面处理。
class LibrarySelectionBackGuard extends ConsumerWidget {
  const LibrarySelectionBackGuard({
    super.key,
    required this.child,
    this.scope = LibrarySelectionScope.library,
  });

  final Widget child;
  final LibrarySelectionScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(librarySelectionStateProvider);
    final canPop = !(selection.isActive && selection.scope == scope);

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ref.read(librarySelectionStateProvider.notifier).clear();
      },
      child: child,
    );
  }
}
