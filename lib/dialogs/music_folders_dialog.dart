import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:linux_directory_access/linux_directory_access.dart';
import 'package:audio_core/audio_core.dart';
import 'package:vynody/dialogs/add_edit_remote_server_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
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
        final pick = await FileSelectorHelper.pickDirectoryDetailed();
        if (pick.accessDenied) {
          if (!mounted) return;
          final l10n = AppLocalizations.of(context);
          AppSnackBar.show(
            context,
            ref,
            SnackBar(
              content: Text(
                l10n?.persistentAccessDenied ?? '无法保存该目录的访问权限，请重新选择一次',
              ),
            ),
          );
          return;
        }
        selectedDirectory = pick.path;
      }

      if (cwd != null) {
        try {
          Directory.current = cwd;
        } catch (_) {}
      }

      if (selectedDirectory != null) {
        if (!mounted) return;

        if (FileSystemEntity.isFileSync(selectedDirectory)) {
          final l10n = AppLocalizations.of(context);
          AppSnackBar.show(
            context,
            ref,
            SnackBar(
              content: Text(
                l10n?.selectDirectoryHint ?? '所选项目为单曲文件，请选择文件夹或点击右上角「打开」',
              ),
            ),
          );
          return;
        }

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

  Future<void> _addRemoteLibrary() async {
    await AddEditRemoteServerDialog.show(context, ref: ref);
  }

  Future<void> _removeRemoteServer(RemoteServer server) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n?.remove ?? '移除'),
        content: Text(
          '${l10n?.deleteServerConfirm ?? '确定要删除此媒体服务器连接吗？'}\n${server.name}',
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
      await ref.read(remoteServersProvider.notifier).deleteServer(server.id);
    }
  }

  Future<void> _saveAndScan() async {
    final scanner = ref.read(scannerServiceProvider);
    final rootFolders = scanner.rootFolders;
    final remoteServers =
        ref.read(remoteServersProvider).asData?.value ?? const <RemoteServer>[];

    if (rootFolders.isEmpty && remoteServers.isEmpty) {
      final l10n = AppLocalizations.of(context);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n?.noDirectoriesAddedTitle ?? '暂未添加任何目录'),
          content: Text(
            l10n?.noDirectoriesAddedDesc ??
                '你尚未添加音乐根目录，是否先进入应用稍后再添加？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n?.cancel ?? '返回添加'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n?.exploreAppFirst ?? '先去逛逛'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    } else if (rootFolders.isNotEmpty) {
      // Trigger background scanning for local folders
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
    final rootFolders = ref.watch(
      scannerServiceProvider.select((s) => s.rootFolders),
    );
    final remoteServers =
        ref.watch(remoteServersProvider).asData?.value ?? const <RemoteServer>[];

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
          maxHeight: 680,
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
                          l10n?.addMediaSource ?? '添加媒体源',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n?.selectFoldersToScan ?? 'Select folders to scan',
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
                  if (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS)
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: l10n?.cancel ?? '关闭',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // Media sources list area / empty state prompt
              Expanded(
                child: rootFolders.isEmpty && remoteServers.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildSourcesList(theme, rootFolders, remoteServers),
              ),

              const SizedBox(height: 18),

              // Bottom action buttons
              _buildBottomButtons(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.create_new_folder_outlined,
              size: 52,
              color: const Color(0xFF39C5BB).withValues(alpha: 0.8),
            ),
            const SizedBox(height: 14),
            Text(
              l10n?.noRootFoldersSelected ?? '暂无已选根目录',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n?.tapAddFolderTip ?? '请点击下方按钮添加你的本地音乐文件夹',
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
      ),
    );
  }

  Widget _buildSourcesList(
    ThemeData theme,
    List<MusicFolder> folders,
    List<RemoteServer> servers,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final totalCount = folders.length + servers.length;

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
        itemCount: totalCount,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 0.5,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        itemBuilder: (context, index) {
          if (index < folders.length) {
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
                tooltip: l10n?.remove ?? '移除',
                onPressed: () => _removeFolder(folder.path),
              ),
            );
          }

          final server = servers[index - folders.length];
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.cloud_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
            title: Text(
              server.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${server.type.displayName} · ${server.url}',
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
              tooltip: l10n?.remove ?? '移除',
              onPressed: () => _removeRemoteServer(server),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomButtons(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final addFolderBtn = SizedBox(
      height: 46,
      child: FilledButton.tonalIcon(
        onPressed: _isPicking ? null : _pickFolder,
        icon: _isPicking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.create_new_folder_rounded, size: 19),
        label: Text(
          l10n?.addFolder ?? '本地文件夹',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );

    final addRemoteLibraryBtn = SizedBox(
      height: 46,
      child: FilledButton.tonalIcon(
        onPressed: _addRemoteLibrary,
        icon: const Icon(Icons.cloud_outlined, size: 19),
        label: Text(
          l10n?.remoteLibrary ?? '远程媒体库',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
        label: Text(
          l10n?.saveAndScan ?? '保存并扫描',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: addFolderBtn),
                  const SizedBox(width: 10),
                  Expanded(child: addRemoteLibraryBtn),
                ],
              ),
              const SizedBox(height: 10),
              saveAndScanBtn,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            addFolderBtn,
            const SizedBox(height: 10),
            addRemoteLibraryBtn,
            const SizedBox(height: 10),
            saveAndScanBtn,
          ],
        );
      },
    );
  }
}
