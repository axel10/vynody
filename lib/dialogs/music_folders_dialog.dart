import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:linux_directory_access/linux_directory_access.dart';
import 'package:audio_core/audio_core.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/transcode/transcode_riverpod.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import 'package:vynody/utils/file_selector_helper.dart';

/// Centered dialog for managing music root folders,
/// used for new user onboarding as well as general library directory management.
class MusicFoldersDialog extends ConsumerStatefulWidget {
  const MusicFoldersDialog({
    super.key,
    this.isOnboarding = false,
  });

  final bool isOnboarding;

  /// Shows the dialog. Returns true if folders were saved / confirmed.
  static Future<bool?> show(
    BuildContext context, {
    bool isOnboarding = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => MusicFoldersDialog(isOnboarding: isOnboarding),
    );
  }

  @override
  ConsumerState<MusicFoldersDialog> createState() => _MusicFoldersDialogState();
}

class _MusicFoldersDialogState extends ConsumerState<MusicFoldersDialog> {
  bool _isPicking = false;

  Future<void> _pickFolder() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      final scanner = ref.read(scannerServiceProvider);
      Directory? cwd;
      try {
        cwd = Directory.current;
      } catch (_) {}

      String? selectedDirectory;
      String? persistentDocumentId;
      AndroidOutputDirectory? androidOutputDirectory;

      if (Platform.isAndroid) {
        // Request audio / storage permission on Android before launching SAF
        try {
          final deviceInfo = DeviceInfoPlugin();
          final androidInfo = await deviceInfo.androidInfo;
          if (androidInfo.version.sdkInt >= 33) {
            await Permission.audio.request();
          } else {
            await Permission.storage.request();
          }
        } catch (e) {
          debugPrint('[MusicFoldersDialog] Permission request error: $e');
        }

        if (!mounted) return;
        androidOutputDirectory = await ref
            .read(transcodeServiceProvider)
            .pickAndroidOutputDirectory();
        selectedDirectory = androidOutputDirectory?.displayPath;
      } else if (Platform.isLinux && await LinuxDirectoryAccess().isFlatpak) {
        final grant = await LinuxDirectoryAccess().pickDirectory();
        selectedDirectory = grant?.path;
        persistentDocumentId = grant?.documentId;
      } else {
        selectedDirectory = await FileSelectorHelper.pickDirectory();
      }

      if (cwd != null) {
        try {
          Directory.current = cwd;
        } catch (_) {}
      }

      if (selectedDirectory != null) {
        if (!mounted) return;

        if (Platform.isWindows) {
          await Future.delayed(const Duration(milliseconds: 300));
        }

        if (Platform.isAndroid && androidOutputDirectory != null) {
          await AndroidSafStorageHelper.saveMapping(
            androidOutputDirectory.displayPath,
            androidOutputDirectory.treeUri,
          );
        }

        final result = await scanner.addRootPath(
          selectedDirectory,
          persistentDocumentId: persistentDocumentId,
        );

        if (!mounted) return;
        final l10n = AppLocalizations.of(context);
        String message;
        switch (result.status) {
          case RootPathAddStatus.added:
          case RootPathAddStatus.alreadyAdded:
            message = l10n?.directoryAddedSuccess ?? '目录添加成功';
            break;
          case RootPathAddStatus.noMusic:
            message = l10n?.directoryAddedNoMusic ?? '目录中未找到支持的音乐文件';
            break;
          case RootPathAddStatus.persistentAccessDenied:
            message = l10n?.persistentAccessDenied ?? '未获得持久访问权限';
            break;
          case RootPathAddStatus.failed:
            message = l10n?.folderAddFailed ?? '添加目录失败';
            break;
        }
        AppSnackBar.show(context, ref, SnackBar(content: Text(message)));
      }
    } catch (e) {
      debugPrint('[MusicFoldersDialog] Error picking folder: $e');
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<void> _removeFolder(String path) async {
    final l10n = AppLocalizations.of(context);
    final folderName = p.basename(path).isEmpty ? path : p.basename(path);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n?.remove ?? '移除目录'),
        content: Text(
          l10n?.removeRootDirectoryConfirmation(folderName) ??
              '确定从曲库中移除此根目录？\n$path',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n?.cancel ?? '取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n?.remove ?? '移除'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final scanner = ref.read(scannerServiceProvider);
      await scanner.removeRootPaths([path]);
    }
  }

  Future<void> _saveAndScan() async {
    final scanner = ref.read(scannerServiceProvider);
    final rootFolders = scanner.rootFolders;

    if (rootFolders.isEmpty) {
      final l10n = AppLocalizations.of(context);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('暂未添加任何目录'),
          content: const Text('你尚未添加音乐根目录，是否先进入应用稍后再添加？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n?.cancel ?? '返回添加'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('先去逛逛'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    } else {
      // Trigger background scanning
      if (Platform.isAndroid) {
        scanner.scanSystemMedia();
      }
      scanner.scan(clearScannedRoots: false);
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scanner = ref.watch(scannerServiceProvider);
    final rootFolders = scanner.rootFolders;

    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;
    final screenWidth = mediaQuery.size.width;
    // On portrait or narrower devices, each button individually occupies a full row
    final stackButtons = isPortrait || screenWidth < 460;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 500,
          maxHeight: 580,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF39C5BB).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.folder_special_rounded,
                      color: Color(0xFF39C5BB),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n?.onboardingStepRootDirectory ?? '音乐文件夹',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n != null && l10n.localeName.startsWith('zh')
                              ? '选择要扫描的音乐文件夹'
                              : 'Select folders to scan',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: l10n?.cancel ?? '关闭',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Directory list area / empty state prompt
              Expanded(
                child: rootFolders.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildFoldersList(theme, rootFolders),
              ),

              const SizedBox(height: 18),

              // Bottom action buttons
              _buildBottomButtons(theme, stackButtons),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.create_new_folder_outlined,
              size: 52,
              color: const Color(0xFF39C5BB).withValues(alpha: 0.8),
            ),
            const SizedBox(height: 14),
            Text(
              '暂无已选根目录',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '请点击下方按钮添加你的本地音乐文件夹',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoldersList(ThemeData theme, List<MusicFolder> folders) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        itemCount: folders.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 0.5,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        itemBuilder: (context, index) {
          final folder = folders[index];
          final dirName = p.basename(folder.path).isEmpty
              ? folder.path
              : p.basename(folder.path);

          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.amber.withValues(alpha: 0.12)
                    : Colors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.folder_rounded,
                color: Colors.amber,
                size: 20,
              ),
            ),
            title: Text(
              dirName,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              folder.path,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: theme.colorScheme.error.withValues(alpha: 0.85),
              ),
              tooltip: '移除',
              onPressed: () => _removeFolder(folder.path),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomButtons(ThemeData theme, bool stackButtons) {
    final addFolderBtn = SizedBox(
      height: 48,
      child: FilledButton.tonalIcon(
        onPressed: _isPicking ? null : _pickFolder,
        icon: _isPicking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.create_new_folder_rounded, size: 20),
        label: const Text(
          '添加文件夹',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );

    final saveAndScanBtn = SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _saveAndScan,
        icon: const Icon(Icons.radar_rounded, size: 20),
        label: const Text(
          '保存并扫描',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF39C5BB),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );

    if (stackButtons) {
      // Portrait / narrow screen: each button occupies its own row
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: double.infinity, child: addFolderBtn),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: saveAndScanBtn),
        ],
      );
    }

    // Landscape / wide screen: buttons side by side
    return Row(
      children: [
        Expanded(child: addFolderBtn),
        const SizedBox(width: 12),
        Expanded(child: saveAndScanBtn),
      ],
    );
  }
}
