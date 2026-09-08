import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/dialogs/progress_bar_style_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
  });

  group('ProgressBarLivePreview', () {
    testWidgets('renders fullWaveform preview without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressBarLivePreview(
              style: ProgressBarStyle.fullWaveform,
              isDark: true,
            ),
          ),
        ),
      );

      expect(find.byType(ProgressBarLivePreview), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders scrollingWaveform preview without error',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressBarLivePreview(
              style: ProgressBarStyle.scrollingWaveform,
              isDark: false,
            ),
          ),
        ),
      );

      expect(find.byType(ProgressBarLivePreview), findsOneWidget);
    });

    testWidgets('renders standard slider preview without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressBarLivePreview(
              style: ProgressBarStyle.standard,
              isDark: false,
            ),
          ),
        ),
      );

      expect(find.byType(ProgressBarLivePreview), findsOneWidget);
    });
  });

  group('ProgressBarStyleDialog', () {
    testWidgets('renders options and switches styles when unlocked',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          isProUnlockedProvider.overrideWith((ref) => true),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ProgressBarStyleDialog(
                settings: settings,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Check all 3 style options exist
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
      expect(find.byIcon(Icons.waves_rounded), findsOneWidget);
      expect(find.byIcon(Icons.linear_scale_rounded), findsOneWidget);

      // Tap standard style
      await tester.tap(find.byIcon(Icons.linear_scale_rounded));
      await tester.pump(const Duration(milliseconds: 200));
      expect(settings.progressBarStyle, equals(ProgressBarStyle.standard));

      // Tap scrollingWaveform style
      await tester.tap(find.byIcon(Icons.waves_rounded));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        settings.progressBarStyle,
        equals(ProgressBarStyle.scrollingWaveform),
      );
    });

    testWidgets('shows recommended tag on scrollingWaveform for Android',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          isProUnlockedProvider.overrideWith((ref) => true),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ProgressBarStyleDialog(
                settings: settings,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ProgressBarStyleDialog)),
      )!;
      expect(find.text(l10n.onboardingRecommendedTag), findsOneWidget);

      final firstStyleFinder = find.descendant(
        of: find.byType(InkWell).first,
        matching: find.text(l10n.progressBarStyleScrollingWaveform),
      );
      expect(firstStyleFinder, findsOneWidget);
    });

    testWidgets('shows recommended tag on fullWaveform for Desktop',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          isProUnlockedProvider.overrideWith((ref) => true),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ProgressBarStyleDialog(
                settings: settings,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ProgressBarStyleDialog)),
      )!;
      expect(find.text(l10n.onboardingRecommendedTag), findsOneWidget);

      final firstStyleFinder = find.descendant(
        of: find.byType(InkWell).first,
        matching: find.text(l10n.progressBarStyleFullWaveform),
      );
      expect(firstStyleFinder, findsOneWidget);
    });
  });
}
