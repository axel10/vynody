import 'dart:ui';

bool isZhLocale([Locale? locale]) {
  final effectiveLocale = locale ?? PlatformDispatcher.instance.locale;
  return effectiveLocale.languageCode.toLowerCase() == 'zh';
}

String localizedText(String zh, String en, {Locale? locale}) {
  return isZhLocale(locale) ? zh : en;
}
