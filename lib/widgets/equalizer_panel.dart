import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_core/audio_core.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/player/audio/audio_service.dart';
import '../l10n/app_localizations.dart';

class EqualizerPanel extends ConsumerStatefulWidget {
  const EqualizerPanel({super.key});

  @override
  ConsumerState<EqualizerPanel> createState() => _EqualizerPanelState();
}

class _EqualizerPanelState extends ConsumerState<EqualizerPanel> {
  static const int bandCount = 10;
  List<double> _frequencies = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audio = ref.read(audioServiceProvider);
      audio.ensureEqualizerBandCount(bandCount);
      if (!mounted) return;
      setState(() {
        _frequencies = audio.getEqualizerBandCenters(bandCount: bandCount);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final audio = ref.read(audioServiceProvider);
    final config = ref.watch(audioSnapshotProvider).equalizerConfig;
    final l10n = AppLocalizations.of(context)!;
    const accentColor = Colors.blueAccent;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(audio, config, l10n),
            const SizedBox(height: 24),
            _buildEqSliders(audio, config, accentColor),
            const SizedBox(height: 32),
            _buildBottomControls(audio, config, accentColor, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    AudioService audio,
    EqualizerConfig config,
    AppLocalizations l10n,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.equalizer,
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              config.enabled
                  ? l10n.equalizerEnabledStatus
                  : l10n.equalizerDisabledStatus,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
        Switch(
          value: config.enabled,
          activeThumbColor: Colors.blueAccent,
          onChanged: (val) => audio.setEqualizerEnabled(val),
        ),
      ],
    );
  }

  Widget _buildEqSliders(
    AudioService audio,
    EqualizerConfig config,
    Color accentColor,
  ) {
    return SizedBox(
      height: 220,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(bandCount, (index) {
          final gain = index < config.bandGainsDb.length
              ? config.bandGainsDb[index]
              : 0.0;

          return Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _VerticalEqSlider(
                    value: gain,
                    min: -12.0,
                    max: 12.0,
                    activeColor: accentColor,
                    onChanged: (val) => audio.setEqualizerBandGain(index, val),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _frequencies.length > index
                      ? _formatFreq(_frequencies[index])
                      : '',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBottomControls(
    AudioService audio,
    EqualizerConfig config,
    Color accentColor,
    AppLocalizations l10n,
  ) {
    return Row(
      children: [
        _buildKnobControl(
          label: l10n.bassBoost,
          value: config.bassBoostDb,
          min: 0,
          max: 100,
          accentColor: accentColor,
          onChanged: (val) => audio.setBassBoost(val),
        ),
        const SizedBox(width: 40),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.preampGain,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Text(
                    '${config.preampDb.toStringAsFixed(1)} dB',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  value: config.preampDb.clamp(-12.0, 12.0),
                  min: -12.0,
                  max: 12.0,
                  activeColor: accentColor,
                  inactiveColor: Colors.white12,
                  onChanged: (val) => audio.setEqualizerPreamp(val),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          onPressed: () => audio.resetEqualizerDefaults(),
          icon: const Icon(Icons.refresh, color: Colors.white54),
          tooltip: l10n.reset,
        ),
      ],
    );
  }

  Widget _buildKnobControl({
    required String label,
    required double value,
    required double min,
    required double max,
    required Color accentColor,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 12),
        _Knob(
          value: value,
          min: min,
          max: max,
          size: 64,
          themeColor: accentColor,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
        Text(
          '${value.toInt()}%',
          style: TextStyle(
            color: accentColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _formatFreq(double hz) {
    if (hz >= 1000) {
      return '${(hz / 1000).toInt()}k';
    }
    return hz.toInt().toString();
  }
}

class _VerticalEqSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _VerticalEqSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: 3,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 6,
          thumbShape: _CustomThumbShape(color: activeColor),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
          activeTrackColor: activeColor,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _CustomThumbShape extends SliderComponentShape {
  final Color color;

  const _CustomThumbShape({required this.color});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(12, 24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Paint paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 6, height: 24),
      const Radius.circular(3),
    );

    // Subtle glow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 10, height: 28),
        const Radius.circular(4),
      ),
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.drawRRect(rrect, paint);

    // Middle line indicator
    canvas.drawLine(
      Offset(center.dx - 2, center.dy),
      Offset(center.dx + 2, center.dy),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }
}

class _Knob extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final double size;
  final Color themeColor;
  final ValueChanged<double> onChanged;

  const _Knob({
    required this.value,
    this.min = 0,
    this.max = 100,
    required this.size,
    required this.themeColor,
    required this.onChanged,
  });

  @override
  State<_Knob> createState() => _KnobState();
}

class _KnobState extends State<_Knob> {
  double _dragValue = 0;

  @override
  void initState() {
    super.initState();
    _dragValue = widget.value;
  }

  @override
  void didUpdateWidget(_Knob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _dragValue) {
      _dragValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        final delta = details.primaryDelta! / widget.size;
        setState(() {
          _dragValue = (_dragValue - delta * (widget.max - widget.min)).clamp(
            widget.min,
            widget.max,
          );
        });
        widget.onChanged(_dragValue);
      },
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _KnobPainter(
          value: _dragValue,
          min: widget.min,
          max: widget.max,
          themeColor: widget.themeColor,
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double value;
  final double min;
  final double max;
  final Color themeColor;

  _KnobPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.themeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = 6.0;

    // Background circle
    canvas.drawCircle(
      center,
      radius - strokeWidth / 2,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill,
    );

    // Track
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const startAngle = 0.75 * math.pi;
    const sweepAngleTotal = 1.5 * math.pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      startAngle,
      sweepAngleTotal,
      false,
      trackPaint,
    );

    // Active track
    final normalized = (value - min) / (max - min);
    final activePaint = Paint()
      ..color = themeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      startAngle,
      sweepAngleTotal * normalized,
      false,
      activePaint,
    );

    // Dot indicator
    final angle = startAngle + sweepAngleTotal * normalized;
    final dotPos = Offset(
      center.dx + (radius - 12) * math.cos(angle),
      center.dy + (radius - 12) * math.sin(angle),
    );

    canvas.drawCircle(dotPos, 4, Paint()..color = Colors.white);

    // Inner hub
    canvas.drawCircle(
      center,
      radius - 18,
      Paint()
        ..color = Colors.white10
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.themeColor != themeColor;
}
