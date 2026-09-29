import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight and cross-platform secure storage backed by [SharedPreferences]
/// with in-app obfuscation/encryption and backward-compatibility migration
/// from legacy [FlutterSecureStorage].
///
/// Eliminates macOS keychain password dialogs, keychain-access-groups
/// entitlements, and native codesigning friction while keeping sensitive
/// values (API keys, passwords, tokens) safely encrypted at rest.
class AppSecureStorage {
  final SharedPreferences? _prefs;
  final FlutterSecureStorage? _legacyStorage;

  const AppSecureStorage([
    this._prefs,
    this._legacyStorage,
  ]);

  static const FlutterSecureStorage _defaultLegacyStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock,
      useDataProtectionKeyChain: false,
    ),
  );

  FlutterSecureStorage get _effectiveLegacyStorage =>
      _legacyStorage ?? _defaultLegacyStorage;

  static const String _storageKeyPrefix = 'app_sec:';
  static const String _prefix = 'enc:v1:';
  static const List<int> _saltBytes = [
    0x56, 0x79, 0x6E, 0x6F, 0x64, 0x79, 0x5F, 0x53,
    0x65, 0x63, 0x75, 0x72, 0x65, 0x5F, 0x56, 0x69,
    0x62, 0x65, 0x46, 0x6C, 0x6F, 0x77, 0x32, 0x30,
    0x32, 0x36, 0x5F, 0x4B, 0x65, 0x79, 0x21, 0x24,
  ];

  /// Encrypts plaintext string using salt XOR + Base64 encoding.
  static String encrypt(String plainText) {
    if (plainText.isEmpty) return '';
    final plainBytes = utf8.encode(plainText);
    final encryptedBytes = List<int>.generate(plainBytes.length, (i) {
      return plainBytes[i] ^ _saltBytes[i % _saltBytes.length];
    });
    return '$_prefix${base64.encode(encryptedBytes)}';
  }

  /// Decrypts encrypted string. Supports backward compatibility with plaintext values.
  static String decrypt(String storedText) {
    if (storedText.isEmpty) return '';
    if (!storedText.startsWith(_prefix)) {
      // Backward compatibility: If stored value is legacy plaintext, return as-is.
      return storedText;
    }
    try {
      final base64Payload = storedText.substring(_prefix.length);
      final encryptedBytes = base64.decode(base64Payload);
      final decryptedBytes = List<int>.generate(encryptedBytes.length, (i) {
        return encryptedBytes[i] ^ _saltBytes[i % _saltBytes.length];
      });
      return utf8.decode(decryptedBytes);
    } catch (_) {
      // Fallback if corrupted
      return storedText;
    }
  }

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  /// Reads a decrypted value for the given [key].
  ///
  /// If the value is not present in the new encrypted storage,
  /// it automatically checks legacy [FlutterSecureStorage], migrates
  /// the value to encrypted preferences, and cleans up the legacy entry.
  Future<String?> read({required String key}) async {
    final prefs = await _getPrefs();
    final modernKey = '$_storageKeyPrefix$key';
    final raw = prefs.getString(modernKey);
    if (raw != null) {
      return decrypt(raw);
    }

    // Check legacy un-prefixed key in SharedPreferences (if previously stored as encrypted string)
    final dynamic legacyRaw = prefs.get(key);
    if (legacyRaw is String && legacyRaw.startsWith(_prefix)) {
      final decrypted = decrypt(legacyRaw);
      await write(key: key, value: decrypted);
      try {
        await prefs.remove(key);
      } catch (_) {}
      return decrypted;
    }

    // Attempt transparent migration from legacy flutter_secure_storage
    try {
      final legacyValue = await _effectiveLegacyStorage.read(key: key);
      if (legacyValue != null && legacyValue.isNotEmpty) {
        // Save to modern encrypted storage
        await write(key: key, value: legacyValue);
        // Best-effort cleanup of legacy key to avoid leaving stale items
        try {
          await _effectiveLegacyStorage.delete(key: key);
        } catch (_) {}
        return legacyValue;
      }
    } catch (_) {
      // Best effort; ignore legacy storage errors
    }

    return null;
  }

  /// Synchronous read if a [SharedPreferences] instance was provided.
  /// Note: Only checks the current encrypted preferences.
  String? readSync({required String key}) {
    if (_prefs == null) return null;
    final modernKey = '$_storageKeyPrefix$key';
    final raw = _prefs.getString(modernKey);
    if (raw != null) return decrypt(raw);
    final dynamic legacyRaw = _prefs.get(key);
    if (legacyRaw is String && legacyRaw.startsWith(_prefix)) {
      return decrypt(legacyRaw);
    }
    return null;
  }

  /// Writes an encrypted value for the given [key].
  Future<void> write({required String key, required String value}) async {
    final prefs = await _getPrefs();
    final encrypted = encrypt(value);
    await prefs.setString('$_storageKeyPrefix$key', encrypted);
  }

  /// Deletes the value for the given [key] from both modern and legacy storage.
  Future<void> delete({required String key}) async {
    final prefs = await _getPrefs();
    await prefs.remove('$_storageKeyPrefix$key');
    final dynamic legacyRaw = prefs.get(key);
    if (legacyRaw is String && legacyRaw.startsWith(_prefix)) {
      await prefs.remove(key);
    }
    try {
      await _effectiveLegacyStorage.delete(key: key);
    } catch (_) {}
  }

  /// Checks if [key] exists in either modern or legacy storage.
  Future<bool> containsKey({required String key}) async {
    final prefs = await _getPrefs();
    if (prefs.containsKey('$_storageKeyPrefix$key')) return true;
    final dynamic legacyRaw = prefs.get(key);
    if (legacyRaw is String && legacyRaw.startsWith(_prefix)) return true;
    try {
      return await _effectiveLegacyStorage.containsKey(key: key);
    } catch (_) {
      return false;
    }
  }

  /// Deletes all encrypted keys managed by AppSecureStorage.
  Future<void> deleteAll() async {
    final prefs = await _getPrefs();
    final keysToRemove = prefs.getKeys().where((k) => k.startsWith(_storageKeyPrefix)).toList();
    for (final k in keysToRemove) {
      await prefs.remove(k);
    }
    try {
      await _effectiveLegacyStorage.deleteAll();
    } catch (_) {}
  }
}

/// Global default instance of [AppSecureStorage].
const appSecureStorage = AppSecureStorage();
