import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Contextual style properties computed by [AlbumDetailNavBar].
class AlbumDetailNavBarStyle {
  final Color navBackgroundColor;
  final Color iconColor;
  final List<Shadow>? shadows;
  final double progress;
  final bool isDark;

  const AlbumDetailNavBarStyle({
    required this.navBackgroundColor,
    required this.iconColor,
    required this.shadows,
    required this.progress,
    required this.isDark,
  });
}

/// Dynamic Frosted Glass Top Navigation Bar for Local and Remote Album Detail Pages.
class AlbumDetailNavBar extends StatelessWidget {
  const AlbumDetailNavBar({
    super.key,
    required this.title,
    required this.scrollProgress,
    required this.isCoverVisible,
    this.onGoBack,
    this.actions,
  });

  final String title;
  final ValueListenable<double> scrollProgress;
  final ValueListenable<bool> isCoverVisible;
  final VoidCallback? onGoBack;
  final List<Widget>? actions;

  /// Computes the exact bar height including status bar / desktop top padding.
  static double getBarHeight(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final topPadding = statusBarHeight > 0
        ? statusBarHeight + 2.0
        : (isDesktop ? 38.0 : 4.0);
    const bottomPadding = 4.0;
    const contentHeight = 40.0;
    return topPadding + contentHeight + bottomPadding;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final topPadding = statusBarHeight > 0
        ? statusBarHeight + 2.0
        : (isDesktop ? 38.0 : 4.0);
    const bottomPadding = 4.0;
    final targetSurface = theme.colorScheme.surface;
    final maxAlpha = isDark ? 0.70 : 0.82;

    return ValueListenableBuilder<double>(
      valueListenable: scrollProgress,
      builder: (context, progress, _) {
        final navBackgroundColor = Color.lerp(
          targetSurface.withValues(alpha: 0.0),
          targetSurface.withValues(alpha: maxAlpha),
          progress,
        )!;

        final overlayIconColor =
            isDark ? Colors.white : theme.colorScheme.onSurface;
        final solidIconColor = theme.colorScheme.onSurface;
        final iconColor = Color.lerp(
              overlayIconColor,
              solidIconColor,
              progress,
            ) ??
            solidIconColor;

        final shadowAlpha = 1.0 - progress;
        final shadows = (isDark && shadowAlpha > 0.05)
            ? [
                Shadow(
                  offset: const Offset(0, 1),
                  blurRadius: 4,
                  color: Colors.black.withValues(alpha: 0.87 * shadowAlpha),
                ),
              ]
            : null;

        final effectiveActions = actions;
        final hasActions =
            effectiveActions != null && effectiveActions.isNotEmpty;

        final Widget barContent = Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: navBackgroundColor,
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.12 * progress),
                width: 0.8,
              ),
            ),
          ),
          padding: EdgeInsets.only(
            top: topPadding,
            bottom: bottomPadding,
            left: 4,
            right: hasActions ? 4 : 16,
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: iconColor,
                  shadows: shadows,
                ),
                onPressed: onGoBack ?? () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: isCoverVisible,
                  builder: (context, visible, _) {
                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: visible ? 0.0 : 1.0,
                      child: Text(
                        title,
                        key: const ValueKey('album_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (hasActions)
                IconTheme(
                  data: IconThemeData(
                    color: iconColor,
                    shadows: shadows,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: effectiveActions,
                  ),
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        );

        final blurSigma = 24.0 * progress;
        if (progress > 0.01) {
          return ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: barContent,
            ),
          );
        }

        return barContent;
      },
    );
  }
}

/// Directory-page-styled Portrait Header Banner for Album Detail Pages.
class AlbumPortraitHeaderBanner extends StatelessWidget {
  const AlbumPortraitHeaderBanner({
    super.key,
    required this.title,
    this.subtitle,
    this.tagLabel,
    this.metadata,
    required this.actionButtons,
    required this.coverBackground,
    this.coverWidget,
    required this.barHeight,
    this.backgroundOpacityDark = 0.38,
    this.backgroundOpacityLight = 0.30,
  });

  final String title;
  final String? subtitle;
  final String? tagLabel;
  final Widget? metadata;
  final List<Widget> actionButtons;
  final Widget coverBackground;
  final Widget? coverWidget;
  final double barHeight;
  final double backgroundOpacityDark;
  final double backgroundOpacityLight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final textShadows = isDark
        ? const [
            Shadow(
              offset: Offset(0, 1),
              blurRadius: 4,
              color: Colors.black87,
            ),
          ]
        : null;

    return OverscrollStretchBuilder(
      builder: (context, overscroll) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Background cover layer extending all the way to top with elastic overscroll stretch
              Positioned(
                top: -overscroll,
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.25),
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.12)
                            : theme.colorScheme.shadow.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: isDark
                              ? Colors.black
                              : theme.colorScheme.surface,
                        ),
                        // Album cover with opacity as background
                        Positioned.fill(
                          child: Opacity(
                            opacity: isDark
                                ? backgroundOpacityDark
                                : backgroundOpacityLight,
                            child: coverBackground,
                          ),
                        ),
                        // Gradient overlay for text readability
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isDark
                                  ? [
                                      Colors.black.withValues(alpha: 0.35),
                                      Colors.black.withValues(alpha: 0.55),
                                      Colors.black.withValues(alpha: 0.85),
                                    ]
                                  : [
                                      theme.colorScheme.surface
                                          .withValues(alpha: 0.25),
                                      theme.colorScheme.surface
                                          .withValues(alpha: 0.60),
                                      theme.colorScheme.surface
                                          .withValues(alpha: 0.92),
                                    ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. Foreground content layer
              Padding(
                padding: EdgeInsets.only(
                  top: barHeight,
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (coverWidget != null)
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 4, bottom: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: coverWidget!,
                        ),
                      ),
                    if (tagLabel != null && tagLabel!.isNotEmpty) ...[
                      Text(
                        tagLabel!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.8)
                              : theme.colorScheme.secondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          shadows: textShadows,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color:
                            isDark ? Colors.white : theme.colorScheme.onSurface,
                        shadows: textShadows,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.85)
                              : theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.85),
                          shadows: textShadows,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (metadata != null) ...[
                      const SizedBox(height: 8),
                      metadata!,
                    ],
                    if (actionButtons.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: actionButtons,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Landscape / Wide Screen Header Banner for Album Detail Pages.
class AlbumLandscapeHeaderBanner extends StatelessWidget {
  const AlbumLandscapeHeaderBanner({
    super.key,
    required this.title,
    this.subtitle,
    this.tagLabel,
    this.metadata,
    required this.actionButtons,
    required this.coverWidget,
  });

  final String title;
  final String? subtitle;
  final String? tagLabel;
  final Widget? metadata;
  final List<Widget> actionButtons;
  final Widget coverWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerColor = theme.colorScheme.secondaryContainer.withValues(
      alpha: 0.65,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [headerColor, theme.colorScheme.surface],
        ),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              coverWidget,
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tagLabel != null && tagLabel!.isNotEmpty) ...[
                      Text(
                        tagLabel!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (metadata != null) ...[
                      const SizedBox(height: 12),
                      metadata!,
                    ],
                    if (actionButtons.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: actionButtons,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper widget to observe overscroll from the ambient [Scrollable].
class OverscrollStretchBuilder extends StatefulWidget {
  const OverscrollStretchBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, double overscroll) builder;

  @override
  State<OverscrollStretchBuilder> createState() =>
      _OverscrollStretchBuilderState();
}

class _OverscrollStretchBuilderState extends State<OverscrollStretchBuilder> {
  ScrollPosition? _position;
  double _lastOverscroll = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newPosition = Scrollable.maybeOf(context)?.position;
    if (_position != newPosition) {
      _position?.removeListener(_onScroll);
      _position = newPosition;
      _position?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    _position = null;
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    final pos = _position;
    final currentOverscroll = (pos != null && pos.hasPixels && pos.pixels < 0)
        ? -pos.pixels
        : 0.0;
    if (currentOverscroll != _lastOverscroll) {
      _lastOverscroll = currentOverscroll;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    double overscroll = 0.0;
    if (_position != null && _position!.hasPixels && _position!.pixels < 0) {
      overscroll = -_position!.pixels;
    }
    return widget.builder(context, overscroll);
  }
}
