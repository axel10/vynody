import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/pro/app_channel.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/pro/pro_models.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProLicenseService Tests', () {
    test('Default GitHub channel defaults to unlimitedCommunity', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = ProLicenseService(prefs: prefs);

      // Default env is github
      if (AppChannel.isGitHubRelease) {
        expect(service.state.type, LicenseType.unlimitedCommunity);
        expect(service.state.isProUnlocked, isTrue);
      }
    });

    test('LicenseState models and trial calculations', () {
      final now = DateTime.now();
      final expire = now.add(const Duration(days: 10));

      final trialState = LicenseState(
        type: LicenseType.activeTrial,
        trialTotalDays: 15,
        trialDaysRemaining: 10,
        firstLaunchTime: now,
        trialExpireTime: expire,
      );

      expect(trialState.isInTrial, isTrue);
      expect(trialState.isProUnlocked, isTrue);
      expect(trialState.trialDaysRemaining, 10);

      final expiredState = LicenseState(
        type: LicenseType.expiredTrial,
        trialTotalDays: 15,
        trialDaysRemaining: 0,
        firstLaunchTime: now.subtract(const Duration(days: 16)),
        trialExpireTime: now.subtract(const Duration(days: 1)),
      );

      expect(expiredState.isTrialExpired, isTrue);
      expect(expiredState.isProUnlocked, isFalse);
    });

    test('ProFeature enum contains dynamicMeshBackground and customImageBackground', () {
      expect(ProFeature.values, contains(ProFeature.dynamicMeshBackground));
      expect(ProFeature.values, contains(ProFeature.customImageBackground));
      expect(ProFeature.dynamicMeshBackground.icon, isNotNull);
      expect(ProFeature.customImageBackground.icon, isNotNull);
    });

    test('Effective settings providers correctly gate features without altering persistent storage', () async {
      SharedPreferences.setMockInitialValues({
        'visualizer_enabled': true,
        'equalizer_enabled': true,
        'playback_background_type': 1, // dynamic mesh
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      // 1. Pro Unlocked container
      final unlockedContainer = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => SettingsService(prefs)),
          isProUnlockedProvider.overrideWithValue(true),
        ],
      );

      expect(unlockedContainer.read(effectiveVisualizerEnabledProvider), isTrue);
      expect(unlockedContainer.read(effectiveEqualizerEnabledProvider), isTrue);
      expect(unlockedContainer.read(effectivePlaybackBackgroundTypeProvider), 1);

      // 2. Pro Locked container
      final lockedContainer = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => SettingsService(prefs)),
          isProUnlockedProvider.overrideWithValue(false),
        ],
      );

      expect(lockedContainer.read(effectiveVisualizerEnabledProvider), isFalse);
      expect(lockedContainer.read(effectiveEqualizerEnabledProvider), isFalse);
      expect(lockedContainer.read(effectivePlaybackBackgroundTypeProvider), 0);

      // Verify underlying persistent storage remains unmodified
      expect(settings.isVisualizerEnabled, isTrue);
      expect(settings.equalizerEnabled, isTrue);
      expect(settings.playbackBackgroundType, 1);
      expect(prefs.getBool('visualizer_enabled'), isTrue);
      expect(prefs.getBool('equalizer_enabled'), isTrue);
      expect(prefs.getInt('playback_background_type'), 1);

      unlockedContainer.dispose();
      lockedContainer.dispose();
    });

    test('v2.13.2 Trial Reset resets expired trial for existing users and flags pending notice', () async {
      final oldExpiredLaunch = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'vynody_license_first_launch_epoch_ms': oldExpiredLaunch,
        // 'vynody_trial_reset_v2_13_2_done' is not set
      });
      final prefs = await SharedPreferences.getInstance();
      final service = ProLicenseService(prefs: prefs);

      if (!AppChannel.isGitHubRelease) {
        // Wait for async _init
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(service.state.isInTrial, isTrue);
        expect(service.state.trialDaysRemaining, ProConfig.trialDays);
        expect(service.pendingTrialResetNotice, isTrue);
        expect(prefs.getBool('vynody_trial_reset_v2_13_2_done'), isTrue);

        await service.consumeTrialResetNotice();
        expect(service.pendingTrialResetNotice, isFalse);
        expect(prefs.getBool('vynody_pending_trial_reset_v2_13_2_notice'), isFalse);
      }
    });

    test('v2.13.2 Trial Reset skips purchased Pro users', () async {
      SharedPreferences.setMockInitialValues({
        'vynody_license_first_launch_epoch_ms': 1000,
        'vynody_license_pro_purchased': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final service = ProLicenseService(prefs: prefs);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.state.isPermanentlyUnlocked, isTrue);
      expect(service.pendingTrialResetNotice, isFalse);
      expect(prefs.getBool('vynody_trial_reset_v2_13_2_done'), isTrue);
    });

    test('Fresh install on v2.13.2+ initializes trial normally without triggering notice dialog', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = ProLicenseService(prefs: prefs);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      if (!AppChannel.isGitHubRelease) {
        expect(service.state.isInTrial, isTrue);
        expect(service.state.trialDaysRemaining, ProConfig.trialDays);
        expect(service.pendingTrialResetNotice, isFalse);
        expect(prefs.getBool('vynody_trial_reset_v2_13_2_done'), isTrue);
        expect(prefs.getBool('vynody_pending_trial_reset_v2_13_2_notice'), isNot(isTrue));
      }
    });

    test('ProLicenseService safely handles String type in vynody_license_first_launch_epoch_ms without crashing', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // Simulate AppSecureStorage encryption string or raw string stored by earlier bug
      final encryptedVal = AppSecureStorage.encrypt(nowMs.toString());
      SharedPreferences.setMockInitialValues({
        'vynody_license_first_launch_epoch_ms': encryptedVal,
        'vynody_trial_reset_v2_13_2_done': true,
      });
      final prefs = await SharedPreferences.getInstance();

      // Synchronous constructor should NOT throw type 'String' is not a subtype of type 'int?'
      final service = ProLicenseService(prefs: prefs);
      expect(service.state, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // After init, dirty data in SharedPreferences should be healed to int
      final healedVal = prefs.get('vynody_license_first_launch_epoch_ms');
      expect(healedVal, isA<int>());
      expect(healedVal, nowMs);
    });

    test('AppSecureStorage uses namespaced prefix and does not overwrite normal SharedPreferences keys', () async {
      SharedPreferences.setMockInitialValues({
        'my_test_key': 12345,
      });
      final prefs = await SharedPreferences.getInstance();
      final secure = AppSecureStorage(prefs);

      await secure.write(key: 'my_test_key', value: 'secret_string');

      // The raw prefs key should remain integer 12345
      expect(prefs.getInt('my_test_key'), 12345);

      // Secure storage should read the encrypted secret string
      expect(await secure.read(key: 'my_test_key'), 'secret_string');
      expect(secure.readSync(key: 'my_test_key'), 'secret_string');
    });
  });
}

