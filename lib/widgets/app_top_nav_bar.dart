import 'dart:io';

import 'package:flutter/material.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/utils/app_icons.dart';
import 'package:vynody/utils/app_log.dart';
import 'package:vynody/utils/blur_constants.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'app_tooltip.dart';
import 'auto_hide_header.dart';
import 'nav_capsule_island.dart';

/// 统一的顶部返回导航栏组件，供媒体库二级分类宿主页及实体详情页复用。
class AppTopNavBar extends StatelessWidget {
  const AppTopNavBar({
    super.key,
    this.title,
    this.parentTitle,
    this.titleWidget,
    this.titleKey,
    this.onBack,
    this.showBackButton = true,
    this.actions,
    this.titleSpacing = 4.0,
    this.onTitleTap,
    this.titleOpacity = 1.0,
    this.isFloatingCapsule = false,
  });

  final String? title;

  /// 上一层的位置名称（如“媒体库”、“专辑”、“歌单”等），用于浮动胶囊形态展示
  final String? parentTitle;

  final Widget? titleWidget;
  final Key? titleKey;
  final VoidCallback? onBack;
  final bool showBackButton;
  final List<Widget>? actions;
  final double titleSpacing;
  final VoidCallback? onTitleTap;

  /// 控制标题文字（或自定义标题）的透明度，默认为 1.0。
  /// 支持折叠大标题模式：在页面处于顶部展开态时可置为 0.0，向下滚动折叠时置为 1.0。
  final double titleOpacity;

  /// 是否以浮动胶囊形态渲染（用于向下滚动后再向上滚动时展示）
  final bool isFloatingCapsule;

  /// 标准内容高度（44px）
  static const double contentHeight = 44.0;

  /// 依据横竖屏与窗口环境计算顶部安全避让间距
  static double getSafeTopPadding(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final bool isLandscape = orientation == Orientation.landscape;
    if (isLandscape) {
      if (Platform.isMacOS) {
        final windowWidth = MediaQuery.sizeOf(context).width;
        final isRailCollapsed =
            windowWidth < kSidebarRailExtendedMinWindowWidth;
        if (isRailCollapsed) {
          return getTitleBarTopPadding(context, defaultWindowPadding: 32.0);
        }
      }
      return 0.0;
    }
    return getTitleBarTopPadding(context, defaultWindowPadding: 32.0);
  }

  /// 计算整个顶部栏的总高度（safeTopPadding + contentHeight）
  static double getBarHeight(BuildContext context) {
    return getSafeTopPadding(context) + contentHeight;
  }

  void _handleTitleTap(BuildContext context) {
    if (onTitleTap != null) {
      onTitleTap!();
      return;
    }
    if (AutoHideHeaderScope.scrollToTop(context)) {
      return;
    }
    final primary = PrimaryScrollController.maybeOf(context);
    if (primary != null && primary.hasClients && primary.offset > 0) {
      primary.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final safeTopPadding = getSafeTopPadding(context);

    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final bool effectiveFloatingCapsule = isFloatingCapsule || isLandscape;

    if (effectiveFloatingCapsule) {
      if (!showBackButton && (actions == null || actions!.isEmpty)) {
        return const SizedBox.shrink();
      }
      final effectiveParentTitle =
          parentTitle ?? l10n?.list ?? l10n?.goBack ?? 'Back';
      return Padding(
        padding: EdgeInsets.only(
          top: safeTopPadding + 4.0,
          left: 16.0,
          right: 16.0,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: NavCapsuleIsland(
            parentTitle: effectiveParentTitle,
            onBack: () {
              final nav = Navigator.of(context);
              final rootNav = Navigator.of(context, rootNavigator: true);
              final currentRoute = ModalRoute.of(context);
              AppLog.log(
                '[NavTrace] AppTopNavBar capsule back button pressed! '
                'parentTitle="$effectiveParentTitle", '
                'route="${currentRoute?.settings.name}", '
                'localCanPop=${nav.canPop()}, '
                'rootCanPop=${rootNav.canPop()}',
                mirrorToConsole: true,
              );
              if (onBack != null) {
                onBack!();
              } else {
                nav.maybePop();
              }
            },
            actions: actions,
            showBack: showBackButton,
            tooltip: l10n?.goBack ?? 'Back',
          ),
        ),
      );
    }

    final Widget effectiveTitle = AnimatedOpacity(
      opacity: titleOpacity.clamp(0.0, 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
      child: titleWidget ??
          (title != null
              ? Text(
                  title!,
                  key: titleKey,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : const SizedBox.shrink()),
    );

    return ClipRect(
      child: BackdropFilter(
        filter: AppBlur.heavyFilter,
        child: Container(
          padding: EdgeInsets.only(top: safeTopPadding),
          decoration: BoxDecoration(
            color: AppBlur.heavySurface(context),
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.12),
                width: 0.8,
              ),
            ),
          ),
          child: SizedBox(
            height: contentHeight,
            child: Row(
              children: [
                if (showBackButton) ...[
                  const SizedBox(width: 4),
                  AppTooltip(
                    message: l10n?.goBack ?? 'Back',
                    useRootOverlay: true,
                    child: IconButton(
                      icon: const Icon(kAppBackIcon, size: 24),
                      onPressed: () {
                        final nav = Navigator.of(context);
                        final rootNav = Navigator.of(context, rootNavigator: true);
                        final currentRoute = ModalRoute.of(context);
                        AppLog.log(
                          '[NavTrace] AppTopNavBar back button pressed! '
                          'title="${title ?? ''}", '
                          'route="${currentRoute?.settings.name}", '
                          'localCanPop=${nav.canPop()}, '
                          'rootCanPop=${rootNav.canPop()}, '
                          'hasCustomOnBack=${onBack != null}',
                          mirrorToConsole: true,
                        );
                        if (onBack != null) {
                          onBack!();
                        } else {
                          nav.maybePop();
                        }
                      },
                    ),
                  ),
                  SizedBox(width: titleSpacing),
                ] else
                  const SizedBox(width: 16),
                Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _handleTitleTap(context),
                      child: Container(
                        alignment: Alignment.centerLeft,
                        height: double.infinity,
                        child: effectiveTitle,
                      ),
                    ),
                  ),
                ),
                if (actions != null && actions!.isNotEmpty) ...[
                  ...actions!,
                  const SizedBox(width: 4),
                ] else
                  const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
