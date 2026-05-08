import 'dart:async';
import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../player/audio_riverpod.dart';
import '../transcode/transcode_models.dart';
import '../transcode/transcode_preset.dart';
import '../transcode/transcode_riverpod.dart';
import '../transcode/transcode_service.dart';
import '../utils/song_context_menu_utils.dart';

class TranscodeSubmitSummary {
  const TranscodeSubmitSummary({
    required this.successCount,
    required this.failureCount,
    this.firstOutputPath,
    this.lastErrorMessage,
  });

  final int successCount;
  final int failureCount;
  final String? firstOutputPath;
  final String? lastErrorMessage;
}

Future<void> showTranscodeDialog(
  BuildContext context, {
  required List<MusicFile> songs,
}) async {
  if (songs.isEmpty) {
    return;
  }

  final summary = await showModalBottomSheet<TranscodeSubmitSummary>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TranscodeDialog(songs: songs),
  );

  if (summary == null || !context.mounted) {
    return;
  }

  final l10n = AppLocalizations.of(context)!;
  final container = ProviderScope.containerOf(context, listen: false);
  final settings = container.read(settingsServiceProvider);
  if (summary.successCount > 0 && settings.transcodeAutoScanOutputEnabled) {
    unawaited(container.read(scannerServiceProvider).scan());
  }

  final total = summary.successCount + summary.failureCount;
  final message = summary.failureCount == 0
      ? l10n.transcodeCompletedCount(summary.successCount)
      : l10n.transcodeCompletedWithFailures(
          summary.successCount,
          total,
          summary.failureCount,
        );

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action:
          summary.firstOutputPath != null &&
              (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          ? SnackBarAction(
              label: l10n.openFileLocation,
              onPressed: () {
                unawaited(openSongFileLocation(summary.firstOutputPath!));
              },
            )
          : null,
    ),
  );

  if (summary.failureCount > 0 && summary.lastErrorMessage != null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(summary.lastErrorMessage!)));
  }
}

class TranscodeDialog extends ConsumerStatefulWidget {
  const TranscodeDialog({super.key, required this.songs});

  final List<MusicFile> songs;

  @override
  ConsumerState<TranscodeDialog> createState() => _TranscodeDialogState();
}

class _TranscodeDialogState extends ConsumerState<TranscodeDialog> {
  static const List<int?> _sampleRateOptions = <int?>[
    null,
    22050,
    32000,
    44100,
    48000,
    88200,
    96000,
  ];
  static const List<int?> _channelOptions = <int?>[null, 1, 2];

  final TextEditingController _bitRateController = TextEditingController();
  final TranscodePresetResolver _presetResolver =
      const TranscodePresetResolver();

  ConverterCapabilities? _capabilities;
  late TranscodeDraft _draft;
  bool _isLoadingCapabilities = true;
  bool _isSubmitting = false;
  double? _currentFileProgress;
  double? _overallProgress;
  String? _submitLabel;
  String? _currentFileLabel;
  String? _errorText;
  AndroidOutputDirectory? _androidOutputDirectory;

  bool get _supportsBitRateControls =>
      _draft.outputFormat.supportsBitRateControls;

  bool get _isLosslessPresetlessFormat => !_supportsBitRateControls;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsServiceProvider);
    final preset = _presetResolver.resolve(
      outputFormat: settings.transcodeDefaultFormat,
      qualityTier: settings.transcodeDefaultQualityTier,
    );
    _draft = TranscodeDraft(
      outputFormat: preset.outputFormat,
      qualityTier: preset.qualityTier,
      bitRate: preset.bitRate,
      bitRateMode: preset.bitRateMode,
      sampleRate: preset.sampleRate,
      channels: preset.channels,
      valueOrigin: TranscodeValueOrigin.presetDerived,
      outputDirectory: _initialOutputDirectory(),
    );
    _bitRateController.text = preset.bitRate.toString();
    unawaited(_loadCapabilities());
  }

  @override
  void dispose() {
    _bitRateController.dispose();
    super.dispose();
  }

  String _initialOutputDirectory() {
    return File(widget.songs.first.path).parent.path;
  }

  Future<void> _loadCapabilities() async {
    try {
      final capabilities = await ref
          .read(transcodeServiceProvider)
          .getCapabilities();
      if (!mounted) return;
      final supported = capabilities.supportedOutputFormats;
      setState(() {
        _capabilities = capabilities;
        _isLoadingCapabilities = false;
        if (supported.isNotEmpty && !supported.contains(_draft.outputFormat)) {
          _resetDraftForPreset(
            outputFormat: supported.first,
            qualityTier: _draft.qualityTier,
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingCapabilities = false;
        _errorText = error.toString();
      });
    }
  }

  List<AudioFormat> get _formatOptions {
    final supported = _capabilities?.supportedOutputFormats;
    if (supported == null || supported.isEmpty) {
      return AudioFormat.values;
    }
    return supported;
  }

  void _resetDraftForPreset({
    AudioFormat? outputFormat,
    TranscodeQualityTier? qualityTier,
  }) {
    final nextFormat = outputFormat ?? _draft.outputFormat;
    final nextTier = qualityTier ?? _draft.qualityTier;
    final resolved = _presetResolver.resolve(
      outputFormat: nextFormat,
      qualityTier: nextTier,
    );
    setState(() {
      _draft = _draft.copyWith(
        outputFormat: nextFormat,
        qualityTier: nextTier,
        bitRate: resolved.bitRate,
        bitRateMode: resolved.bitRateMode,
        sampleRate: resolved.sampleRate,
        channels: resolved.channels,
        valueOrigin: TranscodeValueOrigin.presetDerived,
      );
      _bitRateController.text = resolved.bitRate.toString();
      _errorText = null;
    });
  }

  void _markCustomized({
    int? bitRate,
    BitRateMode? bitRateMode,
    int? sampleRate,
    int? channels,
  }) {
    setState(() {
      _draft = _draft.copyWith(
        bitRate: bitRate,
        bitRateMode: bitRateMode,
        sampleRate: sampleRate,
        channels: channels,
        valueOrigin: TranscodeValueOrigin.customized,
      );
      _errorText = null;
    });
  }

  Future<void> _pickOutputDirectory() async {
    if (Platform.isAndroid) {
      final selected = await ref
          .read(transcodeServiceProvider)
          .pickAndroidOutputDirectory();
      if (selected == null || !mounted) return;
      setState(() {
        _androidOutputDirectory = selected;
        _draft = _draft.copyWith(outputDirectory: selected.displayPath);
      });
      return;
    }

    final selected = await ref
        .read(transcodeServiceProvider)
        .pickOutputDirectory();
    if (selected == null || !mounted) return;
    setState(() {
      _draft = _draft.copyWith(outputDirectory: selected);
    });
  }

  String _previewOutputPath() {
    if (Platform.isAndroid) {
      final selected = _androidOutputDirectory;
      if (selected == null) {
        return '';
      }
      final baseName = p.basenameWithoutExtension(widget.songs.first.path);
      return p.join(
        selected.displayPath,
        '$baseName.${_draft.outputFormat.value}',
      );
    }

    return ref
        .read(transcodeServiceProvider)
        .buildPreviewOutputPath(
          inputPath: widget.songs.first.path,
          outputFormat: _draft.outputFormat,
          outputDirectory: _draft.outputDirectory,
        );
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final l10n = AppLocalizations.of(context)!;
    if (Platform.isAndroid && _androidOutputDirectory == null) {
      setState(() {
        _errorText = 'Please choose an Android output directory first.';
      });
      return;
    }
    final bitRate = int.tryParse(_bitRateController.text.trim());
    if (_draft.outputFormat.supportsBitRateControls &&
        (bitRate == null || bitRate <= 0)) {
      setState(() {
        _errorText = l10n.transcodeBitRateInvalid;
      });
      return;
    }

    final service = ref.read(transcodeServiceProvider);
    final settings = ref.read(settingsServiceProvider);
    final draft = _draft.copyWith(
      bitRate: bitRate ?? _draft.bitRate,
      valueOrigin: _draft.valueOrigin,
    );

    setState(() {
      _isSubmitting = true;
      _currentFileProgress = 0;
      _overallProgress = 0;
      _submitLabel = l10n.transcodePreparing;
      _currentFileLabel = null;
      _errorText = null;
    });

    var successCount = 0;
    var failureCount = 0;
    String? firstOutputPath;
    String? lastErrorMessage;

    for (var index = 0; index < widget.songs.length; index++) {
      final song = widget.songs[index];
      if (!mounted) return;

      final result = await service.convertToOutputDirectory(
        inputPath: song.path,
        draft: draft,
        androidOutputDirectory: _androidOutputDirectory,
        ffmpegPath: settings.transcodeFfmpegPath,
        metadataSourcePath: TranscodeService.resolveMetadataSourcePath(song),
        onProgress: (progress) {
          if (!mounted) return;
          final fileProgress = progress.currentFileProgress?.clamp(0.0, 1.0);
          final batchProgress = fileProgress == null
              ? index / widget.songs.length
              : (index + fileProgress) / widget.songs.length;
          setState(() {
            _currentFileProgress = progress.currentFileProgress;
            _overallProgress = batchProgress.clamp(0.0, 1.0).toDouble();
            _submitLabel =
                progress.message ??
                l10n.transcodeProgress(index + 1, widget.songs.length);
            _currentFileLabel = p.basename(progress.currentFilePath);
          });
        },
      );

      if (result.result.success) {
        successCount += 1;
        firstOutputPath ??=
            result.result.outputPath ?? result.plannedOutputPath;
      } else {
        failureCount += 1;
        lastErrorMessage =
            result.result.errorMessage ?? l10n.transcodeFailedGeneric;
        debugPrint(lastErrorMessage);
      }

      if (!mounted) return;
      setState(() {
        _currentFileProgress = 1;
        _overallProgress = (index + 1) / widget.songs.length;
        _submitLabel = l10n.transcodeProgress(index + 1, widget.songs.length);
        _currentFileLabel = p.basename(song.path);
      });
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      TranscodeSubmitSummary(
        successCount: successCount,
        failureCount: failureCount,
        firstOutputPath: firstOutputPath,
        lastErrorMessage: lastErrorMessage,
      ),
    );
  }

  String _qualityLabel(AppLocalizations l10n, TranscodeQualityTier tier) {
    return switch (tier) {
      TranscodeQualityTier.low => l10n.transcodeQualityLow,
      TranscodeQualityTier.medium => l10n.transcodeQualityMedium,
      TranscodeQualityTier.high => l10n.transcodeQualityHigh,
      TranscodeQualityTier.extreme => l10n.transcodeQualityExtreme,
    };
  }

  String _sampleRateLabel(AppLocalizations l10n, int? value) {
    if (value == null) {
      return l10n.transcodeKeepSource;
    }
    return '$value Hz';
  }

  String _channelsLabel(AppLocalizations l10n, int? value) {
    return switch (value) {
      null => l10n.transcodeKeepSource,
      1 => l10n.transcodeMono,
      2 => l10n.transcodeStereo,
      _ => '$value',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.transcodeTitle,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.songs.length == 1
                                  ? p.basename(widget.songs.first.path)
                                  : l10n.transcodeSongCount(
                                      widget.songs.length,
                                    ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    children: [
                      if (_capabilities != null) _buildCapabilitiesCard(l10n),
                      _buildFormatSection(l10n),
                      const SizedBox(height: 16),
                      _buildQualitySection(l10n),
                      const SizedBox(height: 16),
                      _buildAdvancedSection(l10n),
                      const SizedBox(height: 16),
                      _buildOutputSection(l10n),
                      if (_errorText != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorText!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_isSubmitting)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _currentFileLabel == null
                              ? (_submitLabel ?? l10n.transcodePreparing)
                              : '${_submitLabel ?? l10n.transcodePreparing} · $_currentFileLabel',
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _currentFileProgress,
                          minHeight: 8,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _currentFileProgress == null
                              ? l10n.transcodePreparing
                              : 'Current song ${((_currentFileProgress! * 100).clamp(0, 100)).toStringAsFixed(1)}%',
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _overallProgress,
                          minHeight: 8,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _overallProgress == null
                              ? l10n.transcodePreparing
                              : 'Overall ${((_overallProgress! * 100).clamp(0, 100)).toStringAsFixed(1)}%',
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: FilledButton.icon(
                    onPressed: _isLoadingCapabilities || _isSubmitting
                        ? null
                        : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_alt_rounded),
                    label: Text(
                      _isSubmitting ? l10n.transcoding : l10n.startTranscode,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCapabilitiesCard(AppLocalizations l10n) {
    final capabilities = _capabilities!;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsServiceProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.transcodeEngine(capabilities.engine),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (capabilities.notes != null &&
              capabilities.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(capabilities.notes!),
          ],
          if (capabilities.requiresExternalBinary) ...[
            const SizedBox(height: 8),
            Text(
              settings.transcodeFfmpegPath.trim().isEmpty
                  ? l10n.transcodeUsingSystemFfmpeg
                  : l10n.transcodeUsingCustomFfmpeg(
                      settings.transcodeFfmpegPath,
                    ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormatSection(AppLocalizations l10n) {
    return DropdownButtonFormField<AudioFormat>(
      initialValue: _draft.outputFormat,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l10n.transcodeFormat,
        border: const OutlineInputBorder(),
      ),
      items: _formatOptions
          .map(
            (format) => DropdownMenuItem<AudioFormat>(
              value: format,
              child: Text(format.displayName),
            ),
          )
          .toList(growable: false),
      onChanged: _isSubmitting
          ? null
          : (value) {
              if (value == null) return;
              _resetDraftForPreset(
                outputFormat: value,
                qualityTier: _draft.qualityTier,
              );
            },
    );
  }

  Widget _buildQualitySection(AppLocalizations l10n) {
    if (_isLosslessPresetlessFormat) {
      return _buildDisabledQualitySection(l10n);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.transcodeQualityPreset),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: TranscodeQualityTier.values
              .map((tier) {
                final selected = _draft.qualityTier == tier;
                return ChoiceChip(
                  label: Text(_qualityLabel(l10n, tier)),
                  selected: selected,
                  onSelected: _isSubmitting
                      ? null
                      : (_) {
                          _resetDraftForPreset(
                            outputFormat: _draft.outputFormat,
                            qualityTier: tier,
                          );
                        },
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildDisabledQualitySection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.transcodeQualityPreset,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.transcodeLosslessPresetHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.transcodeAdvancedOptions),
          subtitle: Text(
            _isLosslessPresetlessFormat
                ? l10n.transcodeLosslessAdvancedHint
                : (_draft.isCustomized
                      ? l10n.transcodeAdvancedCustomized
                      : l10n.transcodeAdvancedFollowingPreset),
          ),
          value: _draft.showAdvancedOptions,
          onChanged: _isSubmitting
              ? null
              : (value) {
                  setState(() {
                    _draft = _draft.copyWith(showAdvancedOptions: value);
                  });
                },
        ),
        if (_draft.showAdvancedOptions) ...[
          if (_supportsBitRateControls) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _bitRateController,
              enabled: !_isSubmitting,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.transcodeBitRate,
                suffixText: 'bps',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                final parsed = int.tryParse(value.trim());
                if (parsed != null && parsed > 0) {
                  _markCustomized(bitRate: parsed);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BitRateMode>(
              initialValue: _draft.bitRateMode,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.transcodeBitRateMode,
                border: const OutlineInputBorder(),
              ),
              items: BitRateMode.values
                  .map(
                    (mode) => DropdownMenuItem<BitRateMode>(
                      value: mode,
                      child: Text(mode == BitRateMode.cbr ? 'CBR' : 'VBR'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      if (value == null) return;
                      _markCustomized(bitRateMode: value);
                    },
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<int?>(
            initialValue: _draft.sampleRate,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.transcodeSampleRate,
              border: const OutlineInputBorder(),
            ),
            items: _sampleRateOptions
                .map(
                  (value) => DropdownMenuItem<int?>(
                    value: value,
                    child: Text(_sampleRateLabel(l10n, value)),
                  ),
                )
                .toList(growable: false),
            onChanged: _isSubmitting
                ? null
                : (value) {
                    _markCustomized(sampleRate: value);
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _draft.channels,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.transcodeChannels,
              border: const OutlineInputBorder(),
            ),
            items: _channelOptions
                .map(
                  (value) => DropdownMenuItem<int?>(
                    value: value,
                    child: Text(_channelsLabel(l10n, value)),
                  ),
                )
                .toList(growable: false),
            onChanged: _isSubmitting
                ? null
                : (value) {
                    _markCustomized(channels: value);
                  },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () {
                      _resetDraftForPreset();
                    },
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(
                _supportsBitRateControls
                    ? l10n.transcodeResetToPreset
                    : l10n.transcodeResetLosslessOptions,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOutputSection(AppLocalizations l10n) {
    final outputDirectory = Platform.isAndroid
        ? _androidOutputDirectory?.displayPath
        : (_draft.outputDirectory ?? _initialOutputDirectory());
    final preview = _previewOutputPath();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.transcodeOutputDirectory,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 10),
        SelectableText(
          outputDirectory ?? 'Not selected',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Text(
          outputDirectory == null
              ? 'Please choose an output directory.'
              : '${l10n.transcodeOutputPreview}: $preview',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _pickOutputDirectory,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(l10n.transcodeChooseDirectory),
            ),
            OutlinedButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () {
                      setState(() {
                        if (Platform.isAndroid) {
                          _androidOutputDirectory = null;
                          _draft = _draft.copyWith(outputDirectory: null);
                        } else {
                          _draft = _draft.copyWith(
                            outputDirectory: _initialOutputDirectory(),
                          );
                        }
                      });
                    },
              icon: const Icon(Icons.undo_rounded),
              label: Text(l10n.transcodeUseSourceDirectory),
            ),
          ],
        ),
      ],
    );
  }
}
