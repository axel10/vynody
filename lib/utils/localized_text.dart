import 'dart:ui';
import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

abstract final class LocalizedText {
  static String? overrideLanguageCode;
}

AppLocalizations get currentAppL10n {
  final code = LocalizedText.overrideLanguageCode;
  final langCode = (code != null && code != 'system' && code.isNotEmpty)
      ? code
      : PlatformDispatcher.instance.locale.languageCode;
  try {
    if (langCode == 'zh_Hant') {
      return lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
    }
    return lookupAppLocalizations(Locale(langCode));
  } catch (_) {
    return lookupAppLocalizations(const Locale('en'));
  }
}
