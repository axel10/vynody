import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

const double _timelineOffsetMinSeconds = -20.0;
const double _timelineOffsetMaxSeconds = 20.0;
const double _timelineOffsetStepSeconds = 0.1;

Future<void> showTimelineAdjustmentDialog(
  BuildContext context, {
  required double initialTimelineOffsetSeconds,
  required void Function(double timelineOffsetSeconds) onPreviewChanged,
  required Future<void> Function(Duration timelineOffset) onCommit,
}) async {
  final theme = Theme.of(context);
  final dialogValue = ValueNotifier<double>(initialTimelineOffsetSeconds);

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dialogL10n = AppLocalizations.of(context)!;
            final value = _normalizeTimelineOffsetSeconds(dialogValue.value);
            final label = _timelineOffsetLabel(dialogL10n, value);

            Future<void> commitOffset(double newValue) async {
              final snapped = _normalizeTimelineOffsetSeconds(newValue);
              setDialogState(() {
                dialogValue.value = snapped;
              });
              onPreviewChanged(snapped);
              await onCommit(
                Duration(milliseconds: (snapped * 1000).round()),
              );
            }

            return AlertDialog(
              title: Text(l10n.timelineAdjustmentTitle),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      dialogL10n.timelineAdjustmentDescription,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: value,
                      min: _timelineOffsetMinSeconds,
                      max: _timelineOffsetMaxSeconds,
                      divisions:
                          ((_timelineOffsetMaxSeconds -
                                      _timelineOffsetMinSeconds) /
                                  _timelineOffsetStepSeconds)
                              .round(),
                      label: label,
                      onChanged: (newValue) {
                        final snapped = _normalizeTimelineOffsetSeconds(
                          newValue,
                        );
                        setDialogState(() {
                          dialogValue.value = snapped;
                        });
                        onPreviewChanged(snapped);
                      },
                      onChangeEnd: (newValue) {
                        unawaited(commitOffset(newValue));
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          dialogL10n.timelineOffsetEarlier('20.0'),
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          dialogL10n.timelineOffsetLater('20.0'),
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: value == 0
                      ? null
                      : () {
                          unawaited(commitOffset(0));
                        },
                  child: Text(l10n.reset),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.close),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    dialogValue.dispose();
  }
}

double _normalizeTimelineOffsetSeconds(double value) {
  final clamped = value.clamp(
    _timelineOffsetMinSeconds,
    _timelineOffsetMaxSeconds,
  );
  return (clamped * 10).roundToDouble() / 10.0;
}

String _timelineOffsetLabel(AppLocalizations l10n, double seconds) {
  final normalized = _normalizeTimelineOffsetSeconds(seconds);
  if (normalized == 0) {
    return l10n.timelineOffsetCurrent;
  }

  final value = normalized.abs().toStringAsFixed(1);
  return normalized > 0
      ? l10n.timelineOffsetLater(value)
      : l10n.timelineOffsetEarlier(value);
}
