/// Utility and extensions for formatting audio/media durations.
class TimeFormatUtils {
  const TimeFormatUtils._();

  /// Formats milliseconds into a standard "m:ss" or "h:mm:ss" string.
  /// Returns [fallback] (default `'--:--'`) if [durationMs] is null or negative.
  static String formatMs(int? durationMs, {String fallback = '--:--'}) {
    if (durationMs == null || durationMs < 0) return fallback;
    return formatDuration(Duration(milliseconds: durationMs), fallback: fallback);
  }

  /// Formats a [Duration] into "m:ss" or "h:mm:ss".
  static String formatDuration(Duration? duration, {String fallback = '--:--'}) {
    if (duration == null || duration.isNegative) return fallback;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

extension DurationFormatExt on Duration? {
  String toFormattedString({String fallback = '--:--'}) {
    return TimeFormatUtils.formatDuration(this, fallback: fallback);
  }
}

extension IntDurationFormatExt on int? {
  String toFormattedDuration({String fallback = '--:--'}) {
    return TimeFormatUtils.formatMs(this, fallback: fallback);
  }
}
