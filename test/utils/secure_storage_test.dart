import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/utils/secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSecureStorage Tests', () {
    late SharedPreferences prefs;
    late AppSecureStorage storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      storage = AppSecureStorage(prefs);
    });

    test('encryption and decryption round-trip', () {
      const plaintext = 'sk-test-openai-1234567890!@#\$%^&*()';
      final encrypted = AppSecureStorage.encrypt(plaintext);

      expect(encrypted, isNot(plaintext));
      expect(encrypted.startsWith('enc:v1:'), isTrue);

      final decrypted = AppSecureStorage.decrypt(encrypted);
      expect(decrypted, equals(plaintext));
    });

    test('backward compatibility: returns raw plaintext if not encrypted', () {
      const legacyPlaintext = 'legacy-plain-token';
      final decrypted = AppSecureStorage.decrypt(legacyPlaintext);
      expect(decrypted, equals(legacyPlaintext));
    });

    test('write, read, readSync, and delete', () async {
      await storage.write(key: 'my_key', value: 'secret_value_42');

      // Check stored value in SharedPreferences is encrypted
      final storedRaw = prefs.getString('app_sec:my_key');
      expect(storedRaw, isNotNull);
      expect(storedRaw!.startsWith('enc:v1:'), isTrue);
      expect(storedRaw, isNot(contains('secret_value_42')));

      // Read async
      final decryptedAsync = await storage.read(key: 'my_key');
      expect(decryptedAsync, equals('secret_value_42'));

      // Read sync
      final decryptedSync = storage.readSync(key: 'my_key');
      expect(decryptedSync, equals('secret_value_42'));

      // Delete
      await storage.delete(key: 'my_key');
      expect(await storage.read(key: 'my_key'), isNull);
      expect(storage.readSync(key: 'my_key'), isNull);
    });

    test('reads existing unencrypted legacy preferences seamlessly', () async {
      await prefs.setString('legacy_key', 'plain_api_key_123');
      final value = await storage.read(key: 'legacy_key');
      expect(value, equals('plain_api_key_123'));
    });

    test('migrates data from legacy FlutterSecureStorage seamlessly', () async {
      final fakeLegacy = _FakeFlutterSecureStorage({'migrated_token': 'sk-secret-12345'});
      final migrationStorage = AppSecureStorage(prefs, fakeLegacy);

      // Value should not be in prefs initially
      expect(prefs.getString('app_sec:migrated_token'), isNull);

      // Read triggers transparent migration
      final val = await migrationStorage.read(key: 'migrated_token');
      expect(val, equals('sk-secret-12345'));

      // Now should be saved & encrypted in prefs
      final storedRaw = prefs.getString('app_sec:migrated_token');
      expect(storedRaw, isNotNull);
      expect(storedRaw!.startsWith('enc:v1:'), isTrue);

      // Legacy item should be cleaned up
      expect(fakeLegacy.store.containsKey('migrated_token'), isFalse);
    });
  });
}

class _FakeFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> store;
  _FakeFlutterSecureStorage([Map<String, String>? initial]) : store = initial ?? {};

  @override
  Future<String?> read({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    return store[key];
  }

  @override
  Future<void> write({required String key, required String? value, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value != null) {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    store.remove(key);
  }

  @override
  Future<bool> containsKey({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    return store.containsKey(key);
  }

  @override
  Future<void> deleteAll({IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    store.clear();
  }
}
