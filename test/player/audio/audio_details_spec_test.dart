import 'package:flutter_test/flutter_test.dart';
import 'package:audio_core/audio_core.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';

void main() {
  group('formatAudioSpec', () {
    test('returns empty string when details is null', () {
      expect(formatAudioSpec(null), equals(''));
    });

    test('formats FLAC Hi-Res details correctly', () {
      const details = AudioDetails(
        formatName: 'flac',
        codecName: 'flac',
        duration: Duration(minutes: 3),
        bitrate: 2840000,
        sampleRate: 96000,
        channels: 2,
        bitDepth: 24,
        bitrateMode: 'vbr',
        fileSize: 45000000,
      );

      expect(formatAudioSpec(details), equals('FLAC · 24bit · 96 kHz · 2840 kbps'));
    });

    test('formats MP3 CBR details correctly without bit depth', () {
      const details = AudioDetails(
        formatName: 'mp3',
        codecName: 'mp3',
        duration: Duration(minutes: 4),
        bitrate: 320000,
        sampleRate: 44100,
        channels: 2,
        bitDepth: null,
        bitrateMode: 'cbr',
        fileSize: 9600000,
      );

      expect(formatAudioSpec(details), equals('MP3 · 44.1 kHz · 320 kbps'));
    });

    test('formats WAV CD-quality details correctly', () {
      const details = AudioDetails(
        formatName: 'wav',
        codecName: 'pcm',
        duration: Duration(minutes: 5),
        bitrate: 1411200,
        sampleRate: 44100,
        channels: 2,
        bitDepth: 16,
        bitrateMode: 'cbr',
        fileSize: 50000000,
      );

      expect(formatAudioSpec(details), equals('WAV · 16bit · 44.1 kHz · 1411 kbps'));
    });

    test('handles fractional sample rates such as 88.2 kHz and 48 kHz integer', () {
      const details48k = AudioDetails(
        formatName: 'aac',
        codecName: 'aac',
        duration: Duration(minutes: 2),
        bitrate: 256000,
        sampleRate: 48000,
        channels: 2,
        bitDepth: null,
        bitrateMode: 'vbr',
        fileSize: 4000000,
      );
      expect(formatAudioSpec(details48k), equals('AAC · 48 kHz · 256 kbps'));

      const details88k = AudioDetails(
        formatName: 'alac',
        codecName: 'alac',
        duration: Duration(minutes: 2),
        bitrate: 1800000,
        sampleRate: 88200,
        channels: 2,
        bitDepth: 24,
        bitrateMode: 'vbr',
        fileSize: 20000000,
      );
      expect(formatAudioSpec(details88k), equals('ALAC · 24bit · 88.2 kHz · 1800 kbps'));
    });
  });
}
