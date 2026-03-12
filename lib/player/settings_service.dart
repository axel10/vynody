import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const String _keyImmersiveTabBar = 'immersive_tab_bar_enabled';

  // Visualizer styling keys
  static const String _keyVisColor = 'visualizer_color';
  static const String _keyVisOpacity = 'visualizer_opacity';
  static const String _keyVisGradient = 'visualizer_gradient_enabled';
  static const String _keyVisStartColor = 'visualizer_start_color';
  static const String _keyVisEndColor = 'visualizer_end_color';
  static const String _keyVisGradientStop1 = 'visualizer_gradient_stop_1';
  static const String _keyVisGradientStop2 = 'visualizer_gradient_stop_2';
  static const String _keyVisGradientTileMode = 'visualizer_gradient_tile_mode';

  final SharedPreferences _prefs;
  bool _isImmersiveTabBarEnabled;
  bool _isUserInactive = false;

  // Visualizer styling state
  late Color _visualizerColor;
  late double _visualizerOpacity;
  late bool _isVisualizerGradientEnabled;
  late Color _visualizerStartColor;
  late Color _visualizerEndColor;
  late double _visualizerGradientStop1;
  late double _visualizerGradientStop2;
  late int _visualizerGradientTileMode;

  SettingsService(this._prefs)
    : _isImmersiveTabBarEnabled = _prefs.getBool(_keyImmersiveTabBar) ?? false {
    _visualizerColor = Color(_prefs.getInt(_keyVisColor) ?? Colors.white.value);
    _visualizerOpacity = _prefs.getDouble(_keyVisOpacity) ?? 0.2;
    _isVisualizerGradientEnabled = _prefs.getBool(_keyVisGradient) ?? false;
    _visualizerStartColor = Color(
      _prefs.getInt(_keyVisStartColor) ?? Colors.blue.value,
    );
    _visualizerEndColor = Color(
      _prefs.getInt(_keyVisEndColor) ?? Colors.purple.value,
    );
    _visualizerGradientStop1 = _prefs.getDouble(_keyVisGradientStop1) ?? 0.0;
    _visualizerGradientStop2 = _prefs.getDouble(_keyVisGradientStop2) ?? 1.0;
    _visualizerGradientTileMode =
        _prefs.getInt(_keyVisGradientTileMode) ?? TileMode.clamp.index;
  }

  bool get isImmersiveTabBarEnabled => _isImmersiveTabBarEnabled;
  bool get isUserInactive => _isUserInactive;

  Color get visualizerColor => _visualizerColor;
  double get visualizerOpacity => _visualizerOpacity;
  bool get isVisualizerGradientEnabled => _isVisualizerGradientEnabled;
  Color get visualizerStartColor => _visualizerStartColor;
  Color get visualizerEndColor => _visualizerEndColor;
  double get visualizerGradientStop1 => _visualizerGradientStop1;
  double get visualizerGradientStop2 => _visualizerGradientStop2;
  int get visualizerGradientTileMode => _visualizerGradientTileMode;

  void resetVisualizerAppearance() {
    visualizerOpacity = 0.2;
    visualizerColor = Colors.white;
    isVisualizerGradientEnabled = false;
    visualizerStartColor = Colors.blue;
    visualizerEndColor = Colors.purple;
    visualizerGradientStop1 = 0.0;
    visualizerGradientStop2 = 1.0;
    visualizerGradientTileMode = TileMode.clamp.index;
  }

  set isImmersiveTabBarEnabled(bool value) {
    _isImmersiveTabBarEnabled = value;
    _prefs.setBool(_keyImmersiveTabBar, value);
    notifyListeners();
  }

  set isUserInactive(bool value) {
    if (_isUserInactive != value) {
      _isUserInactive = value;
      notifyListeners();
    }
  }

  set visualizerColor(Color value) {
    _visualizerColor = value;
    _prefs.setInt(_keyVisColor, value.value);
    notifyListeners();
  }

  set visualizerOpacity(double value) {
    _visualizerOpacity = value;
    _prefs.setDouble(_keyVisOpacity, value);
    notifyListeners();
  }

  set isVisualizerGradientEnabled(bool value) {
    _isVisualizerGradientEnabled = value;
    _prefs.setBool(_keyVisGradient, value);
    notifyListeners();
  }

  set visualizerStartColor(Color value) {
    _visualizerStartColor = value;
    _prefs.setInt(_keyVisStartColor, value.value);
    notifyListeners();
  }

  set visualizerEndColor(Color value) {
    _visualizerEndColor = value;
    _prefs.setInt(_keyVisEndColor, value.value);
    notifyListeners();
  }

  set visualizerGradientStop1(double value) {
    _visualizerGradientStop1 = value;
    _prefs.setDouble(_keyVisGradientStop1, value);
    notifyListeners();
  }

  set visualizerGradientStop2(double value) {
    _visualizerGradientStop2 = value;
    _prefs.setDouble(_keyVisGradientStop2, value);
    notifyListeners();
  }

  set visualizerGradientTileMode(int value) {
    _visualizerGradientTileMode = value;
    _prefs.setInt(_keyVisGradientTileMode, value);
    notifyListeners();
  }

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }
}
