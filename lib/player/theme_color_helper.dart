import 'dart:convert';
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
}
