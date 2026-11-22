import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/settings/sections/audio_section.dart';
import 'package:vynody/player/audio/android_usb_exclusive_controller.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/spatial_audio_mode.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/widgets/equalizer_panel.dart';

import 'helpers/mobile_screenshot_harness.dart';

class _FakeUsbExclusiveClient implements AndroidUsbExclusiveClient {
  _FakeUsbExclusiveClient({
    required this.isSupported,
    required bool exclusiveActive,
  }) : _status = UsbExclusiveStatus(
          exclusiveActive: exclusiveActive,
          streamRunning: exclusiveActive,
          paused: false,
          deviceName: exclusiveActive ? 'USB DAC' : '',
          vendorId: exclusiveActive ? 0x1234 : 0,
          productId: exclusiveActive ? 0x5678 : 0,
          uacVersion: exclusiveActive ? 'UAC 2.0' : '',
          sampleRate: exclusiveActive ? 96000 : 0,
          bitDepth: exclusiveActive ? 24 : 0,
          subslotSize: exclusiveActive ? 4 : 0,
          channels: exclusiveActive ? 2 : 0,
          hasFeedbackEndpoint: exclusiveActive,
          bufferedFrames: 0,
          playedFrames: 0,
          underrunCount: 0,
          supportedSampleRates: exclusiveActive ? const [44100, 48000, 96000] : const [],
        );

  @override
  final bool isSupported;

  final UsbExclusiveStatus _status;
  final _eventsController = StreamController<UsbExclusiveEvent>.broadcast();

  void dispose() {
    _eventsController.close();
  }

  @override
  Stream<UsbExclusiveEvent> get events => _eventsController.stream;

  @override
  Future<List<UsbAudioDeviceInfo>> listDevices() async => const [];

  @override
  Future<UsbExclusiveStatus> getStatus() async => _status;

  @override
  Future<UsbExclusiveToggleResult> setExclusiveMode({
    required bool enabled,
    String? deviceName,
  }) async {
    return UsbExclusiveToggleResult(ok: true, status: _status);
  }
}

class _NoopVolumeBridge implements AndroidUsbExclusiveVolumeBridge {
  @override
  Future<void> enterExclusiveVolume() async {}

  @override
  Future<void> exitExclusiveVolume() async {}
}

class _SpyAudioService extends MockAudioService {
  bool equalizerEnabledCalled = false;
  bool spatialAudioCalled = false;
  bool playbackSpeedCalled = false;

  _SpyAudioService({
    required super.snapshot,
    required super.visualizerStream,
  });

  @override
  Future<void> setEqualizerEnabled(bool enabled) async {
    equalizerEnabledCalled = true;
  }

  @override
  Future<void> setSpatialAudioMode(SpatialAudioMode mode) async {
    spatialAudioCalled = true;
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeedCalled = true;
  }
}

AudioSnapshot _buildSnapshot() {
  final demoSong = MusicFile(
    id: 1,
    path: '/test/demo.mp3',
    name: 'demo.mp3',
    title: 'Demo Song',
    artist: 'Demo Artist',
    album: 'Demo Album',
    durationMillis: 180000,
  );

  // Positive gain + 0 preamp would normally trigger the clipping warning.
  final bandGains = Float32List.fromList(
    [4.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  );
  final eqConfig = EqualizerConfig(
    enabled: true,
    bandCount: 10,
    preampDb: 0.0,
    bassBoostDb: 0.0,
    bassBoostFrequencyHz: 80.0,
    bassBoostQ: 1.0,
    bandGainsDb: bandGains,
  );

  return AudioSnapshot(
    isPlaying: false,
    isTransitioning: false,
    isLastActionNext: null,
    currentMusic: demoSong,
    position: Duration.zero,
    duration: const Duration(minutes: 3),
    volume: 1.0,
    isMuted: false,
    playbackQueue: [demoSong],
    currentIndex: 0,
    isRandomMode: false,
    isShuffleRandomMode: false,
    playbackMode: AppPlaybackMode.queue,
    equalizerConfig: eqConfig,
    currentVisualizerOptions: const VisualizerOptimizationOptions(
      frequencyGroups: 100,
    ),
    randomHistory: const [],
    randomQueue: const [],
    historyCursor: null,
    deckCursor: null,
    isVisualizerEnabled: false,
    dynamicStartColor: Colors.blue,
    dynamicEndColor: Colors.black,
    isLyricsActive: false,
    sleepTimerRemaining: null,
    sleepTimerDuration: null,
  );
}

void main() {
  testWidgets(
    'EqualizerPanel grays out and disables all controls when Android USB exclusive mode is active',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settingsService = TestSettingsService(prefs);
      final snapshot = _buildSnapshot();

      final visualizerStreamController = StreamController<FftFrame>.broadcast();
      addTearDown(visualizerStreamController.close);

      final audioService = _SpyAudioService(
        snapshot: snapshot,
        visualizerStream: visualizerStreamController.stream,
      );
      final usbClient = _FakeUsbExclusiveClient(
        isSupported: true,
        exclusiveActive: true,
      );
      addTearDown(usbClient.dispose);

      final container = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settingsService),
          audioServiceProvider.overrideWith((ref) => audioService),
          audioSnapshotProvider.overrideWith((ref) => snapshot),
          isProUnlockedProvider.overrideWithValue(true),
          androidUsbExclusiveClientProvider.overrideWithValue(usbClient),
          androidUsbExclusiveVolumeBridgeProvider
              .overrideWithValue(_NoopVolumeBridge()),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: EqualizerPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Notice banner and disabled subtitle are shown.
      expect(
        find.byKey(const ValueKey<String>('equalizer_usb_exclusive_banner')),
        findsOneWidget,
      );
      expect(
        find.text('当前处于 USB DAC 独占模式（源码直出），音效与倍速调节已停用'),
        findsOneWidget,
      );
      expect(find.text('USB DAC 独占模式下不可用'), findsOneWidget);

      // Clipping warning should be suppressed while EQ is bypassed.
      expect(find.text('音量过大，为了防止爆音请降低前置增益'), findsNothing);

      // Header Switch is disabled.
      final headerSwitch = tester.widget<Switch>(find.byType(Switch).first);
      expect(headerSwitch.onChanged, isNull);
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      expect(audioService.equalizerEnabledCalled, isFalse);

      // Body is wrapped in an ignoring IgnorePointer with reduced opacity.
      final ignorePointers = tester.widgetList<IgnorePointer>(
        find.descendant(
          of: find.byType(EqualizerPanel),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignorePointers.any((w) => w.ignoring), isTrue);

      final animatedOpacities = tester.widgetList<AnimatedOpacity>(
        find.descendant(
          of: find.byType(EqualizerPanel),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(animatedOpacities.any((w) => w.opacity < 0.5), isTrue);

      // Tapping spatial audio chip has no effect.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(EqualizerPanel)),
      )!;
      final concertHallChip = find.text(l10n.spatialAudioConcertHall);
      await tester.ensureVisible(concertHallChip);
      await tester.tap(concertHallChip, warnIfMissed: false);
      await tester.pump();
      expect(audioService.spatialAudioCalled, isFalse);
    },
  );

  testWidgets(
    'AudioSection disables fade effect switch while keeping equalizer band count enabled under USB exclusive mode',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settingsService = TestSettingsService(prefs);
      settingsService.enableFadeEffect = true;
      settingsService.equalizerBandCount = 10;

      final usbClient = _FakeUsbExclusiveClient(
        isSupported: true,
        exclusiveActive: true,
      );
      addTearDown(usbClient.dispose);

      final container = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settingsService),
          audioCurrentMusicProvider.overrideWithValue(null),
          isProUnlockedProvider.overrideWithValue(true),
          androidUsbExclusiveClientProvider.overrideWithValue(usbClient),
          androidUsbExclusiveVolumeBridgeProvider
              .overrideWithValue(_NoopVolumeBridge()),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: AudioSection(settings: settingsService)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fade effect switch is disabled and shows the USB exclusive hint.
      final fadeSwitchFinder = find.byKey(
        const ValueKey<String>('settings_enable_fade_effect_switch'),
      );
      await tester.ensureVisible(fadeSwitchFinder);
      final fadeSwitch = tester.widget<SwitchListTile>(fadeSwitchFinder);
      expect(fadeSwitch.onChanged, isNull);
      expect(find.text('USB DAC 独占模式下音频淡入淡出已自动停用'), findsOneWidget);

      // Equalizer band count SegmentedButton remains interactive.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AudioSection)),
      )!;
      final band15Finder = find.text(l10n.bandsCountOption(15));
      await tester.ensureVisible(band15Finder);
      await tester.tap(band15Finder);
      await tester.pumpAndSettle();
      expect(settingsService.equalizerBandCount, 15);
    },
  );
}
