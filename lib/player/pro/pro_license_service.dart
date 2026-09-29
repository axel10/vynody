import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/dialogs/upgrade_to_pro_dialog.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/pro/app_channel.dart';
import 'package:vynody/player/pro/pro_models.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/secure_storage.dart';

const String _kFirstLaunchTimeKey = 'vynody_license_first_launch_epoch_ms';
const String _kProPurchasedKey = 'vynody_license_pro_purchased';
const String _kTrialResetV2132Key = 'vynody_trial_reset_v2_13_2_done';
const String _kPendingTrialResetNoticeKey = 'vynody_pending_trial_reset_v2_13_2_notice';

/// Service managing trial periods and license verification.
class ProLicenseService extends ChangeNotifier {
  ProLicenseService({SharedPreferences? prefs})
      : _prefs = prefs,
        _pendingTrialResetNotice = prefs?.getBool(_kPendingTrialResetNoticeKey) ?? false,
        _state = _computeInitialState(prefs) {
    _init();
  }

  final SharedPreferences? _prefs;
  static const _secureStorage = appSecureStorage;

  LicenseState _state;
  bool _pendingTrialResetNotice = false;
  bool _disposed = false;

  /// Whether a trial reset notice dialog should be shown to the user.
  bool get pendingTrialResetNotice => _pendingTrialResetNotice;

  /// Mark the trial reset notice as consumed/dismissed.
  Future<void> consumeTrialResetNotice() async {
    _pendingTrialResetNotice = false;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(_kPendingTrialResetNoticeKey, false);
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static LicenseState _computeInitialState(SharedPreferences? prefs) {
    if (AppChannel.isGitHubRelease) {
      return const LicenseState(type: LicenseType.unlimitedCommunity);
    }
    if (prefs == null) {
      return const LicenseState(type: LicenseType.activeTrial);
    }
    if (prefs.getBool(_kProPurchasedKey) == true) {
      return const LicenseState(type: LicenseType.purchasedPro);
    }

    final hasResetV2132 = prefs.getBool(_kTrialResetV2132Key) ?? false;
    final firstLaunchMs = prefs.getInt(_kFirstLaunchTimeKey);

    // If updating to 2.13.2+ and reset hasn't executed yet, provide full active trial immediately
    if (!hasResetV2132 && firstLaunchMs != null && firstLaunchMs > 0) {
      return LicenseState(
        type: LicenseType.activeTrial,
        trialTotalDays: ProConfig.trialDays,
        trialDaysRemaining: ProConfig.trialDays,
        firstLaunchTime: DateTime.now(),
        trialExpireTime: DateTime.now().add(const Duration(days: ProConfig.trialDays)),
      );
    }

    if (firstLaunchMs != null && firstLaunchMs > 0) {
      final firstLaunchTime =
          DateTime.fromMillisecondsSinceEpoch(firstLaunchMs);
      final expireTime =
          firstLaunchTime.add(const Duration(days: ProConfig.trialDays));
      final now = DateTime.now();
      final remainingDifference = expireTime.difference(now);
      final remainingDays = remainingDifference.inDays +
          (remainingDifference.inHours % 24 > 0 ? 1 : 0);
      if (now.isBefore(expireTime) && remainingDays > 0) {
        return LicenseState(
          type: LicenseType.activeTrial,
          trialTotalDays: ProConfig.trialDays,
          trialDaysRemaining: remainingDays.clamp(1, ProConfig.trialDays),
          firstLaunchTime: firstLaunchTime,
          trialExpireTime: expireTime,
        );
      } else {
        return LicenseState(
          type: LicenseType.expiredTrial,
          trialTotalDays: ProConfig.trialDays,
          trialDaysRemaining: 0,
          firstLaunchTime: firstLaunchTime,
          trialExpireTime: expireTime,
        );
      }
    }
    return const LicenseState(type: LicenseType.activeTrial);
  }

  LicenseState get state => _state;

  /// Reads the trial start timestamp from SharedPreferences, Windows PasswordVault, or Keychain.
  Future<int?> _readPersistentFirstLaunchMs(SharedPreferences prefs) async {
    // 1. Fast check in SharedPreferences
    final prefMs = prefs.getInt(_kFirstLaunchTimeKey);
    if (prefMs != null && prefMs > 0) {
      return prefMs;
    }

    // 2. Windows: check PasswordVault via native MethodChannel
    if (Platform.isWindows) {
      try {
        const channel = MethodChannel('vynody/single_instance');
        final dynamic vaultMs = await channel.invokeMethod('getSecureVaultTrialTime');
        if (vaultMs is int && vaultMs > 0) {
          await prefs.setInt(_kFirstLaunchTimeKey, vaultMs);
          return vaultMs;
        }
      } catch (e) {
        debugPrint('[ProLicenseService] Failed to read trial time from PasswordVault: $e');
      }
    }

    // 3. Apple/Other: check Keychain via FlutterSecureStorage
    try {
      final secureVal = await _secureStorage.read(key: _kFirstLaunchTimeKey);
      if (secureVal != null) {
        final parsed = int.tryParse(secureVal);
        if (parsed != null && parsed > 0) {
          await prefs.setInt(_kFirstLaunchTimeKey, parsed);
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('[ProLicenseService] Failed to read trial time from SecureStorage: $e');
    }

    return null;
  }

  /// Writes the trial start timestamp to SharedPreferences, Windows PasswordVault, and Keychain.
  Future<void> _writePersistentFirstLaunchMs(SharedPreferences prefs, int epochMs) async {
    await prefs.setInt(_kFirstLaunchTimeKey, epochMs);

    if (Platform.isWindows) {
      try {
        const channel = MethodChannel('vynody/single_instance');
        await channel.invokeMethod('setSecureVaultTrialTime', {'epochMs': epochMs});
      } catch (e) {
        debugPrint('[ProLicenseService] Failed to write trial time to PasswordVault: $e');
      }
    }

    try {
      await _secureStorage.write(key: _kFirstLaunchTimeKey, value: epochMs.toString());
    } catch (e) {
      debugPrint('[ProLicenseService] Failed to write trial time to SecureStorage: $e');
    }
  }

  Future<void> _init() async {
    // 1. If running GitHub Community build, permanently unlock.
    if (AppChannel.isGitHubRelease) {
      _state = const LicenseState(type: LicenseType.unlimitedCommunity);
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setBool(_kTrialResetV2132Key, true);
      notifyListeners();
      return;
    }

    // 2. Windows Store build: query real Microsoft Store license via WinRT if packaged
    if (Platform.isWindows && AppChannel.isStoreRelease) {
      try {
        const channel = MethodChannel('vynody/single_instance');
        final dynamic res = await channel.invokeMethod('getStoreLicense');
        if (res is Map && res['isPackaged'] == true) {
          final isProPurchased = res['isProPurchased'] as bool? ?? false;
          final isTrial = res['isTrial'] as bool? ?? false;
          final remainingDays = res['remainingDays'] as int? ?? 0;

          if (isProPurchased) {
            _state = const LicenseState(type: LicenseType.purchasedPro);
            notifyListeners();
            return;
          } else if (isTrial && remainingDays > 0) {
            _state = LicenseState(
              type: LicenseType.activeTrial,
              trialTotalDays: ProConfig.trialDays,
              trialDaysRemaining: remainingDays.clamp(1, ProConfig.trialDays),
            );
            notifyListeners();
            return;
          } else if (isTrial && remainingDays <= 0) {
            _state = const LicenseState(
              type: LicenseType.expiredTrial,
              trialTotalDays: ProConfig.trialDays,
              trialDaysRemaining: 0,
            );
            notifyListeners();
            return;
          }
        }
      } catch (e) {
        debugPrint('[ProLicenseService] Failed to query Windows Store license: $e');
      }
    }

    // 3. Store build fallback: Check storage for purchase or trial timestamps.
    final prefs = _prefs ?? await SharedPreferences.getInstance();

    final isPurchased = prefs.getBool(_kProPurchasedKey) ?? false;
    if (isPurchased) {
      _state = const LicenseState(type: LicenseType.purchasedPro);
      await prefs.setBool(_kTrialResetV2132Key, true);
      notifyListeners();
      return;
    }

    final hasResetV2132 = prefs.getBool(_kTrialResetV2132Key) ?? false;
    int? firstLaunchMs = await _readPersistentFirstLaunchMs(prefs);

    if (!hasResetV2132) {
      await prefs.setBool(_kTrialResetV2132Key, true);
      final isExistingUser = firstLaunchMs != null && firstLaunchMs > 0;
      await resetTrialPeriod(triggerPendingNotice: isExistingUser);
      return;
    }

    final now = DateTime.now();
    _pendingTrialResetNotice = prefs.getBool(_kPendingTrialResetNoticeKey) ?? false;
    if (firstLaunchMs == null) {
      firstLaunchMs = now.millisecondsSinceEpoch;
      await _writePersistentFirstLaunchMs(prefs, firstLaunchMs);
    } else {
      await _writePersistentFirstLaunchMs(prefs, firstLaunchMs);
    }

    final firstLaunchTime = DateTime.fromMillisecondsSinceEpoch(firstLaunchMs);
    final expireTime = firstLaunchTime.add(const Duration(days: ProConfig.trialDays));
    final remainingDifference = expireTime.difference(now);

    final remainingDays = remainingDifference.inDays + (remainingDifference.inHours % 24 > 0 ? 1 : 0);

    if (now.isBefore(expireTime) && remainingDays > 0) {
      _state = LicenseState(
        type: LicenseType.activeTrial,
        trialTotalDays: ProConfig.trialDays,
        trialDaysRemaining: remainingDays.clamp(1, ProConfig.trialDays),
        firstLaunchTime: firstLaunchTime,
        trialExpireTime: expireTime,
      );
    } else {
      _state = LicenseState(
        type: LicenseType.expiredTrial,
        trialTotalDays: ProConfig.trialDays,
        trialDaysRemaining: 0,
        firstLaunchTime: firstLaunchTime,
        trialExpireTime: expireTime,
      );
    }

    if (_disposed) return;
    notifyListeners();
  }

  /// Refresh license status (e.g. after returning from Microsoft Store or App Store).
  Future<void> refreshLicense() async {
    await _init();
  }

  /// Mark Pro as purchased (for IAP callback / restore purchases).
  Future<void> setPurchased(bool purchased) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(_kProPurchasedKey, purchased);
    if (_disposed) return;
    if (purchased) {
      _state = _state.copyWith(type: LicenseType.purchasedPro);
    } else {
      await _init();
    }
    if (_disposed) return;
    notifyListeners();
  }

  /// Unified method to reset the trial period back to full duration.
  ///
  /// Resets the persistent trial start time across all storage backends (SharedPreferences,
  /// Windows PasswordVault, and Keychain) and updates the in-memory license state.
  ///
  /// - [triggerPendingNotice]: If true, flags a startup notice dialog for the user.
  /// - [offsetDays]: Backdate the trial start by a number of days (useful for testing expiration).
  /// - [clearPurchased]: If true, resets the purchased Pro status back to trial.
  Future<void> resetTrialPeriod({
    bool triggerPendingNotice = false,
    int offsetDays = 0,
    bool clearPurchased = false,
  }) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final newStart = DateTime.now().subtract(Duration(days: offsetDays));
    final epochMs = newStart.millisecondsSinceEpoch;

    await _writePersistentFirstLaunchMs(prefs, epochMs);

    if (clearPurchased) {
      await prefs.setBool(_kProPurchasedKey, false);
    }

    if (triggerPendingNotice) {
      await prefs.setBool(_kPendingTrialResetNoticeKey, true);
      _pendingTrialResetNotice = true;
    }

    if (_disposed) return;
    await _init();
  }

  /// Debug helper: Reset trial timestamp for testing.
  Future<void> debugResetTrial({int offsetDays = 0}) async {
    await resetTrialPeriod(
      offsetDays: offsetDays,
      clearPurchased: true,
      triggerPendingNotice: false,
    );
  }

  /// Check whether a feature can be accessed.
  bool hasAccess(ProFeature feature) {
    return _state.isProUnlocked;
  }
}

/// Provider for the [ProLicenseService] instance.
final proLicenseServiceProvider = ChangeNotifierProvider<ProLicenseService>((ref) {
  final prefs = ref.read(settingsServiceProvider).prefs;
  return ProLicenseService(prefs: prefs);
});

/// Provider for the current [LicenseState].
final licenseStateProvider = Provider<LicenseState>((ref) {
  final service = ref.watch(proLicenseServiceProvider);
  return service.state;
});

/// Provider for whether a trial reset notice dialog is pending.
final trialResetNoticePendingProvider = Provider<bool>((ref) {
  final service = ref.watch(proLicenseServiceProvider);
  return service.pendingTrialResetNotice;
});

/// Convenience provider: whether Pro features are currently unlocked.
final isProUnlockedProvider = Provider<bool>((ref) {
  final license = ref.watch(licenseStateProvider);
  return license.isProUnlocked;
});

/// Provider for whether audio visualizer is effectively enabled (Pro unlocked & setting enabled).
final effectiveVisualizerEnabledProvider = Provider<bool>((ref) {
  final isProUnlocked = ref.watch(isProUnlockedProvider);
  final isVisualizerSettingEnabled = ref.watch(
    settingsServiceProvider.select((s) => s.isVisualizerEnabled),
  );
  return isProUnlocked && isVisualizerSettingEnabled;
});

/// Provider for whether audio equalizer is effectively enabled (Pro unlocked & setting enabled).
final effectiveEqualizerEnabledProvider = Provider<bool>((ref) {
  final isProUnlocked = ref.watch(isProUnlockedProvider);
  final isEqualizerSettingEnabled = ref.watch(
    settingsServiceProvider.select((s) => s.equalizerEnabled),
  );
  return isProUnlocked && isEqualizerSettingEnabled;
});

/// Provider for whether waveform progress bar is effectively enabled (Pro unlocked & setting enabled).
final isEffectiveWaveformEnabledProvider = Provider<bool>((ref) {
  final isProUnlocked = ref.watch(isProUnlockedProvider);
  final isWaveformSettingEnabled = ref.watch(
    settingsServiceProvider.select((s) => s.isWaveformProgressBarEnabled),
  );
  return isProUnlocked && isWaveformSettingEnabled;
});

/// Provider for the effective progress bar style (falls back to standard if Pro is locked).
final effectiveProgressBarStyleProvider = Provider<ProgressBarStyle>((ref) {
  final isProUnlocked = ref.watch(isProUnlockedProvider);
  final style = ref.watch(
    settingsServiceProvider.select((s) => s.progressBarStyle),
  );
  if (!isProUnlocked && style != ProgressBarStyle.standard) {
    return ProgressBarStyle.standard;
  }
  return style;
});

/// Provider for effective playback background type (falls back to 0 if Pro is locked and dynamic mesh / custom image background is selected).
final effectivePlaybackBackgroundTypeProvider = Provider<int>((ref) {
  final isProUnlocked = ref.watch(isProUnlockedProvider);
  final rawBackgroundType = ref.watch(
    settingsServiceProvider.select((s) => s.playbackBackgroundType),
  );
  if (!isProUnlocked && (rawBackgroundType == 1 || rawBackgroundType == 3)) {
    return 0;
  }
  return rawBackgroundType;
});

/// Provider for whether WASAPI exclusive mode is effectively enabled (Windows, Pro unlocked & setting enabled).
final isEffectiveWasapiExclusiveProvider = Provider<bool>((ref) {
  if (!Platform.isWindows) return false;
  final isProUnlocked = ref.watch(isProUnlockedProvider);
  final isExclusiveSetting = ref.watch(
    settingsServiceProvider.select(
      (s) => s.windowsAudioOutputMode == 'wasapi_exclusive',
    ),
  );
  return isProUnlocked && isExclusiveSetting;
});

/// Check access for a specific Pro feature. If locked, opens the upgrade dialog.
/// Returns true if access is granted, false if blocked.
Future<bool> checkProGate(
  BuildContext context,
  WidgetRef ref, {
  ProFeature? feature,
}) async {
  final isUnlocked = ref.read(isProUnlockedProvider);
  if (isUnlocked) return true;

  if (context.mounted) {
    await showUpgradeToProDialog(context, initialFeature: feature);
  }
  return false;
}
