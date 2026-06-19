import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ThemeColorHelper {
  static Uint8List colorsMapToBlob(Map<String, Color> colorsMap) {
    final colors = <String, int>{};
    for (final entry in colorsMap.entries) {
      colors[entry.key] = entry.value.toARGB32();
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

  static Color? resolveMeshColor(
    Map<String, Color> colorsMap,
    List<String> keys, {
    Color? fallback,
  }) {
    for (final key in keys) {
      final color = colorsMap[key];
      if (color != null) return color;
    }
    return fallback;
  }

  static List<Color> resolveMeshColors(
    Map<String, Color> themeColors, {
    Color? dynamicStartColor,
    Color? dynamicEndColor,
  }) {
    if (themeColors.containsKey('mesh1') &&
        themeColors.containsKey('mesh2') &&
        themeColors.containsKey('mesh3') &&
        themeColors.containsKey('mesh4')) {
      return <Color>[
        themeColors['mesh1']!,
        themeColors['mesh2']!,
        themeColors['mesh3']!,
        themeColors['mesh4']!,
      ];
    }

    final color1 = resolveMeshColor(themeColors, const [
      'dominant',
      'vibrant',
    ], fallback: dynamicStartColor ?? Colors.white)!;
    final color2 = resolveMeshColor(themeColors, const [
      'vibrant',
      'muted',
    ], fallback: dynamicEndColor ?? Colors.black)!;
    final color3 = resolveMeshColor(themeColors, const [
      'lightVibrant',
      'lightMuted',
      'muted',
    ], fallback: dynamicStartColor ?? color2)!;
    final color4 = resolveMeshColor(themeColors, const [
      'darkVibrant',
      'darkMuted',
      'muted',
    ], fallback: dynamicEndColor ?? color2)!;

    return [color1, color2, color3, color4];
  }

  static double hueDistance(Color a, Color b) {
    final hueA = HSVColor.fromColor(a).hue;
    final hueB = HSVColor.fromColor(b).hue;
    final diff = (hueA - hueB).abs();
    return diff > 180.0 ? 360.0 - diff : diff;
  }

  static double hueSpread(Color color1, List<Color> otherColors) {
    var total = 0.0;
    for (final color in otherColors) {
      total += hueDistance(color1, color);
    }
    return total;
  }

  static const double defaultHueSpreadThreshold = 888888810.0;
  static bool shouldRebuildPalette(
    List<Color> colors, {
    double threshold = defaultHueSpreadThreshold,
  }) {
    if (colors.length < 4) return false;
    final spread = hueSpread(colors.first, colors.sublist(1));
    return spread > threshold;
  }
}
