import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'app_log.dart';

class MemoryTrace {
  MemoryTrace._();

  static bool _enabled = false;
  static Timer? _timer;
  static int _peakRssBytes = 0;
  static int _peakPrivateBytes = 0;
  static String _peakRssLabel = '';
  static String _peakPrivateLabel = '';

  static bool get enabled => _enabled;

  static void configure({
    required bool enabled,
    Duration sampleInterval = const Duration(seconds: 20),
  }) {
    _enabled = enabled;
    _timer?.cancel();
    _timer = null;

    if (!enabled) {
      return;
    }

    snapshot('trace enabled', force: true);
    _timer = Timer.periodic(sampleInterval, (_) {
      snapshot('periodic');
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _enabled = false;
  }

  static void snapshot(
    String label, {
    Map<String, Object?> details = const <String, Object?>{},
    bool force = false,
  }) {
    if (!enabled && !force) {
      return;
    }

    final rssBytes = ProcessInfo.currentRss;
    final windowsStats = _tryReadWindowsStats();
    final privateBytes = windowsStats?.privateBytes;
    final workingSetBytes = windowsStats?.workingSetBytes;

    final peakMarkers = <String>[];
    if (rssBytes >= _peakRssBytes) {
      _peakRssBytes = rssBytes;
      _peakRssLabel = label;
      peakMarkers.add('rss');
    }
    if (privateBytes != null && privateBytes >= _peakPrivateBytes) {
      _peakPrivateBytes = privateBytes;
      _peakPrivateLabel = label;
      peakMarkers.add('private');
    }

    final buffer = StringBuffer()
      ..write('[MEM] $label rss=${_formatBytes(rssBytes)}');
    if (privateBytes != null) {
      buffer.write(' private=${_formatBytes(privateBytes)}');
    }
    if (workingSetBytes != null) {
      buffer.write(' ws=${_formatBytes(workingSetBytes)}');
    }
    if (_peakRssBytes > 0) {
      buffer.write(' peakRss=${_formatBytes(_peakRssBytes)}@$_peakRssLabel');
    }
    if (_peakPrivateBytes > 0) {
      buffer.write(
        ' peakPrivate=${_formatBytes(_peakPrivateBytes)}@$_peakPrivateLabel',
      );
    }
    if (peakMarkers.isNotEmpty) {
      buffer.write(' PEAK=${peakMarkers.join(",")}');
    }
    if (details.isNotEmpty) {
      buffer.write(' ');
      buffer.write(
        details.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join(' '),
      );
    }

    AppLog.log(buffer.toString(), mirrorToConsole: enabled || force);
  }

  static String _formatBytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)}MB';
  }

  static _WindowsMemoryStats? _tryReadWindowsStats() {
    if (!Platform.isWindows) {
      return null;
    }

    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final psapi = DynamicLibrary.open('psapi.dll');

      final getCurrentProcess = kernel32.lookupFunction<
        IntPtr Function(),
        int Function()
      >('GetCurrentProcess');
      final getProcessMemoryInfo = psapi.lookupFunction<
        Int32 Function(IntPtr, Pointer<_ProcessMemoryCountersEx>, Uint32),
        int Function(int, Pointer<_ProcessMemoryCountersEx>, int)
      >('GetProcessMemoryInfo');

      final counters = calloc<_ProcessMemoryCountersEx>();
      try {
        counters.ref.cb = sizeOf<_ProcessMemoryCountersEx>();
        final ok = getProcessMemoryInfo(
          getCurrentProcess(),
          counters,
          sizeOf<_ProcessMemoryCountersEx>(),
        );
        if (ok == 0) {
          return null;
        }

        return _WindowsMemoryStats(
          workingSetBytes: counters.ref.workingSetSize,
          privateBytes: counters.ref.privateUsage,
        );
      } finally {
        calloc.free(counters);
      }
    } catch (_) {
      return null;
    }
  }
}

class _WindowsMemoryStats {
  const _WindowsMemoryStats({
    required this.workingSetBytes,
    required this.privateBytes,
  });

  final int workingSetBytes;
  final int privateBytes;
}

base class _ProcessMemoryCountersEx extends Struct {
  @Uint32()
  external int cb;

  @Uint32()
  external int pageFaultCount;

  @UintPtr()
  external int peakWorkingSetSize;

  @UintPtr()
  external int workingSetSize;

  @UintPtr()
  external int quotaPeakPagedPoolUsage;

  @UintPtr()
  external int quotaPagedPoolUsage;

  @UintPtr()
  external int quotaPeakNonPagedPoolUsage;

  @UintPtr()
  external int quotaNonPagedPoolUsage;

  @UintPtr()
  external int pagefileUsage;

  @UintPtr()
  external int peakPagefileUsage;

  @UintPtr()
  external int privateUsage;
}
