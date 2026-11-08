import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/blur_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppBackdropFilter', () {
    testWidgets('renders BackdropFilter when enabled via prop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppBackdropFilter(
            filter: AppBlur.mediumFilter,
            enabled: true,
            child: const Text('Child Content'),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Child Content'), findsOneWidget);
    });

    testWidgets('skips BackdropFilter when disabled via prop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppBackdropFilter(
            filter: AppBlur.mediumFilter,
            enabled: false,
            child: const Text('Child Content'),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Child Content'), findsOneWidget);
    });

    testWidgets('reacts to isBlurEffectEnabledProvider via Riverpod', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      // Explicitly enable blur
      settings.isBlurEffectEnabled = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsServiceProvider.overrideWith((ref) => settings),
          ],
          child: MaterialApp(
            home: AppBackdropFilter(
              filter: AppBlur.mediumFilter,
              child: const Text('Child Content'),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);

      // Disable blur
      settings.isBlurEffectEnabled = false;
      await tester.pumpAndSettle();

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Child Content'), findsOneWidget);
    });
  });
}
