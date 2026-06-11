import 'package:audio_core/audio_core.dart';

import 'transcode_models.dart';

class TranscodePresetResolver {
  const TranscodePresetResolver();

  TranscodeResolvedPreset resolve({
    required AudioFormat outputFormat,
    required TranscodeQualityTier qualityTier,
  }) {
    return TranscodeResolvedPreset(
      qualityTier: qualityTier,
      outputFormat: outputFormat,
      bitRate: _bitRateForTier(qualityTier),
      bitRateMode: _bitRateModeForFormat(outputFormat),
      sampleRate: null,
      channels: null,
    );
  }

  int _bitRateForTier(TranscodeQualityTier tier) {
    return switch (tier) {
      TranscodeQualityTier.low => 128000,
      TranscodeQualityTier.medium => 192000,
      TranscodeQualityTier.high => 256000,
      TranscodeQualityTier.extreme => 320000,
    };
  }

  BitRateMode _bitRateModeForFormat(AudioFormat format) {
    return switch (format) {
      AudioFormat.aac || AudioFormat.m4a || AudioFormat.m4b => BitRateMode.vbr,
      AudioFormat.opus => BitRateMode.vbr,
      AudioFormat.mp3 => BitRateMode.cbr,
      _ => BitRateMode.cbr,
    };
  }
}
