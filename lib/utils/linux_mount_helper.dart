import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class LinuxMountHelper {
  /// Check if the path should be automounted.
  /// True if running on Linux, the path does not exist, and it points to a removable/external media path.
  static bool shouldAttemptMount(String path) {
    if (!Platform.isLinux) return false;
    if (path.isEmpty) return false;

    // Check if the path already exists. If it exists, no need to mount.
    if (Directory(path).existsSync() || File(path).existsSync()) {
      return false;
    }

    // Standard mount point prefixes for Linux desktops
    final normalized = p.normalize(path);
    return normalized.startsWith('/run/media/') || normalized.startsWith('/media/');
  }

  /// Extracts the target mount point path and the volume label from a given file path.
  /// For example, '/run/media/abc/新加卷/Music/song.mp3'
  /// returns MountInfo(mountPoint: '/run/media/abc/新加卷', label: '新加卷').
  static _MountInfo? _getMountInfo(String path) {
    final normalized = p.normalize(path);
    final segments = p.split(normalized).where((s) => s.isNotEmpty).toList();

    if (normalized.startsWith('/run/media/')) {
      if (segments.length >= 4) {
        final mountPoint = '/${segments.sublist(0, 4).join('/')}';
        final label = segments[3];
        return _MountInfo(mountPoint: mountPoint, label: label);
      }
    } else if (normalized.startsWith('/media/')) {
      if (segments.length >= 3) {
        final mountPoint = '/${segments.sublist(0, 3).join('/')}';
        final label = segments[2];
        return _MountInfo(mountPoint: mountPoint, label: label);
      }
    }
    return null;
  }

  /// Attempts to mount the block device matching the path's volume label using [udisksctl].
  /// Returns [true] if mounting was successful or the path now exists, otherwise [false].
  static Future<bool> ensureMounted(String path) async {
    if (!shouldAttemptMount(path)) {
      return false;
    }

    final info = _getMountInfo(path);
    if (info == null) {
      debugPrint('[LinuxMountHelper] Failed to extract mount info from path: $path');
      return false;
    }

    debugPrint('[LinuxMountHelper] Attempting to auto-mount for label: "${info.label}" at "${info.mountPoint}"');

    try {
      // 1. Get block devices list from lsblk in JSON format
      final result = await Process.run('lsblk', ['-o', 'NAME,LABEL,UUID,FSTYPE,MOUNTPOINT', '-J']);
      if (result.exitCode != 0) {
        debugPrint('[LinuxMountHelper] lsblk failed: ${result.stderr}');
        return false;
      }

      final Map<String, dynamic> data = jsonDecode(result.stdout.toString());
      final devices = data['blockdevices'] as List<dynamic>? ?? [];

      // Flatten nested children partitions
      final partitions = <Map<String, dynamic>>[];
      _flattenDevices(devices, partitions);

      // 2. Find any partition matching the label that is NOT mounted
      final candidates = partitions.where((p) {
        final label = p['label'] as String?;
        final mountpoint = p['mountpoint'] as String?;
        return label == info.label && mountpoint == null;
      }).toList();

      if (candidates.isEmpty) {
        debugPrint('[LinuxMountHelper] No unmounted partition found with label: "${info.label}"');
        // Let's also check if it's already mounted but maybe in a different path,
        // or if we just can't find it.
        return Directory(info.mountPoint).existsSync() || File(path).existsSync();
      }

      // 3. Mount the candidate partition(s)
      bool mountedAny = false;
      for (final candidate in candidates) {
        final name = candidate['name'] as String?;
        if (name == null || name.isEmpty) continue;

        final devPath = '/dev/$name';
        debugPrint('[LinuxMountHelper] Running udisksctl mount -b $devPath');
        
        final mountResult = await Process.run('udisksctl', ['mount', '-b', devPath]);
        if (mountResult.exitCode == 0) {
          debugPrint('[LinuxMountHelper] Successfully mounted $devPath: ${mountResult.stdout.toString().trim()}');
          mountedAny = true;
        } else {
          debugPrint('[LinuxMountHelper] Failed to mount $devPath: ${mountResult.stderr.toString().trim()}');
        }
      }

      // Wait a short moment for OS/filesystem to sync
      if (mountedAny) {
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // 4. Verify if the target path now exists
      final exists = Directory(path).existsSync() || File(path).existsSync();
      debugPrint('[LinuxMountHelper] Auto-mount status: exists=$exists');
      return exists;
    } catch (e, st) {
      debugPrint('[LinuxMountHelper] Error during auto-mount: $e\n$st');
    }

    return false;
  }

  static void _flattenDevices(List<dynamic> devices, List<Map<String, dynamic>> result) {
    for (final device in devices) {
      if (device is Map<String, dynamic>) {
        result.add(device);
        final children = device['children'] as List<dynamic>?;
        if (children != null) {
          _flattenDevices(children, result);
        }
      }
    }
  }
}

class _MountInfo {
  final String mountPoint;
  final String label;

  _MountInfo({required this.mountPoint, required this.label});
}
