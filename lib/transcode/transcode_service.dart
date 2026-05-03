import 'dart:io';

import 'package:audio_converter/audio_converter.dart';
import 'package:path/path.dart' as p;

import 'transcode_models.dart';

class TranscodeExecutionResult {
  const TranscodeExecutionResult({
    required this.plannedOutputPath,
    required this.result,
  });

  final String plannedOutputPath;
  final ConvertResult result;
}

class TranscodeService {
  TranscodeService({AudioConverter? converter})
    : _converter = converter ?? AudioConverter();

  final AudioConverter _converter;

  Future<ConverterCapabilities> getCapabilities() {
    return _converter.getCapabilities();
  }

  Future<TranscodeExecutionResult> convert({
    required String inputPath,
    required TranscodeDraft draft,
    String? ffmpegPath,
  }) async {
    final plannedOutputPath = _buildOutputPath(
      inputPath: inputPath,
      outputDirectory: draft.outputDirectory,
      outputFormat: draft.outputFormat,
    );

    final request = ConvertRequest(
      inputPath: inputPath,
      outputPath: plannedOutputPath,
      outputFormat: draft.outputFormat,
      sampleRate: draft.sampleRate,
      channels: draft.channels,
      bitRate: draft.outputFormat.supportsBitRateControls
          ? draft.bitRate
          : null,
      bitRateMode: draft.outputFormat.supportsBitRateControls
          ? draft.bitRateMode
          : null,
      ffmpegPath: _normalizeOptional(ffmpegPath),
    );

    final result = await _converter.convertFile(request);
    return TranscodeExecutionResult(
      plannedOutputPath: plannedOutputPath,
      result: result,
    );
  }

  String buildPreviewOutputPath({
    required String inputPath,
    required AudioFormat outputFormat,
    String? outputDirectory,
  }) {
    return _buildOutputPath(
      inputPath: inputPath,
      outputDirectory: outputDirectory,
      outputFormat: outputFormat,
      ensureUnique: false,
    );
  }

  String _buildOutputPath({
    required String inputPath,
    required AudioFormat outputFormat,
    String? outputDirectory,
    bool ensureUnique = true,
  }) {
    final inputFile = File(inputPath);
    final parent = _normalizeOptional(outputDirectory) ?? inputFile.parent.path;
    final baseName = p.basenameWithoutExtension(inputPath);
    final ext = outputFormat.value;
    final preferredPath = p.join(parent, '$baseName.$ext');

    if (!ensureUnique || !File(preferredPath).existsSync()) {
      return preferredPath;
    }

    for (var index = 1; index < 1000; index++) {
      final candidate = p.join(parent, '$baseName ($index).$ext');
      if (!File(candidate).existsSync()) {
        return candidate;
      }
    }

    return preferredPath;
  }

  String? _normalizeOptional(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
