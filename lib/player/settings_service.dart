import 'dart:async';
import 'dart:convert';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shortcut_bindings.dart';
import '../transcode/transcode_models.dart';

enum LyricsAiProvider { googleAiStudio, openRouter }

extension ThemeModeX on ThemeMode {
  String get storageValue => switch (this) {
    ThemeMode.system => 'system',
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
  };

  static ThemeMode fromStorageValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}

extension LyricsAiProviderX on LyricsAiProvider {
  bool get _isZhLocale =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh';

  String get storageValue => switch (this) {
    LyricsAiProvider.googleAiStudio => 'google_ai_studio',
    LyricsAiProvider.openRouter => 'openrouter',
  };

  String get displayName => switch (this) {
    LyricsAiProvider.googleAiStudio =>
      _isZhLocale ? 'Google AI Studio' : 'Google AI Studio',
    LyricsAiProvider.openRouter => _isZhLocale ? 'OpenRouter' : 'OpenRouter',
  };

  static LyricsAiProvider fromStorageValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'openrouter':
        return LyricsAiProvider.openRouter;
      case 'google_ai_studio':
      case 'google':
      case 'gemini':
      default:
        return LyricsAiProvider.googleAiStudio;
    }
  }
}

class SettingsService extends ChangeNotifier {
  static const String defaultGeminiPrimaryModelId =
      'gemini-3.1-flash-lite-preview';
  static const String defaultGeminiFallbackModelId = 'gemini-2.5-flash';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyImmersiveTabBar = 'immersive_tab_bar_enabled';
  static const String _keySampleStride = 'sample_stride';
  static const String _keyWaveformChunks = 'waveform_chunks';
  static const String geminiApiKeyStorageKey = 'gemini_api_key';
  static const String openRouterApiKeyStorageKey = 'openrouter_api_key';
  static const String _keyLyricsAiProvider = 'lyrics_ai_provider';
  static const String _keyLyricsAiAutoSwitchEnabled =
      'lyrics_ai_auto_switch_enabled';
  static const String _keyGeminiPrimaryModelId = 'gemini_primary_model_id';
  static const String _keyGeminiFallbackModelId = 'gemini_fallback_model_id';
  static const String acoustidApiKeyStorageKey = 'acoustid_api_key';
  static const String _keyShortcutBindings = 'shortcut_bindings';
  static const String _builtInAcoustidApiKey = 'raGXgwxqws';
  static const int _fixedSampleStride = 8;

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
  static const String _keyPlaybackMeshBackgroundSpeed =
      'playback_mesh_background_speed';
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
  static const String _keyIsWaveformProgressBarEnabled =
      'waveform_progress_bar_enabled';
  static const String skipShortAudioScanEnabledStorageKey =
      'scan_skip_short_audio_enabled';
  static const String skipShortAudioScanMinimumDurationSecondsStorageKey =
      'scan_skip_short_audio_min_duration_seconds';
  static const int defaultSkipShortAudioScanMinimumDurationSeconds = 30;
  static const String _keyRandomRange = 'random_range';
  static const String _keyRandomMethod = 'random_method';
  static const String _keyTranscodeDefaultFormat =
      'transcode_default_output_format';
  static const String _keyTranscodeDefaultQualityTier =
      'transcode_default_quality_tier';
  static const String _keyTranscodeFfmpegPath = 'transcode_ffmpeg_path';
  static const String _keyTranscodeAutoScanOutputEnabled =
      'transcode_auto_scan_output_enabled';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  bool _isImmersiveTabBarEnabled;
  int _waveformChunks;
  bool _isUserInactive = false;
  Timer? _inactivityTimer;
  LyricsAiProvider _lyricsAiProvider;
  bool _isLyricsAiAutoSwitchEnabled;
  String _geminiPrimaryModelId;
  String _geminiFallbackModelId;
  Map<String, ShortcutBinding> _shortcutBindings;

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
  late double _playbackMeshBackgroundSpeed;
  late bool _isAutoMode;
  late String _autoSpectrumQuantity;
  late String _autoSpeed;
  late int _portraitFrequencyGroups;
  late int _landscapeFrequencyGroups;
  late double _portraitGap;
  late double _landscapeGap;
  late bool _isWaveformProgressBarEnabled;
  late bool _skipShortAudioScanEnabled;
  late int _skipShortAudioScanMinimumDurationSeconds;
  late int _randomRange; // 0: current, 1: global
  late int _randomMethod; // 0: complete, 1: shuffle
  late AudioFormat _transcodeDefaultFormat;
  late TranscodeQualityTier _transcodeDefaultQualityTier;
  late String _transcodeFfmpegPath;
  late bool _transcodeAutoScanOutputEnabled;

  static String _initialModelId(String? value, String defaultValue) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return defaultValue;
    }
    return normalized;
  }

  SettingsService(this._prefs)
    : _themeMode = ThemeModeX.fromStorageValue(_prefs.getString(_keyThemeMode)),
      _isImmersiveTabBarEnabled = _prefs.getBool(_keyImmersiveTabBar) ?? false,
      _waveformChunks = _prefs.getInt(_keyWaveformChunks) ?? 80,
      _lyricsAiProvider = LyricsAiProviderX.fromStorageValue(
        _prefs.getString(_keyLyricsAiProvider),
      ),
      _isLyricsAiAutoSwitchEnabled =
          _prefs.getBool(_keyLyricsAiAutoSwitchEnabled) ?? false,
      _geminiPrimaryModelId = _initialModelId(
        _prefs.getString(_keyGeminiPrimaryModelId),
        defaultGeminiPrimaryModelId,
      ),
      _geminiFallbackModelId = _initialModelId(
        _prefs.getString(_keyGeminiFallbackModelId),
        defaultGeminiFallbackModelId,
      ),
      _shortcutBindings = _loadShortcutBindings(_prefs) {
    _visualizerColor = Color(
      _prefs.getInt(_keyVisColor) ?? Colors.white.toARGB32(),
    );
    _visualizerOpacity = _prefs.getDouble(_keyVisOpacity) ?? 0.2;
    _isVisualizerGradientEnabled = _prefs.getBool(_keyVisGradient) ?? false;
    _visualizerStartColor = Color(
      _prefs.getInt(_keyVisStartColor) ?? Colors.blue.toARGB32(),
    );
    _visualizerEndColor = Color(
      _prefs.getInt(_keyVisEndColor) ?? Colors.purple.toARGB32(),
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
    _playbackMeshBackgroundSpeed =
        _prefs.getDouble(_keyPlaybackMeshBackgroundSpeed) ?? 0.05;
    _isAutoMode = _prefs.getBool(_keyIsAutoMode) ?? true;
    _autoSpectrumQuantity =
        _prefs.getString(_keyAutoSpectrumQuantity) ?? 'high';
    _autoSpeed = _prefs.getString(_keyAutoSpeed) ?? 'medium';
    _portraitFrequencyGroups =
        _prefs.getInt(_keyPortraitFrequencyGroups) ?? 100;
    _landscapeFrequencyGroups =
        _prefs.getInt(_keyLandscapeFrequencyGroups) ?? 172;
    _portraitGap = _prefs.getDouble(_keyPortraitGap) ?? 1.0;
    _landscapeGap = _prefs.getDouble(_keyLandscapeGap) ?? 2.0;
    _isWaveformProgressBarEnabled =
        _prefs.getBool(_keyIsWaveformProgressBarEnabled) ?? false;
    _skipShortAudioScanEnabled =
        _prefs.getBool(skipShortAudioScanEnabledStorageKey) ?? false;
    _skipShortAudioScanMinimumDurationSeconds =
        _prefs.getInt(skipShortAudioScanMinimumDurationSecondsStorageKey) ??
        defaultSkipShortAudioScanMinimumDurationSeconds;
    _randomRange = _prefs.getInt(_keyRandomRange) ?? 0;
    _randomMethod = _prefs.getInt(_keyRandomMethod) ?? 1; // Default to shuffle
    _transcodeDefaultFormat = _audioFormatFromStorageValue(
      _prefs.getString(_keyTranscodeDefaultFormat),
    );
    _transcodeDefaultQualityTier = TranscodeQualityTierX.fromStorageValue(
      _prefs.getString(_keyTranscodeDefaultQualityTier),
    );
    _transcodeFfmpegPath = _prefs.getString(_keyTranscodeFfmpegPath) ?? '';
    _transcodeAutoScanOutputEnabled =
        _prefs.getBool(_keyTranscodeAutoScanOutputEnabled) ?? true;
  }

  ThemeMode get themeMode => _themeMode;
  bool get isImmersiveTabBarEnabled => _isImmersiveTabBarEnabled;
  int get sampleStride => _fixedSampleStride;
  int get waveformChunks => _waveformChunks;
  bool get isUserInactive => _isUserInactive;
  LyricsAiProvider get lyricsAiProvider => _lyricsAiProvider;
  bool get isLyricsAiAutoSwitchEnabled => _isLyricsAiAutoSwitchEnabled;
  String get geminiPrimaryModelId => _geminiPrimaryModelId;
  String get geminiFallbackModelId => _geminiFallbackModelId;
  String get geminiApiKey => _prefs.getString(geminiApiKeyStorageKey) ?? '';
  String get openRouterApiKey =>
      _prefs.getString(openRouterApiKeyStorageKey) ?? '';
  bool get hasCustomGoogleAiStudioApiKey =>
      _prefs.containsKey(geminiApiKeyStorageKey);
  bool get hasCustomOpenRouterApiKey =>
      _prefs.containsKey(openRouterApiKeyStorageKey);
  bool get hasBothLyricsGenerationApiKeys =>
      geminiApiKey.trim().isNotEmpty && openRouterApiKey.trim().isNotEmpty;
  bool get canAutoSwitchLyricsProvider => hasBothLyricsGenerationApiKeys;
  bool get shouldAutoSwitchLyricsProvider =>
      _isLyricsAiAutoSwitchEnabled && hasBothLyricsGenerationApiKeys;
  String get activeLyricsGenerationApiKey {
    return switch (_lyricsAiProvider) {
      LyricsAiProvider.googleAiStudio => geminiApiKey,
      LyricsAiProvider.openRouter => openRouterApiKey,
    };
  }

  String get activeLyricsApiKey => activeLyricsGenerationApiKey;

  bool get hasActiveLyricsGenerationApiKey =>
      activeLyricsGenerationApiKey.trim().isNotEmpty;
  bool get hasActiveLyricsApiKey => hasActiveLyricsGenerationApiKey;
  String get activeGeminiTranslationApiKey => geminiApiKey;
  bool get hasGeminiTranslationApiKey => geminiApiKey.trim().isNotEmpty;
  bool get hasCustomAcoustidApiKey =>
      _prefs.containsKey(acoustidApiKeyStorageKey);
  ShortcutBinding shortcutBinding(AppShortcutAction action) {
    return _shortcutBindings[action.storageKey] ?? action.defaultBinding;
  }

  Map<AppShortcutAction, ShortcutBinding> get shortcutBindings {
    return {
      for (final action in AppShortcutAction.values)
        action: shortcutBinding(action),
    };
  }

  static String geminiModelDisplayName(String modelId) {
    final isZh =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh';
    switch (modelId.trim()) {
      case defaultGeminiPrimaryModelId:
        return 'Gemini 3.1 Flash Lite Preview';
      case defaultGeminiFallbackModelId:
        return 'Gemini 2.5 Flash';
      default:
        return modelId.trim().isEmpty
            ? (isZh ? '未选择模型' : 'No model selected')
            : modelId.trim();
    }
  }

  static String geminiModelSelectionLabel({
    required String primaryModelId,
    required String fallbackModelId,
  }) {
    final primaryLabel = geminiModelDisplayName(primaryModelId);
    final fallbackLabel = geminiModelDisplayName(fallbackModelId);
    if (primaryLabel == fallbackLabel) {
      return primaryLabel;
    }
    return '$primaryLabel / $fallbackLabel';
  }

  String get acoustidApiKey {
    final stored = _prefs.getString(acoustidApiKeyStorageKey)?.trim();
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    return _builtInAcoustidApiKey;
  }

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
  double get playbackMeshBackgroundSpeed => _playbackMeshBackgroundSpeed;
  bool get isAutoMode => _isAutoMode;
  String get autoSpectrumQuantity => _autoSpectrumQuantity;
  String get autoSpeed => _autoSpeed;
  int get portraitFrequencyGroups => _portraitFrequencyGroups;
  int get landscapeFrequencyGroups => _landscapeFrequencyGroups;
  double get portraitGap => _portraitGap;
  double get landscapeGap => _landscapeGap;
  bool get isWaveformProgressBarEnabled => _isWaveformProgressBarEnabled;
  bool get skipShortAudioScanEnabled => _skipShortAudioScanEnabled;
  int get skipShortAudioScanMinimumDurationSeconds =>
      _skipShortAudioScanMinimumDurationSeconds;
  int get randomRange => _randomRange;
  int get randomMethod => _randomMethod;
  AudioFormat get transcodeDefaultFormat => _transcodeDefaultFormat;
  TranscodeQualityTier get transcodeDefaultQualityTier =>
      _transcodeDefaultQualityTier;
  String get transcodeFfmpegPath => _transcodeFfmpegPath;
  bool get transcodeAutoScanOutputEnabled => _transcodeAutoScanOutputEnabled;

  static AudioFormat _audioFormatFromStorageValue(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return AudioFormat.m4a;
    }
    try {
      return audioFormatFromValue(normalized);
    } catch (_) {
      return AudioFormat.m4a;
    }
  }

  static Map<String, ShortcutBinding> _loadShortcutBindings(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_keyShortcutBindings);
    if (raw == null || raw.trim().isEmpty) {
      return <String, ShortcutBinding>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, ShortcutBinding>{};
      }

      final result = <String, ShortcutBinding>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) {
          continue;
        }
        final binding = ShortcutBinding.fromJson(entry.value);
        if (binding == null) {
          continue;
        }
        result[entry.key as String] = binding;
      }
      return result;
    } catch (_) {
      return <String, ShortcutBinding>{};
    }
  }

  Future<void> _saveShortcutBindings() async {
    if (_shortcutBindings.isEmpty) {
      await _prefs.remove(_keyShortcutBindings);
      return;
    }

    final encoded = jsonEncode({
      for (final entry in _shortcutBindings.entries)
        entry.key: entry.value.toJson(),
    });
    await _prefs.setString(_keyShortcutBindings, encoded);
  }

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
    playbackMeshBackgroundSpeed = 0.05;
    isAutoMode = true;
    autoSpectrumQuantity = 'high';
    autoSpeed = 'medium';
    portraitFrequencyGroups = 100;
    landscapeFrequencyGroups = 172;
    portraitGap = 1.0;
    landscapeGap = 2.0;
    isWaveformProgressBarEnabled = false;
    randomRange = 0;
    randomMethod = 1;
  }

  set isImmersiveTabBarEnabled(bool value) {
    _isImmersiveTabBarEnabled = value;
    _prefs.setBool(_keyImmersiveTabBar, value);
    notifyListeners();
  }

  set themeMode(ThemeMode value) {
    if (_themeMode == value) {
      return;
    }
    _themeMode = value;
    _prefs.setString(_keyThemeMode, value.storageValue);
    notifyListeners();
  }

  set sampleStride(int value) {
    _prefs.setInt(_keySampleStride, _fixedSampleStride);
    notifyListeners();
  }

  set waveformChunks(int value) {
    if (_waveformChunks == value) {
      return;
    }
    _waveformChunks = value;
    _prefs.setInt(_keyWaveformChunks, value);
    notifyListeners();
  }

  set geminiApiKey(String value) {
    final normalized = value.trim();
    final current = geminiApiKey;
    if (current == normalized) {
      return;
    }

    if (normalized.isEmpty) {
      _prefs.remove(geminiApiKeyStorageKey);
    } else {
      _prefs.setString(geminiApiKeyStorageKey, normalized);
    }
    notifyListeners();
  }

  set openRouterApiKey(String value) {
    final normalized = value.trim();
    final current = openRouterApiKey;
    if (current == normalized) {
      return;
    }

    if (normalized.isEmpty) {
      _prefs.remove(openRouterApiKeyStorageKey);
    } else {
      _prefs.setString(openRouterApiKeyStorageKey, normalized);
    }
    notifyListeners();
  }

  set lyricsAiProvider(LyricsAiProvider value) {
    if (_lyricsAiProvider == value) {
      return;
    }
    _lyricsAiProvider = value;
    _prefs.setString(_keyLyricsAiProvider, value.storageValue);
    notifyListeners();
  }

  set isLyricsAiAutoSwitchEnabled(bool value) {
    if (_isLyricsAiAutoSwitchEnabled == value) {
      return;
    }
    _isLyricsAiAutoSwitchEnabled = value;
    _prefs.setBool(_keyLyricsAiAutoSwitchEnabled, value);
    notifyListeners();
  }

  set geminiPrimaryModelId(String value) {
    final normalized = value.trim();
    final current = geminiPrimaryModelId;
    if (current == normalized || normalized.isEmpty) {
      if (normalized.isEmpty && current.isNotEmpty) {
        return;
      }
      return;
    }

    _geminiPrimaryModelId = normalized;
    _prefs.setString(_keyGeminiPrimaryModelId, normalized);
    notifyListeners();
  }

  set geminiFallbackModelId(String value) {
    final normalized = value.trim();
    final current = geminiFallbackModelId;
    if (current == normalized || normalized.isEmpty) {
      if (normalized.isEmpty && current.isNotEmpty) {
        return;
      }
      return;
    }

    _geminiFallbackModelId = normalized;
    _prefs.setString(_keyGeminiFallbackModelId, normalized);
    notifyListeners();
  }

  void resetGeminiModels() {
    geminiPrimaryModelId = defaultGeminiPrimaryModelId;
    geminiFallbackModelId = defaultGeminiFallbackModelId;
  }

  void setShortcutBinding(AppShortcutAction action, ShortcutBinding binding) {
    _shortcutBindings[action.storageKey] = binding;
    unawaited(_saveShortcutBindings());
    notifyListeners();
  }

  void setShortcutBindings(Map<AppShortcutAction, ShortcutBinding> bindings) {
    _shortcutBindings = {
      for (final entry in bindings.entries) entry.key.storageKey: entry.value,
    };
    unawaited(_saveShortcutBindings());
    notifyListeners();
  }

  void resetShortcutBindings() {
    _shortcutBindings = <String, ShortcutBinding>{};
    unawaited(_saveShortcutBindings());
    notifyListeners();
  }

  set acoustidApiKey(String value) {
    final normalized = value.trim();
    final current = acoustidApiKey;
    if (current == normalized) {
      return;
    }

    if (normalized.isEmpty) {
      _prefs.remove(acoustidApiKeyStorageKey);
    } else {
      _prefs.setString(acoustidApiKeyStorageKey, normalized);
    }
    notifyListeners();
  }

  set isUserInactive(bool value) {
    if (_isUserInactive != value) {
      _isUserInactive = value;
      notifyListeners();
    }
    if (!value) {
      // If we are setting it to active (not inactive), reset the timer
      startInactivityTimer();
    }
  }

  void startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: 3), () {
      if (!_isUserInactive) {
        _isUserInactive = true;
        notifyListeners();
      }
    });
  }

  void resetInactivity() {
    if (_isUserInactive) {
      _isUserInactive = false;
      notifyListeners();
    }
    startInactivityTimer();
  }

  set visualizerColor(Color value) {
    _visualizerColor = value;
    _prefs.setInt(_keyVisColor, value.toARGB32());
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
    _prefs.setInt(_keyVisStartColor, value.toARGB32());
    notifyListeners();
  }

  set visualizerEndColor(Color value) {
    _visualizerEndColor = value;
    _prefs.setInt(_keyVisEndColor, value.toARGB32());
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

  set playbackMeshBackgroundSpeed(double value) {
    if (_playbackMeshBackgroundSpeed == value) {
      return;
    }
    _playbackMeshBackgroundSpeed = value;
    _prefs.setDouble(_keyPlaybackMeshBackgroundSpeed, value);
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

  set skipShortAudioScanEnabled(bool value) {
    if (_skipShortAudioScanEnabled == value) {
      return;
    }
    _skipShortAudioScanEnabled = value;
    _prefs.setBool(skipShortAudioScanEnabledStorageKey, value);
    notifyListeners();
  }

  set skipShortAudioScanMinimumDurationSeconds(int value) {
    final normalized = value.clamp(1, 3600).toInt();
    if (_skipShortAudioScanMinimumDurationSeconds == normalized) {
      return;
    }
    _skipShortAudioScanMinimumDurationSeconds = normalized;
    _prefs.setInt(
      skipShortAudioScanMinimumDurationSecondsStorageKey,
      normalized,
    );
    notifyListeners();
  }

  set randomRange(int value) {
    _randomRange = value;
    _prefs.setInt(_keyRandomRange, value);
    notifyListeners();
  }

  set randomMethod(int value) {
    _randomMethod = value;
    _prefs.setInt(_keyRandomMethod, value);
    notifyListeners();
  }

  set transcodeDefaultFormat(AudioFormat value) {
    if (_transcodeDefaultFormat == value) {
      return;
    }
    _transcodeDefaultFormat = value;
    _prefs.setString(_keyTranscodeDefaultFormat, value.value);
    notifyListeners();
  }

  set transcodeDefaultQualityTier(TranscodeQualityTier value) {
    if (_transcodeDefaultQualityTier == value) {
      return;
    }
    _transcodeDefaultQualityTier = value;
    _prefs.setString(_keyTranscodeDefaultQualityTier, value.storageValue);
    notifyListeners();
  }

  set transcodeFfmpegPath(String value) {
    final normalized = value.trim();
    if (_transcodeFfmpegPath == normalized) {
      return;
    }
    _transcodeFfmpegPath = normalized;
    if (normalized.isEmpty) {
      _prefs.remove(_keyTranscodeFfmpegPath);
    } else {
      _prefs.setString(_keyTranscodeFfmpegPath, normalized);
    }
    notifyListeners();
  }

  set transcodeAutoScanOutputEnabled(bool value) {
    if (_transcodeAutoScanOutputEnabled == value) {
      return;
    }
    _transcodeAutoScanOutputEnabled = value;
    _prefs.setBool(_keyTranscodeAutoScanOutputEnabled, value);
    notifyListeners();
  }

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }
}
