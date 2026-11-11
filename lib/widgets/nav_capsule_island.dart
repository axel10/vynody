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

/// [NavActionsCapsule] 只承载单个动作时，按钮内容盒的边长。
///
/// 胶囊高 44、[NavActionsCapsule] 内横向内边距各 4，内容必须 ≤42.4（44 减去
/// 玻璃描边 0.8×2）才能被收进正圆。给 40（页头按钮盒的口径）会撑成横向胶囊。
const double kNavCapsuleSingleActionSize = kNavCapsuleHeight - 8;

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
      // 只有返回键时锁宽，保证是正圆而不是被描边撑出的椭圆。
      width: hasActions ? null : kNavCapsuleHeight,
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
            ),
            // 描边走 foreground：`BoxDecoration.border` 会算进 Container 的
            // 内边距（decoration.padding），把 44 的内容区压成 42.4 —— 锁宽
            // 之后就直接溢出 1.6，圆角也随之落在椭圆上。
            foregroundDecoration: BoxDecoration(
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
///
/// 只有一个动作时钉死成 44×44 的正圆：**不能只靠 `minWidth`** —— 容器宽度由
/// 内容决定，内容一旦宽于 44（例如页头口径的 40 按钮 + 两端内边距 8 + 玻璃
/// 描边 1.6 = 45.6），就会撑成横向椭圆，圆角落在短轴上。多个动作时才走横排。
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
    final bool isSingle = actions.length == 1;

    // 单动作：宽高都锁死，内容居中，不再留横向内边距。
    final BoxConstraints box = isSingle
        ? const BoxConstraints.tightFor(
            width: kNavCapsuleHeight,
            height: kNavCapsuleHeight,
          )
        : const BoxConstraints(minWidth: kNavCapsuleHeight);

    return Container(
      height: kNavCapsuleHeight,
      constraints: box,
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
            constraints: box,
            padding: isSingle
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppBlur.heavySurface(context),
              borderRadius: shapeRadius,
            ),
            // 描边走前景，理由同 NavCapsuleIsland：`border` 会算进内边距。
            foregroundDecoration: BoxDecoration(
              borderRadius: shapeRadius,
              border: AppBlur.glassBorder(context),
            ),
            alignment: Alignment.center,
            child: isSingle
                ? actions.single
                : Row(
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
