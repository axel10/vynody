import 'dart:async';

import 'package:flutter/material.dart';

const double _timelineOffsetMinSeconds = -10.0;
const double _timelineOffsetMaxSeconds = 10.0;
const double _timelineOffsetStepSeconds = 0.1;

Future<void> showTimelineAdjustmentDialog(
  BuildContext context, {
  required double initialTimelineOffsetSeconds,
  required void Function(double timelineOffsetSeconds) onPreviewChanged,
  required Future<void> Function(Duration timelineOffset) onCommit,
}) async {
  final theme = Theme.of(context);
  final dialogValue = ValueNotifier<double>(initialTimelineOffsetSeconds);

  Future<void> commitOffset(double value) async {
    final snapped = _normalizeTimelineOffsetSeconds(value);
    dialogValue.value = snapped;
    onPreviewChanged(snapped);
    await onCommit(Duration(milliseconds: (snapped * 1000).round()));
  }

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('手动调整时间轴'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              final value = _normalizeTimelineOffsetSeconds(dialogValue.value);
              final label = _timelineOffsetLabel(value);
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '向右拖动会让歌词整体延后，向左拖动会让歌词整体提前。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
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
                          '提前 30.0 秒',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '延后 30.0 秒',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: dialogValue.value == 0
                  ? null
                  : () {
                      final snapped = _normalizeTimelineOffsetSeconds(0);
                      dialogValue.value = snapped;
                      onPreviewChanged(snapped);
                      unawaited(commitOffset(snapped));
                    },
              child: const Text('重置'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
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

String _timelineOffsetLabel(double seconds) {
  final normalized = _normalizeTimelineOffsetSeconds(seconds);
  if (normalized == 0) {
    return '当前偏移：0.0 秒';
  }

  final direction = normalized > 0 ? '延后' : '提前';
  return '当前偏移：$direction ${normalized.abs().toStringAsFixed(1)} 秒';
}
