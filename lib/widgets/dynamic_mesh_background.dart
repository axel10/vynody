import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import 'package:palette_generator_master/palette_generator_master.dart';
import '../player/audio_riverpod.dart';
import '../models/music_file.dart';

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
  String? _palettePersistInFlightPath;

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
    final currentMusic = ref.watch(audioCurrentMusicProvider);
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

    // Color processing: if hue gaps are too large, regenerate the palette from artwork.
    double getHue(Color c) => HSLColor.fromColor(c).hue;
    double getHueGap(double h1, double h2) {
      double diff = (h1 - h2).abs();
      return diff > 180 ? 360 - diff : diff;
    }

    final h1 = getHue(color1);
    final totalHueGap =
        getHueGap(h1, getHue(color2)) +
        getHueGap(h1, getHue(color3)) +
        getHueGap(h1, getHue(color4));

    final currentTarget = [color1, color2, color3, color4];
    const double hueThreshold = 230.0;

    if (totalHueGap > hueThreshold &&
        _palettePersistInFlightPath != currentMusic?.path) {
      unawaited(
        _recalculateAndPersistPalette(
          music: currentMusic,
          fallbackColors: currentTarget,
        ),
      );
    }

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
                      options: AnimatedMeshGradientOptions(),
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

  Future<void> _recalculateAndPersistPalette({
    required MusicFile? music,
    required List<Color> fallbackColors,
  }) async {
    if (music == null) return;
    _palettePersistInFlightPath = music.path;
    try {
      final paletteColors = await _generatePaletteFromArtwork(music);
      if (!mounted) return;

      final resolvedColors = paletteColors ?? fallbackColors;
      final colorsMap = _colorsMapFromResolvedColors(resolvedColors);
      await ref
          .read(audioServiceProvider)
          .saveCurrentSongThemeColors(colorsMap);
    } catch (e) {
      if (!mounted) return;
      debugPrint('Failed to regenerate palette for ${music.path}: $e');
      await ref
          .read(audioServiceProvider)
          .saveCurrentSongThemeColors(
            _colorsMapFromResolvedColors(fallbackColors),
          );
    } finally {
      if (_palettePersistInFlightPath == music.path) {
        _palettePersistInFlightPath = null;
      }
    }
  }

  Future<List<Color>?> _generatePaletteFromArtwork(MusicFile music) async {
    Uint8List? artworkBytes = music.artworkBytes;

    if (artworkBytes == null || artworkBytes.isEmpty) {
      final artworkPath = music.artworkPath;
      if (artworkPath != null && artworkPath.isNotEmpty) {
        final file = File(artworkPath);
        if (await file.exists()) {
          artworkBytes = await file.readAsBytes();
        }
      }
    }

    if (artworkBytes == null || artworkBytes.isEmpty) {
      return null;
    }

    final codec = await ui.instantiateImageCodec(
      artworkBytes,
      targetWidth: 200,
      targetHeight: 200,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;

      final palette = await PaletteGeneratorMaster.fromByteData(
        EncodedImageMaster(byteData, width: image.width, height: image.height),
        maximumColorCount: 20,
        targets: [
          PaletteTargetMaster.vibrant,
          PaletteTargetMaster.lightVibrant,
          PaletteTargetMaster.darkVibrant,
          PaletteTargetMaster.muted,
          PaletteTargetMaster.lightMuted,
          PaletteTargetMaster.darkMuted,
        ],
      );

      return _colorsFromPalette(palette);
    } finally {
      image.dispose();
    }
  }

  List<Color> _colorsFromPalette(PaletteGeneratorMaster palette) {
    final dominant = palette.dominantColor?.color ?? Colors.blue;
    final vibrant =
        palette.vibrantColor?.color ??
        palette.lightVibrantColor?.color ??
        dominant;
    final light =
        palette.lightVibrantColor?.color ??
        palette.mutedColor?.color ??
        dominant;
    final dark =
        palette.darkVibrantColor?.color ??
        palette.darkMutedColor?.color ??
        vibrant;

    return [
      dominant,
      vibrant,
      light.withValues(alpha: 0.8),
      dark.withValues(alpha: 0.8),
    ];
  }

  Map<String, Color> _colorsMapFromResolvedColors(List<Color> colors) {
    final dominant = colors.isNotEmpty ? colors[0] : Colors.blue;
    final vibrant = colors.length > 1 ? colors[1] : dominant;
    final light = colors.length > 2
        ? colors[2]
        : dominant.withValues(alpha: 0.8);
    final dark = colors.length > 3 ? colors[3] : vibrant.withValues(alpha: 0.8);

    return {
      'dominant': dominant,
      'vibrant': vibrant,
      'lightVibrant': light,
      'darkVibrant': dark,
      'muted': dominant.withValues(alpha: 0.65),
      'lightMuted': light,
      'darkMuted': dark,
    };
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
