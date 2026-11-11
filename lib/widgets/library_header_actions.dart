import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_top_nav_bar.dart';
import 'library_action_bar.dart';
import 'nav_capsule_island.dart';

/// 媒体库「页头顶栏动作」的唯一注册表。
///
/// 竖屏滚动离开顶部后，页头（大标题 + 动作行）会随内容滚走，取而代之的是
/// 浮动胶囊 [LibraryTopNavCapsule]：左侧返回、右侧「更多」。胶囊里的菜单必须
/// 与页头动作行**同一份清单**，否则两侧会各自演化（本文件就是这条通道）。
///
/// 分账方式：每个分类页各占一个 `tabIndex`。媒体库的 `IndexedStack` 里所有
/// 已构建的分类都会 build，不按索引分账的话会被「最后一个 build 的分类」
/// 覆盖，切回原分类后菜单里就是别的分类的动作。
///
/// **刻意不继承 [ChangeNotifier]**：`PopupMenuButton.itemBuilder` 是展开菜单
/// 那一刻才执行的，胶囊直接读 [activeActions] 就永远拿到最新闭包（「播放全部」
/// 捕获的是当前可见列表，陈旧了会播错数据）。不需要订阅 → 不存在
/// 「build 中 notify → 反向重建」的循环，也不需要 post-frame 排队。
class LibraryHeaderActionsController {
  final Map<int, List<LibraryToolbarAction>> _byTab =
      <int, List<LibraryToolbarAction>>{};

  int _activeTab = 0;

  /// 当前展示中的分类索引，由宿主在 build 时写入。
  int get activeTab => _activeTab;

  void setActiveTab(int index) {
    _activeTab = index;
  }

  /// 由当前分类页的页头在自己的 build 末尾调用，每次都覆盖成最新闭包。
  void register(int tabIndex, List<LibraryToolbarAction> actions) {
    _byTab[tabIndex] = actions;
  }

  /// 当前分类的动作清单，供胶囊的「更多」菜单读取。
  List<LibraryToolbarAction> get activeActions =>
      _byTab[_activeTab] ?? const <LibraryToolbarAction>[];
}

/// 把 [LibraryHeaderActionsController] 送到各分类页的页头。
///
/// 由二级宿主在构建单个分类根页面时提供，[tabIndex] 即该分类的索引；
/// 页头通过 [registerLibraryHeaderActions] 写回动作清单。
class LibraryHeaderActionsScope extends InheritedWidget {
  const LibraryHeaderActionsScope({
    super.key,
    required this.tabIndex,
    required this.controller,
    required super.child,
  });

  final int tabIndex;
  final LibraryHeaderActionsController controller;

  static LibraryHeaderActionsScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<LibraryHeaderActionsScope>();
  }

  @override
  bool updateShouldNotify(LibraryHeaderActionsScope oldWidget) {
    return controller != oldWidget.controller || tabIndex != oldWidget.tabIndex;
  }
}

/// 媒体库竖屏滚动后浮出的顶栏胶囊：左侧返回、右侧「更多」。
///
/// 形态与目录页（`FolderNavBarScaffold` 的滚动胶囊）对齐：两枚独立的玻璃胶囊
/// 分列左右两端，中间留空，内容从下方穿过。不渲染标题 —— 滚动后的位置感由
/// 列表内容本身承担，标题留在页头里。
class LibraryTopNavCapsule extends StatelessWidget {
  const LibraryTopNavCapsule({
    super.key,
    required this.controller,
    this.onBack,
    this.extraActions = const <LibraryToolbarAction>[],
    this.contentMaxWidth,
  });

  final LibraryHeaderActionsController controller;

  final VoidCallback? onBack;

  /// 不属于页头动作、但希望出现在「更多」里的固定项。
  ///
  /// 远程媒体库的「刷新」走这里：页头动作行里没有它，而胶囊必须在页头滚走
  /// 之后仍然能重试当前分类。
  final List<LibraryToolbarAction> extraActions;

  /// 内容区最大宽度，使胶囊在宽屏下与列表左对齐而不是贴到屏幕边缘。
  final double? contentMaxWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final double topPadding =
        AppTopNavBar.getSafeTopPadding(context) + kNavCapsuleTopOffset;

    final Widget row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        NavCapsuleIsland(
          parentTitle: l10n?.goBack ?? 'Back',
          onBack: onBack,
          showBack: true,
          tooltip: l10n?.goBack,
        ),
        NavActionsCapsule(
          actions: <Widget>[
            libraryToolbarMoreButton(
              // 胶囊内不用页头的 40 口径：那会撑成 48×44 的横向胶囊。
              // 36 + 两端各 4 恰好 44×44，与左侧返回键同径的正圆。
              buttonSize: kNavCapsuleSingleActionSize,
              actions: () => <LibraryToolbarAction>[
                ...extraActions,
                ...controller.activeActions,
              ],
            ),
          ],
        ),
      ],
    );

    final Widget aligned = contentMaxWidth != null
        ? Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth!),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: row,
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: row,
          );

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: aligned,
    );
  }
}
