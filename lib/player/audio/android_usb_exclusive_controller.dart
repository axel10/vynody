import 'dart:async';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/pro/pro_license_service.dart';

/// Isolated volume state & persistence helper for Android USB exclusive mode.
///
/// While exclusive mode is active, in-app volume changes are persisted to
/// [storageKey] instead of the normal-mode volume key. Entering exclusive mode
/// for the first time caps the volume at [defaultSafeInitialVolume] (without
/// raising it if the user's current volume is already lower) to protect hearing;
/// exiting restores the exact normal-mode volume state saved on entry.
class UsbExclusiveVolumeVault {
  static const String storageKey = 'android_usb_exclusive_volume';

  /// Safe initial volume (in 0..100) applied on the very first USB exclusive
  /// activation. Under the -60 dB .. 0 dB perceptual curve, 25% is -45 dB:
  /// clearly audible while preventing accidental full-scale blasts.
  static const double defaultSafeInitialVolume = 25.0;

  bool _isActive = false;
  double? _savedNormalVolume;
  bool _savedNormalMuted = false;
  double? _savedNormalPreviousVolume;

  bool get isActive => _isActive;

  ({double volume, bool isMuted, double previousVolume})? enter({
    required SharedPreferences prefs,
    required double currentNormalVolume,
    required bool currentNormalMuted,
    required double currentNormalPreviousVolume,
  }) {
    if (_isActive) return null;

    _savedNormalVolume = currentNormalVolume.clamp(0.0, 100.0);
    _savedNormalMuted = currentNormalMuted;
    _savedNormalPreviousVolume = currentNormalPreviousVolume.clamp(0.0, 100.0);
    _isActive = true;

    final stored = prefs.getDouble(storageKey);
    final double targetVolume;
    if (stored != null && stored.isFinite) {
      targetVolume = stored.clamp(0.0, 100.0);
    } else {
      final currentEffective =
          currentNormalMuted ? 0.0 : currentNormalVolume.clamp(0.0, 100.0);
      targetVolume = currentEffective < defaultSafeInitialVolume
          ? currentEffective
          : defaultSafeInitialVolume;
      unawaited(prefs.setDouble(storageKey, targetVolume));
    }

    return (
      volume: targetVolume,
      isMuted: targetVolume == 0.0,
      previousVolume:
          targetVolume > 0.0 ? targetVolume : defaultSafeInitialVolume,
    );
  }

  void recordExclusiveVolume(SharedPreferences prefs, double volume) {
    if (!_isActive) return;
    unawaited(prefs.setDouble(storageKey, volume.clamp(0.0, 100.0)));
  }

  ({double volume, bool isMuted, double previousVolume})? exit() {
    if (!_isActive) return null;

    final restoredVolume = (_savedNormalVolume ?? 100.0).clamp(0.0, 100.0);
    final restoredMuted = _savedNormalMuted;
    final restoredPrevious =
        (_savedNormalPreviousVolume ?? restoredVolume).clamp(0.0, 100.0);

    _isActive = false;
    _savedNormalVolume = null;
    _savedNormalMuted = false;
    _savedNormalPreviousVolume = null;

    return (
      volume: restoredMuted ? 0.0 : restoredVolume,
      isMuted: restoredMuted,
      previousVolume: restoredPrevious,
    );
  }
}

/// Abstraction bridging [AndroidUsbExclusiveController] to the app's volume
/// controller so exclusive volume isolation can be unit-tested independently.
abstract class AndroidUsbExclusiveVolumeBridge {
  Future<void> enterExclusiveVolume();
  Future<void> exitExclusiveVolume();
}

class _DefaultAndroidUsbExclusiveVolumeBridge
    implements AndroidUsbExclusiveVolumeBridge {
  const _DefaultAndroidUsbExclusiveVolumeBridge(this._ref);

  final Ref _ref;

  @override
  Future<void> enterExclusiveVolume() async {
    await _ref.read(audioServiceProvider).enterAndroidUsbExclusiveVolume();
  }

  @override
  Future<void> exitExclusiveVolume() async {
    await _ref.read(audioServiceProvider).exitAndroidUsbExclusiveVolume();
  }
}

final androidUsbExclusiveVolumeBridgeProvider =
    Provider<AndroidUsbExclusiveVolumeBridge>(
  (ref) => _DefaultAndroidUsbExclusiveVolumeBridge(ref),
);

/// Abstraction over [AndroidUsbExclusiveService] for dependency injection and testing.
abstract class AndroidUsbExclusiveClient {
  bool get isSupported;
  Stream<UsbExclusiveEvent> get events;
  Future<List<UsbAudioDeviceInfo>> listDevices();
  Future<UsbExclusiveStatus> getStatus();
  Future<UsbExclusiveToggleResult> setExclusiveMode({
    required bool enabled,
    String? deviceName,
  });
}

class _DefaultAndroidUsbExclusiveClient implements AndroidUsbExclusiveClient {
  const _DefaultAndroidUsbExclusiveClient();

  AndroidUsbExclusiveService get _service => AndroidUsbExclusiveService.instance;

  @override
  bool get isSupported => _service.isSupported;

  @override
  Stream<UsbExclusiveEvent> get events => _service.events;

  @override
  Future<List<UsbAudioDeviceInfo>> listDevices() => _service.listDevices();

  @override
  Future<UsbExclusiveStatus> getStatus() => _service.getStatus();

  @override
  Future<UsbExclusiveToggleResult> setExclusiveMode({
    required bool enabled,
    String? deviceName,
  }) =>
      _service.setExclusiveMode(enabled: enabled, deviceName: deviceName);
}

final androidUsbExclusiveClientProvider = Provider<AndroidUsbExclusiveClient>(
  (ref) => const _DefaultAndroidUsbExclusiveClient(),
);

@immutable
class AndroidUsbExclusiveState {
  const AndroidUsbExclusiveState({
    required this.isSupported,
    this.isBusy = false,
    this.devices = const <UsbAudioDeviceInfo>[],
    this.selectedDeviceName,
    this.status = UsbExclusiveStatus.empty,
    this.lastError,
    this.detachedNoticeTick = 0,
  });

  final bool isSupported;
  final bool isBusy;
  final List<UsbAudioDeviceInfo> devices;
  final String? selectedDeviceName;
  final UsbExclusiveStatus status;
  final String? lastError;

  /// Monotonically incremented whenever an active exclusive USB DAC is
  /// physically detached, allowing the UI to display a one-shot notice.
  final int detachedNoticeTick;

  bool get isExclusiveActive => status.exclusiveActive;

  AndroidUsbExclusiveState copyWith({
    bool? isSupported,
    bool? isBusy,
    List<UsbAudioDeviceInfo>? devices,
    String? selectedDeviceName,
    bool clearSelectedDeviceName = false,
    UsbExclusiveStatus? status,
    String? lastError,
    bool clearLastError = false,
    int? detachedNoticeTick,
  }) {
    return AndroidUsbExclusiveState(
      isSupported: isSupported ?? this.isSupported,
      isBusy: isBusy ?? this.isBusy,
      devices: devices ?? this.devices,
      selectedDeviceName: clearSelectedDeviceName
          ? null
          : (selectedDeviceName ?? this.selectedDeviceName),
      status: status ?? this.status,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      detachedNoticeTick: detachedNoticeTick ?? this.detachedNoticeTick,
    );
  }
}

class AndroidUsbExclusiveController extends Notifier<AndroidUsbExclusiveState> {
  StreamSubscription<UsbExclusiveEvent>? _eventSub;
  Timer? _trackRefreshTimer;
  bool _disposed = false;

  AndroidUsbExclusiveClient get _client =>
      ref.read(androidUsbExclusiveClientProvider);

  AndroidUsbExclusiveVolumeBridge get _volumeBridge =>
      ref.read(androidUsbExclusiveVolumeBridgeProvider);

  @override
  AndroidUsbExclusiveState build() {
    _disposed = false;
    final supported = _client.isSupported;

    ref.onDispose(() {
      _disposed = true;
      _eventSub?.cancel();
      _eventSub = null;
      _trackRefreshTimer?.cancel();
      _trackRefreshTimer = null;
    });

    if (!supported) {
      return const AndroidUsbExclusiveState(isSupported: false);
    }

    _eventSub = _client.events.listen(_handleUsbEvent);

    // Revoke active exclusive mode if Pro trial expires.
    ref.listen<bool>(isProUnlockedProvider, (previous, next) {
      if (!next && state.isExclusiveActive) {
        unawaited(setExclusiveMode(false));
      }
    });

    // Refresh hardware format telemetry shortly after track changes while active.
    ref.listen<String?>(
      audioCurrentMusicProvider.select((m) => m?.path),
      (previous, next) {
        if (previous != next && state.isExclusiveActive) {
          _trackRefreshTimer?.cancel();
          _trackRefreshTimer = Timer(const Duration(milliseconds: 350), () {
            if (!_disposed && state.isExclusiveActive) {
              unawaited(refreshStatusOnly());
            }
          });
        }
      },
    );

    unawaited(refresh());
    return const AndroidUsbExclusiveState(isSupported: true);
  }

  void _handleUsbEvent(UsbExclusiveEvent event) {
    if (_disposed) return;
    final wasExclusive = state.isExclusiveActive;
    final nowExclusive = event.status.exclusiveActive;
    final detachedWhileExclusive =
        wasExclusive && !nowExclusive && event.eventType == 'device_detached';

    state = state.copyWith(
      status: event.status,
      lastError: event.status.lastError,
      clearLastError: event.status.lastError == null,
      detachedNoticeTick: detachedWhileExclusive
          ? state.detachedNoticeTick + 1
          : state.detachedNoticeTick,
    );
    if (wasExclusive && !nowExclusive) {
      unawaited(_volumeBridge.exitExclusiveVolume());
    } else if (!wasExclusive && nowExclusive) {
      unawaited(_volumeBridge.enterExclusiveVolume());
    }
    unawaited(_refreshDevicesOnly());
  }

  Future<void> refresh() async {
    if (!_client.isSupported || _disposed) return;
    await Future.wait<void>([
      _refreshDevicesOnly(),
      refreshStatusOnly(),
    ]);
  }

  Future<void> _refreshDevicesOnly() async {
    if (!_client.isSupported || _disposed) return;
    try {
      final devices = await _client.listDevices();
      if (_disposed) return;
      String? nextSelected = state.selectedDeviceName;
      if (nextSelected == null ||
          !devices.any((d) => d.deviceName == nextSelected)) {
        final active = devices.where((d) => d.isActiveExclusive).firstOrNull;
        nextSelected = active?.deviceName ??
            (devices.isNotEmpty ? devices.first.deviceName : null);
      }
      state = state.copyWith(
        devices: devices,
        selectedDeviceName: nextSelected,
        clearSelectedDeviceName: nextSelected == null,
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(lastError: e.toString());
    }
  }

  Future<void> refreshStatusOnly() async {
    if (!_client.isSupported || _disposed) return;
    try {
      final status = await _client.getStatus();
      if (_disposed) return;
      final wasExclusive = state.isExclusiveActive;
      final nowExclusive = status.exclusiveActive;
      state = state.copyWith(
        status: status,
        lastError: status.lastError,
        clearLastError: status.lastError == null,
      );
      if (!wasExclusive && nowExclusive) {
        unawaited(_volumeBridge.enterExclusiveVolume());
      } else if (wasExclusive && !nowExclusive) {
        unawaited(_volumeBridge.exitExclusiveVolume());
      }
    } catch (_) {}
  }

  Future<void> selectDevice(String? deviceName) async {
    if (!_client.isSupported || _disposed) return;
    if (deviceName == state.selectedDeviceName) return;
    state = state.copyWith(
      selectedDeviceName: deviceName,
      clearSelectedDeviceName: deviceName == null,
      clearLastError: true,
    );
    if (state.isExclusiveActive && deviceName != null) {
      await setExclusiveMode(true, deviceName: deviceName);
    }
  }

  Future<UsbExclusiveToggleResult> setExclusiveMode(
    bool enabled, {
    String? deviceName,
  }) async {
    if (!_client.isSupported) {
      return const UsbExclusiveToggleResult(
        ok: false,
        status: UsbExclusiveStatus.empty,
        error: 'USB exclusive mode is only supported on Android',
      );
    }
    if (state.isBusy) {
      return UsbExclusiveToggleResult(
        ok: false,
        status: state.status,
      );
    }

    final wasExclusive = state.isExclusiveActive;
    final targetDevice = enabled ? (deviceName ?? state.selectedDeviceName) : null;
    state = state.copyWith(isBusy: true, clearLastError: true);

    // Apply the isolated/safe exclusive volume BEFORE switching the native
    // sink so the very first PCM frames sent to the USB DAC never blast at 100%.
    var enteredVolumeForThisToggle = false;
    if (enabled && !wasExclusive) {
      await _volumeBridge.enterExclusiveVolume();
      enteredVolumeForThisToggle = true;
    }

    try {
      final result = await _client.setExclusiveMode(
        enabled: enabled,
        deviceName: targetDevice,
      );
      if (_disposed) {
        if (enteredVolumeForThisToggle &&
            (!result.ok || !result.status.exclusiveActive)) {
          await _volumeBridge.exitExclusiveVolume();
        }
        return result;
      }

      if (enabled) {
        if (enteredVolumeForThisToggle &&
            (!result.ok || !result.status.exclusiveActive)) {
          await _volumeBridge.exitExclusiveVolume();
        }
      } else if (!result.status.exclusiveActive) {
        await _volumeBridge.exitExclusiveVolume();
      }

      state = state.copyWith(
        isBusy: false,
        status: result.status,
        lastError: result.ok ? null : (result.error ?? result.status.lastError),
        clearLastError: result.ok,
      );
      await _refreshDevicesOnly();
      return result;
    } catch (e) {
      if (enteredVolumeForThisToggle) {
        await _volumeBridge.exitExclusiveVolume();
      }
      if (!_disposed) {
        state = state.copyWith(isBusy: false, lastError: e.toString());
      }
      return UsbExclusiveToggleResult(
        ok: false,
        status: state.status,
        error: e.toString(),
      );
    }
  }
}

final androidUsbExclusiveProvider =
    NotifierProvider<AndroidUsbExclusiveController, AndroidUsbExclusiveState>(
  AndroidUsbExclusiveController.new,
);

/// Whether the Android USB exclusive badge should be displayed in playback UI.
final showAndroidUsbExclusiveBadgeProvider = Provider<bool>((ref) {
  final isProUnlocked = ref.watch(isProUnlockedProvider);
  if (!isProUnlocked) return false;
  return ref.watch(
    androidUsbExclusiveProvider.select(
      (s) => s.isSupported && s.isExclusiveActive,
    ),
  );
});

/// Whether the playback audio info row should occupy space and render
/// (either user enabled audio info, or Android USB exclusive badge is active).
final showPlaybackAudioInfoRowProvider = Provider<bool>((ref) {
  final showAudioInfo = ref.watch(
    settingsServiceProvider.select((s) => s.showPlaybackAudioInfo),
  );
  if (showAudioInfo) return true;
  return ref.watch(showAndroidUsbExclusiveBadgeProvider);
});
