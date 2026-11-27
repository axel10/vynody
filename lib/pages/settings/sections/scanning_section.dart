import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/player/remote/services/remote_scan_root.dart';
import 'package:vynody/player/remote/services/remote_directory_scanner.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import '../widgets/settings_group_card.dart';
import '../widgets/settings_section_header.dart';

class ScanningSection extends ConsumerWidget {
  final SettingsService settings;

  const ScanningSection({
    super.key,
    required this.settings,
  });

  Widget _buildScanSection(
    BuildContext context,
    WidgetRef ref,
    SettingsService settings,
  ) {
    final l10n = AppLocalizations.of(context)!;
    const minSeconds = 5;
    const maxSeconds = 300;
    const stepSeconds = 5;
    final enabled = settings.skipShortAudioScanEnabled;
    final currentSeconds = settings.skipShortAudioScanMinimumDurationSeconds;

    return Column(
      children: [
        SettingsGroupCard(
          title: l10n.scanSectionTitle,
          icon: Icons.filter_list_rounded,
          children: [
            SwitchListTile(
              title: Text(l10n.skipShortAudioDuringScan),
              subtitle: Text(l10n.skipShortAudioDuringScanDescription),
              value: enabled,
              onChanged: (value) {
                settings.skipShortAudioScanEnabled = value;
              },
            ),
            ListTile(
              enabled: enabled,
              title: Text(l10n.shortAudioScanThreshold),
              subtitle: Text(l10n.shortAudioScanThresholdDescription),
              trailing: SizedBox(
                width: 156,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: enabled && currentSeconds > minSeconds
                          ? () {
                              settings.skipShortAudioScanMinimumDurationSeconds =
                                  currentSeconds - stepSeconds;
                            }
                          : null,
                    ),
                    Text(l10n.shortAudioScanThresholdValue(currentSeconds)),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: enabled && currentSeconds < maxSeconds
                          ? () {
                              settings.skipShortAudioScanMinimumDurationSeconds =
                                  currentSeconds + stepSeconds;
                            }
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        _buildRemoteRootsCard(context, ref),
        SettingsGroupCard(
          title: l10n.rebuildIndex,
          icon: Icons.build_circle_outlined,
          children: [
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: Text(l10n.rebuildIndex),
              subtitle: Text(l10n.rebuildIndexDescription),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  final content = l10n.rebuildIndexConfirmation;
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(l10n.rebuildIndex),
                      content: Text(content),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text(l10n.confirm),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    final scanner = ref.read(scannerServiceProvider);
                    unawaited(scanner.rebuildIndex());
                    if (context.mounted) {
                      AppSnackBar.show(
                        context,
                        ref,
                        SnackBar(content: Text(l10n.rebuildIndexStarted)),
                      );
                    }
                  }
                },
                child: Text(l10n.rebuild),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRemoteRootsCard(
    BuildContext context,
    WidgetRef ref,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final rootsAsync = ref.watch(remoteScanRootsProvider);
    final roots = rootsAsync.asData?.value ?? [];
    final progress = ref.watch(remoteScanProgressProvider);

    return SettingsGroupCard(
      title: l10n.remoteMediaFolders,
      icon: Icons.cloud_sync_rounded,
      children: [
        if (roots.isEmpty)
          ListTile(
            leading: const Icon(Icons.cloud_off_rounded),
            title: Text(l10n.noIndexedRemoteFolders),
            subtitle: Text(l10n.noIndexedRemoteFoldersDesc),
          )
        else
          for (final root in roots)
            ListTile(
              leading: Icon(
                root.serverType.name == 'smb'
                    ? Icons.dns_rounded
                    : Icons.cloud_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text('${root.serverName} · ${root.remotePath}'),
              subtitle: Text(
                progress.isScanning && progress.rootId == root.id
                    ? '${progress.currentFolder ?? ""} (${progress.processedCount}/${progress.totalDiscovered})'
                    : '${root.songCount} ${l10n.songs}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (progress.isScanning && progress.rootId == root.id)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: l10n.rebuild,
                      onPressed: () async {
                        final servers =
                            ref.read(remoteServersProvider).asData?.value ?? [];
                        final server = servers
                            .where((s) => s.id == root.serverId)
                            .firstOrNull;
                        if (server == null) return;
                        final storage =
                            await ref.read(remoteServerStorageProvider.future);
                        final password =
                            await storage.getPassword(server.id) ?? '';
                        unawaited(
                          ref.read(remoteDirectoryScannerProvider).scanRoot(
                                server: server,
                                password: password,
                                root: root,
                              ),
                        );
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent),
                    tooltip: l10n.removeFromMediaLibrary,
                    onPressed: () async {
                      await ref
                          .read(remoteDirectoryScannerProvider)
                          .removeRootFromDatabase(root);
                      final currentRoots =
                          ref.read(remoteScanRootsProvider).asData?.value ?? [];
                      ref
                          .read(scannerServiceProvider)
                          .setRemoteRoots(currentRoots);
                    },
                  ),
                ],
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        SettingsSectionHeader(
          title: l10n.scanSectionTitle,
          description: l10n.scanSectionDescription,
        ),
        _buildScanSection(context, ref, settings),
      ],
    );
  }
}
