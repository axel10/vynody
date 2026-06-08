import 'dart:ui';

class LanguageCodeUtils {
  static const String fallbackLanguageCode = 'en';
  static const List<String> supportedTranslationLanguageCodes = <String>[
    'zh-cn',
    'zh-tw',
    'en',
    'ja',
    'ko',
    'fr',
    'de',
    'es',
    'pt',
    'ru',
  ];

  static String currentSystemLanguageCode() {
    final locale = PlatformDispatcher.instance.locale;
    final normalized = normalizeLanguageCode(_localeToRawCode(locale));
    return normalized.isEmpty ? fallbackLanguageCode : normalized;
  }

  static String normalizeLanguageCode(String? languageCode) {
    final text = languageCode?.trim().replaceAll('_', '-').toLowerCase() ?? '';
    if (text.isEmpty) return '';

    final parts = text.split('-').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '';

    final base = parts.first;
    if (base != 'zh') {
      return base;
    }

    final hasTraditionalMarker = parts.any(
      (part) => part == 'hant' || part == 'tw' || part == 'hk' || part == 'mo',
    );
    return hasTraditionalMarker ? 'zh-tw' : 'zh-cn';
  }

  static String languageDisplayName(String languageCode) {
    final normalized = normalizeLanguageCode(languageCode);
    final isZh = PlatformDispatcher.instance.locale.languageCode == 'zh';

    switch (normalized) {
      case 'zh-cn':
        return isZh ? '简体中文' : 'Simplified Chinese';
      case 'zh-tw':
        return isZh ? '繁体中文' : 'Traditional Chinese';
      case 'en':
        return isZh ? '英文' : 'English';
      case 'ja':
        return isZh ? '日文' : 'Japanese';
      case 'ko':
        return isZh ? '韩文' : 'Korean';
      case 'fr':
        return isZh ? '法文' : 'French';
      case 'de':
        return isZh ? '德文' : 'German';
      case 'es':
        return isZh ? '西班牙文' : 'Spanish';
      case 'pt':
        return isZh ? '葡萄牙文' : 'Portuguese';
      case 'ru':
        return isZh ? '俄文' : 'Russian';
      default:
        return normalized.isEmpty
            ? (isZh ? '系统语言' : 'System language')
            : languageCode;
    }
  }

  static String _localeToRawCode(Locale locale) {
    final languageCode = locale.languageCode.trim();
    final scriptCode = locale.scriptCode?.trim();
    final countryCode = locale.countryCode?.trim();

    final parts = <String>[
      if (languageCode.isNotEmpty) languageCode,
      if (scriptCode != null && scriptCode.isNotEmpty) scriptCode,
      if (countryCode != null && countryCode.isNotEmpty) countryCode,
    ];
    return parts.join('-');
  }
}
