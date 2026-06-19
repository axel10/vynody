import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService - API Key Cleared Cleanup', () {
    late SettingsService settingsService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'gemini_api_key': 'test-gemini-key',
        'openrouter_api_key': 'test-openrouter-key',
        'lyrics_generation_primary_provider': 'google_ai_studio',
        'lyrics_generation_primary_model_id': 'gemini-1.5-flash',
        'lyrics_generation_fallback_provider': 'openrouter',
        'lyrics_generation_fallback_model_id': 'google/gemini-2.5-flash',
      });
      final prefs = await SharedPreferences.getInstance();
      settingsService = SettingsService(prefs);
    });

    test('clearing geminiApiKey resets matching generationPrimaryModel to empty model ID and fallback provider', () {
      expect(settingsService.generationPrimaryModel.provider, LyricsAiProvider.googleAiStudio);
      expect(settingsService.generationPrimaryModel.modelId, 'gemini-1.5-flash');

      // Clear geminiApiKey
      settingsService.geminiApiKey = '';

      // The provider should fallback to the remaining valid provider (openRouter)
      // and model ID should be cleared to empty string.
      expect(settingsService.generationPrimaryModel.provider, LyricsAiProvider.openRouter);
      expect(settingsService.generationPrimaryModel.modelId, '');
    });

    test('clearing openRouterApiKey resets matching generationFallbackModel to empty model ID and fallback provider', () {
      expect(settingsService.generationFallbackModel.provider, LyricsAiProvider.openRouter);
      expect(settingsService.generationFallbackModel.modelId, 'google/gemini-2.5-flash');

      // Clear openRouterApiKey
      settingsService.openRouterApiKey = '';

      // Since the only remaining valid provider is googleAiStudio (gemini), it should fallback to googleAiStudio.
      expect(settingsService.generationFallbackModel.provider, LyricsAiProvider.googleAiStudio);
      expect(settingsService.generationFallbackModel.modelId, '');
    });
  });

  group('SettingsService - Auto Set Default Models on Adding API Keys', () {
    late SettingsService settingsService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'lyrics_generation_primary_model_id': '',
        'lyrics_translation_primary_model_id': '',
      });
      final prefs = await SharedPreferences.getInstance();
      settingsService = SettingsService(prefs);
    });

    test('setting non-empty geminiApiKey sets missing primary models to gemini defaults', () {
      expect(settingsService.hasApiKeyForProvider(settingsService.generationPrimaryModel.provider), false);
      expect(settingsService.hasApiKeyForProvider(settingsService.translationPrimaryModel.provider), false);

      settingsService.geminiApiKey = 'new-gemini-key';

      expect(settingsService.generationPrimaryModel.provider, LyricsAiProvider.googleAiStudio);
      expect(settingsService.generationPrimaryModel.modelId, SettingsService.defaultGenerationPrimaryModelId);
      expect(settingsService.translationPrimaryModel.provider, LyricsAiProvider.googleAiStudio);
      expect(settingsService.translationPrimaryModel.modelId, SettingsService.defaultTranslationPrimaryModelId);
    });

    test('setting non-empty openRouterApiKey sets missing primary models to openrouter defaults', () {
      expect(settingsService.hasApiKeyForProvider(settingsService.generationPrimaryModel.provider), false);
      expect(settingsService.hasApiKeyForProvider(settingsService.translationPrimaryModel.provider), false);

      settingsService.openRouterApiKey = 'new-openrouter-key';

      expect(settingsService.generationPrimaryModel.provider, LyricsAiProvider.openRouter);
      expect(settingsService.generationPrimaryModel.modelId, SettingsService.defaultOpenRouterGenerationModelId);
      expect(settingsService.translationPrimaryModel.provider, LyricsAiProvider.openRouter);
      expect(settingsService.translationPrimaryModel.modelId, SettingsService.defaultOpenRouterTranslationModelId);
    });

    test('setting non-empty API key does not overwrite already set primary models', () {
      // Start with openRouter key
      settingsService.openRouterApiKey = 'new-openrouter-key';
      expect(settingsService.generationPrimaryModel.provider, LyricsAiProvider.openRouter);
      expect(settingsService.translationPrimaryModel.provider, LyricsAiProvider.openRouter);

      // Now set gemini API key. It should NOT overwrite the openRouter models since they are already set.
      settingsService.geminiApiKey = 'new-gemini-key';

      expect(settingsService.generationPrimaryModel.provider, LyricsAiProvider.openRouter);
      expect(settingsService.translationPrimaryModel.provider, LyricsAiProvider.openRouter);
    });
  });
}
