import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_flow/player/settings/settings_service.dart';

void main() {
  group('LyricsModelRecommendation - Google AI Studio', () {
    test('gemini-flash version >= 2.5 is recommended', () {
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-2.5-flash'), isTrue);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-3.0-flash'), isTrue);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-3.5-flash'), isTrue);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-3.5-flash-exp'), isTrue);
    });

    test('gemini-flash version < 2.5 is not recommended', () {
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-1.5-flash'), isFalse);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-2.0-flash'), isFalse);
    });

    test('gemini-flash-lite version >= 3.1 is recommended', () {
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-3.1-flash-lite'), isTrue);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-3.5-flash-lite'), isTrue);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-3.5-flash-lite-preview'), isTrue);
    });

    test('gemini-flash-lite version < 3.1 is not recommended', () {
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-1.5-flash-lite'), isFalse);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-3.0-flash-lite'), isFalse);
    });

    test('latest flash and flash-lite models are recommended', () {
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-flash-latest'), isTrue);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-flash-lite-latest'), isTrue);
    });

    test('gemma version >= 4.0 is recommended', () {
      expect(LyricsModelRecommendation.isGoogleRecommended('gemma-4-31b-it'), isTrue);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemma-4.5-pro'), isTrue);
    });

    test('gemma version < 4.0 or without matching version pattern is not recommended', () {
      expect(LyricsModelRecommendation.isGoogleRecommended('gemma-2-27b-it'), isFalse);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemma-2b-it'), isFalse);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemma-7b-it'), isFalse);
    });

    test('models containing "image" or "tts" are not recommended', () {
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-2.5-flash-image'), isFalse);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-3.5-flash-lite-image'), isFalse);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemma-4-31b-it-image'), isFalse);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-2.5-flash-tts'), isFalse);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-3.5-flash-lite-tts'), isFalse);
      expect(LyricsModelRecommendation.isGoogleRecommended('gemma-4-31b-it-tts'), isFalse);
    });

    test('other models are not recommended', () {
      expect(LyricsModelRecommendation.isGoogleRecommended('gemini-1.5-pro'), isFalse);
    });
  });

  group('LyricsModelRecommendation - OpenRouter', () {
    test('matches Google rules with google/ or ~google/ prefix', () {
      expect(LyricsModelRecommendation.isOpenRouterRecommended('google/gemini-2.5-flash'), isTrue);
      expect(LyricsModelRecommendation.isOpenRouterRecommended('~google/gemini-flash-latest'), isTrue);
      expect(LyricsModelRecommendation.isOpenRouterRecommended('google/gemini-3.1-flash-lite'), isTrue);
      expect(LyricsModelRecommendation.isOpenRouterRecommended('google/gemini-3.5-flash:free'), isTrue);
      expect(LyricsModelRecommendation.isOpenRouterRecommended('google/gemma-4-31b-it'), isTrue);
      
      expect(LyricsModelRecommendation.isOpenRouterRecommended('google/gemini-1.5-flash'), isFalse);
      expect(LyricsModelRecommendation.isOpenRouterRecommended('google/gemini-1.5-flash-lite'), isFalse);
      expect(LyricsModelRecommendation.isOpenRouterRecommended('google/gemma-2-27b-it'), isFalse);
      expect(LyricsModelRecommendation.isOpenRouterRecommended('google/gemini-2.5-flash-image'), isFalse);
      expect(LyricsModelRecommendation.isOpenRouterRecommended('google/gemini-2.5-flash-tts'), isFalse);
      expect(LyricsModelRecommendation.isOpenRouterRecommended('meta-llama/llama-3-8b'), isFalse);
    });
  });

  group('LyricsModelRecommendation - Doubao', () {
    test('doubao-seed >= 2.0 with lite/mini/pro suffix is recommended', () {
      expect(LyricsModelRecommendation.isDoubaoRecommended('doubao-seed-2-0-lite-260428'), isTrue);
      expect(LyricsModelRecommendation.isDoubaoRecommended('doubao-seed-2-0-pro-260428'), isTrue);
      expect(LyricsModelRecommendation.isDoubaoRecommended('doubao-seed-3-0-mini-12345'), isTrue);
      expect(LyricsModelRecommendation.isDoubaoRecommended('doubao-seed-2-5-pro'), isTrue);
      expect(LyricsModelRecommendation.isDoubaoRecommended('doubao-seed-2.0-lite'), isTrue);
    });

    test('doubao-seed < 2.0 or other suffixes is not recommended', () {
      expect(LyricsModelRecommendation.isDoubaoRecommended('doubao-seed-1-5-lite'), isFalse);
      expect(LyricsModelRecommendation.isDoubaoRecommended('doubao-seed-2-0-ultra'), isFalse);
      expect(LyricsModelRecommendation.isDoubaoRecommended('doubao-pro-123'), isFalse);
    });
  });

  group('LyricsModelRecommendation - General Provider Dispatcher', () {
    test('deepseek always recommended', () {
      expect(LyricsModelRecommendation.isRecommended('deepseek-chat', LyricsAiProvider.deepseek), isTrue);
      expect(LyricsModelRecommendation.isRecommended('deepseek-coder', LyricsAiProvider.deepseek), isTrue);
    });

    test('correctly dispatches to providers', () {
      expect(LyricsModelRecommendation.isRecommended('gemini-2.5-flash', LyricsAiProvider.googleAiStudio), isTrue);
      expect(LyricsModelRecommendation.isRecommended('google/gemini-2.5-flash', LyricsAiProvider.openRouter), isTrue);
      expect(LyricsModelRecommendation.isRecommended('doubao-seed-2-0-lite', LyricsAiProvider.doubao), isTrue);
    });
  });
}
