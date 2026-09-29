import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Unified cross-platform secure vault for values that must survive
/// application uninstallation and data resets.
///
/// Backends:
/// - Windows: Windows Credential Manager (`winrt::Windows::Security::Credentials::PasswordVault`)
/// - iOS / Android: Secure Keychain / Keystore via [FlutterSecureStorage]
class PlatformSecureVault {
  PlatformSecureVault({FlutterSecureStorage? secureStorage})
      : _storage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _hasInjectedStorage = secureStorage != null;

  final FlutterSecureStorage _storage;
  final bool _hasInjectedStorage;
  static const MethodChannel _windowsChannel = MethodChannel('vynody/single_instance');

  bool get _isKeychainSupported =>
      Platform.isIOS || Platform.isAndroid || _hasInjectedStorage;

  /// Read a persistent value by key across reinstalls.
  Future<String?> read(String key) async {
    // 1. Windows: native WinRT PasswordVault
    if (Platform.isWindows) {
      try {
        final dynamic res = await _windowsChannel.invokeMethod('getSecureVaultString', {'key': key});
        if (res is String && res.isNotEmpty) {
          return res;
        }
        // Legacy fallback for TrialFirstLaunchEpochMs
        if (key == 'vynody_license_first_launch_epoch_ms') {
          final dynamic legacyMs = await _windowsChannel.invokeMethod('getSecureVaultTrialTime');
          if (legacyMs != null) return legacyMs.toString();
        }
        // Legacy fallback for TrialResetV2132Done
        if (key == 'vynody_trial_reset_v2_13_2_done') {
          final dynamic legacyDone = await _windowsChannel.invokeMethod('getSecureVaultTrialResetV2132');
          if (legacyDone == true) return 'true';
        }
      } catch (e) {
        debugPrint('[PlatformSecureVault] Failed to read $key from PasswordVault: $e');
      }
    }

    // 2. iOS / Android: Secure Keychain / Keystore
    if (_isKeychainSupported) {
      try {
        final res = await _storage.read(key: key);
        if (res != null && res.isNotEmpty) {
          return res;
        }
      } catch (e) {
        debugPrint('[PlatformSecureVault] Failed to read $key from Keychain: $e');
      }
    }

    return null;
  }

  /// Write a persistent value by key across reinstalls.
  Future<void> write(String key, String value) async {
    // 1. Windows: native WinRT PasswordVault
    if (Platform.isWindows) {
      try {
        await _windowsChannel.invokeMethod('setSecureVaultString', {
          'key': key,
          'value': value,
        });
        // Legacy fallback sync
        if (key == 'vynody_license_first_launch_epoch_ms') {
          final epochMs = int.tryParse(value) ?? 0;
          if (epochMs > 0) {
            await _windowsChannel.invokeMethod('setSecureVaultTrialTime', {'epochMs': epochMs});
          }
        } else if (key == 'vynody_trial_reset_v2_13_2_done') {
          await _windowsChannel.invokeMethod('setSecureVaultTrialResetV2132', {'done': value == 'true' || value == '1'});
        }
      } catch (e) {
        debugPrint('[PlatformSecureVault] Failed to write $key to PasswordVault: $e');
      }
    }

    // 2. iOS / Android: Secure Keychain / Keystore
    if (_isKeychainSupported) {
      try {
        await _storage.write(key: key, value: value);
      } catch (e) {
        debugPrint('[PlatformSecureVault] Failed to write $key to Keychain: $e');
      }
    }
  }

  /// Delete a persistent value by key.
  Future<void> delete(String key) async {
    if (Platform.isWindows) {
      try {
        await _windowsChannel.invokeMethod('deleteSecureVaultString', {'key': key});
      } catch (e) {
        debugPrint('[PlatformSecureVault] Failed to delete $key from PasswordVault: $e');
      }
    }

    if (_isKeychainSupported) {
      try {
        await _storage.delete(key: key);
      } catch (e) {
        debugPrint('[PlatformSecureVault] Failed to delete $key from Keychain: $e');
      }
    }
  }
}

/// Global default instance of [PlatformSecureVault].
final platformSecureVault = PlatformSecureVault();
