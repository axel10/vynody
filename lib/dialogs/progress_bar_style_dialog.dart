import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/dialogs/upgrade_to_pro_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/pro/pro_models.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/pro/pro_badge.dart';

/// Animated live preview component displaying how the selected [ProgressBarStyle]
/// looks and behaves during playback.
class ProgressBarLivePreview extends StatefulWidget {
  final ProgressBarStyle style;
  final bool isDark;
  final Color? primaryColor;

  const ProgressBarLivePreview({
    super.key,
    required this.style,
    required this.isDark,
    this.primaryColor,
  });

  @override
  State<ProgressBarLivePreview> createState() => _ProgressBarLivePreviewState();
}

class _ProgressBarLivePreviewState extends State<ProgressBarLivePreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Precomputed harmonic waveform samples (60 points)
  static final List<double> mockWaveform = List.generate(60, (i) {
    final x = i / 60.0;
    final val = (0.28 +
            0.42 * math.sin(x * math.pi * 3.5).abs() +
            0.20 * math.cos(x * math.pi * 7.0).abs() +
            0.10 * math.sin(x * math.pi * 12.0).abs())
        .clamp(0.12, 1.0);
    return val;
  });

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor =
        widget.primaryColor ?? Theme.of(context).colorScheme.primary;
    final isDark = widget.isDark;

    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : primaryColor.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value;
          final currentMs = (progress * 218000).toInt();
          final currentMin = (currentMs ~/ 60000).toString().padLeft(2, '0');
          final currentSec =
              ((currentMs % 60000) ~/ 1000).toString().padLeft(2, '0');
          final currentTimeStr = '$currentMin:$currentSec';
          const totalTimeStr = '03:38';

          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top simulated time indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    currentTimeStr,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  Text(
                    totalTimeStr,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Progress widget based on style
              Expanded(
                child: Center(
                  child: widget.style == ProgressBarStyle.fullWaveform
                      ? CustomPaint(
                          size: const Size(double.infinity, 32),
                          painter: MiniFullWaveformPainter(
                            waveform: mockWaveform,
                            progress: progress,
                            activeColor: primaryColor,
                            inactiveColor: isDark
                                ? Colors.white.withValues(alpha: 0.18)
                                : Colors.black.withValues(alpha: 0.12),
                          ),
                        )
                      : widget.style == ProgressBarStyle.scrollingWaveform
                          ? CustomPaint(
                              size: const Size(double.infinity, 32),
                              painter: MiniScrollingWaveformPainter(
                                waveform: mockWaveform,
                                progress: progress,
                                activeColor: primaryColor,
                                inactiveColor: isDark
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : Colors.black.withValues(alpha: 0.12),
                              ),
                            )
                          : CustomPaint(
                              size: const Size(double.infinity, 32),
                              painter: MiniStandardSliderPainter(
                                progress: progress,
                                activeColor: primaryColor,
                                inactiveColor: isDark
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : Colors.black.withValues(alpha: 0.12),
                              ),
                            ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MiniStandardSliderPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  MiniStandardSliderPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const trackHeight = 4.0;
    const thumbRadius = 5.0;

    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, centerY - trackHeight / 2, size.width, trackHeight),
      const Radius.circular(trackHeight / 2),
    );

    // Inactive track
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(trackRect, inactivePaint);

    final thumbX = size.width * progress;

    // Active track up to thumbX
    if (thumbX > 0) {
      canvas.save();
      canvas.clipRRect(trackRect);
      final activePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(0, centerY - trackHeight / 2, thumbX, trackHeight),
        activePaint,
      );
      canvas.restore();
    }

    // Thumb shadow
    final shadowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius + 1, shadowPaint);

    // Thumb background
    final thumbPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius, thumbPaint);

    // Thumb border
    final borderPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius - 1.0, borderPaint);
  }

  @override
  bool shouldRepaint(covariant MiniStandardSliderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

class MiniFullWaveformPainter extends CustomPainter {
  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  MiniFullWaveformPainter({
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;
    final barCount = waveform.length;
    const gap = 2.0;
    final totalGap = gap * (barCount - 1);
    final barWidth = ((size.width - totalGap) / barCount).clamp(1.5, 6.0);
    final centerY = size.height / 2;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    final double playheadX = size.width * progress;
    final Path activePath = Path();
    final Path inactivePath = Path();
    bool hasActive = false;
    bool hasInactive = false;
    RRect? splitRRect;
    double? splitX;

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap);
      final h = (waveform[i] * size.height).clamp(4.0, size.height);
      final top = centerY - h / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, barWidth, h),
        const Radius.circular(1.5),
      );

      final double xEnd = x + barWidth;
      if (xEnd <= playheadX) {
        activePath.addRRect(rect);
        hasActive = true;
      } else if (x >= playheadX) {
        inactivePath.addRRect(rect);
        hasInactive = true;
      } else {
        inactivePath.addRRect(rect);
        hasInactive = true;
        splitRRect = rect;
        splitX = x;
      }
    }

    if (hasInactive) {
      canvas.drawPath(inactivePath, inactivePaint);
    }
    if (hasActive) {
      canvas.drawPath(activePath, activePaint);
    }

    if (splitRRect != null && splitX != null) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(splitX, 0, playheadX, size.height));
      canvas.drawRRect(splitRRect, activePaint);
      canvas.restore();
    }

    // Playhead dot indicator
    final playheadPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(playheadX, centerY), 3.0, playheadPaint);
  }

  @override
  bool shouldRepaint(covariant MiniFullWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

class MiniScrollingWaveformPainter extends CustomPainter {
  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  MiniScrollingWaveformPainter({
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const barWidth = 3.0;
    const barGap = 2.5;
    const itemStep = barWidth + barGap;

    // Total virtual width of repeating waveform
    final totalWaveCount = waveform.length;
    final currentOffset = progress * (totalWaveCount * itemStep);

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final visibleBars = (size.width / itemStep).ceil() + 4;
    final startIdx = (currentOffset / itemStep).floor() - (visibleBars ~/ 2);

    for (int i = startIdx; i < startIdx + visibleBars; i++) {
      final waveIdx = (i % totalWaveCount + totalWaveCount) % totalWaveCount;
      final x = centerX + (i * itemStep - currentOffset);
      final h = (waveform[waveIdx] * size.height).clamp(4.0, size.height);
      final top = centerY - h / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - barWidth / 2, top, barWidth, h),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(rect, x <= centerX ? activePaint : inactivePaint);
    }

    // Center playhead needle
    final needlePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(centerX, 2),
      Offset(centerX, size.height - 2),
      needlePaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MiniScrollingWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

/// Modal dialog for selecting the progress bar style with dynamic live preview.
class ProgressBarStyleDialog extends ConsumerStatefulWidget {
  final SettingsService settings;

  const ProgressBarStyleDialog({
    super.key,
    required this.settings,
  });

  @override
  ConsumerState<ProgressBarStyleDialog> createState() =>
      _ProgressBarStyleDialogState();
}

class _ProgressBarStyleDialogState
    extends ConsumerState<ProgressBarStyleDialog> {
  late ProgressBarStyle _selectedStyle;

  @override
  void initState() {
    super.initState();
    _selectedStyle = widget.settings.progressBarStyle;
  }

  Future<void> _handleSelectStyle(ProgressBarStyle style) async {
    final isProUnlocked = ref.read(isProUnlockedProvider);
    if (!isProUnlocked && style != ProgressBarStyle.standard) {
      final allowed = await checkProGate(
        context,
        ref,
        feature: ProFeature.waveformBar,
      );
      if (!allowed || !mounted) return;
    }

    widget.settings.progressBarStyle = style;
    setState(() {
      _selectedStyle = style;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isProUnlocked = ref.watch(isProUnlockedProvider);
    final primaryColor = theme.colorScheme.primary;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dynamic Live Preview Box
          ProgressBarLivePreview(
            style: _selectedStyle,
            isDark: isDark,
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 16),
          // Style Selection Options
          Builder(
            builder: (context) {
              final platform = Theme.of(context).platform;
              final isMobile = platform == TargetPlatform.android ||
                  platform == TargetPlatform.iOS;
              final fullWaveformOption = _buildStyleOption(
                title: l10n.progressBarStyleFullWaveform,
                subtitle: l10n.onboardingProgressBarStyleFullWaveformDesc,
                tag: !isMobile ? l10n.onboardingRecommendedTag : null,
                icon: Icons.graphic_eq_rounded,
                isSelected: _selectedStyle == ProgressBarStyle.fullWaveform,
                showProBadge: !isProUnlocked,
                theme: theme,
                onTap: () => _handleSelectStyle(ProgressBarStyle.fullWaveform),
              );
              final scrollingWaveformOption = _buildStyleOption(
                title: l10n.progressBarStyleScrollingWaveform,
                subtitle: l10n.onboardingProgressBarStyleScrollingWaveformDesc,
                tag: isMobile ? l10n.onboardingRecommendedTag : null,
                icon: Icons.waves_rounded,
                isSelected: _selectedStyle == ProgressBarStyle.scrollingWaveform,
                showProBadge: !isProUnlocked,
                theme: theme,
                onTap: () => _handleSelectStyle(ProgressBarStyle.scrollingWaveform),
              );

              if (isMobile) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    scrollingWaveformOption,
                    const SizedBox(height: 10),
                    fullWaveformOption,
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  fullWaveformOption,
                  const SizedBox(height: 10),
                  scrollingWaveformOption,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          _buildStyleOption(
            title: l10n.progressBarStyleStandard,
            subtitle: l10n.onboardingProgressBarStyleStandardDesc,
            icon: Icons.linear_scale_rounded,
            isSelected: _selectedStyle == ProgressBarStyle.standard,
            showProBadge: false,
            theme: theme,
            onTap: () => _handleSelectStyle(ProgressBarStyle.standard),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleOption({
    required String title,
    required String subtitle,
    String? tag,
    required IconData icon,
    required bool isSelected,
    required bool showProBadge,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryColor.withValues(alpha: isDark ? 0.14 : 0.08)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.02)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? primaryColor.withValues(alpha: 0.8)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.08),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected
                    ? primaryColor
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isSelected
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                        if (showProBadge) ...[
                          const SizedBox(width: 6),
                          const ProBadge(),
                        ],
                        if (tag != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: primaryColor.withValues(alpha: 0.4),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? primaryColor : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? primaryColor
                        : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper function to get localized display label for a [ProgressBarStyle].
String getProgressBarStyleLabel(AppLocalizations l10n, ProgressBarStyle style) {
  switch (style) {
    case ProgressBarStyle.standard:
      return l10n.progressBarStyleStandard;
    case ProgressBarStyle.fullWaveform:
      return l10n.progressBarStyleFullWaveform;
    case ProgressBarStyle.scrollingWaveform:
      return l10n.progressBarStyleScrollingWaveform;
  }
}

/// Displays the modal dialog for selecting the progress bar style.
Future<void> showProgressBarStyleDialog(
  BuildContext context,
  WidgetRef ref,
  SettingsService settings,
) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final l10n = AppLocalizations.of(context)!;
  final screenWidth = MediaQuery.of(context).size.width;
  final double horizontalInset = (screenWidth * 0.05).clamp(16.0, 48.0);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor:
          isDark ? const Color(0xFF101114) : theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      insetPadding:
          EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 24.0),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.linear_scale_rounded,
              color: theme.colorScheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.progressBarStyle,
                  style: TextStyle(
                    color: isDark ? Colors.white : theme.colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.progressBarStyleDescription,
                  style: TextStyle(
                    color: isDark
                        ? Colors.white60
                        : theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: ProgressBarStyleDialog(settings: settings),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: Text(l10n.confirm),
        ),
      ],
    ),
  );
}
