import 'package:audio_core/audio_core.dart';

/// 空间音效模式（独立于均衡器开关运行）。
enum SpatialAudioMode {
  off('off'),
  concertHall('freeverb'),
  naturalEcho('fundsp_fdn');

  const SpatialAudioMode(this.storageValue);

  final String storageValue;

  static SpatialAudioMode fromStorage(String? raw) {
    switch (raw?.trim()) {
      case 'freeverb':
        return SpatialAudioMode.concertHall;
      case 'fundsp_fdn':
        return SpatialAudioMode.naturalEcho;
      case 'off':
      default:
        return SpatialAudioMode.off;
    }
  }

  /// 使用 audio_core 默认参数构造对应的 [ReverbConfig]。
  ReverbConfig toReverbConfig({bool isProUnlocked = true}) {
    final bool enabled = isProUnlocked && this != SpatialAudioMode.off;
    switch (this) {
      case SpatialAudioMode.off:
        return const ReverbConfig(
          enabled: false,
          algorithm: ReverbAlgorithm.freeverb,
          dryMix: 0.90,
          wetMix: 0.22,
          roomSize: 0.70,
          damping: 0.50,
          width: 0.85,
          timeSeconds: 3.02,
          freeze: false,
        );
      case SpatialAudioMode.concertHall:
        return ReverbConfig(
          enabled: enabled,
          algorithm: ReverbAlgorithm.freeverb,
          dryMix: 0.90,
          wetMix: 0.22,
          roomSize: 0.70,
          damping: 0.50,
          width: 0.85,
          timeSeconds: 3.02,
          freeze: false,
        );
      case SpatialAudioMode.naturalEcho:
        return ReverbConfig(
          enabled: enabled,
          algorithm: ReverbAlgorithm.fundspStereo,
          dryMix: 0.76,
          wetMix: 1.00,
          roomSize: 0.88,
          damping: 1.00,
          width: 0.85,
          timeSeconds: 3.02,
          freeze: false,
        );
    }
  }
}
