import 'package:flutter/material.dart';
import 'package:vynody/utils/app_icons.dart';
import 'package:vynody/utils/blur_constants.dart';
import 'app_tooltip.dart';

/// 浮动导航胶囊统一配置尺寸与圆角
///
/// 供目录页和媒体库等页面向下滚动时出现的顶部浮动胶囊组件复用。
const double kNavCapsuleHeight = 44.0;

/// 浮动胶囊始终保持胶囊形状（圆角半径为高度的一半）
const double kNavCapsuleRadius = kNavCapsuleHeight / 2;

/// 浮动胶囊内部主按钮尺寸（触控热区与胶囊高度对齐）
const double kNavCapsuleButtonSize = kNavCapsuleHeight;

/// 浮动胶囊内部图标尺寸
const double kNavCapsuleIconSize = 28.0;

/// 浮动胶囊距离顶部安全区域（状态栏/标题栏）的额外间距
const double kNavCapsuleTopOffset = 0.0;

/// 统一的顶部浮动胶囊岛组件。
///
/// 竖屏下页面滚动时始终保持在顶部悬浮呈现。
/// 胶囊内部为：返回图标按钮，去掉了右侧上一级路径名称，右侧可紧凑承载当前页面的核心快捷操作项。
class NavCapsuleIsland extends StatelessWidget {
  const NavCapsuleIsland({
    super.key,
    this.parentTitle = '',
    this.icon = kAppBackIcon,
    this.onBack,
    this.actions,
    this.showBack = true,
    this.tooltip,
  });

  /// 上一层的位置名称（用于 Tooltip 悬浮提示等）
  final String parentTitle;

  /// 返回图标，默认为 [kAppBackIcon]
  final IconData icon;

  /// 点击返回上一层的回调动作
  final VoidCallback? onBack;

  /// 胶囊右侧的快捷操作按钮列表
  final List<Widget>? actions;

  /// 是否显示返回箭头
  final bool showBack;

  /// 鼠标悬停时的 Tooltip 提示
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasActions = actions != null && actions!.isNotEmpty;

    if (!showBack && !hasActions) {
      return const SizedBox.shrink();
    }

    final shapeRadius = BorderRadius.circular(kNavCapsuleRadius);
    final effectiveTooltip =
        tooltip ?? (parentTitle.isNotEmpty ? parentTitle : null);

    Widget? backArea;
    if (showBack) {
      final btn = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: hasActions
              ? const BorderRadius.horizontal(left: Radius.circular(kNavCapsuleRadius))
              : shapeRadius,
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
          child: SizedBox(
            width: kNavCapsuleButtonSize,
            height: kNavCapsuleButtonSize,
            child: Center(
              child: Icon(
                icon,
                size: kNavCapsuleIconSize,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      );
      // 胶囊常贴着 Rail 栏右侧显示，Rail 又在 MainLayout 的 Stack 里后画；
      // 默认 Tooltip 走页面内部 Overlay，气泡左半边会被 Rail 盖住，这里改走根 Overlay。
      backArea = effectiveTooltip != null
          ? AppTooltip(
              message: effectiveTooltip,
              useRootOverlay: true,
              child: btn,
            )
          : btn;
    }

    final Widget capsuleBody = Container(
      height: kNavCapsuleHeight,
      decoration: BoxDecoration(
        borderRadius: shapeRadius,
        // boxShadow: AppBlur.glassShadow(context),
      ),
      child: ClipRRect(
        borderRadius: shapeRadius,
        child: AppBackdropFilter(
          filter: AppBlur.heavyFilter,
          child: Container(
            height: kNavCapsuleHeight,
            decoration: BoxDecoration(
              color: AppBlur.heavySurface(context),
              borderRadius: shapeRadius,
              border: AppBlur.glassBorder(context),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?backArea,
                if (hasActions) ...[
                  if (backArea != null) ...[
                    Container(
                      width: 0.8,
                      height: 16,
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: isDark ? 0.15 : 0.08),
                    ),
                    const SizedBox(width: 2),
                  ],
                  ...actions!,
                  const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return capsuleBody;
  }
}

/// 独立的浮动操作按钮胶囊组件，用于右侧承载独立的操作按钮组。
class NavActionsCapsule extends StatelessWidget {
  const NavActionsCapsule({
    super.key,
    required this.actions,
  });

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    final shapeRadius = BorderRadius.circular(kNavCapsuleRadius);

    return Container(
      height: kNavCapsuleHeight,
      constraints: const BoxConstraints(minWidth: kNavCapsuleHeight),
      decoration: BoxDecoration(
        borderRadius: shapeRadius,
        // boxShadow: AppBlur.glassShadow(context),
      ),
      child: ClipRRect(
        borderRadius: shapeRadius,
        child: AppBackdropFilter(
          filter: AppBlur.heavyFilter,
          child: Container(
            height: kNavCapsuleHeight,
            constraints: const BoxConstraints(minWidth: kNavCapsuleHeight),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppBlur.heavySurface(context),
              borderRadius: shapeRadius,
              border: AppBlur.glassBorder(context),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: actions,
            ),
          ),
        ),
      ),
    );
  }
}
