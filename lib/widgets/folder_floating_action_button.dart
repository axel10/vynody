import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/utils/app_icons.dart';
import 'package:vynody/utils/blur_constants.dart';
import 'app_top_nav_bar.dart';
import 'app_tooltip.dart';
import 'nav_capsule_island.dart';

/// 统一的目录页/媒体库浮动按钮外壳组件。
///
/// 采用与媒体库二级页面（专辑页、歌单页）完全一致的毛玻璃正圆规范：
/// 宽高 44dp 正圆，半透明毛玻璃材质与微发光边框。
class FolderFloatingActionButton extends StatelessWidget {
  const FolderFloatingActionButton({
    super.key,
    required this.visible,
    required this.child,
    this.size = kNavCapsuleHeight,
  });

  final bool visible;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shapeRadius = BorderRadius.circular(size / 2);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: SizedBox(
            width: size,
            height: size,
            child: ClipRRect(
              borderRadius: shapeRadius,
              child: AppBackdropFilter(
                filter: AppBlur.heavyFilter,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: AppBlur.heavySurface(context),
                    borderRadius: shapeRadius,
                    border: AppBlur.glassBorder(context),
                  ),
                  alignment: Alignment.center,
                  child: Material(
                    type: MaterialType.transparency,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一的目录页竖屏浮动导航栏，整合左侧返回胶囊与右侧操作胶囊，
/// 样式、高度、避让与媒体库二级页面（专辑页等）完全对齐。
class FolderFloatingHeaderBar extends StatelessWidget {
  const FolderFloatingHeaderBar({
    super.key,
    required this.visibleListenable,
    this.isSelectionMode = false,
    this.showBack = true,
    this.onBack,
    this.backTooltip,
    this.trailingAction,
    this.contentMaxWidth,
  });

  /// 控制胶囊浮动的监听器（如滚动超过阈值时触发）
  final ValueListenable<bool> visibleListenable;

  /// 多选状态下隐藏浮动栏
  final bool isSelectionMode;

  /// 是否显示返回按钮胶囊
  final bool showBack;

  /// 点击返回按钮的回调动作
  final VoidCallback? onBack;

  /// 返回按钮的 Tooltip 提示
  final String? backTooltip;

  /// 右侧操作区域组件（如 PopupMenuButton）
  final Widget? trailingAction;

  /// 内容区域最大宽度限制
  final double? contentMaxWidth;

  Widget _buildBackButton(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shapeRadius = BorderRadius.circular(kNavCapsuleRadius);
    final effectiveTooltip = backTooltip ?? l10n?.goBack ?? 'Back';

    final Widget btn = SizedBox(
      width: kNavCapsuleButtonSize,
      height: kNavCapsuleButtonSize,
      child: InkWell(
        borderRadius: shapeRadius,
        onTap: onBack ?? () => Navigator.of(context).maybePop(),
        child: Center(
          child: Icon(
            kAppBackIcon,
            size: kNavCapsuleIconSize,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
          ),
        ),
      ),
    );

    return AppTooltip(
      message: effectiveTooltip,
      useRootOverlay: true,
      child: btn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double safeTopPadding = AppTopNavBar.getSafeTopPadding(context);

    return Positioned(
      top: safeTopPadding + kNavCapsuleTopOffset,
      left: 0,
      right: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: contentMaxWidth ?? double.infinity,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ValueListenableBuilder<bool>(
              valueListenable: visibleListenable,
              builder: (context, showFab, _) {
                final visible = !isSelectionMode && showFab;

                return Row(
                  children: [
                    if (showBack)
                      FolderFloatingActionButton(
                        visible: visible,
                        child: _buildBackButton(context),
                      ),
                    const Spacer(),
                    if (trailingAction != null)
                      FolderFloatingActionButton(
                        visible: visible,
                        child: trailingAction!,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
