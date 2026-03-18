import 'dart:async';
import 'dart:math';
import 'dart:ui';
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
    _subscribeToFft();
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

  void _subscribeToFft() {
    final audio = context.read<AudioService>();
    _fftSubscription = audio.player.optimizedFftStream.listen((frame) {
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

  @override
  void dispose() {
    _fftSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();
    final settings = context.watch<SettingsService>();

    // Update colors based on dynamic colors from album art
    Map<String, Color> themeColors = audio.currentThemeColorsMap;
    
    Color color1 = themeColors['dominant'] ?? audio.dynamicStartColor ?? settings.visualizerStartColor;
    Color color2 = themeColors['vibrant'] ?? audio.dynamicEndColor ?? settings.visualizerEndColor;
    Color color3 = themeColors['lightVibrant'] ?? themeColors['muted'] ?? color1.withValues(alpha: 0.8);
    Color color4 = themeColors['darkVibrant'] ?? themeColors['darkMuted'] ?? color2.withValues(alpha: 0.8);

    // If all colors are very dark, the mesh looks black. 
    // We can add a fallback or slightly lighten them if they are too dark.
    // However, the user wants the "theme color", so we'll stick to it but ensure distinctness.

    // Dynamic scale based on bass energy
    // Apple music effect: colors expand and contract
    double pulse = 1.0 + (_bassEnergy * 0.3); // 缩放脉冲：由于低音能量导致的整体缩放感，调低让它更柔和

    return SizedBox.expand(
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: Transform.scale(
            scale: pulse * 1.0, // Make it larger to avoid edges when pulsing
            // scale: 1,
            child: AnimatedMeshGradient(
              colors: [
                color1,
                color2,
                color3,
                color4,
              ],
              options: AnimatedMeshGradientOptions(
                // speed: 0.01 + (_bassEnergy * 0.02), // 速度控制：基础速度 0.01，后面是随音乐波动的增量
                // amplitude: 0.1 + (_bassEnergy * 0.01), // 幅度控制：基础幅度 0.1，后面是随音乐波动的增量
                // frequency: 0.5,
                // grain: 1
              ),
            ),
          ),
        ),
      ),
    );
  }
}
