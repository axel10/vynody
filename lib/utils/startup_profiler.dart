import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'app_log.dart';

/// 专用于在 Profile / Debug 模式下录制应用启动期性能数据的实用类。
class StartupProfiler {
  StartupProfiler._();

  static bool _hasStarted = false;

  /// 在启动时自动开启 CPU 采样与 Timeline 记录，并在指定时长后保存到本地。
  /// [duration] 录制时长，默认 10 秒。
  static void recordStartup({Duration duration = const Duration(seconds: 10)}) {
    // Release 模式下无 VM Service，自动跳过
    if (kReleaseMode || _hasStarted) return;
    _hasStarted = true;

    // 异步执行录制任务，避免阻塞 main 线程的 UI 与引擎初始化
    unawaited(_runRecording(duration));
  }
  static Future<VmService?> _connectToVmService() async {
    Object? lastError;
    Uri? lastUri;
    for (int i = 0; i < 30; i++) {
      try {
        final serviceInfo = await developer.Service.getInfo();
        final serverWsUri = serviceInfo.serverWebSocketUri;
        lastUri = serverWsUri;
        if (serverWsUri != null) {
          final client = await vmServiceConnectUri(serverWsUri.toString());
          return client;
        }
      } catch (e) {
        lastError = e;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('[StartupProfiler] 连接 VM Service 失败 (请确认是否添加了 --no-dds): URI=$lastUri, Error=$lastError');
    return null;
  }

  static Future<void> _runRecording(Duration duration) async {
    try {
      debugPrint('[StartupProfiler] 🚀 开始启动性能录制，录制时长: ${duration.inSeconds} 秒...');

      // 1. 在启动初期尝试建立连接并开启 Profiler 与 Timeline Flags
      VmService? client = await _connectToVmService();
      if (client != null) {
        try {
          // 显式激活 Dart VM CPU 采样器及采样周期 (1000 微秒 = 1ms)
          await client.setFlag('profiler', 'true');
          await client.setFlag('profile_period', '1000');
        } catch (e) {
          debugPrint('[StartupProfiler] 激活 Profiler 提示: $e');
        }

        try {
          await client.setVMTimelineFlags(<String>['Dart', 'Embedder', 'GC']);
        } catch (e) {
          debugPrint('[StartupProfiler] 初始化 Timeline Flags 提示: $e');
        }
      }

      // 2. 持续录制指定时间
      await Future.delayed(duration);

      // 3. 检查连接是否依然存活，若已失效则尝试重连
      var isHealthy = false;
      if (client != null) {
        try {
          await client.getVersion();
          isHealthy = true;
        } catch (_) {
          isHealthy = false;
        }
      }

      if (!isHealthy) {
        client = await _connectToVmService();
      }

      if (client == null) {
        debugPrint('[StartupProfiler] 无法获取有效的 VM Service 连接，跳过导出。');
        return;
      }

      // 4. 计算保存目录（Android 优先保存在外部私有目录，确保 adb pull 拥有直接读取权限）
      Directory targetDir;
      try {
        if (Platform.isAndroid) {
          final extDir = await getExternalStorageDirectory();
          final baseDir = extDir ?? (await getApplicationDocumentsDirectory());
          targetDir = Directory(p.join(baseDir.path, 'profiling'));
        } else if (Platform.isIOS) {
          final docDir = await getApplicationDocumentsDirectory();
          targetDir = Directory(p.join(docDir.path, 'profiling'));
        } else {
          targetDir = Directory(p.join(Directory.current.path, 'build', 'profiling'));
        }
        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }
      } catch (_) {
        targetDir = Directory.systemTemp.createTempSync('profiling_');
      }

      final timestampStr = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final cpuFile = File(p.join(targetDir.path, 'cpu_profile_$timestampStr.json'));
      final timelineFile = File(p.join(targetDir.path, 'timeline_$timestampStr.json'));

      // 5. 导出 CPU Profile（获取从进程启动至今的全量 samples）
      int sampleCount = 0;
      try {
        final vm = await client.getVM();
        final isolates = vm.isolates ?? <IsolateRef>[];
        final mainIsolate = isolates.firstWhere(
          (iso) => (iso.name ?? '').contains('main'),
          orElse: () => isolates.isNotEmpty ? isolates.first : IsolateRef(id: 'isolates/0'),
        );

        final isolateId = mainIsolate.id;
        if (isolateId != null) {
          // getCpuSamples(isolateId, timeOriginMicros, timeExtentMicros) 依赖单调时钟 Dart_TimelineGetMicros
          // 传入 0, 0 会导致区间为 [0, 0] 从而返回 0 个采样点。此处通过 getVMTimelineMicros() 获取当前时间戳
          // 并指定为 timeExtentMicros，覆盖启动至今的全量 samples。
          int timeExtent = 0x3fffffffffffffff;
          try {
            final ts = await client.getVMTimelineMicros();
            if (ts.timestamp != null && ts.timestamp! > 0) {
              timeExtent = ts.timestamp! + 10000000;
            }
          } catch (_) {}

          final CpuSamples cpuSamples = await client.getCpuSamples(isolateId, 0, timeExtent);
          sampleCount = cpuSamples.sampleCount ?? 0;
          await cpuFile.writeAsString(jsonEncode(cpuSamples.json));
        }
      } catch (e) {
        debugPrint('[StartupProfiler] 导出 CPU Profile 失败: $e');
      }

      // 6. 导出 VM Timeline
      try {
        final Timeline timeline = await client.getVMTimeline();
        await timelineFile.writeAsString(jsonEncode(timeline.json));
      } catch (e) {
        debugPrint('[StartupProfiler] 导出 Timeline 失败: $e');
      }

      await client.dispose();

      // 7. 打印拉取指引
      final hasCpu = cpuFile.existsSync();
      final hasTimeline = timelineFile.existsSync();

      debugPrint('\n========================= [StartupProfiler] =========================');
      debugPrint('✅ 启动期性能录制完成（时长: ${duration.inSeconds} 秒）！');
      if (hasCpu) {
        debugPrint('📁 CPU Profile : ${cpuFile.path} (采样数: $sampleCount)');
      }
      if (hasTimeline) {
        debugPrint('📁 Timeline    : ${timelineFile.path}');
      }
      if (Platform.isAndroid) {
        debugPrint('💻 电脑拉取命令 (请在电脑终端直接运行):');
        if (hasCpu) debugPrint('adb pull "${cpuFile.path}" ./');
        if (hasTimeline) debugPrint('adb pull "${timelineFile.path}" ./');
      }
      debugPrint('======================================================================\n');

      AppLog.log(
        '[StartupProfiler] Profiling completed, saved to ${targetDir.path}',
        mirrorToConsole: true,
      );
    } catch (e, st) {
      debugPrint('[StartupProfiler] 录制过程发生错误: $e\n$st');
    }
  }
}
