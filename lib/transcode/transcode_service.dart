import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:audio_converter/audio_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/music_file.dart';
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
  TranscodeService({
    AudioConverter? converter,
    AudioCoreController? audioCoreController,
  }) : _converter = converter ?? AudioConverter(),
       _audioCoreController = audioCoreController ?? AudioCoreController();

  final AudioConverter _converter;
  final AudioCoreController _audioCoreController;

  Future<ConverterCapabilities> getCapabilities() {
    return _converter.getCapabilities();
  }

  Future<String?> pickOutputDirectory() {
    return _converter.pickOutputDirectory();
  }

  Future<TranscodeExecutionResult> convert({
    required String inputPath,
    required TranscodeDraft draft,
    String? ffmpegPath,
    String? metadataSourcePath,
    AudioConverterProgressCallback? onProgress,
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

    final result = await _converter.convertFile(
      request,
      onProgress: onProgress,
    );
    if (result.success) {
      final outputPath = result.outputPath ?? plannedOutputPath;
      await _copyMetadataFromSourceToOutput(
        sourcePath: _normalizeOptional(metadataSourcePath) ?? inputPath,
        outputPath: outputPath,
      );
    }
    return TranscodeExecutionResult(
      plannedOutputPath: plannedOutputPath,
      result: result,
    );
  }

  Future<void> _copyMetadataFromSourceToOutput({
    required String sourcePath,
    required String outputPath,
  }) async {
    if (sourcePath.trim().isEmpty || outputPath.trim().isEmpty) {
      return;
    }
    if (!File(outputPath).existsSync()) {
      debugPrint(
        '[Transcode] Skipping metadata copy because output file is missing: '
        '$outputPath',
      );
      return;
    }

    try {
      if (!_audioCoreController.isInitialized) {
        await _audioCoreController.initialize();
      }

      final copied = await _audioCoreController.copyMetadataPairs(
        [AudioTrack(id: sourcePath, uri: sourcePath)],
        [AudioTrack(id: outputPath, uri: outputPath)],
      );
      if (copied.isEmpty || !copied.first) {
        debugPrint(
          '[Transcode] Metadata copy failed: $sourcePath -> $outputPath',
        );
      }
    } catch (e) {
      debugPrint(
        '[Transcode] Failed to copy metadata from $sourcePath to '
        '$outputPath: $e',
      );
    }
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

  static String resolveMetadataSourcePath(MusicFile song) {
    if (Platform.isAndroid || Platform.isIOS) {
      final mediaUri = song.mediaUri?.trim();
      if (mediaUri != null && mediaUri.isNotEmpty) {
        return mediaUri;
      }
    }
    return song.path;
  }
}
