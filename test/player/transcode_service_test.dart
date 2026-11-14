import 'package:audio_core/audio_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/transcode/transcode_models.dart';
import 'package:vynody/transcode/transcode_preset.dart';
import 'package:vynody/transcode/transcode_service.dart';

class _FakeAudioCoreController extends Fake implements AudioCoreController {}

class _RecordingAudioConverter extends Fake implements AudioConverter {
  final List<Map<String, Object?>> singleCalls = [];
  final List<Map<String, Object?>> batchCalls = [];
  bool nextSuccess = true;
  String? nextOutputPath;
  String? nextErrorMessage;

  @override
  String buildOutputPath({
    required String inputPath,
    required String outputDirectory,
    required AudioFormat outputFormat,
    bool ensureUnique = true,
  }) {
    final baseName = inputPath.split('/').last.split('.').first;
    return '$outputDirectory/$baseName.${outputFormat.value}';
  }

  @override
  Future<ConvertResult> convertToOutputDirectory({
    required String inputPath,
    required String outputDirectory,
    required AudioFormat outputFormat,
    int? sampleRate,
    int? channels,
    int? bitRate,
    BitRateMode? bitRateMode,
    AacEncoder? aacEncoder,
    bool allowFallbackToFfmpeg = true,
    Map<String, String>? extraOptions,
    List<String>? customArgs,
    AndroidOutputDirectory? androidOutputDirectory,
    bool useSystemEncoder = false,
    AudioConverterProgressCallback? onProgress,
    bool overwrite = false,
  }) async {
    singleCalls.add({
      'inputPath': inputPath,
      'outputDirectory': outputDirectory,
      'outputFormat': outputFormat,
      'sampleRate': sampleRate,
      'channels': channels,
      'bitRate': bitRate,
      'bitRateMode': bitRateMode,
      'aacEncoder': aacEncoder,
      'useSystemEncoder': useSystemEncoder,
    });
    final planned = buildOutputPath(
      inputPath: inputPath,
      outputDirectory: outputDirectory,
      outputFormat: outputFormat,
    );
    return ConvertResult(
      success: nextSuccess,
      outputPath: nextOutputPath ?? planned,
      outputFormat: outputFormat,
      errorMessage: nextErrorMessage,
    );
  }

  @override
  Future<List<ConvertResult>> convertFilesToOutputDirectory({
    required List<String> inputPaths,
    required String outputDirectory,
    required AudioFormat outputFormat,
    int? sampleRate,
    int? channels,
    int? bitRate,
    BitRateMode? bitRateMode,
    AacEncoder? aacEncoder,
    bool allowFallbackToFfmpeg = true,
    Map<String, String>? extraOptions,
    List<String>? customArgs,
    AndroidOutputDirectory? androidOutputDirectory,
    bool useSystemEncoder = false,
    AudioConverterProgressCallback? onProgress,
    bool copyMetadata = true,
    AudioCoreController? audioCoreController,
    bool overwrite = false,
  }) async {
    batchCalls.add({
      'inputPaths': inputPaths,
      'outputDirectory': outputDirectory,
      'outputFormat': outputFormat,
      'sampleRate': sampleRate,
      'channels': channels,
      'bitRate': bitRate,
      'bitRateMode': bitRateMode,
      'aacEncoder': aacEncoder,
      'useSystemEncoder': useSystemEncoder,
      'copyMetadata': copyMetadata,
    });
    return inputPaths
        .map(
          (path) => ConvertResult(
            success: nextSuccess,
            outputPath: buildOutputPath(
              inputPath: path,
              outputDirectory: outputDirectory,
              outputFormat: outputFormat,
            ),
            outputFormat: outputFormat,
            errorMessage: nextErrorMessage,
          ),
        )
        .toList();
  }
}

void main() {
  group('Transcode models & TranscodePresetResolver', () {
    test('TranscodeQualityTierX storage round-trip and fallback', () {
      for (final tier in TranscodeQualityTier.values) {
        expect(
          TranscodeQualityTierX.fromStorageValue(tier.storageValue),
          tier,
        );
      }
      expect(
        TranscodeQualityTierX.fromStorageValue('  EXTREME  '),
        TranscodeQualityTier.extreme,
      );
      expect(
        TranscodeQualityTierX.fromStorageValue('unknown'),
        TranscodeQualityTier.high,
      );
      expect(
        TranscodeQualityTierX.fromStorageValue(null),
        TranscodeQualityTier.high,
      );
    });

    test('AudioFormatDisplayX.supportsBitRateControls disables lossless formats', () {
      expect(AudioFormat.flac.supportsBitRateControls, isFalse);
      expect(AudioFormat.wav.supportsBitRateControls, isFalse);
      expect(AudioFormat.alac.supportsBitRateControls, isFalse);
      expect(AudioFormat.aiff.supportsBitRateControls, isFalse);

      expect(AudioFormat.mp3.supportsBitRateControls, isTrue);
      expect(AudioFormat.aac.supportsBitRateControls, isTrue);
      expect(AudioFormat.m4a.supportsBitRateControls, isTrue);
      expect(AudioFormat.opus.supportsBitRateControls, isTrue);
    });

    test('TranscodePresetResolver resolves bitRate and bitRateMode per tier/format', () {
      const resolver = TranscodePresetResolver();

      final lowAac = resolver.resolve(
        outputFormat: AudioFormat.aac,
        qualityTier: TranscodeQualityTier.low,
      );
      expect(lowAac.bitRate, 128000);
      expect(lowAac.bitRateMode, BitRateMode.vbr);

      final medM4a = resolver.resolve(
        outputFormat: AudioFormat.m4a,
        qualityTier: TranscodeQualityTier.medium,
      );
      expect(medM4a.bitRate, 192000);
      expect(medM4a.bitRateMode, BitRateMode.vbr);

      final highOpus = resolver.resolve(
        outputFormat: AudioFormat.opus,
        qualityTier: TranscodeQualityTier.high,
      );
      expect(highOpus.bitRate, 256000);
      expect(highOpus.bitRateMode, BitRateMode.vbr);

      final extremeMp3 = resolver.resolve(
        outputFormat: AudioFormat.mp3,
        qualityTier: TranscodeQualityTier.extreme,
      );
      expect(extremeMp3.bitRate, 320000);
      expect(extremeMp3.bitRateMode, BitRateMode.cbr);
    });

    test('TranscodeDraft.copyWith can explicitly clear outputDirectory to null', () {
      const draft = TranscodeDraft(
        outputFormat: AudioFormat.mp3,
        qualityTier: TranscodeQualityTier.high,
        bitRate: 256000,
        bitRateMode: BitRateMode.cbr,
        valueOrigin: TranscodeValueOrigin.presetDerived,
        outputDirectory: '/tmp/out',
      );

      final kept = draft.copyWith(bitRate: 320000);
      expect(kept.outputDirectory, '/tmp/out');

      final cleared = draft.copyWith(outputDirectory: null);
      expect(cleared.outputDirectory, isNull);
    });
  });

  group('TranscodeService', () {
    late _RecordingAudioConverter converter;
    late TranscodeService service;

    setUp(() {
      converter = _RecordingAudioConverter();
      service = TranscodeService(
        converter: converter,
        audioCoreController: _FakeAudioCoreController(),
      );
    });

    test('convertToOutputDirectory forwards bitRate controls for lossy format', () async {
      const draft = TranscodeDraft(
        outputFormat: AudioFormat.mp3,
        qualityTier: TranscodeQualityTier.extreme,
        bitRate: 320000,
        bitRateMode: BitRateMode.cbr,
        valueOrigin: TranscodeValueOrigin.customized,
        sampleRate: 48000,
        channels: 2,
        outputDirectory: '/music/out',
      );

      final res = await service.convertToOutputDirectory(
        inputPath: '/music/in/song.flac',
        draft: draft,
        copyMetadata: false,
      );

      expect(res.plannedOutputPath, '/music/out/song.mp3');
      expect(res.result.success, isTrue);
      expect(converter.singleCalls, hasLength(1));
      final call = converter.singleCalls.single;
      expect(call['bitRate'], 320000);
      expect(call['bitRateMode'], BitRateMode.cbr);
      expect(call['sampleRate'], 48000);
      expect(call['channels'], 2);
      expect(call['aacEncoder'], isNull);
    });

    test('convertToOutputDirectory strips bitRate controls for lossless format', () async {
      const draft = TranscodeDraft(
        outputFormat: AudioFormat.flac,
        qualityTier: TranscodeQualityTier.high,
        bitRate: 256000,
        bitRateMode: BitRateMode.vbr,
        valueOrigin: TranscodeValueOrigin.presetDerived,
        outputDirectory: '/music/out',
      );

      final res = await service.convertToOutputDirectory(
        inputPath: '/music/in/song.wav',
        draft: draft,
        copyMetadata: false,
      );

      expect(res.plannedOutputPath, '/music/out/song.flac');
      final call = converter.singleCalls.single;
      expect(call['bitRate'], isNull);
      expect(call['bitRateMode'], isNull);
      expect(call['aacEncoder'], isNull);
    });

    test('convertMultipleToOutputDirectory maps results with planned output paths', () async {
      // Simulate failure so background TagLib metadata probe is skipped cleanly.
      converter.nextSuccess = false;
      converter.nextErrorMessage = 'mock fail';

      const draft = TranscodeDraft(
        outputFormat: AudioFormat.wav,
        qualityTier: TranscodeQualityTier.high,
        bitRate: 256000,
        bitRateMode: BitRateMode.cbr,
        valueOrigin: TranscodeValueOrigin.presetDerived,
        outputDirectory: '/music/out',
      );

      final results = await service.convertMultipleToOutputDirectory(
        inputPaths: ['/music/a.mp3', '/music/b.flac'],
        draft: draft,
      );

      expect(results, hasLength(2));
      expect(results[0].plannedOutputPath, '/music/out/a.wav');
      expect(results[1].plannedOutputPath, '/music/out/b.wav');
      expect(results[0].result.success, isFalse);
      expect(results[0].result.errorMessage, 'mock fail');
      expect(converter.batchCalls.single['bitRate'], isNull);
      expect(converter.batchCalls.single['bitRateMode'], isNull);
    });
  });
}
