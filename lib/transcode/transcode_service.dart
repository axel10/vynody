import 'dart:async';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';

import 'package:vynody/models/music_file.dart';
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

  Future<AndroidOutputDirectory?> pickAndroidOutputDirectory() {
    return _converter.pickAndroidOutputDirectory();
  }

  String buildPreviewOutputPath({
    required String inputPath,
    required AudioFormat outputFormat,
    String? outputDirectory,
  }) {
    return _converter.buildOutputPath(
      inputPath: inputPath,
      outputDirectory: outputDirectory ?? File(inputPath).parent.path,
      outputFormat: outputFormat,
    );
  }

  Future<TranscodeExecutionResult> convertToOutputDirectory({
    required String inputPath,
    required TranscodeDraft draft,
    AndroidOutputDirectory? androidOutputDirectory,
    String? metadataSourcePath,
    AudioConverterProgressCallback? onProgress,
  }) async {
    final outputDirectory =
        draft.outputDirectory ?? File(inputPath).parent.path;
    final plannedOutputPath = _converter.buildOutputPath(
      inputPath: inputPath,
      outputDirectory: outputDirectory,
      outputFormat: draft.outputFormat,
    );

    final supportsBitRate = draft.outputFormat.supportsBitRateControls;
    final hasAacEncoder =
        supportsBitRate &&
        !draft.useSystemEncoder &&
        !(Platform.isIOS || Platform.isMacOS);

    final result = androidOutputDirectory != null
        ? await _converter.convertAndSaveToAndroidDirectory(
            ConvertRequest.forOutputDirectory(
              inputPath: inputPath,
              outputDirectory: outputDirectory,
              outputFormat: draft.outputFormat,
              sampleRate: draft.sampleRate,
              channels: draft.channels,
              bitRate: supportsBitRate ? draft.bitRate : null,
              bitRateMode: supportsBitRate ? draft.bitRateMode : null,
              useSystemEncoder: draft.useSystemEncoder,
              aacEncoder: hasAacEncoder ? draft.aacEncoder : null,
            ),
            androidOutputDirectory,
            onProgress: onProgress,
          )
        : ConvertAndSaveResult(
            conversionResult: await _converter.convertToOutputDirectory(
              inputPath: inputPath,
              outputDirectory: outputDirectory,
              outputFormat: draft.outputFormat,
              sampleRate: draft.sampleRate,
              channels: draft.channels,
              bitRate: supportsBitRate ? draft.bitRate : null,
              bitRateMode: supportsBitRate ? draft.bitRateMode : null,
              useSystemEncoder: draft.useSystemEncoder,
              aacEncoder: hasAacEncoder ? draft.aacEncoder : null,
              onProgress: onProgress,
            ),
          );

    if (result.success) {
      await _copyMetadataFromSourceToOutput(
        sourcePath: _normalizeOptional(metadataSourcePath) ?? inputPath,
        outputPath: result.outputPath ?? plannedOutputPath,
      );
      await _logTranscodedFileMetadata(
        result.outputPath ?? plannedOutputPath,
      );
    }

    return TranscodeExecutionResult(
      plannedOutputPath: plannedOutputPath,
      result: result.conversionResult.copyWith(
        success: result.success,
        outputPath: result.outputPath ?? result.conversionResult.outputPath,
        errorMessage: result.errorMessage,
      ),
    );
  }

  Future<List<TranscodeExecutionResult>> convertMultipleToOutputDirectory({
    required List<String> inputPaths,
    required TranscodeDraft draft,
    AndroidOutputDirectory? androidOutputDirectory,
    List<String>? metadataSourcePaths,
    AudioConverterProgressCallback? onProgress,
  }) async {
    final outputDirectory =
        draft.outputDirectory ??
        (inputPaths.isNotEmpty ? File(inputPaths.first).parent.path : '');

    final supportsBitRate = draft.outputFormat.supportsBitRateControls;
    final hasAacEncoder =
        supportsBitRate &&
        !draft.useSystemEncoder &&
        !(Platform.isIOS || Platform.isMacOS);

    final rawResults = await _converter.convertFilesToOutputDirectory(
      inputPaths: inputPaths,
      outputDirectory: outputDirectory,
      outputFormat: draft.outputFormat,
      sampleRate: draft.sampleRate,
      channels: draft.channels,
      bitRate: supportsBitRate ? draft.bitRate : null,
      bitRateMode: supportsBitRate ? draft.bitRateMode : null,
      useSystemEncoder: draft.useSystemEncoder,
      aacEncoder: hasAacEncoder ? draft.aacEncoder : null,
      androidOutputDirectory: androidOutputDirectory,
      onProgress: onProgress,
      copyMetadata: true,
      audioCoreController: _audioCoreController,
    );

    final results = <TranscodeExecutionResult>[];
    for (var index = 0; index < rawResults.length; index++) {
      final rawResult = rawResults[index];
      final inputPath = inputPaths[index];

      final plannedOutputPath = _converter.buildOutputPath(
        inputPath: inputPath,
        outputDirectory: outputDirectory,
        outputFormat: draft.outputFormat,
      );

      results.add(
        TranscodeExecutionResult(
          plannedOutputPath: plannedOutputPath,
          result: rawResult,
        ),
      );

      if (rawResult.success) {
        unawaited(
          _logTranscodedFileMetadata(
            rawResult.outputPath ?? plannedOutputPath,
          ),
        );
      }
    }

    return results;
  }

  Future<void> _logTranscodedFileMetadata(String outputPath) async {
    final normalizedPath = outputPath.trim();
    if (normalizedPath.isEmpty) {
      return;
    }

    try {
      final file = File(normalizedPath);
      if (!await file.exists()) {
        debugPrint(
          '[Transcode] Metadata probe skipped because output file is missing: '
          '$normalizedPath',
        );
        return;
      }

      final metadata = readMetadata(file, getImage: false);
      debugPrint(
        '[Transcode] Output metadata path=$normalizedPath '
        'title="${metadata.title ?? ''}" '
        'artist="${metadata.artist ?? ''}" '
        'album="${metadata.album ?? ''}" '
        'durationMs=${metadata.duration?.inMilliseconds ?? 'null'} '
        'trackNumber=${metadata.trackNumber ?? 'null'} '
        'hasArtwork=${metadata.hasArtwork}',
      );
    } catch (error) {
      debugPrint(
        '[Transcode] Failed to read output metadata for $normalizedPath: '
        '$error',
      );
    }
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
