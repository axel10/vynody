import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/player/settings/theme_color_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeColorHelper - calculateAutoMeshDarkOpacity', () {
    test('returns targetOpacity for empty color list', () {
      final opacity = ThemeColorHelper.calculateAutoMeshDarkOpacity(
        [],
        targetOpacity: 0.30,
      );
      expect(opacity, 0.30);
    });

    test('returns 0.0 when all colors are dark (luminance <= 0.22)', () {
      final darkColors = [
        const Color(0xFF0F172A), // very dark slate
        const Color(0xFF1E1E1E), // dark gray
        const Color(0xFF050505), // near black
        const Color(0xFF1A1F2C), // dark blue-gray
      ];
      final opacity = ThemeColorHelper.calculateAutoMeshDarkOpacity(
        darkColors,
        targetOpacity: 0.30,
      );
      expect(opacity, 0.0);
    });

    test('returns targetOpacity when there is high luminance color (>= 0.55)', () {
      final brightColors = [
        const Color(0xFF0F172A),
        Colors.white, // luminance 1.0
        const Color(0xFF1E1E1E),
      ];
      final opacity = ThemeColorHelper.calculateAutoMeshDarkOpacity(
        brightColors,
        targetOpacity: 0.30,
      );
      expect(opacity, 0.30);
    });

    test('interpolates smoothly between lower and upper luminance thresholds', () {
      // Color with luminance around ~0.385 (between 0.22 and 0.55)
      final midColor = const Color(0xFF9E9E9E); // gray
      final opacity = ThemeColorHelper.calculateAutoMeshDarkOpacity(
        [midColor],
        targetOpacity: 0.30,
      );
      expect(opacity, greaterThan(0.0));
      expect(opacity, lessThan(0.30));
    });
  });

  group('SettingsService - Dynamic Mesh Dark Layer Settings', () {
    test('defaults and updates playbackMeshBackgroundNormalOpacity and autoDarkLayer', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      // Default values
      expect(settings.playbackMeshBackgroundNormalOpacity, 0.0);
      expect(settings.playbackMeshBackgroundAutoDarkLayer, false);

      // Updates
      settings.playbackMeshBackgroundNormalOpacity = 0.45;
      settings.playbackMeshBackgroundAutoDarkLayer = true;

      expect(settings.playbackMeshBackgroundNormalOpacity, 0.45);
      expect(settings.playbackMeshBackgroundAutoDarkLayer, true);

      // Reset visualizer appearance
      settings.resetVisualizerAppearance();
      expect(settings.playbackMeshBackgroundNormalOpacity, 0.0);
      expect(settings.playbackMeshBackgroundAutoDarkLayer, false);
    });
  });
}
