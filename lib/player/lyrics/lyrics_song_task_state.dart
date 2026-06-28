import 'dart:ui';

import 'package:vynody/player/lyrics/lyrics_generation_phase.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/l10n/app_localizations_en.dart';
import 'package:vynody/l10n/app_localizations_zh.dart';

AppLocalizations _l10n() {
  return PlatformDispatcher.instance.locale.languageCode == 'zh' 
      ? AppLocalizationsZh() 
      : AppLocalizationsEn();
}

class LyricsSongTaskState {
  const LyricsSongTaskState({
    this.isLoading = false,
    this.isGenerationQueued = false,
    this.isGenerationRunning = false,
    this.generationPhase = LyricsGenerationPhase.idle,
    this.generationProgress = 0.0,
    this.generationStatus = '',
    this.isTranslationQueued = false,
    this.isTranslationRunning = false,
    this.translationStatus = '',
  });

  final bool isLoading;
  final bool isGenerationQueued;
  final bool isGenerationRunning;
  final LyricsGenerationPhase generationPhase;
  final double generationProgress;
  final String generationStatus;
  final bool isTranslationQueued;
  final bool isTranslationRunning;
  final String translationStatus;

  bool get isGenerationBusy => isGenerationQueued || isGenerationRunning;
  bool get isTranslationBusy => isTranslationQueued || isTranslationRunning;
  bool get isAnyBusy => isLoading || isGenerationBusy || isTranslationBusy;

  String get activeStatusLabel {
    final generationLabel = generationStatus.trim();
    if (isGenerationBusy) {
      if (generationLabel.isNotEmpty) {
        return generationLabel;
      }
      return switch (generationPhase) {
        LyricsGenerationPhase.transcoding =>
          _l10n().transcodingSongFile,
        LyricsGenerationPhase.uploading =>
          _l10n().uploadingSongFile,
        LyricsGenerationPhase.processing =>
          _l10n().waitingForFileReadiness,
        LyricsGenerationPhase.requesting =>
          _l10n().requestingModelResponse,
        LyricsGenerationPhase.generating =>
          _l10n().generatingLyrics,
        LyricsGenerationPhase.retrying => _l10n().retrying,
        LyricsGenerationPhase.idle => _l10n().processing,
      };
    }

    final translationLabel = translationStatus.trim();
    if (isTranslationBusy) {
      return translationLabel.isNotEmpty
          ? translationLabel
          : _l10n().translatingLyrics;
    }

    return '';
  }

  LyricsSongTaskState copyWith({
    bool? isLoading,
    bool? isGenerationQueued,
    bool? isGenerationRunning,
    LyricsGenerationPhase? generationPhase,
    double? generationProgress,
    String? generationStatus,
    bool? isTranslationQueued,
    bool? isTranslationRunning,
    String? translationStatus,
  }) {
    return LyricsSongTaskState(
      isLoading: isLoading ?? this.isLoading,
      isGenerationQueued: isGenerationQueued ?? this.isGenerationQueued,
      isGenerationRunning: isGenerationRunning ?? this.isGenerationRunning,
      generationPhase: generationPhase ?? this.generationPhase,
      generationProgress: generationProgress ?? this.generationProgress,
      generationStatus: generationStatus ?? this.generationStatus,
      isTranslationQueued: isTranslationQueued ?? this.isTranslationQueued,
      isTranslationRunning: isTranslationRunning ?? this.isTranslationRunning,
      translationStatus: translationStatus ?? this.translationStatus,
    );
  }
}
