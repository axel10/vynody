import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibe_flow/player/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService.geminiModelDisplayName', () {
    test('formats default primary model correctly', () {
      expect(
        SettingsService.geminiModelDisplayName('gemini-3.1-flash-lite-preview'),
        'Gemini 3.1 Flash Lite Preview',
      );
    });

    test('formats default fallback model correctly', () {
      expect(
        SettingsService.geminiModelDisplayName('gemini-2.5-flash'),
        'Gemini 2.5 Flash',
      );
    });

    test('formats unrecognized/custom translation model ID correctly (hyphens replaced, title-cased)', () {
      expect(
        SettingsService.geminiModelDisplayName('gemma-4-31b-it'),
        'Gemma 4 31b It',
      );
    });

    test('formats other unrecognized model IDs correctly', () {
      expect(
        SettingsService.geminiModelDisplayName('deepseek-r1-llama-70b'),
        'Deepseek R1 Llama 70b',
      );
      expect(
        SettingsService.geminiModelDisplayName('claude-3-5-sonnet-latest'),
        'Claude 3 5 Sonnet Latest',
      );
    });

    test('handles empty model ID correctly', () {
      final displayName = SettingsService.geminiModelDisplayName('');
      expect(
        displayName == '未选择模型' || displayName == 'No model selected',
        isTrue,
      );
    });
  });

  group('SettingsService translation model', () {
    test('initializes with default value', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      expect(settings.geminiTranslationModelId, 'gemma-4-31b-it');
    });

    test('saves and loads custom value', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      settings.geminiTranslationModelId = 'custom-model';
      expect(settings.geminiTranslationModelId, 'custom-model');
      expect(prefs.getString('gemini_translation_model_id'), 'custom-model');

      final settingsReloaded = SettingsService(prefs);
      expect(settingsReloaded.geminiTranslationModelId, 'custom-model');
    });

    test('resets to default value', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      settings.geminiTranslationModelId = 'custom-model';
      settings.resetGeminiModels();
      expect(settings.geminiTranslationModelId, 'gemma-4-31b-it');
    });
  });
}
