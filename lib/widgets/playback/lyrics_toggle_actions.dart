import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';
import 'package:vynody/dialogs/ai_guide_dialog.dart';
import 'package:vynody/dialogs/lyrics_model_recommendation_dialog.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/lyrics/lyrics_riverpod.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/pro/pro_models.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import '../../l10n/app_localizations.dart';

/// 「歌词翻译」与「逐字歌词」开关的共用处理逻辑。
///
/// 竖屏歌词模式播控组件上方的按钮与横屏歌词模式标题右侧的更多菜单共用，
/// 已有翻译/逐字数据时直接切换开关，否则引导用户生成。
Future<void> handleLyricsTranslationTap(
  BuildContext context,
  WidgetRef ref,
  MusicFile? currentMusic,
  AppLocalizations l10n,
) async {
  if (currentMusic == null) return;
  final lyricsController = ref.read(lyricsControllerProvider.notifier);
  final taskState = lyricsController.taskStateForSong(currentMusic.path);
  if (taskState.isTranslationBusy) {
    showToast(l10n.songAlreadyQueuedForTranslation);
    return;
  }

  final lyricsState = ref.read(lyricsControllerProvider);
  final displayLyrics = lyricsController.currentLyricsForCurrentSong();
  final targetLang = lyricsState.lyricsTranslationLanguageCode;
  final effectiveLang =
      displayLyrics?.getEffectiveTranslationLanguage(targetLang) ?? targetLang;
  final translation = displayLyrics?.translationFor(effectiveLang);
  final hasTranslation = translation != null && translation.hasContent;

  if (hasTranslation) {
    final settings = ref.read(settingsServiceProvider);
    final nextState = !settings.showLyricsTranslation;
    settings.showLyricsTranslation = nextState;
    showToast(nextState ? l10n.lyricsTranslationEnabled : l10n.lyricsTranslationDisabled);
    return;
  }

  if (!lyricsState.hasLyrics &&
      (displayLyrics == null || displayLyrics.plainText.trim().isEmpty)) {
    showToast(l10n.noLyricsAvailableForTranslation);
    return;
  }

  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.translateLyrics),
      content: Text(l10n.noTranslationAiPrompt),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.confirm),
        ),
      ],
    ),
  );

  if (confirm != true || !context.mounted) return;

  if (!await checkProGate(context, ref, feature: ProFeature.aiTranslation)) {
    return;
  }
  if (!context.mounted) return;
  if (await ensureGeminiApiKey(context, ref)) {
    if (!context.mounted) return;
    ref.read(settingsServiceProvider).showLyricsTranslation = true;
    final errorMessage =
        await lyricsController.translateLyricsForCurrentSong();
    if (errorMessage != null && context.mounted) {
      AppSnackBar.show(context, ref, SnackBar(content: Text(errorMessage)));
    }
  }
}

Future<void> handleLyricsWordByWordTap(
  BuildContext context,
  WidgetRef ref,
  MusicFile? currentMusic,
  AppLocalizations l10n,
) async {
  if (currentMusic == null) return;
  final lyricsController = ref.read(lyricsControllerProvider.notifier);
  final taskState = lyricsController.taskStateForSong(currentMusic.path);
  if (taskState.isGenerationBusy) {
    showToast(l10n.convertingToKaraoke);
    return;
  }

  final displayLyrics = lyricsController.currentLyricsForCurrentSong();
  final syncedLines = displayLyrics?.syncedLines ?? const [];
  final hasWordByWord = syncedLines
      .any((line) => line.words != null && line.words!.isNotEmpty);
  final hasTimedLyrics = syncedLines.any((line) => line.isTimed);

  if (hasWordByWord) {
    final settings = ref.read(settingsServiceProvider);
    final nextState = !settings.showLyricsWordByWord;
    settings.showLyricsWordByWord = nextState;
    showToast(
      nextState
          ? l10n.wordByWordLyricsEnabled
          : l10n.wordByWordLyricsDisabled,
    );
    return;
  }

  if (!hasTimedLyrics) {
    showToast(l10n.karaokeRequiresSyncedLyrics);
    return;
  }

  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.convertToKaraoke),
      content: Text(l10n.noKaraokeAiPrompt),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.confirm),
        ),
      ],
    ),
  );

  if (confirm != true || !context.mounted) return;

  if (!await checkProGate(context, ref, feature: ProFeature.aiLyrics)) return;
  if (!context.mounted) return;
  if (await ensureLyricsGenerationApiKey(context, ref)) {
    if (!context.mounted) return;
    if (!await ensureLyricsKaraokeModelRecommendation(context, ref)) return;
    if (!context.mounted) return;
    ref.read(settingsServiceProvider).showLyricsWordByWord = true;
    final errorMessage =
        await lyricsController.convertToKaraokeLyricsForCurrentSong();
    if (errorMessage != null && context.mounted) {
      AppSnackBar.show(context, ref, SnackBar(content: Text(errorMessage)));
    }
  }
}
