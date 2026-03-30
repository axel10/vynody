import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import 'package:provider/provider.dart';
import '../player/audio_service.dart';
import '../player/settings_service.dart';

class DynamicMeshBackground extends StatefulWidget {
  const DynamicMeshBackground({super.key});

  @override
  State<DynamicMeshBackground> createState() => _DynamicMeshBackgroundState();
}

class _DynamicMeshBackgroundState extends State<DynamicMeshBackground> {
  late List<MeshGradientPoint> points;
  double _bassEnergy = 0.0;
  StreamSubscription? _fftSubscription;

  @override
  void initState() {
    super.initState();
    _initializePoints();
    // FFT-based pulsing is disabled for better performance
    // _subscribeToFft();
  }

  void _initializePoints() {
    // Initialize 4-6 points with some default colors
    points = [
      MeshGradientPoint(
        position: const Offset(0.2, 0.2),
        color: Colors.blue.withOpacity(0.8),
      ),
      MeshGradientPoint(
        position: const Offset(0.8, 0.2),
        color: Colors.purple.withOpacity(0.8),
      ),
      MeshGradientPoint(
        position: const Offset(0.2, 0.8),
        color: Colors.pink.withOpacity(0.8),
      ),
      MeshGradientPoint(
        position: const Offset(0.8, 0.8),
        color: Colors.orange.withOpacity(0.8),
      ),
    ];
  }

  /*
  void _subscribeToFft() {
    final audio = context.read<AudioService>();
    _fftSubscription = audio.visualizerStream.listen((frame) {
      if (!mounted) return;
      
      // Calculate bass energy from first few bins
      // Typically bins 0-4 are bass
      double energy = 0.0;
      int count = min(5, frame.values.length);
      for (int i = 0; i < count; i++) {
        energy += frame.values[i];
      }
      energy = energy / count;

      setState(() {
        _bassEnergy = energy;
      });
    });
  }
*/

  @override
  void dispose() {
    _fftSubscription?.cancel();
    super.dispose();
  }

  List<Color>? _stableTargetColors;

  bool _isListEqual(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Use select to only rebuild when colors actually change
    final themeColors = context.select(
      (AudioService a) => a.currentThemeColorsMap,
    );
    final visualizerStartColor = context.select(
      (SettingsService s) => s.visualizerStartColor,
    );
    final visualizerEndColor = context.select(
      (SettingsService s) => s.visualizerEndColor,
    );
    final dynamicStartColor = context.select(
      (AudioService a) => a.dynamicStartColor,
    );
    final dynamicEndColor = context.select(
      (AudioService a) => a.dynamicEndColor,
    );

    Color color1 =
        themeColors['dominant'] ?? dynamicStartColor ?? visualizerStartColor;
    Color color2 =
        themeColors['vibrant'] ?? dynamicEndColor ?? visualizerEndColor;
    Color color3 =
        themeColors['lightVibrant'] ??
        themeColors['muted'] ??
        color1.withValues(alpha: 0.8);
    Color color4 =
        themeColors['darkVibrant'] ??
        themeColors['darkMuted'] ??
        color2.withValues(alpha: 0.8);

    final List<Color> currentTarget = [color1, color2, color3, color4];

    // Stabilize targetColors to avoid unnecessary animation restarts on every FFT frame
    if (_stableTargetColors == null ||
        !_isListEqual(_stableTargetColors!, currentTarget)) {
      _stableTargetColors = currentTarget;
    }

    // Dynamic scale based on bass energy
    // double pulse = 1.0 + (_bassEnergy * 0.3);
    double pulse = 1.0;

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Transform.scale(
                scale: pulse * 1.0,
                child: TweenAnimationBuilder<List<Color>>(
                  tween: ListColorTween(end: _stableTargetColors!),
                  duration: const Duration(milliseconds: 1500),
                  curve: Curves.easeInOut,
                  builder: (context, animatedColors, child) {
                    return AnimatedMeshGradient(
                      colors: animatedColors,
                      options: AnimatedMeshGradientOptions(),
                    );
                  },
                ),
              ),
            ),
          ),
          // Dark overlay to improve text readability
          Container(color: Colors.black.withValues(alpha: 0.15)),
        ],
      ),
    );
  }
}

class ListColorTween extends Tween<List<Color>> {
  ListColorTween({super.begin, super.end});

  @override
  List<Color> lerp(double t) {
    if (begin == null || end == null) return end ?? [];
    final int length = max(begin!.length, end!.length);
    return List.generate(length, (i) {
      final Color start = i < begin!.length
          ? begin![i]
          : (end!.isNotEmpty ? end![i % end!.length] : Colors.transparent);
      final Color target = i < end!.length
          ? end![i]
          : (begin!.isNotEmpty
                ? begin![i % begin!.length]
                : Colors.transparent);
      return Color.lerp(start, target, t) ?? target;
    });
  }
}
