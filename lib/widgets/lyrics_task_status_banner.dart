import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/lyrics_generation_phase.dart';
import '../player/lyrics_riverpod.dart';

class LyricsTaskStatusBanner extends ConsumerWidget {
  const LyricsTaskStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(lyricsTaskQueueSummaryProvider);
    final generationState = ref.watch(lyricsGenerationDisplayStateProvider);
    if (!summary.isBusy) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = colorScheme.primary;
    final fallbackModelLabel = ref
        .read(lyricsAiServiceProvider)
        .currentGenerationModelLabel;
    final modelLabel = generationState.modelLabel.trim().isNotEmpty
        ? generationState.modelLabel.trim()
        : fallbackModelLabel;
    final providerLabel = generationState.providerLabel.trim().isNotEmpty
        ? generationState.providerLabel.trim()
        : _splitModelLabel(modelLabel).$1;
    final modelNameLabel = generationState.modelNameLabel.trim().isNotEmpty
        ? generationState.modelNameLabel.trim()
        : _splitModelLabel(modelLabel).$2;
    final taskLabel = summary.activeStatusLabel.trim().isNotEmpty
        ? summary.activeStatusLabel.trim()
        : generationState.statusLabel.trim().isNotEmpty
        ? generationState.statusLabel.trim()
        : '正在处理';
    final activeSong = summary.activeSong?.displayName.trim() ?? '';
    final subtitle = activeSong.isNotEmpty
        ? summary.showQueueCount
              ? '当前处理《$activeSong》'
              : '《$activeSong》'
        : '';
    final progress = generationState.progress.clamp(0.0, 1.0);
    final showProgress =
        generationState.phase != LyricsGenerationPhase.idle && progress > 0.0;
    final phaseLabel = switch (generationState.phase) {
      LyricsGenerationPhase.uploading => '上传中',
      LyricsGenerationPhase.processing => '处理中',
      LyricsGenerationPhase.generating => '生成中',
      LyricsGenerationPhase.idle => '',
    };

    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: 1.0,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth.isFinite
                ? math
                      .max(0.0, math.min(constraints.maxWidth - 32, 440.0))
                      .toDouble()
                : 440.0;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.98,
                        ),
                        colorScheme.surface.withValues(alpha: 0.95),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withValues(alpha: 0.18)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              summary.showQueueCount
                                  ? Icons.queue_music_rounded
                                  : Icons.auto_awesome_rounded,
                              color: accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: RichText(
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        text: TextSpan(
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: colorScheme.onSurface,
                                          ),
                                          children: [
                                            TextSpan(text: taskLabel),
                                            if (activeSong.isNotEmpty)
                                              TextSpan(
                                                text: ' · 《$activeSong》',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 12,
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (showProgress) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        phaseLabel,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      SizedBox(
                                        width: 32,
                                        height: 4,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(2),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            backgroundColor: accent.withValues(alpha: 0.1),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (summary.showQueueCount) ...[
                                      const SizedBox(width: 8),
                                      _BannerPill(
                                        label: '队列 ${summary.taskCount}',
                                        accent: accent,
                                        filled: true,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                _BannerInfoRow(
                                  value: [
                                    if (providerLabel.isNotEmpty) providerLabel,
                                    if (modelNameLabel.isNotEmpty) modelNameLabel,
                                  ].join(' · '),
                                  accent: accent,
                                  theme: theme,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  (String, String) _splitModelLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return ('', '');
    }

    final delimiterIndex = trimmed.indexOf(' · ');
    if (delimiterIndex < 0) {
      return (trimmed, '');
    }

    return (
      trimmed.substring(0, delimiterIndex).trim(),
      trimmed.substring(delimiterIndex + 3).trim(),
    );
  }
}

class _BannerInfoRow extends StatelessWidget {
  const _BannerInfoRow({
    required this.value,
    required this.accent,
    required this.theme,
  });

  final String value;
  final Color accent;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;

    return Opacity(
      opacity: 0.7,
      child: Row(
        children: [
          Icon(
            Icons.bolt_rounded,
            size: 12,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '未知模型',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerPill extends StatelessWidget {
  const _BannerPill({
    required this.label,
    required this.accent,
    required this.filled,
  });

  final String label;
  final Color accent;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final background = filled
        ? accent.withValues(alpha: 0.12)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
