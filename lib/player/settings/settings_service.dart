import 'dart:async';
import 'dart:convert';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vibe_flow/player/settings/shortcut_bindings.dart';
import 'package:vibe_flow/transcode/transcode_models.dart';

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

class SettingProperty<T> {
  final String key;
  final T defaultValue;
  final SharedPreferences prefs;
  final VoidCallback? onChanged;
  final T Function(SharedPreferences prefs, String key, T defaultValue)? customRead;
  final void Function(SharedPreferences prefs, String key, T value)? customWrite;

  T _value;

  SettingProperty({
    required this.key,
    required this.defaultValue,
    required this.prefs,
    this.onChanged,
    this.customRead,
    this.customWrite,
  }) : _value = _read(prefs, key, defaultValue, customRead);

  T get value => _value;

  set value(T newValue) {
    if (_value == newValue) return;
    _value = newValue;
    _write(prefs, key, newValue, customWrite);
    onChanged?.call();
  }

  static T _read<T>(
    SharedPreferences prefs,
    String key,
    T defaultValue,
    T Function(SharedPreferences prefs, String key, T defaultValue)? customRead,
  ) {
    if (customRead != null) {
      return customRead(prefs, key, defaultValue);
    }
    if (T == bool) {
      return (prefs.getBool(key) ?? defaultValue) as T;
    }
    if (T == int) {
      return (prefs.getInt(key) ?? defaultValue) as T;
    }
    if (T == double) {
      return (prefs.getDouble(key) ?? defaultValue) as T;
    }
    if (T == String) {
      return (prefs.getString(key) ?? defaultValue) as T;
    }
    return defaultValue;
  }

  static void _write<T>(
    SharedPreferences prefs,
    String key,
    T value,
    void Function(SharedPreferences prefs, String key, T value)? customWrite,
  ) {
    if (customWrite != null) {
      customWrite(prefs, key, value);
      return;
    }
    if (value is bool) {
      prefs.setBool(key, value);
    } else if (value is int) {
      prefs.setInt(key, value);
    } else if (value is double) {
      prefs.setDouble(key, value);
    } else if (value is String) {
      prefs.setString(key, value);
    }
  }

  void reset() {
    value = defaultValue;
  }
}

class SettingsService extends ChangeNotifier {
  static const String defaultGeminiPrimaryModelId =
      'gemini-flash-lite-latest';
  static const String defaultGeminiFallbackModelId = 'gemini-2.5-flash';
  static const String defaultGeminiTranslationModelId = 'gemma-4-31b-it';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyImmersiveTabBar = 'immersive_tab_bar_enabled';
  static const String _keySampleStride = 'sample_stride';
  static const String _keyWaveformChunks = 'waveform_chunks';
  static const String geminiApiKeyStorageKey = 'gemini_api_key';
  static const String openRouterApiKeyStorageKey = 'openrouter_api_key';
  static const String _keyLyricsAiProvider = 'lyrics_ai_provider';
  static const String _keyLyricsAiAutoSwitchEnabled =
      'lyrics_ai_auto_switch_enabled';
  static const String _keyLyricsFontScale = 'lyrics_font_scale';
  static const String _keyGeminiPrimaryModelId = 'gemini_primary_model_id';
  static const String _keyGeminiFallbackModelId = 'gemini_fallback_model_id';
  static const String _keyGeminiTranslationModelId =
      'gemini_translation_model_id';
  static const String acoustidApiKeyStorageKey = 'acoustid_api_key';
  static const String _keyShortcutBindings = 'shortcut_bindings';
  static const String _builtInAcoustidApiKey = 'raGXgwxqws';
  static const int defaultSampleStride = 1;
  static const double defaultLyricsFontScale = 1.0;
  static const double minLyricsFontScale = 0.8;
  static const double maxLyricsFontScale = 1.5;
  static const double lyricsFontScaleStep = 0.1;

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
  static const String _keyPlaybackRadialGradientEnabled = 'playback_radial_gradient_enabled';
  static const String _keyPlaybackBackgroundColor = 'playback_background_color';
  static const String _keyPlaybackBackgroundCustomImagePath = 'playback_background_custom_image_path';
  static const String _keyPlaybackBackgroundNormalOpacity = 'playback_background_normal_opacity';
  static const String _keyPlaybackBackgroundLyricsOpacity = 'playback_background_lyrics_opacity';
  static const String _keyPlaybackBlurredArtworkBlurSigma = 'playback_blurred_artwork_blur_sigma';
  static const String _keyPlaybackCustomImageBlurSigma = 'playback_custom_image_blur_sigma';
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
  static const String _keyShowDeveloperOptions = 'show_developer_options';
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

  static const String _keySmallWindowWidth = 'small_window_width';
  static const String _keySmallWindowHeight = 'small_window_height';
  static const String _keySmallWindowQueueWidth = 'small_window_queue_width';
  static const String _keySmallWindowQueueHeight = 'small_window_queue_height';
  static const String _keyWasSmallWindowQueueExpanded = 'was_small_window_queue_expanded';
  static const String _keyHasShownOnboarding = 'has_shown_onboarding';

  final SharedPreferences _prefs;
  bool _isUserInactive = false;
  Timer? _inactivityTimer;
  Map<String, ShortcutBinding> _shortcutBindings;

  // SettingProperty definitions for all configuration options
  late final _hasShownOnboardingProperty = SettingProperty<bool>(
    key: _keyHasShownOnboarding,
    defaultValue: false,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _themeModeProperty = SettingProperty<ThemeMode>(
    key: _keyThemeMode,
    defaultValue: ThemeMode.system,
    prefs: _prefs,
    onChanged: notifyListeners,
    customRead: (prefs, key, def) => ThemeModeX.fromStorageValue(prefs.getString(key)),
    customWrite: (prefs, key, val) => prefs.setString(key, val.storageValue),
  );

  late final _isImmersiveTabBarEnabledProperty = SettingProperty<bool>(
    key: _keyImmersiveTabBar,
    defaultValue: false,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _waveformChunksProperty = SettingProperty<int>(
    key: _keyWaveformChunks,
    defaultValue: 120,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _sampleStrideProperty = SettingProperty<int>(
    key: _keySampleStride,
    defaultValue: defaultSampleStride,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _lyricsAiProviderProperty = SettingProperty<LyricsAiProvider>(
    key: _keyLyricsAiProvider,
    defaultValue: LyricsAiProvider.googleAiStudio,
    prefs: _prefs,
    onChanged: notifyListeners,
    customRead: (prefs, key, def) => LyricsAiProviderX.fromStorageValue(prefs.getString(key)),
    customWrite: (prefs, key, val) => prefs.setString(key, val.storageValue),
  );

  late final _isLyricsAiAutoSwitchEnabledProperty = SettingProperty<bool>(
    key: _keyLyricsAiAutoSwitchEnabled,
    defaultValue: false,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _lyricsFontScaleProperty = SettingProperty<double>(
    key: _keyLyricsFontScale,
    defaultValue: defaultLyricsFontScale,
    prefs: _prefs,
    onChanged: notifyListeners,
    customRead: (prefs, key, def) => _normalizeLyricsFontScale(prefs.getDouble(key) ?? def),
    customWrite: (prefs, key, val) => prefs.setDouble(key, _normalizeLyricsFontScale(val)),
  );

  late final _geminiPrimaryModelIdProperty = SettingProperty<String>(
    key: _keyGeminiPrimaryModelId,
    defaultValue: defaultGeminiPrimaryModelId,
    prefs: _prefs,
    onChanged: notifyListeners,
    customRead: (prefs, key, def) => _initialModelId(prefs.getString(key), def),
  );

  late final _geminiFallbackModelIdProperty = SettingProperty<String>(
    key: _keyGeminiFallbackModelId,
    defaultValue: defaultGeminiFallbackModelId,
    prefs: _prefs,
    onChanged: notifyListeners,
    customRead: (prefs, key, def) => _initialModelId(prefs.getString(key), def),
  );

  late final _geminiTranslationModelIdProperty = SettingProperty<String>(
    key: _keyGeminiTranslationModelId,
    defaultValue: defaultGeminiTranslationModelId,
    prefs: _prefs,
    onChanged: notifyListeners,
    customRead: (prefs, key, def) => _initialModelId(prefs.getString(key), def),
  );

  late final _geminiApiKeyProperty = SettingProperty<String>(
    key: geminiApiKeyStorageKey,
    defaultValue: '',
    prefs: _prefs,
    onChanged: notifyListeners,
    customWrite: (prefs, key, val) {
      final normalized = val.trim();
      if (normalized.isEmpty) {
        prefs.remove(key);
      } else {
        prefs.setString(key, normalized);
      }
    },
  );

  late final _openRouterApiKeyProperty = SettingProperty<String>(
    key: openRouterApiKeyStorageKey,
    defaultValue: '',
    prefs: _prefs,
    onChanged: notifyListeners,
    customWrite: (prefs, key, val) {
      final normalized = val.trim();
      if (normalized.isEmpty) {
        prefs.remove(key);
      } else {
        prefs.setString(key, normalized);
      }
    },
  );

  late final _visualizerColorProperty = SettingProperty<Color>(
    key: _keyVisColor,
    defaultValue: Colors.white,
    prefs: _prefs,
    onChanged: notifyListeners,
    customRead: (prefs, key, def) => Color(prefs.getInt(key) ?? def.toARGB32()),
    customWrite: (prefs, key, val) => prefs.setInt(key, val.toARGB32()),
  );

  late final _visualizerOpacityProperty = SettingProperty<double>(
    key: _keyVisOpacity,
    defaultValue: 0.2,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _isVisualizerGradientEnabledProperty = SettingProperty<bool>(
    key: _keyVisGradient,
    defaultValue: false,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _visualizerStartColorProperty = SettingProperty<Color>(
    key: _keyVisStartColor,
    defaultValue: Colors.blue,
    prefs: _prefs,
    onChanged: notifyListeners,
    customRead: (prefs, key, def) => Color(prefs.getInt(key) ?? def.toARGB32()),
    customWrite: (prefs, key, val) => prefs.setInt(key, val.toARGB32()),
  );

  late final _visualizerEndColorProperty = SettingProperty<Color>(
    key: _keyVisEndColor,
    defaultValue: Colors.purple,
    prefs: _prefs,
    onChanged: notifyListeners,
    customRead: (prefs, key, def) => Color(prefs.getInt(key) ?? def.toARGB32()),
    customWrite: (prefs, key, val) => prefs.setInt(key, val.toARGB32()),
  );

  late final _visualizerGradientStop1Property = SettingProperty<double>(
    key: _keyVisGradientStop1,
    defaultValue: 0.0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _visualizerGradientStop2Property = SettingProperty<double>(
    key: _keyVisGradientStop2,
    defaultValue: 1.0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _visualizerGradientTileModeProperty = SettingProperty<int>(
    key: _keyVisGradientTileMode,
    defaultValue: TileMode.clamp.index,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _isVisualizerDynamicColorProperty = SettingProperty<bool>(
    key: _keyVisualizerDynamicColor,
    defaultValue: false,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _isVisualizerDynamicStartColorProperty = SettingProperty<bool>(
    key: _keyVisualizerDynamicStartColor,
    defaultValue: false,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _isVisualizerDynamicEndColorProperty = SettingProperty<bool>(
    key: _keyVisualizerDynamicEndColor,
    defaultValue: false,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _playbackBackgroundTypeProperty = SettingProperty<int>(
    key: _keyPlaybackBackgroundType,
    defaultValue: 0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _playbackRadialGradientEnabledProperty = SettingProperty<bool>(
    key: _keyPlaybackRadialGradientEnabled,
    defaultValue: true,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _playbackBackgroundColorProperty = SettingProperty<int>(
    key: _keyPlaybackBackgroundColor,
    defaultValue: 0xFF1A1F2C,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _playbackBackgroundCustomImagePathProperty = SettingProperty<String>(
    key: _keyPlaybackBackgroundCustomImagePath,
    defaultValue: '',
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _playbackBackgroundNormalOpacityProperty = SettingProperty<double>(
    key: _keyPlaybackBackgroundNormalOpacity,
    defaultValue: 0.20,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _playbackBackgroundLyricsOpacityProperty = SettingProperty<double>(
    key: _keyPlaybackBackgroundLyricsOpacity,
    defaultValue: 0.40,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _playbackBlurredArtworkBlurSigmaProperty = SettingProperty<double>(
    key: _keyPlaybackBlurredArtworkBlurSigma,
    defaultValue: 30.0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _playbackCustomImageBlurSigmaProperty = SettingProperty<double>(
    key: _keyPlaybackCustomImageBlurSigma,
    defaultValue: 0.0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _playbackMeshBackgroundSpeedProperty = SettingProperty<double>(
    key: _keyPlaybackMeshBackgroundSpeed,
    defaultValue: 0.05,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _isAutoModeProperty = SettingProperty<bool>(
    key: _keyIsAutoMode,
    defaultValue: true,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _autoSpectrumQuantityProperty = SettingProperty<String>(
    key: _keyAutoSpectrumQuantity,
    defaultValue: 'high',
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _autoSpeedProperty = SettingProperty<String>(
    key: _keyAutoSpeed,
    defaultValue: 'medium',
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _portraitFrequencyGroupsProperty = SettingProperty<int>(
    key: _keyPortraitFrequencyGroups,
    defaultValue: 100,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _landscapeFrequencyGroupsProperty = SettingProperty<int>(
    key: _keyLandscapeFrequencyGroups,
    defaultValue: 172,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _portraitGapProperty = SettingProperty<double>(
    key: _keyPortraitGap,
    defaultValue: 1.0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _landscapeGapProperty = SettingProperty<double>(
    key: _keyLandscapeGap,
    defaultValue: 2.0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _isWaveformProgressBarEnabledProperty = SettingProperty<bool>(
    key: _keyIsWaveformProgressBarEnabled,
    defaultValue: true,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _showDeveloperOptionsProperty = SettingProperty<bool>(
    key: _keyShowDeveloperOptions,
    defaultValue: false,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _skipShortAudioScanEnabledProperty = SettingProperty<bool>(
    key: skipShortAudioScanEnabledStorageKey,
    defaultValue: false,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _skipShortAudioScanMinimumDurationSecondsProperty = SettingProperty<int>(
    key: skipShortAudioScanMinimumDurationSecondsStorageKey,
    defaultValue: defaultSkipShortAudioScanMinimumDurationSeconds,
    prefs: _prefs,
    onChanged: notifyListeners,
    customWrite: (prefs, key, val) {
      prefs.setInt(key, val.clamp(1, 3600).toInt());
    },
  );

  late final _randomRangeProperty = SettingProperty<int>(
    key: _keyRandomRange,
    defaultValue: 0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _randomMethodProperty = SettingProperty<int>(
    key: _keyRandomMethod,
    defaultValue: 1, // Default to shuffle
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _transcodeDefaultFormatProperty = SettingProperty<AudioFormat>(
    key: _keyTranscodeDefaultFormat,
    defaultValue: AudioFormat.m4a,
    prefs: _prefs,
    onChanged: notifyListeners,
    customRead: (prefs, key, def) => _audioFormatFromStorageValue(prefs.getString(key)),
    customWrite: (prefs, key, val) => prefs.setString(key, val.value),
  );

  late final _transcodeDefaultQualityTierProperty = SettingProperty<TranscodeQualityTier>(
    key: _keyTranscodeDefaultQualityTier,
    defaultValue: TranscodeQualityTier.medium,
    prefs: _prefs,
    onChanged: notifyListeners,
    customRead: (prefs, key, def) => TranscodeQualityTierX.fromStorageValue(prefs.getString(key)),
    customWrite: (prefs, key, val) => prefs.setString(key, val.storageValue),
  );

  late final _transcodeFfmpegPathProperty = SettingProperty<String>(
    key: _keyTranscodeFfmpegPath,
    defaultValue: '',
    prefs: _prefs,
    onChanged: notifyListeners,
    customWrite: (prefs, key, val) {
      final normalized = val.trim();
      if (normalized.isEmpty) {
        prefs.remove(key);
      } else {
        prefs.setString(key, normalized);
      }
    },
  );

  late final _transcodeAutoScanOutputEnabledProperty = SettingProperty<bool>(
    key: _keyTranscodeAutoScanOutputEnabled,
    defaultValue: true,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _smallWindowWidthProperty = SettingProperty<double>(
    key: _keySmallWindowWidth,
    defaultValue: 360.0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _smallWindowHeightProperty = SettingProperty<double>(
    key: _keySmallWindowHeight,
    defaultValue: 360.0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _smallWindowQueueWidthProperty = SettingProperty<double>(
    key: _keySmallWindowQueueWidth,
    defaultValue: 360.0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _smallWindowQueueHeightProperty = SettingProperty<double>(
    key: _keySmallWindowQueueHeight,
    defaultValue: 600.0,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  late final _wasSmallWindowQueueExpandedProperty = SettingProperty<bool>(
    key: _keyWasSmallWindowQueueExpanded,
    defaultValue: false,
    prefs: _prefs,
    onChanged: notifyListeners,
  );

  static String _initialModelId(String? value, String defaultValue) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return defaultValue;
    }
    return normalized;
  }

  SettingsService(this._prefs)
      : _shortcutBindings = _loadShortcutBindings(_prefs);

  bool get hasShownOnboarding => _hasShownOnboardingProperty.value;
  set hasShownOnboarding(bool value) => _hasShownOnboardingProperty.value = value;

  ThemeMode get themeMode => _themeModeProperty.value;
  set themeMode(ThemeMode value) => _themeModeProperty.value = value;

  bool get isImmersiveTabBarEnabled => _isImmersiveTabBarEnabledProperty.value;
  set isImmersiveTabBarEnabled(bool value) => _isImmersiveTabBarEnabledProperty.value = value;

  int get sampleStride => _sampleStrideProperty.value;
  set sampleStride(int value) => _sampleStrideProperty.value = value;

  int get waveformChunks => _waveformChunksProperty.value;
  set waveformChunks(int value) => _waveformChunksProperty.value = value;

  bool get isUserInactive => _isUserInactive;
  set isUserInactive(bool value) {
    if (_isUserInactive != value) {
      _isUserInactive = value;
      notifyListeners();
    }
    if (!value) {
      startInactivityTimer();
    }
  }

  LyricsAiProvider get lyricsAiProvider => _lyricsAiProviderProperty.value;
  set lyricsAiProvider(LyricsAiProvider value) => _lyricsAiProviderProperty.value = value;

  bool get isLyricsAiAutoSwitchEnabled => _isLyricsAiAutoSwitchEnabledProperty.value;
  set isLyricsAiAutoSwitchEnabled(bool value) => _isLyricsAiAutoSwitchEnabledProperty.value = value;

  double get lyricsFontScale => _lyricsFontScaleProperty.value;
  set lyricsFontScale(double value) => _lyricsFontScaleProperty.value = value;

  String get geminiPrimaryModelId => _geminiPrimaryModelIdProperty.value;
  set geminiPrimaryModelId(String value) => _geminiPrimaryModelIdProperty.value = value;

  String get geminiFallbackModelId => _geminiFallbackModelIdProperty.value;
  set geminiFallbackModelId(String value) => _geminiFallbackModelIdProperty.value = value;

  String get geminiTranslationModelId => _geminiTranslationModelIdProperty.value;
  set geminiTranslationModelId(String value) => _geminiTranslationModelIdProperty.value = value;

  String get geminiApiKey => _geminiApiKeyProperty.value;
  set geminiApiKey(String value) => _geminiApiKeyProperty.value = value;

  String get openRouterApiKey => _openRouterApiKeyProperty.value;
  set openRouterApiKey(String value) => _openRouterApiKeyProperty.value = value;

  bool get hasCustomGoogleAiStudioApiKey =>
      _prefs.containsKey(geminiApiKeyStorageKey);
  bool get hasCustomOpenRouterApiKey =>
      _prefs.containsKey(openRouterApiKeyStorageKey);
  bool get hasBothLyricsGenerationApiKeys =>
      geminiApiKey.trim().isNotEmpty && openRouterApiKey.trim().isNotEmpty;
  bool get canAutoSwitchLyricsProvider => hasBothLyricsGenerationApiKeys;
  bool get shouldAutoSwitchLyricsProvider =>
      isLyricsAiAutoSwitchEnabled && hasBothLyricsGenerationApiKeys;
  String get activeLyricsGenerationApiKey {
    return switch (lyricsAiProvider) {
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
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) {
      return isZh ? '未选择模型' : 'No model selected';
    }

    final normalized = trimmed.startsWith('google/')
        ? trimmed.substring('google/'.length)
        : trimmed;
    return normalized.split('-').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
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

  Color get visualizerColor => _visualizerColorProperty.value;
  set visualizerColor(Color value) => _visualizerColorProperty.value = value;

  double get visualizerOpacity => _visualizerOpacityProperty.value;
  set visualizerOpacity(double value) => _visualizerOpacityProperty.value = value;

  bool get isVisualizerGradientEnabled => _isVisualizerGradientEnabledProperty.value;
  set isVisualizerGradientEnabled(bool value) => _isVisualizerGradientEnabledProperty.value = value;

  Color get visualizerStartColor => _visualizerStartColorProperty.value;
  set visualizerStartColor(Color value) => _visualizerStartColorProperty.value = value;

  Color get visualizerEndColor => _visualizerEndColorProperty.value;
  set visualizerEndColor(Color value) => _visualizerEndColorProperty.value = value;

  double get visualizerGradientStop1 => _visualizerGradientStop1Property.value;
  set visualizerGradientStop1(double value) => _visualizerGradientStop1Property.value = value;

  double get visualizerGradientStop2 => _visualizerGradientStop2Property.value;
  set visualizerGradientStop2(double value) => _visualizerGradientStop2Property.value = value;

  int get visualizerGradientTileMode => _visualizerGradientTileModeProperty.value;
  set visualizerGradientTileMode(int value) => _visualizerGradientTileModeProperty.value = value;

  bool get isVisualizerDynamicColor => _isVisualizerDynamicColorProperty.value;
  set isVisualizerDynamicColor(bool value) => _isVisualizerDynamicColorProperty.value = value;

  bool get isVisualizerDynamicStartColor => _isVisualizerDynamicStartColorProperty.value;
  set isVisualizerDynamicStartColor(bool value) => _isVisualizerDynamicStartColorProperty.value = value;

  bool get isVisualizerDynamicEndColor => _isVisualizerDynamicEndColorProperty.value;
  set isVisualizerDynamicEndColor(bool value) => _isVisualizerDynamicEndColorProperty.value = value;

  int get playbackBackgroundType => _playbackBackgroundTypeProperty.value;
  set playbackBackgroundType(int value) => _playbackBackgroundTypeProperty.value = value;

  bool get playbackRadialGradientEnabled => _playbackRadialGradientEnabledProperty.value;
  set playbackRadialGradientEnabled(bool value) => _playbackRadialGradientEnabledProperty.value = value;

  int get playbackBackgroundColor => _playbackBackgroundColorProperty.value;
  set playbackBackgroundColor(int value) => _playbackBackgroundColorProperty.value = value;

  String get playbackBackgroundCustomImagePath => _playbackBackgroundCustomImagePathProperty.value;
  set playbackBackgroundCustomImagePath(String value) => _playbackBackgroundCustomImagePathProperty.value = value;

  double get playbackBackgroundNormalOpacity => _playbackBackgroundNormalOpacityProperty.value;
  set playbackBackgroundNormalOpacity(double value) => _playbackBackgroundNormalOpacityProperty.value = value;

  double get playbackBackgroundLyricsOpacity => _playbackBackgroundLyricsOpacityProperty.value;
  set playbackBackgroundLyricsOpacity(double value) => _playbackBackgroundLyricsOpacityProperty.value = value;

  double get playbackBlurredArtworkBlurSigma => _playbackBlurredArtworkBlurSigmaProperty.value;
  set playbackBlurredArtworkBlurSigma(double value) => _playbackBlurredArtworkBlurSigmaProperty.value = value;

  double get playbackCustomImageBlurSigma => _playbackCustomImageBlurSigmaProperty.value;
  set playbackCustomImageBlurSigma(double value) => _playbackCustomImageBlurSigmaProperty.value = value;

  double get playbackMeshBackgroundSpeed => _playbackMeshBackgroundSpeedProperty.value;
  set playbackMeshBackgroundSpeed(double value) => _playbackMeshBackgroundSpeedProperty.value = value;

  bool get isAutoMode => _isAutoModeProperty.value;
  set isAutoMode(bool value) => _isAutoModeProperty.value = value;

  String get autoSpectrumQuantity => _autoSpectrumQuantityProperty.value;
  set autoSpectrumQuantity(String value) => _autoSpectrumQuantityProperty.value = value;

  String get autoSpeed => _autoSpeedProperty.value;
  set autoSpeed(String value) => _autoSpeedProperty.value = value;

  int get portraitFrequencyGroups => _portraitFrequencyGroupsProperty.value;
  set portraitFrequencyGroups(int value) => _portraitFrequencyGroupsProperty.value = value;

  int get landscapeFrequencyGroups => _landscapeFrequencyGroupsProperty.value;
  set landscapeFrequencyGroups(int value) => _landscapeFrequencyGroupsProperty.value = value;

  double get portraitGap => _portraitGapProperty.value;
  set portraitGap(double value) => _portraitGapProperty.value = value;

  double get landscapeGap => _landscapeGapProperty.value;
  set landscapeGap(double value) => _landscapeGapProperty.value = value;

  bool get isWaveformProgressBarEnabled => _isWaveformProgressBarEnabledProperty.value;
  set isWaveformProgressBarEnabled(bool value) => _isWaveformProgressBarEnabledProperty.value = value;

  bool get showDeveloperOptions => _showDeveloperOptionsProperty.value;
  set showDeveloperOptions(bool value) => _showDeveloperOptionsProperty.value = value;

  bool get skipShortAudioScanEnabled => _skipShortAudioScanEnabledProperty.value;
  set skipShortAudioScanEnabled(bool value) => _skipShortAudioScanEnabledProperty.value = value;

  int get skipShortAudioScanMinimumDurationSeconds => _skipShortAudioScanMinimumDurationSecondsProperty.value;
  set skipShortAudioScanMinimumDurationSeconds(int value) => _skipShortAudioScanMinimumDurationSecondsProperty.value = value;

  int get randomRange => _randomRangeProperty.value;
  set randomRange(int value) => _randomRangeProperty.value = value;

  int get randomMethod => _randomMethodProperty.value;
  set randomMethod(int value) => _randomMethodProperty.value = value;

  AudioFormat get transcodeDefaultFormat => _transcodeDefaultFormatProperty.value;
  set transcodeDefaultFormat(AudioFormat value) => _transcodeDefaultFormatProperty.value = value;

  TranscodeQualityTier get transcodeDefaultQualityTier => _transcodeDefaultQualityTierProperty.value;
  set transcodeDefaultQualityTier(TranscodeQualityTier value) => _transcodeDefaultQualityTierProperty.value = value;

  String get transcodeFfmpegPath => _transcodeFfmpegPathProperty.value;
  set transcodeFfmpegPath(String value) => _transcodeFfmpegPathProperty.value = value;

  bool get transcodeAutoScanOutputEnabled => _transcodeAutoScanOutputEnabledProperty.value;
  set transcodeAutoScanOutputEnabled(bool value) => _transcodeAutoScanOutputEnabledProperty.value = value;

  double get smallWindowWidth => _smallWindowWidthProperty.value;
  set smallWindowWidth(double value) => _smallWindowWidthProperty.value = value;

  double get smallWindowHeight => _smallWindowHeightProperty.value;
  set smallWindowHeight(double value) => _smallWindowHeightProperty.value = value;

  double get smallWindowQueueWidth => _smallWindowQueueWidthProperty.value;
  set smallWindowQueueWidth(double value) => _smallWindowQueueWidthProperty.value = value;

  double get smallWindowQueueHeight => _smallWindowQueueHeightProperty.value;
  set smallWindowQueueHeight(double value) => _smallWindowQueueHeightProperty.value = value;

  bool get wasSmallWindowQueueExpanded => _wasSmallWindowQueueExpandedProperty.value;
  set wasSmallWindowQueueExpanded(bool value) => _wasSmallWindowQueueExpandedProperty.value = value;

  Size get savedSmallWindowSize => Size(smallWindowWidth, smallWindowHeight);
  set savedSmallWindowSize(Size size) {
    smallWindowWidth = size.width;
    smallWindowHeight = size.height;
  }

  Size get savedSmallWindowQueueSize => Size(smallWindowQueueWidth, smallWindowQueueHeight);
  set savedSmallWindowQueueSize(Size size) {
    smallWindowQueueWidth = size.width;
    smallWindowQueueHeight = size.height;
  }

  SharedPreferences get prefs => _prefs;

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
    _visualizerOpacityProperty.reset();
    _visualizerColorProperty.reset();
    _isVisualizerGradientEnabledProperty.reset();
    _visualizerStartColorProperty.reset();
    _visualizerEndColorProperty.reset();
    _visualizerGradientStop1Property.reset();
    _visualizerGradientStop2Property.reset();
    _visualizerGradientTileModeProperty.reset();
    _isVisualizerDynamicColorProperty.reset();
    _isVisualizerDynamicStartColorProperty.reset();
    _isVisualizerDynamicEndColorProperty.reset();
    _playbackMeshBackgroundSpeedProperty.reset();
    _playbackBackgroundColorProperty.reset();
    _playbackRadialGradientEnabledProperty.reset();
    _playbackBackgroundCustomImagePathProperty.reset();
    _playbackBackgroundNormalOpacityProperty.reset();
    _playbackBackgroundLyricsOpacityProperty.reset();
    _playbackBlurredArtworkBlurSigmaProperty.reset();
    _playbackCustomImageBlurSigmaProperty.reset();
    _isAutoModeProperty.reset();
    _autoSpectrumQuantityProperty.reset();
    _autoSpeedProperty.reset();
    _portraitFrequencyGroupsProperty.reset();
    _landscapeFrequencyGroupsProperty.reset();
    _portraitGapProperty.reset();
    _landscapeGapProperty.reset();
    _isWaveformProgressBarEnabledProperty.reset();
    _showDeveloperOptionsProperty.reset();
    _randomRangeProperty.reset();
    _randomMethodProperty.reset();
  }

  void increaseLyricsFontScale() {
    lyricsFontScale = lyricsFontScale + lyricsFontScaleStep;
  }

  void decreaseLyricsFontScale() {
    lyricsFontScale = lyricsFontScale - lyricsFontScaleStep;
  }

  void resetLyricsFontScale() {
    _lyricsFontScaleProperty.reset();
  }

  void resetGeminiModels() {
    _geminiPrimaryModelIdProperty.reset();
    _geminiFallbackModelIdProperty.reset();
    _geminiTranslationModelIdProperty.reset();
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
    if (acoustidApiKey == normalized) {
      return;
    }

    if (normalized.isEmpty) {
      _prefs.remove(acoustidApiKeyStorageKey);
    } else {
      _prefs.setString(acoustidApiKeyStorageKey, normalized);
    }
    notifyListeners();
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

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  static double _normalizeLyricsFontScale(double value) {
    final clamped = value.clamp(minLyricsFontScale, maxLyricsFontScale);
    return (clamped * 10).roundToDouble() / 10.0;
  }

  bool _isSmallWindowMode = false;
  bool get isSmallWindowMode => _isSmallWindowMode;
  set isSmallWindowMode(bool value) {
    if (_isSmallWindowMode != value) {
      _isSmallWindowMode = value;
      if (!value) {
        _isSmallWindowQueueExpanded = false;
      } else {
        _isSmallWindowQueueExpanded = wasSmallWindowQueueExpanded;
      }
      notifyListeners();
    }
  }

  bool _isSmallWindowQueueExpanded = false;
  bool get isSmallWindowQueueExpanded => _isSmallWindowQueueExpanded;
  set isSmallWindowQueueExpanded(bool value) {
    if (_isSmallWindowQueueExpanded != value) {
      _isSmallWindowQueueExpanded = value;
      wasSmallWindowQueueExpanded = value;
      notifyListeners();
    }
  }

  Size? savedRegularWindowSize;
}
