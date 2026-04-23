import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../player/audio_riverpod.dart';

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
    await audio.startSleepTimer(_selectedDuration);
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

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _mode == _SleepTimerSheetMode.active
                ? _buildActiveView(context, remaining, l10n)
                : _buildConfigureView(context, l10n),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildConfigureView(BuildContext context, AppLocalizations l10n) {
    return Column(
      key: const ValueKey('configure'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitle(l10n.sleepTimerTitle, l10n.sleepTimerDescription),
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
    final displayRemaining = remaining ?? Duration.zero;
    return Column(
      key: const ValueKey('active'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitle(
          l10n.sleepTimerRunningTitle,
          l10n.sleepTimerRunningDescription,
        ),
        const SizedBox(height: 22),
        Center(
          child: Text(
            _formatDuration(displayRemaining),
            style: const TextStyle(
              color: Colors.white,
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
              color: Colors.white.withValues(alpha: 0.65),
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
