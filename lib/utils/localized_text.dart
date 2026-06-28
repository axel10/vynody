import 'dart:ui';
import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_en.dart';
import '../l10n/app_localizations_zh.dart';

AppLocalizations get currentAppL10n {
  final locale = PlatformDispatcher.instance.locale;
  return locale.languageCode == 'zh' ? AppLocalizationsZh() : AppLocalizationsEn();
}
