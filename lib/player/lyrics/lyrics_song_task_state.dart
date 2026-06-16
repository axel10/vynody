import 'package:flutter/widgets.dart';

import 'package:vynody/player/lyrics/lyrics_generation_phase.dart';

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
    final isZh =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh';
    if (isGenerationBusy) {
      if (generationLabel.isNotEmpty) {
        return generationLabel;
      }
      return switch (generationPhase) {
        LyricsGenerationPhase.uploading =>
          isZh ? '正在上传歌曲文件' : 'Uploading song file',
        LyricsGenerationPhase.processing =>
          isZh ? '正在等待文件就绪' : 'Waiting for file readiness',
        LyricsGenerationPhase.requesting =>
          isZh ? '正在请求模型响应' : 'Requesting model response',
        LyricsGenerationPhase.generating =>
          isZh ? '正在生成歌词' : 'Generating lyrics',
        LyricsGenerationPhase.retrying => isZh ? '正在重试' : 'Retrying',
        LyricsGenerationPhase.idle => isZh ? '正在处理' : 'Processing',
      };
    }

    final translationLabel = translationStatus.trim();
    if (isTranslationBusy) {
      return translationLabel.isNotEmpty
          ? translationLabel
          : (isZh ? '正在翻译歌词' : 'Translating lyrics');
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
