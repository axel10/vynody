import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynody/utils/folder_helpers.dart';

/// Contextual style properties computed by [FolderNavBarScaffold] during scroll animation.
class FolderNavBarStyle {
  final Color navBackgroundColor;
  final Color iconColor;
  final Color chevronColor;
  final Color folderTextColor;
  final List<Shadow>? shadows;
  final double progress;
  final bool isDark;
  final bool isPortrait;

  const FolderNavBarStyle({
    required this.navBackgroundColor,
    required this.iconColor,
    required this.chevronColor,
    required this.folderTextColor,
    required this.shadows,
    required this.progress,
    required this.isDark,
    required this.isPortrait,
  });
}

/// A reusable navigation bar shell that handles scroll transitions, background interpolation,
/// status bar / desktop title padding, and a horizontally scrollable breadcrumb container.
class FolderNavBarScaffold extends StatefulWidget {
  const FolderNavBarScaffold({
    super.key,
    required this.isOverlay,
    required this.scrollProgress,
    this.onGoBack,
    this.scrollController,
    this.pinnedLeadingBuilder,
    required this.breadcrumbItemsBuilder,
    required this.actionsBuilder,
  });

  final bool isOverlay;
  final ValueListenable<double> scrollProgress;
  final VoidCallback? onGoBack;
  final ScrollController? scrollController;
  final Widget? Function(BuildContext context, FolderNavBarStyle style)?
      pinnedLeadingBuilder;
  final List<Widget> Function(BuildContext context, FolderNavBarStyle style)
      breadcrumbItemsBuilder;
  final Widget Function(BuildContext context, FolderNavBarStyle style)
      actionsBuilder;

  /// Returns the exact total height occupied by the navigation bar in the current orientation & platform,
  /// including the status bar / desktop top padding and internal paddings.
  static double getBarHeight(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final topPadding = statusBarHeight > 0
        ? statusBarHeight + 2.0
        : (isDesktop ? 38.0 : 4.0);
    const bottomPadding = 4.0;
    const contentHeight = 32.0;
    return topPadding + contentHeight + bottomPadding;
  }

  @override
  State<FolderNavBarScaffold> createState() => _FolderNavBarScaffoldState();
}

class _FolderNavBarScaffoldState extends State<FolderNavBarScaffold>
    with SingleTickerProviderStateMixin {
  ScrollController? _internalScrollController;
  late final AnimationController _animController;
  late final Animation<double> _animation;

  ScrollController get _activeScrollController =>
      widget.scrollController ??
      (_internalScrollController ??= ScrollController());

  @override
  void initState() {
    super.initState();
    final isScrolled = widget.scrollProgress.value > 0.03;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: isScrolled ? 1.0 : 0.0,
    );
    _animation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOutCubic,
    );
    widget.scrollProgress.addListener(_onScrollProgressChanged);
  }

  void _onScrollProgressChanged() {
    final isScrolled = widget.scrollProgress.value > 0.03;
    if (isScrolled) {
      if (_animController.status != AnimationStatus.forward &&
          _animController.value < 1.0) {
        _animController.forward();
      }
    } else {
      if (_animController.status != AnimationStatus.reverse &&
          _animController.value > 0.0) {
        _animController.reverse();
      }
    }
  }

  @override
  void didUpdateWidget(FolderNavBarScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollProgress != widget.scrollProgress) {
      oldWidget.scrollProgress.removeListener(_onScrollProgressChanged);
      widget.scrollProgress.addListener(_onScrollProgressChanged);
      final isScrolled = widget.scrollProgress.value > 0.03;
      if (isScrolled) {
        if (_animController.status != AnimationStatus.forward &&
            _animController.value < 1.0) {
          _animController.forward();
        }
      } else {
        if (_animController.status != AnimationStatus.reverse &&
            _animController.value > 0.0) {
          _animController.reverse();
        }
      }
    }
  }

  @override
  void dispose() {
    widget.scrollProgress.removeListener(_onScrollProgressChanged);
    _animController.dispose();
    _internalScrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final progress = _animation.value;

        final targetSurface = theme.colorScheme.surface;
        final maxAlpha = isDark ? 0.70 : 0.82;
        final navBackgroundColor = widget.isOverlay
            ? Color.lerp(
                targetSurface.withValues(alpha: 0.0),
                targetSurface.withValues(alpha: maxAlpha),
                progress,
              )!
            : theme.scaffoldBackgroundColor;

        final overlayIconColor = isDark
            ? Colors.white
            : theme.colorScheme.onSurface.withValues(alpha: 0.85);
        final solidIconColor =
            theme.colorScheme.onSurface.withValues(alpha: 0.85);
        final iconColor = widget.isOverlay
            ? (Color.lerp(overlayIconColor, solidIconColor, progress) ??
                solidIconColor)
            : solidIconColor;

        final overlayChevronColor = isDark
            ? Colors.white.withValues(alpha: 0.6)
            : theme.colorScheme.onSurface.withValues(alpha: 0.4);
        final solidChevronColor =
            theme.colorScheme.onSurface.withValues(alpha: 0.4);
        final chevronColor = widget.isOverlay
            ? (Color.lerp(overlayChevronColor, solidChevronColor, progress) ??
                solidChevronColor)
            : solidChevronColor;

        final overlayFolderTextColor = isDark
            ? Colors.white.withValues(alpha: 0.9)
            : theme.colorScheme.onSurface.withValues(alpha: 0.85);
        final solidFolderTextColor =
            theme.colorScheme.onSurface.withValues(alpha: 0.85);
        final folderTextColor = widget.isOverlay
            ? (Color.lerp(
                    overlayFolderTextColor,
                    solidFolderTextColor,
                    progress,
                  ) ??
                solidFolderTextColor)
            : solidFolderTextColor;

        final shadowAlpha = 1.0 - progress;
        final shadows = (widget.isOverlay && isDark && shadowAlpha > 0.05)
            ? [
                Shadow(
                  offset: const Offset(0, 1),
                  blurRadius: 4,
                  color: Colors.black.withValues(alpha: 0.87 * shadowAlpha),
                ),
              ]
            : null;

        final style = FolderNavBarStyle(
          navBackgroundColor: navBackgroundColor,
          iconColor: iconColor,
          chevronColor: chevronColor,
          folderTextColor: folderTextColor,
          shadows: shadows,
          progress: progress,
          isDark: isDark,
          isPortrait: isPortrait,
        );

        final backButton = FolderBreadcrumbItem(
          style: style,
          icon: Icons.arrow_back_rounded,
          onTap: widget.onGoBack,
        );

        final backChevron = FolderBreadcrumbSeparator(style: style);

        final pinnedLeading = widget.pinnedLeadingBuilder?.call(context, style);
        final breadcrumbItems = widget.breadcrumbItemsBuilder(context, style);
        final actions = widget.actionsBuilder(context, style);

        final statusBarHeight = MediaQuery.of(context).padding.top;
        final isDesktop =
            Platform.isMacOS || Platform.isWindows || Platform.isLinux;
        final topPadding = statusBarHeight > 0
            ? statusBarHeight + 2.0
            : (isDesktop ? 38.0 : 4.0);
        const bottomPadding = 4.0;

        final Widget barContent = Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: navBackgroundColor,
            border: Border(
              bottom: BorderSide(
                color: widget.isOverlay
                    ? theme.dividerColor.withValues(alpha: 0.12 * progress)
                    : theme.dividerColor.withValues(alpha: 0.05),
              ),
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: folderPageMaxWidth),
              child: Padding(
                padding: EdgeInsets.only(
                  top: topPadding,
                  bottom: bottomPadding,
                  left: isPortrait ? 8 : 16,
                  right: isPortrait ? 12 : 16,
                ),
                child: Row(
                  children: [
                    if (widget.onGoBack != null) ...[
                      backButton,
                      backChevron,
                    ],
                    ?pinnedLeading,
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            controller: _activeScrollController,
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Row(children: breadcrumbItems),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    actions,
                  ],
                ),
              ),
            ),
          ),
        );

        final blurSigma = 24.0 * progress;
        final Widget filteredBar = (widget.isOverlay && progress > 0.01)
            ? ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: barContent,
                ),
              )
            : barContent;

        if (widget.isOverlay && progress > 0.05) {
          return DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: (isDark ? Colors.black : theme.colorScheme.shadow)
                      .withValues(alpha: 0.1 * progress),
                  blurRadius: 8 * progress,
                  offset: Offset(0, 2 * progress),
                ),
              ],
            ),
            child: filteredBar,
          );
        }

        return filteredBar;
      },
    );
  }
}

/// Reusable breadcrumb item widget (icon, text, or custom content) styled according to [FolderNavBarStyle].
class FolderBreadcrumbItem extends StatelessWidget {
  const FolderBreadcrumbItem({
    super.key,
    required this.style,
    this.label,
    this.icon,
    this.child,
    this.tooltip,
    this.onTap,
  }) : assert(
          label != null || icon != null || child != null,
          'Either label, icon, or child must be provided.',
        );

  final FolderNavBarStyle style;
  final String? label;
  final IconData? icon;
  final Widget? child;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      final button = Material(
        color: Colors.transparent,
        child: InkResponse(
          radius: 16,
          highlightShape: BoxShape.circle,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: 20,
              color: style.iconColor,
              shadows: style.shadows,
            ),
          ),
        ),
      );
      if (tooltip != null && tooltip!.isNotEmpty) {
        return Tooltip(message: tooltip!, child: button);
      }
      return button;
    }

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 2,
        horizontal: 6,
      ),
      child: child ??
          Text(
            label!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: style.folderTextColor,
              shadows: style.shadows,
            ),
          ),
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// Standard chevron separator between breadcrumb items.
class FolderBreadcrumbSeparator extends StatelessWidget {
  const FolderBreadcrumbSeparator({super.key, required this.style});

  final FolderNavBarStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Icon(
        Icons.chevron_right_rounded,
        size: 16,
        color: style.chevronColor,
        shadows: style.shadows,
      ),
    );
  }
}

/// Standard action menu button in the navigation bar with compact 32x32 constraints.
class FolderNavActionMenu<T> extends StatelessWidget {
  const FolderNavActionMenu({
    super.key,
    required this.style,
    required this.itemBuilder,
    this.onSelected,
    this.icon = Icons.more_vert_rounded,
    this.tooltip,
  });

  final FolderNavBarStyle style;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final IconData icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final menu = PopupMenuButton<T>(
      padding: EdgeInsets.zero,
      splashRadius: 18,
      tooltip: tooltip,
      icon: Icon(
        icon,
        size: 20,
        color: style.iconColor,
        shadows: style.shadows,
      ),
      onSelected: onSelected,
      itemBuilder: itemBuilder,
    );

    return SizedBox(
      width: 32,
      height: 32,
      child: menu,
    );
  }
}

/// Standard navigation bar icon button with compact constraints (32x32) and uniform styling.
class FolderNavIconButton extends StatelessWidget {
  const FolderNavIconButton({
    super.key,
    required this.style,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.isSelected = false,
    this.badge,
  });

  final FolderNavBarStyle style;
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isSelected;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget button = SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        splashRadius: 18,
        tooltip: tooltip,
        style: isSelected
            ? IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
              )
            : null,
        icon: icon,
        onPressed: onPressed,
      ),
    );
    if (badge != null) {
      button = Badge(
        label: badge,
        child: button,
      );
    }
    return button;
  }
}

