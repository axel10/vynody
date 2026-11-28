import 'dart:math' as math;

/// How loudness normalization selects the reference loudness for a track.
enum LoudnessNormalizationMode {
  off,
  track,
  album;

  static LoudnessNormalizationMode fromStorage(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'album':
        return LoudnessNormalizationMode.album;
      case 'track':
        return LoudnessNormalizationMode.track;
      default:
        return LoudnessNormalizationMode.off;
    }
  }

  String get storageKey => name;
}

/// Source of the stored loudness data on [SongMetadata.loudnessSource].
abstract final class LoudnessSource {
  static const int none = 0;
  static const int embeddedTag = 1;
  static const int analyzedEbuR128 = 2;
}

/// Parsed ReplayGain / Opus R128 loudness values converted to LUFS and linear peak.
class ReplayGainParseResult {
  const ReplayGainParseResult({
    this.trackLufs,
    this.trackPeak,
    this.albumLufs,
    this.albumPeak,
  });

  final double? trackLufs;
  final double? trackPeak;
  final double? albumLufs;
  final double? albumPeak;

  bool get hasAny => trackLufs != null || albumLufs != null;
}

/// Standard ReplayGain 2.0 reference loudness (-18 LUFS).
const double kReplayGainReferenceLufs = -18.0;

/// RFC 7845 Opus R128 reference loudness (-23 LUFS).
const double kOpusR128ReferenceLufs = -23.0;

/// Safe clamping bounds for applied normalization gain (dB).
const double kMinNormalizationGainDb = -24.0;
const double kMaxNormalizationGainDb = 18.0;

/// Default ceiling for true-peak clipping protection (dBTP).
const double kDefaultMaxPeakDb = -1.0;

/// Parses ReplayGain (`REPLAYGAIN_*`) and Opus R128 (`R128_*`) tags from
/// TagLib property maps (`Map<String, List<String>>` or `Map<String, String>`).
ReplayGainParseResult parseReplayGainTags(Map<String, dynamic> properties) {
  if (properties.isEmpty) {
    return const ReplayGainParseResult();
  }

  final normalized = <String, String>{};
  for (final entry in properties.entries) {
    final key = entry.key.trim().toLowerCase();
    final value = _extractFirstTagValue(entry.value);
    if (value != null && value.isNotEmpty) {
      normalized[key] = value;
    }
  }

  double? trackLufs;
  double? albumLufs;

  final rgTrackGain = _parseGainDb(normalized['replaygain_track_gain']);
  if (rgTrackGain != null) {
    trackLufs = kReplayGainReferenceLufs - rgTrackGain;
  } else {
    final r128Track = _parseR128Q78Db(normalized['r128_track_gain']);
    if (r128Track != null) {
      trackLufs = kOpusR128ReferenceLufs - r128Track;
    }
  }

  final rgAlbumGain = _parseGainDb(normalized['replaygain_album_gain']);
  if (rgAlbumGain != null) {
    albumLufs = kReplayGainReferenceLufs - rgAlbumGain;
  } else {
    final r128Album = _parseR128Q78Db(normalized['r128_album_gain']);
    if (r128Album != null) {
      albumLufs = kOpusR128ReferenceLufs - r128Album;
    }
  }

  final trackPeak = _parsePositivePeak(normalized['replaygain_track_peak']);
  final albumPeak = _parsePositivePeak(normalized['replaygain_album_peak']);

  return ReplayGainParseResult(
    trackLufs: trackLufs,
    trackPeak: trackPeak,
    albumLufs: albumLufs,
    albumPeak: albumPeak,
  );
}

/// Computes the playback gain (in dB) to apply for a track given user settings
/// and stored loudness measurements.
double computeNormalizationGainDb({
  required bool enabled,
  required LoudnessNormalizationMode mode,
  required double targetLufs,
  required bool clippingProtection,
  double maxPeakDb = kDefaultMaxPeakDb,
  double fallbackGainDb = 0.0,
  double? trackLufs,
  double? trackPeak,
  double? albumLufs,
  double? albumPeak,
}) {
  if (!enabled || mode == LoudnessNormalizationMode.off) {
    return 0.0;
  }

  double? selectedLufs;
  double? selectedPeak;

  if (mode == LoudnessNormalizationMode.album) {
    selectedLufs = albumLufs ?? trackLufs;
    selectedPeak = albumPeak ?? trackPeak;
  } else {
    selectedLufs = trackLufs ?? albumLufs;
    selectedPeak = trackPeak ?? albumPeak;
  }

  if (selectedLufs == null || !selectedLufs.isFinite) {
    return fallbackGainDb.clamp(
      kMinNormalizationGainDb,
      kMaxNormalizationGainDb,
    );
  }

  var gainDb = targetLufs - selectedLufs;

  if (clippingProtection &&
      selectedPeak != null &&
      selectedPeak.isFinite &&
      selectedPeak > 0.0) {
    final peakDb = 20.0 * (math.log(selectedPeak) / math.ln10);
    final maxAllowedGain = maxPeakDb - peakDb;
    if (gainDb > maxAllowedGain) {
      gainDb = maxAllowedGain;
    }
  }

  return gainDb.clamp(kMinNormalizationGainDb, kMaxNormalizationGainDb);
}

String? _extractFirstTagValue(dynamic raw) {
  if (raw == null) return null;
  if (raw is String) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (raw is Iterable) {
    for (final item in raw) {
      final s = item?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
  }
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}

double? _parseGainDb(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final match = RegExp(r'[-+]?\d+(?:\.\d+)?').firstMatch(raw);
  if (match == null) return null;
  final value = double.tryParse(match.group(0)!);
  if (value == null || !value.isFinite) return null;
  return value;
}

double? _parseR128Q78Db(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final q78 = int.tryParse(raw.trim());
  if (q78 == null) return null;
  return q78 / 256.0;
}

double? _parsePositivePeak(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final value = double.tryParse(raw.trim());
  if (value == null || !value.isFinite || value <= 0.0) return null;
  return value;
}
