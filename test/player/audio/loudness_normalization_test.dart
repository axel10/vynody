import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/audio/loudness_normalization.dart';

void main() {
  group('parseReplayGainTags', () {
    test('parses standard ReplayGain tags with dB suffix and case insensitivity', () {
      final result = parseReplayGainTags({
        'TXXX:REPLAYGAIN_TRACK_GAIN': null,
        'REPLAYGAIN_TRACK_GAIN': ['-7.04 dB'],
        'REPLAYGAIN_TRACK_PEAK': ['1.104187'],
        'replaygain_album_gain': '-9.32 dB',
        'replaygain_album_peak': '1.235053',
      });

      expect(result.hasAny, isTrue);
      expect(result.trackLufs, closeTo(-10.96, 1e-6));
      expect(result.trackPeak, closeTo(1.104187, 1e-6));
      expect(result.albumLufs, closeTo(-8.68, 1e-6));
      expect(result.albumPeak, closeTo(1.235053, 1e-6));
    });

    test('parses ReplayGain values without dB unit', () {
      final result = parseReplayGainTags({
        'replaygain_track_gain': ['-11.29'],
        'replaygain_track_peak': ['1.0'],
      });

      expect(result.trackLufs, closeTo(-6.71, 1e-6));
      expect(result.trackPeak, closeTo(1.0, 1e-6));
    });

    test('parses Opus R128 Q7.8 gain tags relative to -23 LUFS', () {
      // +2560 in Q7.8 => +10.0 dB => -23 - 10 = -33 LUFS
      final result = parseReplayGainTags({
        'R128_TRACK_GAIN': ['2560'],
        'R128_ALBUM_GAIN': ['-1280'],
      });

      expect(result.trackLufs, closeTo(-33.0, 1e-6));
      expect(result.albumLufs, closeTo(-18.0, 1e-6));
    });

    test('returns empty result for invalid or missing tags', () {
      final result = parseReplayGainTags({
        'REPLAYGAIN_TRACK_GAIN': ['invalid'],
        'REPLAYGAIN_TRACK_PEAK': ['-0.5'],
      });

      expect(result.hasAny, isFalse);
      expect(result.trackLufs, isNull);
      expect(result.trackPeak, isNull);
    });
  });

  group('computeNormalizationGainDb', () {
    test('returns 0.0 when disabled or mode is off', () {
      expect(
        computeNormalizationGainDb(
          enabled: false,
          mode: LoudnessNormalizationMode.track,
          targetLufs: -18.0,
          clippingProtection: true,
          trackLufs: -8.0,
          trackPeak: 1.0,
        ),
        0.0,
      );

      expect(
        computeNormalizationGainDb(
          enabled: true,
          mode: LoudnessNormalizationMode.off,
          targetLufs: -18.0,
          clippingProtection: true,
          trackLufs: -8.0,
          trackPeak: 1.0,
        ),
        0.0,
      );
    });

    test('computes track and album gains with fallback behavior', () {
      final trackGain = computeNormalizationGainDb(
        enabled: true,
        mode: LoudnessNormalizationMode.track,
        targetLufs: -18.0,
        clippingProtection: false,
        trackLufs: -8.19,
        albumLufs: -8.68,
      );
      expect(trackGain, closeTo(-9.81, 1e-6));

      final albumGain = computeNormalizationGainDb(
        enabled: true,
        mode: LoudnessNormalizationMode.album,
        targetLufs: -18.0,
        clippingProtection: false,
        trackLufs: -8.19,
        albumLufs: -8.68,
      );
      expect(albumGain, closeTo(-9.32, 1e-6));

      final fallbackToTrack = computeNormalizationGainDb(
        enabled: true,
        mode: LoudnessNormalizationMode.album,
        targetLufs: -18.0,
        clippingProtection: false,
        trackLufs: -10.0,
      );
      expect(fallbackToTrack, closeTo(-8.0, 1e-6));

      final unanalyzedFallback = computeNormalizationGainDb(
        enabled: true,
        mode: LoudnessNormalizationMode.track,
        targetLufs: -18.0,
        clippingProtection: true,
        fallbackGainDb: -4.0,
      );
      expect(unanalyzedFallback, closeTo(-4.0, 1e-6));
    });

    test('applies true-peak clipping protection at -1.0 dBTP ceiling', () {
      // Quiet track: -24 LUFS, target -14 LUFS => raw +10 dB.
      // Peak = 0.5 (-6.02 dBFS) => max gain to reach -1.0 dBTP is +5.02 dB.
      final capped = computeNormalizationGainDb(
        enabled: true,
        mode: LoudnessNormalizationMode.track,
        targetLufs: -14.0,
        clippingProtection: true,
        trackLufs: -24.0,
        trackPeak: 0.5,
      );
      expect(capped, closeTo(5.0206, 1e-3));

      final uncapped = computeNormalizationGainDb(
        enabled: true,
        mode: LoudnessNormalizationMode.track,
        targetLufs: -14.0,
        clippingProtection: false,
        trackLufs: -24.0,
        trackPeak: 0.5,
      );
      expect(uncapped, closeTo(10.0, 1e-6));
    });
  });
}
