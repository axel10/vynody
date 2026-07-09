import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DevicePerformanceHelper {
  static bool? _isLowMidEndCache;

  /// Detects whether the current device is a low-to-mid-end Android SoC,
  /// including the Snapdragon 8s Gen series, which is known to experience lag
  /// during complex animations.
  static Future<bool> isLowMidEndDevice() async {
    if (_isLowMidEndCache != null) {
      return _isLowMidEndCache!;
    }

    if (!Platform.isAndroid) {
      _isLowMidEndCache = false;
      return false;
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final hardware = androidInfo.hardware;
      final board = androidInfo.board;

      // Kirin 980 and above are powerful enough and should not use optimizations
      if (_isKirin980OrAbove(hardware) || _isKirin980OrAbove(board)) {
        _isLowMidEndCache = false;
        return false;
      }

      // 1. Core count check: < 8 cores is typically low/mid end on Android.
      if (Platform.numberOfProcessors < 8) {
        _isLowMidEndCache = true;
        return true;
      }

      // 2. RAM check: if total RAM is <= 6GB (reported as < 6.5 GB due to kernel/system reserved), it's low/mid end.
      final totalRamKb = await _getTotalRamKb();
      if (totalRamKb != null) {
        final totalRamGb = totalRamKb / (1024 * 1024);
        if (totalRamGb < 6.5) {
          _isLowMidEndCache = true;
          return true;
        }
      }

      // 3. Chipset check via hardware, board or ro.soc.model property
      String? socModel;
      try {
        final result = await Process.run('/system/bin/getprop', ['ro.soc.model']);
        if (result.exitCode == 0) {
          socModel = result.stdout.toString().trim();
        }
      } catch (_) {}

      if (_isLowMidEndOr8sChip(hardware) ||
          _isLowMidEndOr8sChip(board) ||
          (socModel != null && _isLowMidEndOr8sChip(socModel))) {
        _isLowMidEndCache = true;
        return true;
      }

      _isLowMidEndCache = false;
    } catch (e) {
      debugPrint('[DevicePerformanceHelper] Error checking device specs: $e');
      _isLowMidEndCache = true; // Fallback to safe/optimized on error
    }

    return _isLowMidEndCache!;
  }

  static Future<int?> _getTotalRamKb() async {
    try {
      final file = File('/proc/meminfo');
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          if (line.startsWith('MemTotal:')) {
            final match = RegExp(r'\d+').firstMatch(line);
            if (match != null) {
              return int.tryParse(match.group(0)!);
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _isLowMidEndOr8sChip(String hardware) {
    final hw = hardware.toLowerCase();
    
    // Qualcomm Snapdragon: 
    // - Low/mid-end: sm4xxx, sm6xxx, sm7xxx, sdm4xx, sdm6xx, sdm7xx
    // - Snapdragon 8s Gen series: sm8635 (8s Gen 3) and future 8s models matching sm8x35 format (e.g. sm8735)
    if (hw.contains('sm4') ||
        hw.contains('sm6') ||
        hw.contains('sm7') ||
        hw.contains('sdm4') ||
        hw.contains('sdm6') ||
        hw.contains('sdm7') ||
        hw.contains('sm8635') ||
        RegExp(r'sm8\d35').hasMatch(hw)) {
      return true;
    }
    
    // MediaTek: 
    // - Helio low-end/mid-range: mt67xx
    // - Dimensity low-end/mid-range: mt6833 (Dimensity 700), mt6853 (Dimensity 720), mt6873 (Dimensity 800), mt6877 (Dimensity 900)
    if (hw.startsWith('mt67') ||
        hw.contains('mt6833') ||
        hw.contains('mt6853') ||
        hw.contains('mt6873') ||
        hw.contains('mt6877')) {
      return true;
    }
    
    // Samsung Exynos:
    // - Low/mid-end: exynos 850, 9611, etc., or s5e88xx (Exynos 1280/1380/1480)
    if (hw.contains('exynos8') ||
        hw.contains('exynos96') ||
        hw.contains('s5e88')) {
      return true;
    }
    
    // Unisoc / Spreadtrum / low-end manufacturers
    if (hw.contains('sc98') ||
        hw.contains('ums') ||
        hw.contains('tiger') ||
        hw.contains('unisoc') ||
        hw.contains('sprd')) {
      return true;
    }
    
    return false;
  }

  static bool _isKirin980OrAbove(String str) {
    final s = str.toLowerCase();
    return s.contains('kirin980') ||
        s.contains('kirin990') ||
        s.contains('kirin90') ||
        s.contains('hi3680') ||
        s.contains('hi3690') ||
        s.contains('hi36a');
  }
}
