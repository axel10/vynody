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
  static const String _keyVisGradientDirection =
      'visualizer_gradient_direction'; // 0: LTR, 1: TTB

  final SharedPreferences _prefs;
  bool _isImmersiveTabBarEnabled;
  bool _isUserInactive = false;

  // Visualizer styling state
  late Color _visualizerColor;
  late double _visualizerOpacity;
  late bool _isVisualizerGradientEnabled;
  late Color _visualizerStartColor;
  late Color _visualizerEndColor;
  late int _visualizerGradientDirection;

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
    _visualizerGradientDirection = _prefs.getInt(_keyVisGradientDirection) ?? 0;
  }

  bool get isImmersiveTabBarEnabled => _isImmersiveTabBarEnabled;
  bool get isUserInactive => _isUserInactive;

  Color get visualizerColor => _visualizerColor;
  double get visualizerOpacity => _visualizerOpacity;
  bool get isVisualizerGradientEnabled => _isVisualizerGradientEnabled;
  Color get visualizerStartColor => _visualizerStartColor;
  Color get visualizerEndColor => _visualizerEndColor;
  int get visualizerGradientDirection => _visualizerGradientDirection;

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

  set visualizerGradientDirection(int value) {
    _visualizerGradientDirection = value;
    _prefs.setInt(_keyVisGradientDirection, value);
    notifyListeners();
  }

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }
}
