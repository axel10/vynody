import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/utils/platform_secure_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformSecureVault Tests', () {
    test('read, write, delete with injected secure storage backend', () async {
      final fakeStorage = _FakeSecureStorage();
      final vault = PlatformSecureVault(secureStorage: fakeStorage);

      expect(await vault.read('test_key'), isNull);

      await vault.write('test_key', 'hello_world');
      expect(await vault.read('test_key'), 'hello_world');
      expect(fakeStorage.store['test_key'], 'hello_world');

      await vault.delete('test_key');
      expect(await vault.read('test_key'), isNull);
      expect(fakeStorage.store.containsKey('test_key'), isFalse);
    });
  });
}

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return store[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return store.containsKey(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.clear();
  }
}
