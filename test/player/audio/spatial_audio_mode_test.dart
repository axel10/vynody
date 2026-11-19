import 'package:audio_core/audio_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/spatial_audio_mode.dart';
import 'package:vynody/player/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpatialAudioMode', () {
    test('fromStorage parses known values and falls back to off', () {
      expect(SpatialAudioMode.fromStorage(null), SpatialAudioMode.off);
      expect(SpatialAudioMode.fromStorage(''), SpatialAudioMode.off);
      expect(SpatialAudioMode.fromStorage('unknown'), SpatialAudioMode.off);
      expect(SpatialAudioMode.fromStorage('off'), SpatialAudioMode.off);
      expect(
        SpatialAudioMode.fromStorage('freeverb'),
        SpatialAudioMode.concertHall,
      );
      expect(
        SpatialAudioMode.fromStorage('fundsp_fdn'),
        SpatialAudioMode.naturalEcho,
      );
    });

    test('toReverbConfig uses audio_core default parameters', () {
      final off = SpatialAudioMode.off.toReverbConfig();
      expect(off.enabled, isFalse);

      final hall = SpatialAudioMode.concertHall.toReverbConfig();
      expect(hall.enabled, isTrue);
      expect(hall.algorithm, ReverbAlgorithm.freeverb);
      expect(hall.dryMix, closeTo(0.90, 1e-6));
      expect(hall.wetMix, closeTo(0.22, 1e-6));
      expect(hall.roomSize, closeTo(0.70, 1e-6));
      expect(hall.damping, closeTo(0.50, 1e-6));
      expect(hall.width, closeTo(0.85, 1e-6));
      expect(hall.timeSeconds, closeTo(3.02, 1e-6));
      expect(hall.freeze, isFalse);

      final echo = SpatialAudioMode.naturalEcho.toReverbConfig();
      expect(echo.enabled, isTrue);
      expect(echo.algorithm, ReverbAlgorithm.fundspStereo);
      expect(echo.dryMix, closeTo(0.76, 1e-6));
      expect(echo.wetMix, closeTo(1.00, 1e-6));
      expect(echo.roomSize, closeTo(0.88, 1e-6));
      expect(echo.damping, closeTo(1.00, 1e-6));
      expect(echo.width, closeTo(0.85, 1e-6));
      expect(echo.timeSeconds, closeTo(3.02, 1e-6));
      expect(echo.freeze, isFalse);
    });

    test('toReverbConfig disables reverb when Pro is locked', () {
      final hallLocked = SpatialAudioMode.concertHall.toReverbConfig(
        isProUnlocked: false,
      );
      expect(hallLocked.enabled, isFalse);
      expect(hallLocked.algorithm, ReverbAlgorithm.freeverb);

      final echoLocked = SpatialAudioMode.naturalEcho.toReverbConfig(
        isProUnlocked: false,
      );
      expect(echoLocked.enabled, isFalse);
      expect(echoLocked.algorithm, ReverbAlgorithm.fundspStereo);
    });
  });

  group('SettingsService.spatialAudioMode', () {
    test('defaults to off and persists selection', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      expect(settings.spatialAudioMode, SpatialAudioMode.off);

      settings.spatialAudioMode = SpatialAudioMode.concertHall;
      expect(settings.spatialAudioMode, SpatialAudioMode.concertHall);

      final reloaded = SettingsService(prefs);
      expect(reloaded.spatialAudioMode, SpatialAudioMode.concertHall);

      reloaded.spatialAudioMode = SpatialAudioMode.naturalEcho;
      expect(
        SettingsService(prefs).spatialAudioMode,
        SpatialAudioMode.naturalEcho,
      );
    });
  });
}
