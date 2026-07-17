import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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
    return normalized.startsWith('/run/media/') ||
        normalized.startsWith('/media/');
  }

  /// Extracts the target mount point path and the volume label from a given file path.
  /// For example, '/run/media/abc/新加卷/Music/song.mp3'
  /// returns MountInfo(mountPoint: '/run/media/abc/新加卷', label: '新加卷').
  @visibleForTesting
  static bool isLabelMatch(String seg, String label) {
    if (seg == label) return true;
    if (!seg.startsWith(label)) return false;
    final suffix = seg.substring(label.length);
    if (suffix.isEmpty) return true;

    // Suffix must be optional separator followed by digits
    var startIdx = 0;
    if (suffix.startsWith(' ') ||
        suffix.startsWith('_') ||
        suffix.startsWith('-')) {
      startIdx = 1;
    }
    if (startIdx >= suffix.length) return false;
    for (int i = startIdx; i < suffix.length; i++) {
      final code = suffix.codeUnitAt(i);
      if (code < 48 || code > 57) return false; // Not a digit
    }
    return true;
  }

  /// Extracts the target mount point path and the volume label from a given file path.
  /// For example, '/run/media/abc/新加卷/Music/song.mp3'
  /// returns MountInfo(mountPoint: '/run/media/abc/新加卷', label: '新加卷').
  static Future<_MountInfo?> _getMountInfo(String path) async {
    final normalized = p.normalize(path);
    final segments = p
        .split(normalized)
        .where((s) => s.isNotEmpty && s != '/')
        .toList();

    // Standard mount point prefixes for Linux desktops
    if (!normalized.startsWith('/run/media/') &&
        !normalized.startsWith('/media/')) {
      return null;
    }

    // 1. Get labels from lsblk
    final labels = <String>{};
    try {
      final result = await Process.run('lsblk', ['-o', 'LABEL', '-J']);
      if (result.exitCode == 0) {
        final Map<String, dynamic> data = jsonDecode(result.stdout.toString());
        final devices = data['blockdevices'] as List<dynamic>? ?? [];
        final partitions = <Map<String, dynamic>>[];
        _flattenDevices(devices, partitions);
        for (final part in partitions) {
          final label = part['label'] as String?;
          if (label != null && label.isNotEmpty) {
            labels.add(label);
          }
        }
      }
    } catch (e) {
      debugPrint('[LinuxMountHelper] Failed to list labels via lsblk: $e');
    }

    // 2. Match segments against labels (longest label first)
    final sortedLabels = labels.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      for (final label in sortedLabels) {
        if (isLabelMatch(seg, label)) {
          final mountPoint = '/${segments.sublist(0, i + 1).join('/')}';
          return _MountInfo(mountPoint: mountPoint, label: label);
        }
      }
    }

    // 3. Fallback logic if lsblk failed or no label matched
    if (normalized.startsWith('/run/media/')) {
      if (segments.length >= 4) {
        final mountPoint = '/${segments.sublist(0, 4).join('/')}';
        final label = segments[3];
        return _MountInfo(mountPoint: mountPoint, label: label);
      }
    } else if (normalized.startsWith('/media/')) {
      if (segments.length >= 4) {
        final mountPoint = '/${segments.sublist(0, 4).join('/')}';
        final label = segments[3];
        return _MountInfo(mountPoint: mountPoint, label: label);
      } else if (segments.length >= 3) {
        final mountPoint = '/${segments.sublist(0, 3).join('/')}';
        final label = segments[2];
        return _MountInfo(mountPoint: mountPoint, label: label);
      }
    }

    return null;
  }

  /// Deprecated compatibility method. Mounting is intentionally delegated to
  /// the operating system and is never initiated by the app.
  @Deprecated('Configure automatic mounting in the operating system instead')
  static Future<bool> ensureMounted(String path) async {
    return Directory(path).existsSync() || File(path).existsSync();
  }

  static void _flattenDevices(
    List<dynamic> devices,
    List<Map<String, dynamic>> result,
  ) {
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

  static Future<List<Map<String, dynamic>>> _getDevices() async {
    try {
      final result = await Process.run('lsblk', [
        '-o',
        'NAME,LABEL,UUID,FSTYPE,MOUNTPOINT',
        '-J',
      ]);
      if (result.exitCode == 0) {
        final Map<String, dynamic> data = jsonDecode(result.stdout.toString());
        final devices = data['blockdevices'] as List<dynamic>? ?? [];
        final partitions = <Map<String, dynamic>>[];
        _flattenDevices(devices, partitions);
        return partitions;
      }
    } catch (e) {
      debugPrint('[LinuxMountHelper] Failed to get devices: $e');
    }
    return [];
  }

  static Map<String, dynamic>? _findPartitionByUuid(
    List<Map<String, dynamic>> partitions,
    String uuid,
  ) {
    for (final part in partitions) {
      if (part['uuid'] == uuid) {
        return part;
      }
    }
    return null;
  }

  /// Resolves the current root paths by matching against saved partition UUIDs
  /// to dynamically translate mountpoint paths in case of dual-partition naming collisions.
  static Future<List<String>> resolveAndMountRootPaths(
    List<String> paths,
  ) async {
    if (!Platform.isLinux) return paths;

    final prefs = await SharedPreferences.getInstance();
    final uuidJson = prefs.getString('linux_root_path_uuids') ?? '{}';
    Map<String, String> pathToUuid = {};
    try {
      pathToUuid = Map<String, String>.from(jsonDecode(uuidJson));
    } catch (_) {}

    // Get current devices
    var devices = await _getDevices();
    final updatedPaths = <String>[];
    bool changed = false;

    for (final path in paths) {
      if (!shouldAttemptMount(path) && !Directory(path).existsSync()) {
        // If it shouldn't be mounted and doesn't exist, keep as is
        updatedPaths.add(path);
        continue;
      }

      // Check if we have a saved UUID for this path
      final savedUuid = pathToUuid[path];
      if (savedUuid != null && savedUuid.isNotEmpty) {
        // Find partition by UUID
        final partition = _findPartitionByUuid(devices, savedUuid);
        if (partition != null) {
          final mountPoint = partition['mountpoint'] as String?;
          if (mountPoint != null && mountPoint.isNotEmpty) {
            // Already mounted!
            // Let's check if the partition is mounted at a different mount point, translate it!
            final oldMountInfo = await _getMountInfo(path);
            if (oldMountInfo != null && oldMountInfo.mountPoint != mountPoint) {
              final newPath = path.replaceFirst(
                oldMountInfo.mountPoint,
                mountPoint,
              );
              debugPrint(
                '[LinuxMountHelper] Translating path for UUID $savedUuid: $path -> $newPath',
              );
              updatedPaths.add(newPath);
              pathToUuid[newPath] = savedUuid;
              pathToUuid.remove(path);
              changed = true;
              continue;
            }
          }
        }
      }

      // Fallback / Discovery: If we don't have a saved UUID, or it wasn't resolved by UUID,
      // search for a matching partition by label and verify directory existence.
      final oldMountInfo = await _getMountInfo(path);
      if (oldMountInfo != null) {
        final label = oldMountInfo.label;
        // Find all partitions with this label
        final candidates = devices.where((d) => d['label'] == label).toList();
        bool foundMatch = false;

        for (final candidate in candidates) {
          final mountPoint = candidate['mountpoint'] as String?;
          final uuid = candidate['uuid'] as String?;

          if (mountPoint != null && mountPoint.isNotEmpty) {
            final testPath = path.replaceFirst(
              oldMountInfo.mountPoint,
              mountPoint,
            );
            if (Directory(testPath).existsSync() ||
                File(testPath).existsSync()) {
              // Found the correct partition!
              debugPrint(
                '[LinuxMountHelper] Discovered matching partition for path $path: mountPoint=$mountPoint, uuid=$uuid',
              );
              updatedPaths.add(testPath);
              if (uuid != null && uuid.isNotEmpty) {
                pathToUuid[testPath] = uuid;
                pathToUuid.remove(path);
                changed = true;
              }
              foundMatch = true;
              break;
            }
          }
        }

        if (foundMatch) {
          continue;
        }
      }

      // If the partition is not mounted, preserve the saved path so the UI can
      // report it as unavailable and guide the user to configure auto-mount.
      updatedPaths.add(path);
    }

    // Clean up stale paths
    pathToUuid.removeWhere((key, _) => !updatedPaths.contains(key));

    if (changed) {
      await prefs.setString('linux_root_path_uuids', jsonEncode(pathToUuid));
    }

    return updatedPaths;
  }
}

class _MountInfo {
  final String mountPoint;
  final String label;

  _MountInfo({required this.mountPoint, required this.label});
}
