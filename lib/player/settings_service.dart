import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const String _keyImmersiveTabBar = 'immersive_tab_bar_enabled';

  final SharedPreferences _prefs;
  bool _isImmersiveTabBarEnabled;
  bool _isUserInactive = false;

  SettingsService(this._prefs)
    : _isImmersiveTabBarEnabled = _prefs.getBool(_keyImmersiveTabBar) ?? false;

  bool get isImmersiveTabBarEnabled => _isImmersiveTabBarEnabled;
  bool get isUserInactive => _isUserInactive;

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

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }
}
