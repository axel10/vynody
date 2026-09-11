import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/dialogs/lyrics_model_recommendation_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestApp({
    required Widget child,
    required ProviderContainer container,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: child),
      ),
    );
  }

  group('LyricsModelRecommendationDialog', () {
    testWidgets('renders current and recommended model info', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: LyricsModelRecommendationDialog(
              currentModelId: 'gemini-2.5-flash',
              recommendedModelId: 'gemini-3.1-flash-lite',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('非推荐模型提醒'), findsOneWidget);
      expect(find.textContaining('gemini-2.5-flash'), findsOneWidget);
      expect(find.textContaining('gemini-3.1-flash-lite'), findsOneWidget);
      expect(find.text('以后不再弹出'), findsOneWidget);
      expect(find.text('中止'), findsOneWidget);
      expect(find.text('继续生成'), findsOneWidget);
      expect(find.text('换成推荐模型'), findsOneWidget);
    });

    testWidgets('tapping abort returns abort action with checkbox state', (tester) async {
      LyricsModelRecommendationResult? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<LyricsModelRecommendationResult>(
                  context: context,
                  builder: (_) => const LyricsModelRecommendationDialog(
                    currentModelId: 'gemini-flash-lite-latest',
                    recommendedModelId: 'gemini-3.1-flash-lite',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Tap the checkbox to toggle do-not-show-again
      await tester.tap(find.text('以后不再弹出'));
      await tester.pumpAndSettle();

      // Tap abort
      await tester.tap(find.text('中止'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.action, LyricsModelRecommendationAction.abort);
      expect(result!.doNotShowAgain, isTrue);
    });

    testWidgets('tapping switch returns switchToRecommended action', (tester) async {
      LyricsModelRecommendationResult? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<LyricsModelRecommendationResult>(
                  context: context,
                  builder: (_) => const LyricsModelRecommendationDialog(
                    currentModelId: 'gemini-flash-lite-latest',
                    recommendedModelId: 'gemini-3.1-flash-lite',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('换成推荐模型'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.action, LyricsModelRecommendationAction.switchToRecommended);
      expect(result!.doNotShowAgain, isFalse);
    });
  });

  group('ensureLyricsGenerationModelRecommendation', () {
    late SharedPreferences prefs;
    late SettingsService settings;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      settings = SettingsService(prefs);
      container = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    testWidgets('returns true without dialog when model is already gemini-3.1-flash-lite', (tester) async {
      settings.generationPrimaryModel = const LyricsAiModelSelection(
        provider: LyricsAiProvider.googleAiStudio,
        modelId: 'gemini-3.1-flash-lite',
      );

      bool? allowed;
      await tester.pumpWidget(
        buildTestApp(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () async {
                allowed = await ensureLyricsGenerationModelRecommendation(context, ref);
              },
              child: const Text('check'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(allowed, isTrue);
      expect(find.text('非推荐模型提醒'), findsNothing);
    });

    testWidgets('switches model and returns true when user selects switchAndGenerate', (tester) async {
      settings.generationPrimaryModel = const LyricsAiModelSelection(
        provider: LyricsAiProvider.googleAiStudio,
        modelId: 'gemini-flash-lite-latest',
      );

      bool? allowed;
      await tester.pumpWidget(
        buildTestApp(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () async {
                allowed = await ensureLyricsGenerationModelRecommendation(context, ref);
              },
              child: const Text('check'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(find.text('非推荐模型提醒'), findsOneWidget);

      await tester.tap(find.text('换成推荐模型'));
      await tester.pumpAndSettle();

      expect(allowed, isTrue);
      expect(settings.generationPrimaryModel.modelId, 'gemini-3.1-flash-lite');
    });

    testWidgets('returns false when user selects abort', (tester) async {
      settings.generationPrimaryModel = const LyricsAiModelSelection(
        provider: LyricsAiProvider.googleAiStudio,
        modelId: 'gemini-2.5-flash',
      );

      bool? allowed;
      await tester.pumpWidget(
        buildTestApp(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () async {
                allowed = await ensureLyricsGenerationModelRecommendation(context, ref);
              },
              child: const Text('check'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(find.text('非推荐模型提醒'), findsOneWidget);

      await tester.tap(find.text('中止'));
      await tester.pumpAndSettle();

      expect(allowed, isFalse);
      expect(settings.generationPrimaryModel.modelId, 'gemini-2.5-flash');
    });

    testWidgets('skips dialog when ignoreNonRecommendedLyricsModelWarning is true', (tester) async {
      settings.generationPrimaryModel = const LyricsAiModelSelection(
        provider: LyricsAiProvider.googleAiStudio,
        modelId: 'gemini-2.5-flash',
      );
      settings.ignoreNonRecommendedLyricsModelWarning = true;

      bool? allowed;
      await tester.pumpWidget(
        buildTestApp(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () async {
                allowed = await ensureLyricsGenerationModelRecommendation(context, ref);
              },
              child: const Text('check'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(allowed, isTrue);
      expect(find.text('非推荐模型提醒'), findsNothing);
    });

    testWidgets('OpenRouter: returns true without dialog when model is google/gemini-3.1-flash-lite', (tester) async {
      settings.generationPrimaryModel = const LyricsAiModelSelection(
        provider: LyricsAiProvider.openRouter,
        modelId: 'google/gemini-3.1-flash-lite',
      );

      bool? allowed;
      await tester.pumpWidget(
        buildTestApp(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () async {
                allowed = await ensureLyricsGenerationModelRecommendation(context, ref);
              },
              child: const Text('check'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(allowed, isTrue);
      expect(find.text('非推荐模型提醒'), findsNothing);
    });

    testWidgets('OpenRouter: warns and switches to google/gemini-3.1-flash-lite', (tester) async {
      settings.generationPrimaryModel = const LyricsAiModelSelection(
        provider: LyricsAiProvider.openRouter,
        modelId: 'openai/gpt-4o',
      );

      bool? allowed;
      await tester.pumpWidget(
        buildTestApp(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () async {
                allowed = await ensureLyricsGenerationModelRecommendation(context, ref);
              },
              child: const Text('check'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();

      expect(find.text('非推荐模型提醒'), findsOneWidget);
      expect(find.textContaining('openai/gpt-4o'), findsOneWidget);
      expect(find.textContaining('google/gemini-3.1-flash-lite'), findsOneWidget);

      await tester.tap(find.text('换成推荐模型'));
      await tester.pumpAndSettle();

      expect(allowed, isTrue);
      expect(settings.generationPrimaryModel.modelId, 'google/gemini-3.1-flash-lite');
    });
  });
}

