import 'lyrics_generation_phase.dart';

class LyricsGenerationDisplayState {
  const LyricsGenerationDisplayState({
    this.songPath,
    this.statusLabel = '',
    this.modelLabel = '',
    this.phase = LyricsGenerationPhase.idle,
    this.progress = 0.0,
  });

  final String? songPath;
  final String statusLabel;
  final String modelLabel;
  final LyricsGenerationPhase phase;
  final double progress;

  String get providerLabel {
    final label = modelLabel.trim();
    if (label.isEmpty) return '';

    final delimiterIndex = label.indexOf(' · ');
    if (delimiterIndex <= 0) return label;
    return label.substring(0, delimiterIndex).trim();
  }

  String get modelNameLabel {
    final label = modelLabel.trim();
    if (label.isEmpty) return '';

    final delimiterIndex = label.indexOf(' · ');
    if (delimiterIndex < 0) return label;
    return label.substring(delimiterIndex + 3).trim();
  }

  bool get isBusy =>
      statusLabel.trim().isNotEmpty ||
      modelLabel.trim().isNotEmpty ||
      phase != LyricsGenerationPhase.idle;

  @override
  bool operator ==(Object other) {
    return other is LyricsGenerationDisplayState &&
        other.songPath == songPath &&
        other.statusLabel == statusLabel &&
        other.modelLabel == modelLabel &&
        other.phase == phase &&
        other.progress == progress;
  }

  @override
  int get hashCode =>
      Object.hash(songPath, statusLabel, modelLabel, phase, progress);

  LyricsGenerationDisplayState copyWith({
    String? songPath,
    bool clearSongPath = false,
    String? statusLabel,
    String? modelLabel,
    LyricsGenerationPhase? phase,
    double? progress,
  }) {
    return LyricsGenerationDisplayState(
      songPath: clearSongPath ? null : songPath ?? this.songPath,
      statusLabel: statusLabel ?? this.statusLabel,
      modelLabel: modelLabel ?? this.modelLabel,
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
    );
  }
}
