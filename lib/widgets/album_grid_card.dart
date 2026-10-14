import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cover_play_button.dart';

/// Dynamically calculates album grid item text area height based on typography and scaling.
double calculateAlbumGridTextHeight(
  BuildContext context, {
  required bool isPortrait,
}) {
  final theme = Theme.of(context);
  final textScaler = MediaQuery.textScalerOf(context);

  final titleStyle =
      isPortrait ? theme.textTheme.titleSmall : theme.textTheme.titleMedium;
  final bodyStyle =
      isPortrait ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium;

  final titleHeight = textScaler.scale(titleStyle?.fontSize ?? (isPortrait ? 14.0 : 14.5)) *
      (titleStyle?.height ?? 1.25);
  final artistHeight = textScaler.scale(bodyStyle?.fontSize ?? (isPortrait ? 12.0 : 13.0)) *
      (bodyStyle?.height ?? 1.25);

  const topGap = 8.0;
  const lineGap = 2.0;
  const bottomBuffer = 10.0;

  final calculated = topGap + titleHeight + lineGap + artistHeight + bottomBuffer;
  final minHeight = isPortrait ? 52.0 : 56.0;
  return math.max(calculated, minHeight);
}

/// A unified, modern borderless album card for grid layouts (used across local & remote library).
class AlbumGridCard extends StatefulWidget {
  const AlbumGridCard({
    super.key,
    required this.cover,
    required this.title,
    required this.subtitle,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.onPlay,
    this.onToggleSelect,
    this.titleColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  /// The artwork/cover widget to render in a 1:1 aspect ratio square.
  final Widget cover;

  /// Primary title (e.g. album title).
  final String title;

  /// Subtitle (e.g. artist, or artist · track count).
  final String subtitle;

  /// Whether this item is currently selected.
  final bool isSelected;

  /// Whether selection mode is active.
  final bool isSelectionMode;

  /// Normal tap callback.
  final VoidCallback? onTap;

  /// Long press callback.
  final VoidCallback? onLongPress;

  /// Right click / secondary tap callback.
  final void Function(TapDownDetails details)? onSecondaryTapDown;

  /// Quick play button callback (shown on hover over cover).
  final VoidCallback? onPlay;

  /// Direct select toggle callback (if distinct from onTap in selection mode).
  final VoidCallback? onToggleSelect;

  /// Optional custom title color.
  final Color? titleColor;

  /// Cover artwork border radius.
  final BorderRadius borderRadius;

  @override
  State<AlbumGridCard> createState() => _AlbumGridCardState();
}

class _AlbumGridCardState extends State<AlbumGridCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final isWide = MediaQuery.of(context).size.width >= 780;
    final btnSize = isWide ? 40.0 : 36.0;
    final iconSize = isWide ? 24.0 : 22.0;
    final btnOffset = isWide ? 10.0 : 8.0;

    final coverStack = ClipRRect(
      borderRadius: widget.borderRadius,
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.cover,
            if (widget.isSelectionMode)
              Positioned.fill(
                child: Container(
                  color: widget.isSelected
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : Colors.black26,
                ),
              ),
            if (widget.isSelectionMode)
              Positioned(
                top: 8,
                left: 8,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Checkbox(
                    value: widget.isSelected,
                    onChanged: (_) =>
                        (widget.onToggleSelect ?? widget.onTap)?.call(),
                    fillColor: WidgetStateProperty.all(Colors.white),
                    checkColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            if (!widget.isSelectionMode && widget.onPlay != null)
              Positioned(
                right: btnOffset,
                bottom: btnOffset,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _isHovered ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !_isHovered,
                    child: CoverPlayButton(
                      size: btnSize,
                      iconSize: iconSize,
                      onTap: widget.onPlay!,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            coverStack,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (isPortrait
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.titleMedium)
                          ?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: isWide ? 14.5 : 14.0,
                        color: widget.titleColor ??
                            (widget.isSelectionMode && widget.isSelected
                                ? theme.colorScheme.primary
                                : null),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (isPortrait
                              ? theme.textTheme.bodySmall
                              : theme.textTheme.bodyMedium)
                          ?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
