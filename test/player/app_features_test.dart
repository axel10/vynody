import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/pro/app_channel.dart';
import 'package:vynody/pages/settings/settings_search_registry.dart';
import 'package:vynody/widgets/lyrics_panel.dart';

void main() {
  group('AppFeatures.enableAi', () {
    test('defaults to true and gates AI-related surfaces', () {
      const expected = bool.fromEnvironment('ENABLE_AI', defaultValue: true);
      expect(AppFeatures.enableAi, expected);
      expect(shouldShowGenerateLyricsButton(hasCurrentSong: true), expected);

      const aiSettingIds = {
        'lyrics.translation_language',
        'lyrics.google_ai_key',
        'lyrics.openrouter_key',
        'lyrics.doubao_key',
        'lyrics.deepseek_key',
        'lyrics.custom_provider',
        'lyrics.models',
      };
      final indexedIds = settingsSearchRegistry.map((item) => item.id).toSet();
      if (expected) {
        expect(indexedIds.containsAll(aiSettingIds), isTrue);
      } else {
        expect(indexedIds.intersection(aiSettingIds), isEmpty);
      }
    });
  });
}
