import 'package:audio_core/audio_core.dart';

enum TranscodeQualityTier { low, medium, high, extreme }

extension TranscodeQualityTierX on TranscodeQualityTier {
  String get storageValue => switch (this) {
    TranscodeQualityTier.low => 'low',
    TranscodeQualityTier.medium => 'medium',
    TranscodeQualityTier.high => 'high',
    TranscodeQualityTier.extreme => 'extreme',
  };

  static TranscodeQualityTier fromStorageValue(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'low' => TranscodeQualityTier.low,
      'medium' => TranscodeQualityTier.medium,
      'high' => TranscodeQualityTier.high,
      'extreme' => TranscodeQualityTier.extreme,
      _ => TranscodeQualityTier.high,
    };
  }
}

extension AudioFormatDisplayX on AudioFormat {
  String get displayName => switch (this) {
    AudioFormat.aac => 'AAC',
    AudioFormat.alac => 'ALAC',
    AudioFormat.aiff => 'AIFF',
    AudioFormat.caf => 'CAF',
    AudioFormat.flac => 'FLAC',
    AudioFormat.m4a => 'M4A',
    AudioFormat.m4b => 'M4B',
    AudioFormat.mp3 => 'MP3',
    AudioFormat.ogg => 'OGG',
    AudioFormat.opus => 'Opus',
    AudioFormat.wav => 'WAV',
  };

  bool get supportsBitRateControls => switch (this) {
    AudioFormat.alac ||
    AudioFormat.aiff ||
    AudioFormat.flac ||
    AudioFormat.wav => false,
    _ => true,
  };
}

enum TranscodeValueOrigin { presetDerived, customized }

class TranscodeResolvedPreset {
  const TranscodeResolvedPreset({
    required this.qualityTier,
    required this.outputFormat,
    required this.bitRate,
    required this.bitRateMode,
    this.sampleRate,
    this.channels,
  });

  final TranscodeQualityTier qualityTier;
  final AudioFormat outputFormat;
  final int bitRate;
  final BitRateMode bitRateMode;
  final int? sampleRate;
  final int? channels;
}

class TranscodeDraft {
  const TranscodeDraft({
    required this.outputFormat,
    required this.qualityTier,
    required this.bitRate,
    required this.bitRateMode,
    required this.valueOrigin,
    this.sampleRate,
    this.channels,
    this.outputDirectory,
    this.showAdvancedOptions = false,
  });

  final AudioFormat outputFormat;
  final TranscodeQualityTier qualityTier;
  final int bitRate;
  final BitRateMode bitRateMode;
  final int? sampleRate;
  final int? channels;
  final String? outputDirectory;
  final bool showAdvancedOptions;
  final TranscodeValueOrigin valueOrigin;

  bool get isCustomized => valueOrigin == TranscodeValueOrigin.customized;

  TranscodeDraft copyWith({
    AudioFormat? outputFormat,
    TranscodeQualityTier? qualityTier,
    int? bitRate,
    BitRateMode? bitRateMode,
    int? sampleRate,
    int? channels,
    Object? outputDirectory = _sentinel,
    bool? showAdvancedOptions,
    TranscodeValueOrigin? valueOrigin,
  }) {
    return TranscodeDraft(
      outputFormat: outputFormat ?? this.outputFormat,
      qualityTier: qualityTier ?? this.qualityTier,
      bitRate: bitRate ?? this.bitRate,
      bitRateMode: bitRateMode ?? this.bitRateMode,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      outputDirectory: identical(outputDirectory, _sentinel)
          ? this.outputDirectory
          : outputDirectory as String?,
      showAdvancedOptions: showAdvancedOptions ?? this.showAdvancedOptions,
      valueOrigin: valueOrigin ?? this.valueOrigin,
    );
  }

  static const Object _sentinel = Object();
}
