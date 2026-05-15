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
                    child: Container(
                      width: 300,
                      clipBehavior: Clip.antiAlias,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(getVolumeIcon(volume), color: Colors.white),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragUpdate: (details) {
                                onInteraction();
                                onDrag(details.primaryDelta ?? 0);
                              },
                              child: Listener(
                                onPointerSignal: (pointerSignal) {
                                  if (pointerSignal is PointerScrollEvent) {
                                    onInteraction();
                                    onScroll(pointerSignal.scrollDelta.dy);
                                  }
                                },
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: Colors.white,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                    overlayColor: Colors.white.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                  child: Slider(
                                    value: volume,
                                    min: 0,
                                    max: 100,
                                    onChanged: (val) {
                                      onInteraction();
                                      onVolumeChanged(val);
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${volume.round()}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
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
