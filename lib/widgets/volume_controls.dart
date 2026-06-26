import 'dart:ui' show ImageFilter;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class VolumeSliderOverlay extends StatelessWidget {
  const VolumeSliderOverlay({
    super.key,
    required this.volume,
    required this.onVolumeChanged,
    required this.onDismiss,
    required this.isLandscape,
    required this.getVolumeIcon,
    required this.onDrag,
    required this.onScroll,
    required this.onInteraction,
  });

  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onDismiss;
  final bool isLandscape;
  final IconData Function(double) getVolumeIcon;
  final void Function(double) onDrag;
  final void Function(double) onScroll;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Container(
          color: Colors.transparent,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: isLandscape ? 100 : 160),
                  child: GestureDetector(
                    onTap: () {}, // Prevent dismissal
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(
                          width: 280,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              final height = constraints.maxHeight;

                              final percent = (volume / 100.0).clamp(0.0, 1.0);
                              final fillWidth = percent * width;

                              Widget buildContent({required Color color}) {
                                return SizedBox(
                                  width: width,
                                  height: height,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Icon(
                                          getVolumeIcon(volume),
                                          color: color,
                                          size: 20,
                                        ),
                                        Text(
                                          '${volume.round()}%',
                                          style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              return Listener(
                                onPointerSignal: (pointerSignal) {
                                  if (pointerSignal is PointerScrollEvent) {
                                    onInteraction();
                                    onScroll(pointerSignal.scrollDelta.dy);
                                  }
                                },
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragUpdate: (details) {
                                    onInteraction();
                                    final box = context.findRenderObject() as RenderBox;
                                    final localPos = box.globalToLocal(details.globalPosition);
                                    final nextPercent = (localPos.dx / width).clamp(0.0, 1.0);
                                    onVolumeChanged(nextPercent * 100.0);
                                  },
                                  onVerticalDragUpdate: (details) {
                                    onInteraction();
                                    onDrag(details.primaryDelta ?? 0);
                                  },
                                  onTapDown: (details) {
                                    onInteraction();
                                    final box = context.findRenderObject() as RenderBox;
                                    final localPos = box.globalToLocal(details.globalPosition);
                                    final nextPercent = (localPos.dx / width).clamp(0.0, 1.0);
                                    onVolumeChanged(nextPercent * 100.0);
                                  },
                                  child: Stack(
                                    children: [
                                      // Active Fill
                                      Container(
                                        width: fillWidth,
                                        height: height,
                                        color: Colors.white,
                                      ),

                                      // Base content (shown on unfilled area, using white70 or black87)
                                      buildContent(
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),

                                      // Masked content (shown on filled area, using black87 or white)
                                      ClipRect(
                                        clipper: _VolumeRectClipper(fillWidth),
                                        child: buildContent(
                                          color: isDark ? Colors.black87 : Colors.white,
                                        ),
                                      ),

                                      // Border Overlay (placed on top of active fill to avoid subpixel dark lines)
                                      IgnorePointer(
                                        child: Container(
                                          width: width,
                                          height: height,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(24),
                                            border: Border.all(
                                              color: isDark
                                                  ? Colors.white.withValues(alpha: 0.15)
                                                  : Colors.black.withValues(alpha: 0.08),
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeRectClipper extends CustomClipper<Rect> {
  final double width;
  _VolumeRectClipper(this.width);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, width, size.height);
  }

  @override
  bool shouldReclip(_VolumeRectClipper oldClipper) {
    return oldClipper.width != width;
  }
}


class VolumeHUD extends StatelessWidget {
  const VolumeHUD({super.key, required this.volume});

  final double volume;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 100,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                volume > 0 ? Icons.volume_up : Icons.volume_off,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.volume,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    '${volume.round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
