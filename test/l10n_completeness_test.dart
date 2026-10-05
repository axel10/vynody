import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';

void main() {
  test('All supported locales provide non-empty values for newly added font & model keys', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(l10n.selectLyricsFont, isNotEmpty, reason: '${locale.languageCode}: selectLyricsFont');
      expect(l10n.systemFonts, isNotEmpty, reason: '${locale.languageCode}: systemFonts');
      expect(l10n.recommendedFonts, isNotEmpty, reason: '${locale.languageCode}: recommendedFonts');
      expect(l10n.cjkFonts, isNotEmpty, reason: '${locale.languageCode}: cjkFonts');
      expect(l10n.latinFonts, isNotEmpty, reason: '${locale.languageCode}: latinFonts');
      expect(l10n.allFonts, isNotEmpty, reason: '${locale.languageCode}: allFonts');
      expect(l10n.searchFontHint, isNotEmpty, reason: '${locale.languageCode}: searchFontHint');
      expect(l10n.lyricsFontPreview, isNotEmpty, reason: '${locale.languageCode}: lyricsFontPreview');
      expect(l10n.defaultFontOption, isNotEmpty, reason: '${locale.languageCode}: defaultFontOption');
      expect(l10n.importFontFile, isNotEmpty, reason: '${locale.languageCode}: importFontFile');
      expect(l10n.importedFonts, isNotEmpty, reason: '${locale.languageCode}: importedFonts');
      expect(l10n.noImportedFontsHint, isNotEmpty, reason: '${locale.languageCode}: noImportedFontsHint');
      expect(l10n.deleteFontConfirm('TestFont'), contains('TestFont'), reason: '${locale.languageCode}: deleteFontConfirm');
      expect(l10n.fontImportSuccess, isNotEmpty, reason: '${locale.languageCode}: fontImportSuccess');
      expect(l10n.fontImportFailed, isNotEmpty, reason: '${locale.languageCode}: fontImportFailed');
      expect(l10n.lyricsKaraokeModel, isNotEmpty, reason: '${locale.languageCode}: lyricsKaraokeModel');
      expect(l10n.lyricsKaraokeModelDescription, isNotEmpty, reason: '${locale.languageCode}: lyricsKaraokeModelDescription');
      expect(l10n.lyricsTimelineTitle, isNotEmpty, reason: '${locale.languageCode}: lyricsTimelineTitle');
      expect(l10n.lyricsTimelineSubtitle(10), contains('10'), reason: '${locale.languageCode}: lyricsTimelineSubtitle');
      expect(l10n.lyricsTimelineMaxHistoryLabel, isNotEmpty, reason: '${locale.languageCode}: lyricsTimelineMaxHistoryLabel');
      expect(l10n.lyricsTimelineMaxHistoryDescription, isNotEmpty, reason: '${locale.languageCode}: lyricsTimelineMaxHistoryDescription');
      expect(l10n.lyricsTimelineMaxHistoryCountOption(10), contains('10'), reason: '${locale.languageCode}: lyricsTimelineMaxHistoryCountOption');
      expect(l10n.lyricsTimelineMaxHistoryCountOptionDefault(10), contains('10'), reason: '${locale.languageCode}: lyricsTimelineMaxHistoryCountOptionDefault');
      expect(l10n.lyricsTimelineMaxHistoryCountOptionMax(50), contains('50'), reason: '${locale.languageCode}: lyricsTimelineMaxHistoryCountOptionMax');
      expect(l10n.restoreThisVersion, isNotEmpty, reason: '${locale.languageCode}: restoreThisVersion');
      expect(l10n.noTimelineHistory, isNotEmpty, reason: '${locale.languageCode}: noTimelineHistory');
      expect(l10n.noTimelineHistoryHint, isNotEmpty, reason: '${locale.languageCode}: noTimelineHistoryHint');
      expect(l10n.currentVersion, isNotEmpty, reason: '${locale.languageCode}: currentVersion');
      expect(l10n.timelineActionManualEdit, isNotEmpty, reason: '${locale.languageCode}: timelineActionManualEdit');
      expect(l10n.timelineActionTimelineAdjust, isNotEmpty, reason: '${locale.languageCode}: timelineActionTimelineAdjust');
      expect(l10n.timelineActionOnlineMatch, isNotEmpty, reason: '${locale.languageCode}: timelineActionOnlineMatch');
      expect(l10n.timelineActionImportFile, isNotEmpty, reason: '${locale.languageCode}: timelineActionImportFile');
      expect(l10n.timelineActionAiGenerate, isNotEmpty, reason: '${locale.languageCode}: timelineActionAiGenerate');
      expect(l10n.timelineActionInitial, isNotEmpty, reason: '${locale.languageCode}: timelineActionInitial');
      expect(l10n.timelineActionRestore, isNotEmpty, reason: '${locale.languageCode}: timelineActionRestore');
      expect(l10n.lyricsRestoredSuccess, isNotEmpty, reason: '${locale.languageCode}: lyricsRestoredSuccess');
    }
  });
}
