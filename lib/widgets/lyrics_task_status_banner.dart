import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/player/lyrics/lyrics_generation_phase.dart';
import 'package:vibe_flow/player/lyrics/lyrics_riverpod.dart';
import 'package:vibe_flow/player/lyrics/lyrics_task_queue_summary.dart';

class LyricsTaskStatusBanner extends ConsumerStatefulWidget {
  const LyricsTaskStatusBanner({super.key});

  static const Duration _transitionDuration = Duration(milliseconds: 260);
  static const Duration _reverseTransitionDuration = Duration(
    milliseconds: 200,
  );
  static const Duration _shimmerDuration = Duration(milliseconds: 1800);

  @override
  ConsumerState<LyricsTaskStatusBanner> createState() =>
      _LyricsTaskStatusBannerState();
}

class _LyricsTaskStatusBannerState extends ConsumerState<LyricsTaskStatusBanner> {
  bool _isHovered = false;

  @override
  void didUpdateWidget(covariant LyricsTaskStatusBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final summary = ref.read(lyricsTaskQueueSummaryProvider);
    if (!summary.isBusy) {
      _isHovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final summary = ref.watch(lyricsTaskQueueSummaryProvider);
    final generationState = ref.watch(lyricsGenerationDisplayStateProvider);
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
        : l10n.lyricsTaskProcessing;
    final activeSong = summary.activeSong?.displayName.trim() ?? '';
    final progress = generationState.progress.clamp(0.0, 1.0);
    final showProgress =
        generationState.phase != LyricsGenerationPhase.idle && progress > 0.0;
    final phaseLabel = switch (generationState.phase) {
      LyricsGenerationPhase.uploading => l10n.lyricsTaskUploading,
      LyricsGenerationPhase.processing => l10n.lyricsTaskWaiting,
      LyricsGenerationPhase.requesting => l10n.lyricsTaskRequesting,
      LyricsGenerationPhase.generating => l10n.lyricsTaskGenerating,
      LyricsGenerationPhase.retrying => l10n.lyricsTaskRetrying,
      LyricsGenerationPhase.idle => '',
    };

    return AnimatedSwitcher(
      duration: LyricsTaskStatusBanner._transitionDuration,
      reverseDuration: LyricsTaskStatusBanner._reverseTransitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            ...previousChildren,
            if (currentChild case final Widget child) child,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      child: summary.isBusy
          ? LayoutBuilder(
              key: const ValueKey('lyrics_task_status_banner_visible'),
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth.isFinite
                    ? math
                          .max(
                            0.0,
                            math.min(constraints.maxWidth - 32, 440.0),
                          )
                          .toDouble()
                    : 440.0;

                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _isHovered = true),
                      onExit: (_) => setState(() => _isHovered = false),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
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
                          border: Border.all(
                            color: accent.withValues(alpha: 0.18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: _BusyBannerBody(
                          summary: summary,
                          taskLabel: taskLabel,
                          activeSong: activeSong,
                          showProgress: showProgress,
                          progress: progress,
                          phaseLabel: phaseLabel,
                          providerLabel: providerLabel,
                          modelNameLabel: modelNameLabel,
                          retryLabel: generationState.retryLabel,
                          l10n: l10n,
                          theme: theme,
                          colorScheme: colorScheme,
                          accent: accent,
                          shimmerDuration: LyricsTaskStatusBanner._shimmerDuration,
                          isHovered: _isHovered,
                          onCancel: () {
                            ref
                                .read(lyricsControllerProvider.notifier)
                                .cancelActiveAiTask();
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          : const SizedBox.shrink(
              key: ValueKey('lyrics_task_status_banner_hidden'),
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

class _BusyBannerBody extends StatelessWidget {
  const _BusyBannerBody({
    required this.summary,
    required this.taskLabel,
    required this.activeSong,
    required this.showProgress,
    required this.progress,
    required this.phaseLabel,
    required this.providerLabel,
    required this.modelNameLabel,
    required this.retryLabel,
    required this.l10n,
    required this.theme,
    required this.colorScheme,
    required this.accent,
    required this.shimmerDuration,
    required this.isHovered,
    required this.onCancel,
  });

  final LyricsTaskQueueSummary summary;
  final String taskLabel;
  final String activeSong;
  final bool showProgress;
  final double progress;
  final String phaseLabel;
  final String providerLabel;
  final String modelNameLabel;
  final String retryLabel;
  final AppLocalizations l10n;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final Color accent;
  final Duration shimmerDuration;
  final bool isHovered;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final shimmerBase = accent.withValues(alpha: 0.30);
    final shimmerHighlight = accent.withValues(alpha: 0.78);

    final Widget rightSideWidget;
    if (isHovered) {
      rightSideWidget = _CancelButton(
        key: const ValueKey('cancel_button'),
        label: l10n.cancel,
        onPressed: onCancel,
        accentColor: accent,
        colorScheme: colorScheme,
        theme: theme,
      );
    } else {
      rightSideWidget = Row(
        key: const ValueKey('status_info'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showProgress) ...[
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
            Shimmer.fromColors(
              baseColor: shimmerBase,
              highlightColor: shimmerHighlight,
              period: shimmerDuration,
              child: _BannerPill(
                label: '${l10n.queueTab} ${summary.taskCount}',
                accent: accent,
                filled: true,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Shimmer.fromColors(
              baseColor: shimmerBase,
              highlightColor: shimmerHighlight,
              period: shimmerDuration,
              child: Container(
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
                      const SizedBox(width: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SizeTransition(
                              sizeFactor: animation,
                              axis: Axis.horizontal,
                              alignment: Alignment.centerRight,
                              child: child,
                            ),
                          );
                        },
                        child: rightSideWidget,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _BannerInfoRow(
                    icon: Icons.bolt_rounded,
                    value: [
                      if (providerLabel.isNotEmpty) providerLabel,
                      if (modelNameLabel.isNotEmpty) modelNameLabel,
                    ].join(' · '),
                    theme: theme,
                  ),
                  if (retryLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _BannerInfoRow(
                      icon: Icons.refresh_rounded,
                      value: retryLabel,
                      theme: theme,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BannerInfoRow extends StatelessWidget {
  const _BannerInfoRow({
    required this.icon,
    required this.value,
    required this.theme,
  });

  final IconData icon;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = theme.colorScheme;

    return Opacity(
      opacity: 0.7,
      child: Row(
        children: [
          Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : l10n.unknownModel,
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

class _CancelButton extends StatefulWidget {
  const _CancelButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.accentColor,
    required this.colorScheme,
    required this.theme,
  });

  final String label;
  final VoidCallback onPressed;
  final Color accentColor;
  final ColorScheme colorScheme;
  final ThemeData theme;

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  bool _isButtonHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final hoverBgColor = colorScheme.error.withValues(alpha: 0.12);
    final normalBgColor = widget.accentColor.withValues(alpha: 0.08);
    final hoverBorderColor = colorScheme.error.withValues(alpha: 0.3);
    final normalBorderColor = widget.accentColor.withValues(alpha: 0.18);
    final hoverTextColor = colorScheme.error;
    final normalTextColor = widget.accentColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _isButtonHovered = true),
      onExit: (_) => setState(() => _isButtonHovered = false),
      child: AnimatedScale(
        scale: _isButtonHovered ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(999),
          hoverColor: Colors.transparent,
          splashColor: _isButtonHovered
              ? colorScheme.error.withValues(alpha: 0.15)
              : widget.accentColor.withValues(alpha: 0.15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            decoration: BoxDecoration(
              color: _isButtonHovered ? hoverBgColor : normalBgColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _isButtonHovered ? hoverBorderColor : normalBorderColor,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: _isButtonHovered ? hoverTextColor : normalTextColor,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: widget.theme.textTheme.labelSmall?.copyWith(
                    color: _isButtonHovered ? hoverTextColor : normalTextColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
