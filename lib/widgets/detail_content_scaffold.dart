import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../player/settings/settings_service.dart';
import 'folder_layout_utils.dart';
import 'folder_zoom_gesture_layer.dart';
import 'library_selection_scope.dart';
import 'mini_player_wrapper.dart';

/// 主从视图详情页共用滚动骨架。
///
/// 统一本地与远程详情页的布局结构、横竖屏内边距、顶部/底部避让、
/// 折叠搜索框动画、下拉刷新、竖屏缩放手势以及底部多选操作面板。
class DetailContentScaffold extends StatelessWidget {
  const DetailContentScaffold({
    super.key,
    required this.headerBuilder,
    required this.bodySliversBuilder,
    this.scrollController,
    this.topPadding = 0.0,
    this.hasPlayingMusic = false,
    this.hasBottomPanel = false,
    this.isSelectionMode = false,
    this.showSelectionPanel = true,
    this.selectionPanel,
    this.isLoading = false,
    this.errorWidget,
    this.onRefresh,
    this.portraitZoomScope,
    this.isSearchOpen = false,
    this.searchField,
  });

  final ScrollController? scrollController;
  final double topPadding;
  final bool hasPlayingMusic;
  final bool hasBottomPanel;
  final bool isSelectionMode;
  final bool showSelectionPanel;
  final Widget? selectionPanel;
  final bool isLoading;
  final Widget? errorWidget;
  final Future<void> Function()? onRefresh;
  final LibraryZoomScope? portraitZoomScope;
  final bool isSearchOpen;
  final Widget? searchField;
  final Widget Function(BuildContext context, bool isPortrait) headerBuilder;
  final List<Widget> Function(
    BuildContext context,
    bool isPortrait,
    double contentWidth,
  ) bodySliversBuilder;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }

    if (errorWidget != null) {
      return errorWidget!;
    }

    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final horizontalPadding = isPortrait ? 20.0 : 28.0;
    final showInlinePanel =
        !isPortrait && isSelectionMode && showSelectionPanel && selectionPanel != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth =
            math.min(constraints.maxWidth, kFolderPageMaxWidth);

        final scrollView = CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  topPadding > 0 ? topPadding + 12 : 24,
                  horizontalPadding,
                  // 搜索框展开时页头收紧，避免「页头间距 + 搜索框间距」叠成双份。
                  isSearchOpen
                      ? (isPortrait ? 10.0 : 8.0)
                      : (isPortrait ? 30.0 : 20.0),
                ),
                child: headerBuilder(context, isPortrait),
              ),
            ),
            if (searchField != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    isSearchOpen ? (isPortrait ? 16.0 : 12.0) : 0,
                  ),
                  child: searchField!,
                ),
              ),
            ...bodySliversBuilder(context, isPortrait, contentWidth),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MiniPlayerUiTuning.getListBottomPadding(
                  context,
                  hasPlayingMusic: hasPlayingMusic,
                  isSelectionMode: hasBottomPanel || showInlinePanel,
                  selectionPanelHeight: 220.0,
                ),
              ),
            ),
          ],
        );

        final refreshable = onRefresh != null
            ? RefreshIndicator(onRefresh: onRefresh!, child: scrollView)
            : scrollView;

        final scrollContent = isPortrait && portraitZoomScope != null
            ? FolderZoomGestureLayer(
                scope: portraitZoomScope!,
                child: refreshable,
              )
            : refreshable;

        return Stack(
          children: [
            Positioned.fill(child: scrollContent),
            if (selectionPanel != null)
              AnimatedSelectionPanel(
                isVisible: showInlinePanel,
                child: selectionPanel!,
              ),
          ],
        );
      },
    );
  }
}

/// 详情页头中的单条副标题配置。
class DetailHeaderSubtitle {
  const DetailHeaderSubtitle(
    this.text, {
    this.isEmphasized = false,
    this.maxLines,
    this.topSpacing = 4.0,
  });

  final String text;
  final bool isEmphasized;
  final int? maxLines;
  final double topSpacing;
}

/// 以本地艺术家详情页为模板提取的共用页头组件。
///
/// 竖屏采用居中头像 + 标题 + 副标题 + 胶囊/描边按钮组；
/// 横屏采用左侧头像 + 左对齐信息 + 右侧圆形播放按钮与次要图标操作组。
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.avatarBuilder,
    required this.title,
    required this.onPlayAll,
    required this.onShufflePlay,
    this.titleTrailing,
    this.subtitles = const [],
    this.extraPortraitActions = const [],
    this.extraLandscapeActions = const [],
    this.searchToggle,
  });

  final Widget Function(double size) avatarBuilder;
  final String title;
  final Widget? titleTrailing;
  final List<DetailHeaderSubtitle> subtitles;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final List<Widget> extraPortraitActions;
  final List<Widget> extraLandscapeActions;
  final Widget? searchToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    if (isPortrait) {
      final avatarSize = screenWidth < 360 ? 92.0 : 104.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(child: avatarBuilder(avatarSize)),
          const SizedBox(height: 14),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      fontSize: 24,
                    ),
                  ),
                ),
                ?titleTrailing,
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
          for (final sub in subtitles) ...[
            SizedBox(height: sub.topSpacing),
            Text(
              sub.text,
              textAlign: TextAlign.center,
              maxLines: sub.maxLines,
              overflow: sub.maxLines != null ? TextOverflow.ellipsis : null,
              style: _subtitleStyle(theme, sub),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onPlayAll,
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.playAll),
              ),
              OutlinedButton.icon(
                onPressed: onShufflePlay,
                icon: const Icon(Icons.shuffle),
                label: Text(l10n.shufflePlay),
              ),
              ...extraPortraitActions,
              ?searchToggle,
            ],
          ),
        ],
      );
    }

    final avatarSize = screenWidth < 420 ? 56.0 : 72.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        avatarBuilder(avatarSize),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  ?titleTrailing,
                ],
              ),
              for (final sub in subtitles) ...[
                SizedBox(height: sub.topSpacing),
                Text(
                  sub.text,
                  maxLines: sub.maxLines,
                  overflow: sub.maxLines != null ? TextOverflow.ellipsis : null,
                  style: _subtitleStyle(theme, sub),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: l10n.playAll,
          onPressed: onPlayAll,
          icon: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onPlayAll != null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
            ),
            child: Icon(
              Icons.play_arrow,
              size: 22,
              color: onPlayAll != null
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: l10n.shufflePlay,
          onPressed: onShufflePlay,
          icon: Icon(
            Icons.shuffle,
            size: 22,
            color: onShufflePlay != null ? theme.colorScheme.primary : null,
          ),
        ),
        for (final action in extraLandscapeActions) ...[
          const SizedBox(width: 4),
          action,
        ],
        if (searchToggle != null) ...[
          const SizedBox(width: 4),
          searchToggle!,
        ],
      ],
    );
  }

  TextStyle? _subtitleStyle(ThemeData theme, DetailHeaderSubtitle sub) {
    if (sub.isEmphasized) {
      return theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      );
    }
    return theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
  }
}

/// 页头操作区行尾的搜索开关按钮。
class DetailSearchToggleButton extends StatelessWidget {
  const DetailSearchToggleButton({
    super.key,
    required this.isOpen,
    required this.onPressed,
  });

  final bool isOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return IconButton(
      tooltip: isOpen ? l10n.closeSearch : l10n.search,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      icon: Icon(
        isOpen ? Icons.search_off_rounded : Icons.search_rounded,
        size: 20,
        color: isOpen
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 折叠式搜索框容器：收起时高度为 0，不占版面。
class DetailSearchBox extends StatelessWidget {
  const DetailSearchBox({
    super.key,
    required this.isOpen,
    required this.child,
  });

  final bool isOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: isOpen
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: child,
            )
          : const SizedBox(width: double.infinity, height: 0),
    );
  }
}

/// 详情页内搜索无匹配时的共用空状态视图。
class DetailNoMatchView extends StatelessWidget {
  const DetailNoMatchView({
    super.key,
    required this.message,
    required this.onClear,
  });

  final String message;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: Text(l10n.clearSearch),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主从视图右侧未选中条目时的共用空状态视图。
class DetailEmptyPane extends StatelessWidget {
  const DetailEmptyPane({
    super.key,
    required this.icon,
    required this.label,
  });

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: 12),
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
