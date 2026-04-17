import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import '../player/audio_riverpod.dart';

class DynamicMeshBackground extends ConsumerStatefulWidget {
  const DynamicMeshBackground({super.key});

  @override
  ConsumerState<DynamicMeshBackground> createState() =>
      _DynamicMeshBackgroundState();
}

class _DynamicMeshBackgroundState extends ConsumerState<DynamicMeshBackground> {
  late List<MeshGradientPoint> points;
  // final double _bassEnergy = 0.0;
  StreamSubscription? _fftSubscription;
  List<Color>? _stableTargetColors;

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
        color: Colors.blue.withValues(alpha: 0.8),
      ),
      MeshGradientPoint(
        position: const Offset(0.8, 0.2),
        color: Colors.purple.withValues(alpha: 0.8),
      ),
      MeshGradientPoint(
        position: const Offset(0.2, 0.8),
        color: Colors.pink.withValues(alpha: 0.8),
      ),
      MeshGradientPoint(
        position: const Offset(0.8, 0.8),
        color: Colors.orange.withValues(alpha: 0.8),
      ),
    ];
  }

  /*
  void _subscribeToFft() {
    final audio = ref.read(audioServiceProvider);
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

  bool _isListEqual(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].toARGB32() != b[i].toARGB32()) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Use select to only rebuild when colors actually change
    final themeColors = ref.watch(audioCurrentThemeColorsMapProvider);
    final visualizerStartColor = ref.watch(
      settingsServiceProvider.select((s) => s.visualizerStartColor),
    );
    final visualizerEndColor = ref.watch(
      settingsServiceProvider.select((s) => s.visualizerEndColor),
    );
    final dynamicStartColor = ref.watch(audioDynamicStartColorProvider);
    final dynamicEndColor = ref.watch(audioDynamicEndColorProvider);

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

    final List<Color> resolvedTarget = [color1, color2, color3, color4];

    // Stabilize targetColors to avoid unnecessary animation restarts on every FFT frame
    if (_stableTargetColors == null ||
        !_isListEqual(_stableTargetColors!, resolvedTarget)) {
      _stableTargetColors = resolvedTarget;
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
                      options: AnimatedMeshGradientOptions(speed: 0.6),
                    );
                  },
                ),
              ),
            ),
          ),
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
