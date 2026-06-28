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
    return normalized.startsWith('/run/media/') || normalized.startsWith('/media/');
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
    if (suffix.startsWith(' ') || suffix.startsWith('_') || suffix.startsWith('-')) {
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
    final segments = p.split(normalized).where((s) => s.isNotEmpty && s != '/').toList();

    // Standard mount point prefixes for Linux desktops
    if (!normalized.startsWith('/run/media/') && !normalized.startsWith('/media/')) {
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
    final sortedLabels = labels.toList()..sort((a, b) => b.length.compareTo(a.length));
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

  /// Attempts to mount the block device matching the path's volume label using [udisksctl].
  /// Returns [true] if mounting was successful or the path now exists, otherwise [false].
  static Future<bool> ensureMounted(String path) async {
    if (!shouldAttemptMount(path)) {
      return false;
    }

    final info = await _getMountInfo(path);
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

  static Future<List<Map<String, dynamic>>> _getDevices() async {
    try {
      final result = await Process.run('lsblk', ['-o', 'NAME,LABEL,UUID,FSTYPE,MOUNTPOINT', '-J']);
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

  static Map<String, dynamic>? _findPartitionByUuid(List<Map<String, dynamic>> partitions, String uuid) {
    for (final part in partitions) {
      if (part['uuid'] == uuid) {
        return part;
      }
    }
    return null;
  }


  /// Resolves the current root paths by matching against saved partition UUIDs
  /// to dynamically translate mountpoint paths in case of dual-partition naming collisions,
  /// and mounts any offline partition.
  static Future<List<String>> resolveAndMountRootPaths(List<String> paths) async {
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
          final name = partition['name'] as String?;
          if (mountPoint != null && mountPoint.isNotEmpty) {
            // Already mounted!
            // Let's check if the partition is mounted at a different mount point, translate it!
            final oldMountInfo = await _getMountInfo(path);
            if (oldMountInfo != null && oldMountInfo.mountPoint != mountPoint) {
              final newPath = path.replaceFirst(oldMountInfo.mountPoint, mountPoint);
              debugPrint('[LinuxMountHelper] Translating path for UUID $savedUuid: $path -> $newPath');
              updatedPaths.add(newPath);
              pathToUuid[newPath] = savedUuid;
              pathToUuid.remove(path);
              changed = true;
              continue;
            }
          } else if (name != null && name.isNotEmpty) {
            // Not mounted! Let's mount it
            final devPath = '/dev/$name';
            debugPrint('[LinuxMountHelper] Mounting device $devPath by UUID $savedUuid');
            final mountResult = await Process.run('udisksctl', ['mount', '-b', devPath]);
            if (mountResult.exitCode == 0) {
              // Wait for OS to sync
              await Future.delayed(const Duration(milliseconds: 200));
              // Re-fetch devices to get the new mountpoint
              final freshDevices = await _getDevices();
              final freshPartition = _findPartitionByUuid(freshDevices, savedUuid);
              final freshMountPoint = freshPartition?['mountpoint'] as String?;
              if (freshMountPoint != null && freshMountPoint.isNotEmpty) {
                final oldMountInfo = await _getMountInfo(path);
                if (oldMountInfo != null && oldMountInfo.mountPoint != freshMountPoint) {
                  final newPath = path.replaceFirst(oldMountInfo.mountPoint, freshMountPoint);
                  debugPrint('[LinuxMountHelper] Mounted and translated path for UUID $savedUuid: $path -> $newPath');
                  updatedPaths.add(newPath);
                  pathToUuid[newPath] = savedUuid;
                  pathToUuid.remove(path);
                  changed = true;
                  continue;
                }
              }
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
          var mountPoint = candidate['mountpoint'] as String?;
          final name = candidate['name'] as String?;
          final uuid = candidate['uuid'] as String?;

          if (mountPoint == null || mountPoint.isEmpty) {
            if (name != null && name.isNotEmpty) {
              // Mount candidate
              final devPath = '/dev/$name';
              debugPrint('[LinuxMountHelper] Fallback mounting candidate $devPath');
              final mountResult = await Process.run('udisksctl', ['mount', '-b', devPath]);
              if (mountResult.exitCode == 0) {
                await Future.delayed(const Duration(milliseconds: 200));
                // Re-fetch devices
                final freshDevices = await _getDevices();
                devices = freshDevices; // update local devices list
                final freshCandidate = freshDevices.cast<Map<String, dynamic>?>().firstWhere(
                  (d) => d?['name'] == name,
                  orElse: () => null,
                );
                mountPoint = freshCandidate?['mountpoint'] as String?;
              }
            }
          }

          if (mountPoint != null && mountPoint.isNotEmpty) {
            final testPath = path.replaceFirst(oldMountInfo.mountPoint, mountPoint);
            if (Directory(testPath).existsSync() || File(testPath).existsSync()) {
              // Found the correct partition!
              debugPrint('[LinuxMountHelper] Discovered matching partition for path $path: mountPoint=$mountPoint, uuid=$uuid');
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

      // If all else fails, attempt the standard ensureMounted and keep original path
      await ensureMounted(path);
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
