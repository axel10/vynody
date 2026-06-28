import 'dart:ui';
import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_en.dart';
import '../l10n/app_localizations_zh.dart';

abstract final class LocalizedText {
  static String? overrideLanguageCode;
}

AppLocalizations get currentAppL10n {
  final code = LocalizedText.overrideLanguageCode;
  final isZh = code == 'zh' || (code != 'en' && PlatformDispatcher.instance.locale.languageCode == 'zh');
  return isZh ? AppLocalizationsZh() : AppLocalizationsEn();
}
