import 'lyrics_generation_phase.dart';

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
