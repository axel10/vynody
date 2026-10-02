import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../widgets/app_bottom_sheet.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';

enum _SleepTimerSheetMode { configure, active }

class SleepTimerSheet extends ConsumerStatefulWidget {
  const SleepTimerSheet({super.key});

  @override
  ConsumerState<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<SleepTimerSheet> {
  static const Duration _defaultDuration = Duration(minutes: 30);

  late _SleepTimerSheetMode _mode;
  late Duration _selectedDuration;
  bool _stopAfterCurrentSong = false;

  @override
  void initState() {
    super.initState();
    final audio = ref.read(audioServiceProvider);
    _mode = audio.hasSleepTimer
        ? _SleepTimerSheetMode.active
        : _SleepTimerSheetMode.configure;
    _selectedDuration =
        audio.sleepTimerDuration ??
        ref.read(audioDurationProvider) - ref.read(audioPositionProvider);
    _stopAfterCurrentSong = audio.sleepTimerStopAfterCurrentSong;
    if (_selectedDuration <= Duration.zero) {
      _selectedDuration = _defaultDuration;
    }
  }

  String _formatDuration(Duration duration) {
    final safe = duration < Duration.zero ? Duration.zero : duration;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);
    return [
      hours.toString().padLeft(2, '0'),
      minutes.toString().padLeft(2, '0'),
      seconds.toString().padLeft(2, '0'),
    ].join(':');
  }

  Future<void> _startCustomTimer() async {
    final audio = ref.read(audioServiceProvider);
    await audio.startSleepTimer(
      _selectedDuration,
      stopAfterCurrentSong: _stopAfterCurrentSong,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _endTimer() async {
    final audio = ref.read(audioServiceProvider);
    await audio.cancelSleepTimer();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _resetTimer() async {
    final audio = ref.read(audioServiceProvider);
    final initialDuration = audio.sleepTimerDuration ?? _defaultDuration;
    await audio.cancelSleepTimer();
    if (!mounted) return;
    setState(() {
      _mode = _SleepTimerSheetMode.configure;
      _selectedDuration = initialDuration <= Duration.zero
          ? _defaultDuration
          : initialDuration;
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = ref.watch(audioSleepTimerRemainingProvider);
    final l10n = AppLocalizations.of(context)!;
    final isActive = _mode == _SleepTimerSheetMode.active;

    return AppAdaptiveSheet(
      sheetMaxWidth: 600,
      dialogMaxWidth: 560,
      landscapeMaxWidth: 760,
      title: isActive ? l10n.sleepTimerRunningTitle : l10n.sleepTimerTitle,
      subtitle: isActive
          ? l10n.sleepTimerRunningDescription
          : l10n.sleepTimerDescription,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: isActive
              ? _buildActiveView(context, remaining, l10n)
              : _buildConfigureView(context, l10n),
        ),
      ),
    );
  }

  Widget _buildConfigureView(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      key: const ValueKey('configure'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SizedBox(
            height: 210,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: theme.brightness,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: isDark
                          ? Colors.white
                          : theme.colorScheme.onSurface,
                      fontSize: 22,
                    ),
                  ),
                ),
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.hms,
                  initialTimerDuration: _selectedDuration,
                  minuteInterval: 1,
                  secondInterval: 1,
                  alignment: Alignment.center,
                  onTimerDurationChanged: (value) {
                    setState(() {
                      _selectedDuration = value;
                    });
                  },
                ),
              ),
            ),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _stopAfterCurrentSong,
            onChanged: (value) {
              setState(() {
                _stopAfterCurrentSong = value ?? false;
              });
            },
            title: Text(l10n.sleepTimerStopAfterCurrentSong),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _startCustomTimer,
                child: Text(l10n.startCountdown),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveView(
    BuildContext context,
    Duration? remaining,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final displayRemaining = remaining ?? Duration.zero;

    return Column(
      key: const ValueKey('active'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(
          child: Text(
            _formatDuration(displayRemaining),
            style: TextStyle(
              color: isDark ? Colors.white : theme.colorScheme.onSurface,
              fontSize: 40,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            l10n.remainingTime,
            style: TextStyle(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.65)
                  : theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _resetTimer,
                child: Text(l10n.reset),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _endTimer,
                child: Text(l10n.end),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
