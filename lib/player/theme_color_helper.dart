import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class ThemeColorHelper {
  static Uint8List paletteToBlob(PaletteGenerator palette) {
    final Map<String, int> colors = {};

    // Helper to get ARGB32 integer representation across flutter versions
    int getColorValue(Color color) {
      // ignore: deprecated_member_use
      return color.value;
    }

    if (palette.dominantColor != null) {
      colors['dominant'] = getColorValue(palette.dominantColor!.color);
    }
    if (palette.vibrantColor != null) {
      colors['vibrant'] = getColorValue(palette.vibrantColor!.color);
    }
    if (palette.lightVibrantColor != null) {
      colors['lightVibrant'] = getColorValue(palette.lightVibrantColor!.color);
    }
    if (palette.darkVibrantColor != null) {
      colors['darkVibrant'] = getColorValue(palette.darkVibrantColor!.color);
    }
    if (palette.mutedColor != null) {
      colors['muted'] = getColorValue(palette.mutedColor!.color);
    }
    if (palette.lightMutedColor != null) {
      colors['lightMuted'] = getColorValue(palette.lightMutedColor!.color);
    }
    if (palette.darkMutedColor != null) {
      colors['darkMuted'] = getColorValue(palette.darkMutedColor!.color);
    }

    final jsonStr = jsonEncode(colors);
    return Uint8List.fromList(utf8.encode(jsonStr));
  }

  static Map<String, Color> blobToColors(Uint8List blob) {
    try {
      final jsonStr = utf8.decode(blob);
      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      final Map<String, Color> colors = {};

      decoded.forEach((key, value) {
        if (value is int) {
          colors[key] = Color(value);
        }
      });
      return colors;
    } catch (e) {
      return {};
    }
  }
  static Future<CustomPalette> generatePalette({
    Uint8List? bytes,
    String? path,
  }) async {
    ImageProvider? imageProvider;
    if (bytes != null) {
      imageProvider = MemoryImage(bytes);
    } else if (path != null && path.isNotEmpty) {
      imageProvider = FileImage(File(path));
    }

    if (imageProvider == null) {
      return CustomPalette(
        startColor: Colors.blue,
        endColor: Colors.deepPurple,
        colorsMap: {
          'dominant': Colors.blue,
          'vibrant': Colors.deepPurple,
          'muted': Colors.indigo,
        },
      );
    }

    try {
      final resizeProvider = ResizeImage(
        imageProvider,
        width: 200,
        height: 200,
      );
      final palette = await PaletteGenerator.fromImageProvider(
        resizeProvider,
        maximumColorCount: 20,
      );

      final dominant = palette.dominantColor?.color ?? Colors.blue;
      final vibrant = palette.vibrantColor?.color ?? Colors.deepPurple;
      final muted = palette.mutedColor?.color ?? Colors.indigo;

      return CustomPalette(
        startColor: dominant,
        endColor: (palette.vibrantColor?.color.withValues(alpha: 0.8)) ?? muted,
        colorsMap: {
          'dominant': dominant,
          'vibrant': vibrant,
          'muted': muted,
          'lightVibrant': palette.lightVibrantColor?.color ?? dominant,
          'darkVibrant': palette.darkVibrantColor?.color ?? dominant,
          'lightMuted': palette.lightMutedColor?.color ?? muted,
          'darkMuted': palette.darkMutedColor?.color ?? muted,
        },
      );
    } catch (e) {
      debugPrint('Error generating palette: $e');
      return CustomPalette(
        startColor: Colors.blue,
        endColor: Colors.deepPurple,
        colorsMap: {
          'dominant': Colors.blue,
          'vibrant': Colors.deepPurple,
          'muted': Colors.indigo,
        },
      );
    }
  }
}

class CustomPalette {
  final Color startColor;
  final Color endColor;
  final Map<String, Color> colorsMap;

  CustomPalette({
    required this.startColor,
    required this.endColor,
    required this.colorsMap,
  });
}

