import 'dart:ui';

class LanguageCodeUtils {
  static const String fallbackLanguageCode = 'en';

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
