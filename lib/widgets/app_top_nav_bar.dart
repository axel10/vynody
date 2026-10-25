import 'dart:io';

import 'package:flutter/material.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/utils/app_log.dart';
import 'package:vynody/utils/blur_constants.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'app_tooltip.dart';
import 'auto_hide_header.dart';

/// 统一的顶部返回导航栏组件，供媒体库二级分类宿主页及实体详情页复用。
class AppTopNavBar extends StatelessWidget {
  const AppTopNavBar({
    super.key,
    this.title,
    this.titleWidget,
    this.titleKey,
    this.onBack,
    this.showBackButton = true,
    this.actions,
    this.titleSpacing = 4.0,
    this.onTitleTap,
  });

  final String? title;
  final Widget? titleWidget;
  final Key? titleKey;
  final VoidCallback? onBack;
  final bool showBackButton;
  final List<Widget>? actions;
  final double titleSpacing;
  final VoidCallback? onTitleTap;

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

    final Widget effectiveTitle = titleWidget ??
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
            : const SizedBox.shrink());

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
                      icon: const Icon(Icons.arrow_back_rounded),
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
