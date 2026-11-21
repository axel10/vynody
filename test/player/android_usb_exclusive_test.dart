import 'dart:async';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/settings/sections/audio_section.dart';
import 'package:vynody/pages/settings_page.dart';
import 'package:vynody/player/audio/android_usb_exclusive_controller.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/playback/playback_progress_section.dart';

class _FakeAndroidUsbExclusiveClient implements AndroidUsbExclusiveClient {
  _FakeAndroidUsbExclusiveClient({
    this.devices = const <UsbAudioDeviceInfo>[],
    this.status = UsbExclusiveStatus.empty,
  });

  @override
  bool get isSupported => true;

  List<UsbAudioDeviceInfo> devices;
  UsbExclusiveStatus status;
  bool shouldFailToggle = false;
  String? toggleError;
  int setExclusiveCalls = 0;
  bool? lastRequestedEnabled;
  String? lastRequestedDeviceName;

  final StreamController<UsbExclusiveEvent> _eventController =
      StreamController<UsbExclusiveEvent>.broadcast();

  @override
  Stream<UsbExclusiveEvent> get events => _eventController.stream;

  void emitEvent(UsbExclusiveEvent event) {
    status = event.status;
    _eventController.add(event);
  }

  Future<void> close() => _eventController.close();

  @override
  Future<List<UsbAudioDeviceInfo>> listDevices() async => devices;

  @override
  Future<UsbExclusiveStatus> getStatus() async => status;

  @override
  Future<UsbExclusiveToggleResult> setExclusiveMode({
    required bool enabled,
    String? deviceName,
  }) async {
    setExclusiveCalls++;
    lastRequestedEnabled = enabled;
    lastRequestedDeviceName = deviceName;
    if (shouldFailToggle) {
      return UsbExclusiveToggleResult(
        ok: false,
        status: status,
        error: toggleError ?? 'USB permission denied',
      );
    }
    if (enabled) {
      status = _activeStatus;
    } else {
      status = UsbExclusiveStatus.empty;
    }
    return UsbExclusiveToggleResult(ok: true, status: status);
  }
}

class _FixedAudioDetailsNotifier extends CurrentAudioDetailsNotifier {
  _FixedAudioDetailsNotifier(this._details);

  final AudioDetails? _details;

  @override
  AudioDetails? build() => _details;
}

const _sampleDevice = UsbAudioDeviceInfo(
  deviceName: '/dev/bus/usb/001/002',
  productName: 'KA13',
  manufacturerName: 'FiiO',
  vendorId: 0x2972,
  productId: 0x0085,
  hasPermission: true,
  isActiveExclusive: false,
);

const _activeStatus = UsbExclusiveStatus(
  exclusiveActive: true,
  streamRunning: true,
  paused: false,
  deviceName: 'FiiO KA13',
  vendorId: 0x2972,
  productId: 0x0085,
  uacVersion: 'uac2',
  sampleRate: 96000,
  channels: 2,
  bitDepth: 24,
  subslotSize: 4,
  hasFeedbackEndpoint: true,
  playedFrames: 1024,
  bufferedFrames: 512,
  underrunCount: 0,
  supportedSampleRates: <int>[44100, 48000, 96000],
);

const _sampleAudioDetails = AudioDetails(
  formatName: 'flac',
  codecName: 'FLAC',
  duration: Duration(minutes: 4),
  bitrate: 2800,
  sampleRate: 96000,
  channels: 2,
  bitDepth: 24,
  bitrateMode: 'VBR',
  fileSize: 45000000,
);

void main() {
  group('AndroidUsbExclusiveController', () {
    test('discovers devices, toggles exclusive mode, and handles detach events',
        () async {
      final fakeClient = _FakeAndroidUsbExclusiveClient(
        devices: const [_sampleDevice],
      );
      addTearDown(fakeClient.close);

      final container = ProviderContainer(
        overrides: [
          androidUsbExclusiveClientProvider.overrideWithValue(fakeClient),
          isProUnlockedProvider.overrideWithValue(true),
          audioCurrentMusicProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      container.read(androidUsbExclusiveProvider);
      await Future<void>.delayed(Duration.zero);

      final initial = container.read(androidUsbExclusiveProvider);
      expect(initial.isSupported, isTrue);
      expect(initial.devices, hasLength(1));
      expect(initial.selectedDeviceName, _sampleDevice.deviceName);
      expect(initial.isExclusiveActive, isFalse);

      final notifier = container.read(androidUsbExclusiveProvider.notifier);
      final res = await notifier.setExclusiveMode(true);
      expect(res.ok, isTrue);
      expect(fakeClient.lastRequestedEnabled, isTrue);
      expect(fakeClient.lastRequestedDeviceName, _sampleDevice.deviceName);

      final active = container.read(androidUsbExclusiveProvider);
      expect(active.isExclusiveActive, isTrue);
      expect(active.status.sampleRate, 96000);
      expect(active.detachedNoticeTick, 0);

      fakeClient.devices = const [];
      fakeClient.emitEvent(
        const UsbExclusiveEvent(
          eventType: 'device_detached',
          status: UsbExclusiveStatus.empty,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final detached = container.read(androidUsbExclusiveProvider);
      expect(detached.isExclusiveActive, isFalse);
      expect(detached.detachedNoticeTick, 1);
      expect(detached.devices, isEmpty);
    });

    test('records error when USB permission is denied', () async {
      final fakeClient = _FakeAndroidUsbExclusiveClient(
        devices: const [_sampleDevice],
      )
        ..shouldFailToggle = true
        ..toggleError = 'USB permission denied by user';
      addTearDown(fakeClient.close);

      final container = ProviderContainer(
        overrides: [
          androidUsbExclusiveClientProvider.overrideWithValue(fakeClient),
          isProUnlockedProvider.overrideWithValue(true),
          audioCurrentMusicProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      container.read(androidUsbExclusiveProvider);
      await Future<void>.delayed(Duration.zero);

      final res = await container
          .read(androidUsbExclusiveProvider.notifier)
          .setExclusiveMode(true);
      expect(res.ok, isFalse);

      final state = container.read(androidUsbExclusiveProvider);
      expect(state.isExclusiveActive, isFalse);
      expect(state.lastError, 'USB permission denied by user');
    });
  });

  group('PlaybackAudioInfoLabel USB exclusive badge', () {
    Widget buildHarness({
      required _FakeAndroidUsbExclusiveClient client,
      required SettingsService settings,
      required bool isProUnlocked,
      NavigatorObserver? observer,
    }) {
      return ProviderScope(
        overrides: [
          androidUsbExclusiveClientProvider.overrideWithValue(client),
          isProUnlockedProvider.overrideWithValue(isProUnlocked),
          audioCurrentMusicProvider.overrideWithValue(null),
          settingsServiceProvider.overrideWith((ref) => settings),
          currentAudioDetailsProvider.overrideWith(
            () => _FixedAudioDetailsNotifier(_sampleAudioDetails),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [?observer],
          home: const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: PlaybackAudioInfoLabel(
                controlsScale: 1.0,
                width: 320,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('hides badge when exclusive mode is inactive', (tester) async {
      final client = _FakeAndroidUsbExclusiveClient(
        devices: const [_sampleDevice],
        status: UsbExclusiveStatus.empty,
      );
      addTearDown(client.close);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs)..showPlaybackAudioInfo = true;

      await tester.pumpWidget(
        buildHarness(client: client, settings: settings, isProUnlocked: true),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('playback_usb_exclusive_badge')),
        findsNothing,
      );
      expect(find.textContaining('FLAC'), findsOneWidget);
    });

    testWidgets(
      'shows badge alongside audio spec when audio info is enabled and navigates on tap',
      (tester) async {
        final client = _FakeAndroidUsbExclusiveClient(
          devices: const [_sampleDevice],
          status: _activeStatus,
        );
        addTearDown(client.close);

        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsService(prefs)..showPlaybackAudioInfo = true;

        Route<dynamic>? pushedRoute;
        final observer = _RecordingNavigatorObserver(
          onPush: (route) => pushedRoute = route,
        );

        await tester.pumpWidget(
          buildHarness(
            client: client,
            settings: settings,
            isProUnlocked: true,
            observer: observer,
          ),
        );
        await tester.pumpAndSettle();

        final badgeFinder = find.byKey(
          const ValueKey<String>('playback_usb_exclusive_badge'),
        );
        expect(badgeFinder, findsOneWidget);
        expect(find.text('独占模式'), findsOneWidget);
        expect(find.textContaining('FLAC'), findsOneWidget);

        await tester.tap(badgeFinder);
        await tester.pump();

        expect(pushedRoute, isA<MaterialPageRoute<void>>());
        final route = pushedRoute! as MaterialPageRoute<void>;
        final builtPage = route.builder(tester.element(badgeFinder));
        expect(builtPage, isA<SettingsPage>());
        expect((builtPage as SettingsPage).initialSection, SettingsSection.audio);
      },
    );

    testWidgets(
      'shows standalone exclusive badge row when audio info is disabled',
      (tester) async {
        final client = _FakeAndroidUsbExclusiveClient(
          devices: const [_sampleDevice],
          status: _activeStatus,
        );
        addTearDown(client.close);

        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsService(prefs)..showPlaybackAudioInfo = false;

        await tester.pumpWidget(
          buildHarness(
            client: client,
            settings: settings,
            isProUnlocked: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('playback_usb_exclusive_badge')),
          findsOneWidget,
        );
        expect(find.text('独占模式'), findsOneWidget);
        expect(find.textContaining('FLAC'), findsNothing);
      },
    );
  });

  group('AudioSection Android USB card', () {
    testWidgets(
      'renders USB exclusive toggle, stacked device selector on narrow screen, and active format card',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final client = _FakeAndroidUsbExclusiveClient(
          devices: const [_sampleDevice],
          status: _activeStatus,
        );
        addTearDown(client.close);

        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsService(prefs);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              androidUsbExclusiveClientProvider.overrideWithValue(client),
              isProUnlockedProvider.overrideWithValue(true),
              audioCurrentMusicProvider.overrideWithValue(null),
              settingsServiceProvider.overrideWith((ref) => settings),
            ],
            child: MaterialApp(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: AudioSection(settings: settings),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('USB 音频输出'), findsOneWidget);
        expect(find.text('USB 独占模式'), findsOneWidget);
        expect(find.text('USB 音频设备'), findsOneWidget);
        expect(find.text('FiiO KA13'), findsOneWidget);
        expect(find.text('UAC2'), findsOneWidget);
        expect(
          find.text('FiiO KA13 • 96 kHz / 24-bit / Stereo (2.0)'),
          findsOneWidget,
        );
      },
    );
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  _RecordingNavigatorObserver({required this.onPush});

  final ValueChanged<Route<dynamic>> onPush;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    onPush(route);
  }
}
