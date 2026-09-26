import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/settings/shortcut_bindings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StandaloneQueue Shortcut serialization and binding tests', () {
    test('AppShortcutAction to/from storage key', () {
      for (final action in AppShortcutAction.values) {
        final key = action.storageKey;
        final decoded = AppShortcutActionX.fromStorageKey(key);
        expect(decoded, equals(action));
      }
    });

    test('ShortcutBinding serialization roundtrip', () {
      const binding = ShortcutBinding(
        keyId: 0x00000020, // space
        control: true,
        shift: false,
        alt: false,
        meta: false,
      );

      final json = binding.toJson();
      final recovered = ShortcutBinding.fromJson(json);

      expect(recovered, isNotNull);
      expect(recovered!.keyId, equals(binding.keyId));
      expect(recovered.control, isTrue);
      expect(recovered.shift, isFalse);
    });

    test('All AppShortcutActions have default activator', () {
      for (final action in AppShortcutAction.values) {
        final activator = action.defaultBinding.toActivator();
        expect(activator, isNotNull);
      }
    });
  });
}
