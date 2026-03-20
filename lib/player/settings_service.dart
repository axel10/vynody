import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const String _keyImmersiveTabBar = 'immersive_tab_bar_enabled';
  static const String _keySampleStride = 'sample_stride';
  static const String _keyWaveformChunks = 'waveform_chunks';

  // Visualizer styling keys
  static const String _keyVisColor = 'visualizer_color';
  static const String _keyVisOpacity = 'visualizer_opacity';
  static const String _keyVisGradient = 'visualizer_gradient_enabled';
  static const String _keyVisStartColor = 'visualizer_start_color';
  static const String _keyVisEndColor = 'visualizer_end_color';
  static const String _keyVisGradientStop1 = 'visualizer_gradient_stop_1';
  static const String _keyVisGradientStop2 = 'visualizer_gradient_stop_2';
  static const String _keyVisGradientTileMode = 'visualizer_gradient_tile_mode';
  static const String _keyVisualizerDynamicColor = 'visualizer_dynamic_color';
  static const String _keyVisualizerDynamicStartColor =
      'visualizer_dynamic_start_color';
  static const String _keyVisualizerDynamicEndColor =
      'visualizer_dynamic_end_color';
  static const String _keyPlaybackBackgroundType = 'playback_background_type';
  static const String _keyIsAutoMode = 'visualizer_auto_mode';
  static const String _keyAutoSpectrumQuantity =
      'visualizer_auto_spectrum_quantity';
  static const String _keyAutoSpeed = 'visualizer_auto_speed';
  static const String _keyPortraitFrequencyGroups =
      'visualizer_portrait_frequency_groups';
  static const String _keyLandscapeFrequencyGroups =
      'visualizer_landscape_frequency_groups';
  static const String _keyPortraitGap = 'visualizer_portrait_gap';
  static const String _keyLandscapeGap = 'visualizer_landscape_gap';
  static const String _keyIsWaveformProgressBarEnabled = 'waveform_progress_bar_enabled';

  final SharedPreferences _prefs;
  bool _isImmersiveTabBarEnabled;
  int _sampleStride;
  int _waveformChunks;
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
  late bool _isVisualizerDynamicColor;
  late bool _isVisualizerDynamicStartColor;
  late bool _isVisualizerDynamicEndColor;
  late int _playbackBackgroundType;
  late bool _isAutoMode;
  late String _autoSpectrumQuantity;
  late String _autoSpeed;
  late int _portraitFrequencyGroups;
  late int _landscapeFrequencyGroups;
  late double _portraitGap;
  late double _landscapeGap;
  late bool _isWaveformProgressBarEnabled;

  SettingsService(this._prefs)
    : _isImmersiveTabBarEnabled = _prefs.getBool(_keyImmersiveTabBar) ?? false,
      _sampleStride = _prefs.getInt(_keySampleStride) ?? 4,
      _waveformChunks = _prefs.getInt(_keyWaveformChunks) ?? 80 {
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
    _isVisualizerDynamicColor =
        _prefs.getBool(_keyVisualizerDynamicColor) ?? false;
    _isVisualizerDynamicStartColor =
        _prefs.getBool(_keyVisualizerDynamicStartColor) ?? false;
    _isVisualizerDynamicEndColor =
        _prefs.getBool(_keyVisualizerDynamicEndColor) ?? false;
    _playbackBackgroundType = _prefs.getInt(_keyPlaybackBackgroundType) ?? 0;
    _isAutoMode = _prefs.getBool(_keyIsAutoMode) ?? true;
    _autoSpectrumQuantity =
        _prefs.getString(_keyAutoSpectrumQuantity) ?? 'high';
    _autoSpeed = _prefs.getString(_keyAutoSpeed) ?? 'medium';
    _portraitFrequencyGroups = _prefs.getInt(_keyPortraitFrequencyGroups) ?? 100;
    _landscapeFrequencyGroups =
        _prefs.getInt(_keyLandscapeFrequencyGroups) ?? 172;
    _portraitGap = _prefs.getDouble(_keyPortraitGap) ?? 1.0;
    _landscapeGap = _prefs.getDouble(_keyLandscapeGap) ?? 2.0;
    _isWaveformProgressBarEnabled = _prefs.getBool(_keyIsWaveformProgressBarEnabled) ?? false;
  }

  bool get isImmersiveTabBarEnabled => _isImmersiveTabBarEnabled;
  int get sampleStride => _sampleStride;
  int get waveformChunks => _waveformChunks;
  bool get isUserInactive => _isUserInactive;

  Color get visualizerColor => _visualizerColor;
  double get visualizerOpacity => _visualizerOpacity;
  bool get isVisualizerGradientEnabled => _isVisualizerGradientEnabled;
  Color get visualizerStartColor => _visualizerStartColor;
  Color get visualizerEndColor => _visualizerEndColor;
  double get visualizerGradientStop1 => _visualizerGradientStop1;
  double get visualizerGradientStop2 => _visualizerGradientStop2;
  int get visualizerGradientTileMode => _visualizerGradientTileMode;
  bool get isVisualizerDynamicColor => _isVisualizerDynamicColor;
  bool get isVisualizerDynamicStartColor => _isVisualizerDynamicStartColor;
  bool get isVisualizerDynamicEndColor => _isVisualizerDynamicEndColor;
  int get playbackBackgroundType => _playbackBackgroundType;
  bool get isAutoMode => _isAutoMode;
  String get autoSpectrumQuantity => _autoSpectrumQuantity;
  String get autoSpeed => _autoSpeed;
  int get portraitFrequencyGroups => _portraitFrequencyGroups;
  int get landscapeFrequencyGroups => _landscapeFrequencyGroups;
  double get portraitGap => _portraitGap;
  double get landscapeGap => _landscapeGap;
  bool get isWaveformProgressBarEnabled => _isWaveformProgressBarEnabled;

  void resetVisualizerAppearance() {
    visualizerOpacity = 0.2;
    visualizerColor = Colors.white;
    isVisualizerGradientEnabled = false;
    visualizerStartColor = Colors.blue;
    visualizerEndColor = Colors.purple;
    visualizerGradientStop1 = 0.0;
    visualizerGradientStop2 = 1.0;
    visualizerGradientTileMode = TileMode.clamp.index;
    isVisualizerDynamicColor = false;
    isVisualizerDynamicStartColor = false;
    isVisualizerDynamicEndColor = false;
    isAutoMode = true;
    autoSpectrumQuantity = 'high';
    autoSpeed = 'medium';
    portraitFrequencyGroups = 100;
    landscapeFrequencyGroups = 172;
    portraitGap = 1.0;
    landscapeGap = 2.0;
    isWaveformProgressBarEnabled = false;
  }

  set isImmersiveTabBarEnabled(bool value) {
    _isImmersiveTabBarEnabled = value;
    _prefs.setBool(_keyImmersiveTabBar, value);
    notifyListeners();
  }

  set sampleStride(int value) {
    _sampleStride = value;
    _prefs.setInt(_keySampleStride, value);
    notifyListeners();
  }

  set waveformChunks(int value) {
    _waveformChunks = value;
    _prefs.setInt(_keyWaveformChunks, value);
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

  set isVisualizerDynamicColor(bool value) {
    _isVisualizerDynamicColor = value;
    _prefs.setBool(_keyVisualizerDynamicColor, value);
    notifyListeners();
  }

  set isVisualizerDynamicStartColor(bool value) {
    _isVisualizerDynamicStartColor = value;
    _prefs.setBool(_keyVisualizerDynamicStartColor, value);
    notifyListeners();
  }

  set isVisualizerDynamicEndColor(bool value) {
    _isVisualizerDynamicEndColor = value;
    _prefs.setBool(_keyVisualizerDynamicEndColor, value);
    notifyListeners();
  }

  set playbackBackgroundType(int value) {
    _playbackBackgroundType = value;
    _prefs.setInt(_keyPlaybackBackgroundType, value);
    notifyListeners();
  }

  set isAutoMode(bool value) {
    _isAutoMode = value;
    _prefs.setBool(_keyIsAutoMode, value);
    notifyListeners();
  }

  set autoSpectrumQuantity(String value) {
    _autoSpectrumQuantity = value;
    _prefs.setString(_keyAutoSpectrumQuantity, value);
    notifyListeners();
  }

  set autoSpeed(String value) {
    _autoSpeed = value;
    _prefs.setString(_keyAutoSpeed, value);
    notifyListeners();
  }

  set portraitFrequencyGroups(int value) {
    _portraitFrequencyGroups = value;
    _prefs.setInt(_keyPortraitFrequencyGroups, value);
    notifyListeners();
  }

  set landscapeFrequencyGroups(int value) {
    _landscapeFrequencyGroups = value;
    _prefs.setInt(_keyLandscapeFrequencyGroups, value);
    notifyListeners();
  }

  set portraitGap(double value) {
    _portraitGap = value;
    _prefs.setDouble(_keyPortraitGap, value);
    notifyListeners();
  }

  set landscapeGap(double value) {
    _landscapeGap = value;
    _prefs.setDouble(_keyLandscapeGap, value);
    notifyListeners();
  }

  set isWaveformProgressBarEnabled(bool value) {
    _isWaveformProgressBarEnabled = value;
    _prefs.setBool(_keyIsWaveformProgressBarEnabled, value);
    notifyListeners();
  }

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }
}
