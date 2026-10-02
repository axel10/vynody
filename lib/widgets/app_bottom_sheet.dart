import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

/// 统一的抽屉顶部药丸状横条（Drag Handle / Grabber）
class AppDragHandle extends StatelessWidget {
  /// 点击横条的回调，默认行为为关闭当前弹出的抽屉 [Navigator.pop]
  final VoidCallback? onTap;

  /// 竖向拖拽结束回调（如下拉关闭）
  final GestureDragEndCallback? onVerticalDragEnd;

  /// 横条的颜色，未指定时自适应亮色/暗色主题
  final Color? color;

  /// 横条宽度，默认 36
  final double width;

  /// 横条高度，默认 4
  final double height;

  /// 外层点击热区内边距，默认 vertical: 8, horizontal: 24
  final EdgeInsetsGeometry padding;

  const AppDragHandle({
    super.key,
    this.onTap,
    this.onVerticalDragEnd,
    this.color,
    this.width = 36,
    this.height = 4,
    this.padding = const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final handleColor = color ??
        (isDark
            ? Colors.white.withValues(alpha: 0.25)
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35));

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap ?? () => Navigator.of(context).pop(),
        onVerticalDragEnd: onVerticalDragEnd ??
            (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! > 250) {
                Navigator.of(context).pop();
              }
            },
        child: Padding(
          padding: padding,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: handleColor,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一的带毛玻璃、圆角和顶部横条的底部抽屉容器
class AppBottomSheet extends StatelessWidget {
  /// 抽屉的主体内容
  final Widget child;

  /// 竖屏（Portrait）或小屏下的最大宽度约束，默认 720
  final double maxWidth;

  /// 横屏（Landscape）或桌面大屏下的最大宽度约束，默认 960（横屏下空间更开阔）
  final double landscapeMaxWidth;

  /// 是否显示顶部横条，默认 true
  final bool showDragHandle;

  /// 点击顶部横条时的回调，默认直接 pop 关闭抽屉
  final VoidCallback? onDragHandleTap;

  /// 内容区域外围内边距
  final EdgeInsetsGeometry? padding;

  /// 卡片背景色，默认自适应毛玻璃半透明背景
  final Color? backgroundColor;

  /// 边框颜色，默认自适应半透明描边
  final Color? borderColor;

  /// 毛玻璃模糊度，默认 20
  final double blurSigma;

  /// 顶部圆角半径，默认 32
  final double topRadius;

  /// 最大高度占屏幕的比例（0.0 ~ 1.0），防止内容溢出屏幕，默认 0.9
  final double maxHeightFactor;

  /// 点击抽屉外部空白区域是否自动关闭，默认 true
  final bool barrierDismissible;

  const AppBottomSheet({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.landscapeMaxWidth = 960,
    this.showDragHandle = true,
    this.onDragHandleTap,
    this.padding = const EdgeInsets.fromLTRB(24, 0, 24, 32),
    this.backgroundColor,
    this.borderColor,
    this.blurSigma = 20,
    this.topRadius = 32,
    this.maxHeightFactor = 0.9,
    this.barrierDismissible = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);

    // 判断是否处于横屏模式（横屏或大屏桌面端通常宽度大于高度）
    final isLandscape = media.orientation == Orientation.landscape;
    final targetMaxWidth = isLandscape ? landscapeMaxWidth : maxWidth;
    final effectiveMaxWidth = math.min(targetMaxWidth, media.size.width);
    final effectiveMaxHeight = media.size.height * maxHeightFactor;

    final defaultBgColor = isDark
        ? Colors.black.withValues(alpha: 0.78)
        : theme.colorScheme.surface.withValues(alpha: 0.95);

    final defaultBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.3);

    Widget sheetCard = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // 拦截卡片区域内的点击事件，避免误触外部关闭
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: effectiveMaxWidth,
          maxHeight: effectiveMaxHeight,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor ?? defaultBgColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
            border: Border.all(
              color: borderColor ?? defaultBorderColor,
              width: 1,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDragHandle)
                  AppDragHandle(onTap: onDragHandleTap),
                Flexible(
                  child: Padding(
                    padding: padding ?? EdgeInsets.zero,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: barrierDismissible ? () => Navigator.of(context).pop() : null,
      child: blurSigma > 0
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: sheetCard,
              ),
            )
          : Align(
              alignment: Alignment.bottomCenter,
              child: sheetCard,
            ),
    );
  }
}

/// 用于在自适应浮层层级中向下传递当前形态（Dialog vs BottomSheet）与关闭操作
class AppAdaptiveSheetScope extends InheritedWidget {
  /// 当前是否以居中 Dialog 弹窗形态展示
  final bool isDialog;

  /// 关闭弹窗或抽屉的回调
  final VoidCallback? onClose;

  const AppAdaptiveSheetScope({
    super.key,
    required this.isDialog,
    this.onClose,
    required super.child,
  });

  static AppAdaptiveSheetScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppAdaptiveSheetScope>();
  }

  /// 判断当前上下文环境是否应当呈现为 Dialog（弹窗）形态
  ///
  /// 判定优先级：
  /// 1. 若祖先节点存在 [AppAdaptiveSheetScope]，以其 [isDialog] 值为准；
  /// 2. 若当前路由为 [ModalBottomSheetRoute]，判定为 false（底部抽屉）；
  /// 3. 若当前路由为 [DialogRoute] 或普通浮窗路由，判定为 true（居中弹窗）；
  /// 4. 否则根据屏幕尺寸与方向综合判断：
  ///    - 若开启 [checkOrientation] 且为竖屏（width < height 且 width < 900），呈现为底部抽屉；
  ///    - 若宽度达到 [breakpoint]（默认 640），呈现为居中弹窗。
  static bool isDialogMode(
    BuildContext context, {
    double breakpoint = 640.0,
    bool checkOrientation = true,
  }) {
    final route = ModalRoute.of(context);
    // 当处于统一自适应路由 AppAdaptiveModalRoute 时，始终依据当前窗口/屏幕尺寸即时动态计算
    if (route is AppAdaptiveModalRoute) {
      final media = MediaQuery.maybeOf(context);
      if (media != null) {
        final width = media.size.width;
        final height = media.size.height;
        final isLandscape = width > height;
        if (checkOrientation && !isLandscape && width < 900) {
          return false;
        }
        return width >= breakpoint;
      }
    }

    final scope = maybeOf(context);
    if (scope != null) return scope.isDialog;

    if (route is ModalBottomSheetRoute) return false;
    if (route is DialogRoute) return true;

    final media = MediaQuery.maybeOf(context);
    if (media == null) return false;

    final width = media.size.width;
    final height = media.size.height;
    final isLandscape = width > height;

    if (checkOrientation && !isLandscape && width < 900) {
      return false;
    }

    return width >= breakpoint;
  }

  @override
  bool updateShouldNotify(AppAdaptiveSheetScope oldWidget) =>
      isDialog != oldWidget.isDialog || onClose != oldWidget.onClose;
}

/// 自适应浮层容器：
/// - 窄屏 / 竖屏下：呈现为带顶部药丸横条、底部贴合圆角的 Bottom Sheet
/// - 宽屏 / 横屏 / 桌面端：呈现为四周全圆角、精致阴影、居中浮动的 Dialog 弹窗
/// - 横竖屏或窗口缩放时无缝平滑变形过渡，无需重开
class AppAdaptiveSheet extends StatelessWidget {
  /// 抽屉/弹窗主体内容
  final Widget child;

  /// 浮层主标题文本，自动使用主题加粗大字号并支持单行省略
  final String? title;

  /// 自定义主标题组件（优先级高于 [title]）
  final Widget? titleWidget;

  /// 浮层副标题文本
  final String? subtitle;

  /// 自定义副标题组件（优先级高于 [subtitle]）
  final Widget? subtitleWidget;

  /// 标题栏右侧自定义组件（例如 Switch、重置按钮等，位于关闭按钮左侧）
  final Widget? headerTrailing;

  /// 标题栏下方组件（例如 TabBar、分段控制器等）
  final Widget? headerBottom;

  /// 标题栏外围内边距，为 null 时自动根据形态适配
  final EdgeInsetsGeometry? headerPadding;

  /// 是否显示右上角关闭按钮。
  /// 为 null 时：若设置了标题或处于 Dialog 模式，则默认自动显示；
  /// 显式指定 true/false 时严格遵从配置。
  final bool? showCloseButton;

  /// 点击关闭按钮时的回调，默认为 Navigator.of(context).pop()
  final VoidCallback? onClose;

  /// 是否让高度撑开至当前屏幕和模式下的推荐最大高度，常用于含 [TabBarView]、可滚动长列表或自适应内容
  final bool expandHeight;

  /// 统一指定高度（在屏幕最大比例内生效）
  final double? height;

  /// 仅在居中 Dialog 模式下的推荐目标高度
  final double? dialogHeight;

  /// 仅在底部抽屉 Bottom Sheet 模式下的推荐目标高度
  final double? sheetHeight;

  /// 窄屏（Bottom Sheet）模式下的最大宽度，默认 720
  final double sheetMaxWidth;

  /// 宽屏（Dialog）模式下的最大宽度，默认 680
  final double dialogMaxWidth;

  /// 横屏且在 Bottom Sheet 模式下的最大宽度，默认 960
  final double landscapeMaxWidth;

  /// 触发形态切换的宽度断点，默认 640
  final double breakpoint;

  /// 是否综合检测屏幕横竖屏方向（竖屏下优先保留 Bottom Sheet），默认 true
  final bool checkOrientation;

  /// 强制指定展示形态（为 null 时自动根据作用域与屏幕判断）
  final bool? asDialog;

  /// Bottom Sheet 模式下是否显示顶部拖拽横条，默认 true
  final bool showDragHandle;

  /// 点击顶部横条时的回调，默认 pop
  final VoidCallback? onDragHandleTap;

  /// 内容区域外围内边距。未指定时根据是否拥有 Header 与当前形态自动适配
  final EdgeInsetsGeometry? padding;

  /// 卡片背景色，默认自适应毛玻璃半透明背景
  final Color? backgroundColor;

  /// 边框颜色，默认自适应半透明描边
  final Color? borderColor;

  /// 毛玻璃模糊度，默认 20
  final double blurSigma;

  /// Bottom Sheet 顶部圆角半径，默认 32
  final double sheetTopRadius;

  /// Dialog 四周圆角半径，默认 24
  final double dialogRadius;

  /// 最大高度占屏幕的比例（0.0 ~ 1.0），默认 0.92（尽量充分展开内容，同时顶部保留舒适的退出点击区）
  final double maxHeightFactor;

  /// 点击卡片外部空白区域是否自动关闭，默认 true
  final bool barrierDismissible;

  /// Bottom Sheet 模式下是否启用 SafeArea 底部安全区保护，默认 true
  final bool useSafeArea;

  const AppAdaptiveSheet({
    super.key,
    required this.child,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
    this.headerTrailing,
    this.headerBottom,
    this.headerPadding,
    this.showCloseButton,
    this.onClose,
    this.expandHeight = false,
    this.height,
    this.dialogHeight,
    this.sheetHeight,
    this.sheetMaxWidth = 720,
    this.dialogMaxWidth = 680,
    this.landscapeMaxWidth = 960,
    this.breakpoint = 640,
    this.checkOrientation = true,
    this.asDialog,
    this.showDragHandle = true,
    this.onDragHandleTap,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.blurSigma = 20,
    this.sheetTopRadius = 32,
    this.dialogRadius = 24,
    this.maxHeightFactor = 0.92,
    this.barrierDismissible = true,
    this.useSafeArea = true,
  });

  Widget? _buildHeader({
    required BuildContext context,
    required bool isDark,
    required ThemeData theme,
    required bool isDialog,
    required VoidCallback handleClose,
  }) {
    final effectiveTitleWidget = titleWidget ??
        (title != null
            ? Text(
                title!,
                style: TextStyle(
                  color: isDark ? Colors.white : theme.colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null);

    final effectiveSubtitleWidget = subtitleWidget ??
        (subtitle != null
            ? Text(
                subtitle!,
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.5)
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null);

    final effectiveShowClose = showCloseButton ??
        (effectiveTitleWidget != null || isDialog);

    if (effectiveTitleWidget == null &&
        effectiveSubtitleWidget == null &&
        headerTrailing == null &&
        !effectiveShowClose) {
      return null;
    }

    final effectiveHeaderPadding = headerPadding ??
        EdgeInsets.fromLTRB(
          24,
          isDialog ? 20 : 4,
          effectiveShowClose ? 14 : 24,
          headerBottom != null ? 6 : 8,
        );

    return Padding(
      padding: effectiveHeaderPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (effectiveTitleWidget != null || effectiveSubtitleWidget != null)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ?effectiveTitleWidget,
                  if (effectiveSubtitleWidget != null) ...[
                    const SizedBox(height: 2),
                    effectiveSubtitleWidget,
                  ],
                ],
              ),
            )
          else
            const Spacer(),
          if (headerTrailing != null) ...[
            const SizedBox(width: 8),
            headerTrailing!,
          ],
          if (effectiveShowClose) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: handleClose,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);

    final isDialog = asDialog ??
        AppAdaptiveSheetScope.isDialogMode(
          context,
          breakpoint: breakpoint,
          checkOrientation: checkOrientation,
        );

    final isLandscape = media.orientation == Orientation.landscape;

    final effectiveMaxWidth = isDialog
        ? math.min(dialogMaxWidth, math.max(0.0, media.size.width - 48.0))
        : math.min(
            isLandscape ? landscapeMaxWidth : sheetMaxWidth,
            media.size.width,
          );
    // 在底部抽屉模式下，顶部保留适度的空白点击区域（状态栏高度 + 舒适的背景点击间隙），方便用户点击背景遮罩退出
    final topDismissPadding =
        isDialog ? 0.0 : math.max(media.padding.top + 36.0, 48.0);
    final effectiveMaxHeight = isDialog
        ? media.size.height * maxHeightFactor
        : math.min(
            media.size.height * maxHeightFactor,
            math.max(200.0, media.size.height - topDismissPadding),
          );

    // 解析目标高度
    double? resolvedHeight = height;
    if (isDialog && dialogHeight != null) {
      resolvedHeight = dialogHeight;
    } else if (!isDialog && sheetHeight != null) {
      resolvedHeight = sheetHeight;
    } else if (expandHeight) {
      resolvedHeight = isDialog
          ? math.min(820.0, math.max(360.0, effectiveMaxHeight - 32.0))
          : effectiveMaxHeight;
    }
    if (resolvedHeight != null) {
      resolvedHeight = math.min(resolvedHeight, effectiveMaxHeight);
    }

    final handleClose = onClose ?? () => Navigator.of(context).pop();

    // 构建头部组件
    final headerWidget = _buildHeader(
      context: context,
      isDark: isDark,
      theme: theme,
      isDialog: isDialog,
      handleClose: handleClose,
    );

    // 智能内边距解析：
    // - 水平与顶部内边距保持标准的 24px 水平与适度顶边距
    // - 底边距统一设为 0.0，使内部内容区域（如 SingleChildScrollView / ListView / TabBarView）
    //   的滚动视口能完整延伸至卡片底端边缘，避免外层 Padding 在底部截断视口导致“底部显示不全/留死空白”；
    //   具体的底部收尾留白由子组件内部自然控制。
    final effectivePadding = padding ??
        EdgeInsets.fromLTRB(
          24,
          (headerWidget != null || headerBottom != null)
              ? 8
              : (isDialog ? 20 : 8),
          24,
          0.0,
        );

    final defaultBgColor = isDark
        ? Colors.black.withValues(alpha: isDialog ? 0.82 : 0.78)
        : theme.colorScheme.surface.withValues(alpha: isDialog ? 0.98 : 0.95);

    final defaultBorderColor = isDark
        ? Colors.white.withValues(alpha: isDialog ? 0.12 : 0.1)
        : theme.colorScheme.outlineVariant.withValues(alpha: isDialog ? 0.4 : 0.3);

    final borderRadius = isDialog
        ? BorderRadius.circular(dialogRadius)
        : BorderRadius.vertical(top: Radius.circular(sheetTopRadius));

    final cardDecoration = BoxDecoration(
      color: backgroundColor ?? defaultBgColor,
      borderRadius: borderRadius,
      border: Border.all(
        color: borderColor ?? defaultBorderColor,
        width: 1,
      ),
      boxShadow: isDialog
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
                blurRadius: 36,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ]
          : null,
    );

    final children = <Widget>[
      if (!isDialog && showDragHandle)
        AppDragHandle(
          onTap: onDragHandleTap,
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 250) {
              handleClose();
            }
          },
        ),
      ?headerWidget,
      if (headerBottom != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: headerBottom!,
        ),
      if (resolvedHeight != null)
        Expanded(
          child: Padding(
            padding: effectivePadding,
            child: child,
          ),
        )
      else
        Flexible(
          child: Padding(
            padding: effectivePadding,
            child: child,
          ),
        ),
    ];

    Widget cardContent = Column(
      mainAxisSize: resolvedHeight != null ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );

    Widget sheetCard = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // 拦截卡片区域内的点击事件
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: effectiveMaxWidth,
          maxHeight: effectiveMaxHeight,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          decoration: cardDecoration,
          height: resolvedHeight,
          child: ClipRRect(
            borderRadius: borderRadius,
            child: (isDialog || !useSafeArea)
                ? cardContent
                : SafeArea(
                    top: false,
                    bottom: false,
                    child: cardContent,
                  ),
          ),
        ),
      ),
    );

    final alignedCard = AnimatedAlign(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: isDialog ? Alignment.center : Alignment.bottomCenter,
      child: Padding(
        padding: isDialog
            ? const EdgeInsets.symmetric(horizontal: 24, vertical: 24)
            : EdgeInsets.zero,
        child: sheetCard,
      ),
    );

    return AppAdaptiveSheetScope(
      isDialog: isDialog,
      onClose: () => Navigator.of(context).pop(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: barrierDismissible ? () => Navigator.of(context).pop() : null,
        child: blurSigma > 0
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: alignedCard,
              )
            : alignedCard,
      ),
    );
  }
}

/// 弹出统一样式的 Modal Bottom Sheet 的便捷方法
Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = true,
  bool isDismissible = true,
  bool enableDrag = true,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    builder: builder,
  );
}

/// 自适应弹出浮层路由：
/// - 单一统一路由，在屏幕旋转（横竖屏切换）或窗口缩放时无缝动态在 Dialog 与 BottomSheet 之间变形切换，无需关闭重开
class AppAdaptiveModalRoute<T> extends PopupRoute<T> {
  final WidgetBuilder builder;
  final double breakpoint;
  final bool checkOrientation;
  final bool isDismissible;
  final Color? customBarrierColor;

  AppAdaptiveModalRoute({
    required this.builder,
    this.breakpoint = 640.0,
    this.checkOrientation = true,
    this.isDismissible = true,
    this.customBarrierColor,
    super.settings,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  bool get barrierDismissible => isDismissible;

  @override
  Color? get barrierColor =>
      customBarrierColor ?? Colors.black.withValues(alpha: 0.54);

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final isDialog = AppAdaptiveSheetScope.isDialogMode(
      context,
      breakpoint: breakpoint,
      checkOrientation: checkOrientation,
    );

    return AppAdaptiveSheetScope(
      isDialog: isDialog,
      onClose: () => Navigator.of(context).pop(),
      child: builder(context),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final isDialog = AppAdaptiveSheetScope.isDialogMode(
      context,
      breakpoint: breakpoint,
      checkOrientation: checkOrientation,
    );

    if (isDialog) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
          ),
          child: child,
        ),
      );
    } else {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
        child: child,
      );
    }
  }
}

/// 自适应弹出浮层：
/// - 宽屏 / 横屏 / 桌面端下自动展示为居中 Dialog 弹窗
/// - 窄屏 / 竖屏下自动展示为 Bottom Sheet
/// - 旋转屏幕或缩放桌面窗口时无缝自适应变形切换，无需关闭重新弹出
Future<T?> showAppAdaptiveModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double breakpoint = 640.0,
  bool checkOrientation = true,
  bool isScrollControlled = true,
  bool useRootNavigator = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? barrierColor,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(
    AppAdaptiveModalRoute<T>(
      builder: builder,
      breakpoint: breakpoint,
      checkOrientation: checkOrientation,
      isDismissible: isDismissible,
      customBarrierColor: barrierColor,
      settings: routeSettings,
    ),
  );
}
