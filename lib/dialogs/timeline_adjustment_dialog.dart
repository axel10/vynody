import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// 时间轴偏移统一精度（秒），即 0.1 秒。
const double _timelineOffsetStepScale = 10.0;

/// 弹窗默认允许的最大调整幅度（秒）。
const double kTimelineOffsetDefaultRangeSeconds = 20.0;

/// 弹窗内「最大调整范围」输入框允许的下限 / 上限（秒）。
const double kTimelineOffsetMinRangeSeconds = 1.0;
const double kTimelineOffsetMaxRangeSeconds = 600.0;

/// 偏移值的兜底硬上限（秒）：只用于防止异常值写入，不作为界面上限。
const double kTimelineOffsetHardLimitSeconds = 3600.0;

/// 把偏移量对齐到 0.1 秒精度，并做兜底钳制。
double normalizeTimelineOffsetSeconds(double value) {
  final clamped = value.clamp(
    -kTimelineOffsetHardLimitSeconds,
    kTimelineOffsetHardLimitSeconds,
  );
  return (clamped * _timelineOffsetStepScale).roundToDouble() /
      _timelineOffsetStepScale;
}

Future<void> showTimelineAdjustmentDialog(
  BuildContext context, {
  required double initialTimelineOffsetSeconds,
  required void Function(double timelineOffsetSeconds) onPreviewChanged,
  required Future<void> Function(Duration timelineOffset) onCommit,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _TimelineAdjustmentDialog(
      initialTimelineOffsetSeconds: initialTimelineOffsetSeconds,
      onPreviewChanged: onPreviewChanged,
      onCommit: onCommit,
    ),
  );
}

/// 弹窗本体。控制器与焦点在 State 里创建/释放：`showDialog` 的 Future 完成时
/// 路由还在退出转场，此时外部强行 dispose 会让仍在树上的 TextField 取到已释放的
/// FocusNode（A FocusNode was used after being disposed）。
class _TimelineAdjustmentDialog extends StatefulWidget {
  const _TimelineAdjustmentDialog({
    required this.initialTimelineOffsetSeconds,
    required this.onPreviewChanged,
    required this.onCommit,
  });

  final double initialTimelineOffsetSeconds;
  final void Function(double timelineOffsetSeconds) onPreviewChanged;
  final Future<void> Function(Duration timelineOffset) onCommit;

  @override
  State<_TimelineAdjustmentDialog> createState() =>
      _TimelineAdjustmentDialogState();
}

class _TimelineAdjustmentDialogState extends State<_TimelineAdjustmentDialog> {
  late double _maxRangeSeconds;
  late double _value;
  late final TextEditingController _rangeController;
  final FocusNode _rangeFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _maxRangeSeconds = _initialRangeSeconds(widget.initialTimelineOffsetSeconds);
    _value = _clampToRange(
      normalizeTimelineOffsetSeconds(widget.initialTimelineOffsetSeconds),
    );
    _rangeController = TextEditingController(
      text: _formatRange(_maxRangeSeconds),
    );
    _rangeFocusNode.addListener(_handleRangeFocusChanged);
  }

  @override
  void dispose() {
    _rangeFocusNode.removeListener(_handleRangeFocusChanged);
    _rangeFocusNode.dispose();
    _rangeController.dispose();
    super.dispose();
  }

  double _clampToRange(double seconds) {
    return seconds.clamp(-_maxRangeSeconds, _maxRangeSeconds);
  }

  void _handleRangeFocusChanged() {
    if (_rangeFocusNode.hasFocus) return;
    // 弹窗正在关闭（点了关闭或遮罩）时失焦不再回写，避免关闭帧里又 setState。
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _applyRangeInput();
  }

  /// 输入框失焦或回车时生效，避免边输入边改范围导致偏移被反复钳制。
  void _applyRangeInput() {
    if (!mounted) return;
    final raw = _rangeController.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw);
    final nextRange = normalizeTimelineOffsetSeconds(
      (parsed == null || parsed.isNaN ? _maxRangeSeconds : parsed).clamp(
        kTimelineOffsetMinRangeSeconds,
        kTimelineOffsetMaxRangeSeconds,
      ),
    );
    final previousValue = _value;
    final nextValue = normalizeTimelineOffsetSeconds(
      previousValue,
    ).clamp(-nextRange, nextRange);

    setState(() {
      _maxRangeSeconds = nextRange;
      _rangeController.text = _formatRange(nextRange);
      _value = nextValue;
    });

    if (nextValue == previousValue) return;
    // 范围被收窄到当前偏移之下：把偏移钳进新范围，避免界面与库内值不一致。
    widget.onPreviewChanged(nextValue);
    unawaited(
      widget.onCommit(Duration(milliseconds: (nextValue * 1000).round())),
    );
  }

  Future<void> _commit(double newValue) async {
    if (!mounted) return;
    final snapped = _clampToRange(normalizeTimelineOffsetSeconds(newValue));
    setState(() {
      _value = snapped;
    });
    widget.onPreviewChanged(snapped);
    await widget.onCommit(Duration(milliseconds: (snapped * 1000).round()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final value = _clampToRange(normalizeTimelineOffsetSeconds(_value));
    final label = _timelineOffsetLabel(l10n, value);

    return AlertDialog(
      title: Text(l10n.timelineAdjustmentTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.timelineAdjustmentDescription,
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
              min: -_maxRangeSeconds,
              max: _maxRangeSeconds,
              label: label,
              onChanged: (newValue) {
                final snapped = _clampToRange(
                  normalizeTimelineOffsetSeconds(newValue),
                );
                setState(() {
                  _value = snapped;
                });
                widget.onPreviewChanged(snapped);
              },
              onChangeEnd: (newValue) {
                unawaited(_commit(newValue));
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.timelineOffsetEarlier(_formatRange(_maxRangeSeconds)),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
                Text(
                  l10n.timelineOffsetLater(_formatRange(_maxRangeSeconds)),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: SizedBox(
                width: 150,
                child: TextField(
                  controller: _rangeController,
                  focusNode: _rangeFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l10n.timelineMaxRangeLabel,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) {
                    _rangeFocusNode.unfocus();
                  },
                  onTapOutside: (_) {
                    _rangeFocusNode.unfocus();
                  },
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: value == 0
                      ? null
                      : () {
                          unawaited(_commit(0));
                        },
                  child: Text(l10n.reset),
                ),
                TextButton(
                  onPressed: () {
                    _applyRangeInput();
                    Navigator.of(context).pop();
                  },
                  child: Text(l10n.close),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// 默认范围至少 [kTimelineOffsetDefaultRangeSeconds]，且必须覆盖已有偏移。
double _initialRangeSeconds(double initialOffsetSeconds) {
  final magnitude = initialOffsetSeconds.abs();
  if (magnitude <= kTimelineOffsetDefaultRangeSeconds) {
    return kTimelineOffsetDefaultRangeSeconds;
  }
  return (magnitude / 10).ceilToDouble() * 10;
}

String _formatRange(double seconds) {
  return seconds == seconds.roundToDouble()
      ? seconds.toStringAsFixed(0)
      : seconds.toStringAsFixed(1);
}

String _timelineOffsetLabel(AppLocalizations l10n, double seconds) {
  final normalized = normalizeTimelineOffsetSeconds(seconds);
  if (normalized == 0) {
    return l10n.timelineOffsetCurrent;
  }

  final value = normalized.abs().toStringAsFixed(1);
  return normalized > 0
      ? l10n.timelineOffsetLater(value)
      : l10n.timelineOffsetEarlier(value);
}
