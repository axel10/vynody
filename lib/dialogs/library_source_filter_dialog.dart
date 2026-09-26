import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../player/library/library_source_filter.dart';
import '../player/remote/remote_server_models.dart';

Future<LibrarySourceFilter?> showLibrarySourceFilterDialog(BuildContext context) {
  return showDialog<LibrarySourceFilter>(
    context: context,
    builder: (context) => const LibrarySourceFilterDialog(),
  );
}

class LibrarySourceFilterDialog extends ConsumerStatefulWidget {
  const LibrarySourceFilterDialog({super.key});

  @override
  ConsumerState<LibrarySourceFilterDialog> createState() =>
      _LibrarySourceFilterDialogState();
}

class _LibrarySourceFilterDialogState
    extends ConsumerState<LibrarySourceFilterDialog> {
  late LibrarySourceFilter _selectedFilter;

  @override
  void initState() {
    super.initState();
    _selectedFilter = ref.read(librarySourceFilterProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final remoteServers = ref.watch(remoteIndexedServersProvider);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.tune_rounded,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Text(l10n.librarySourceFilterTitle),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioListTile<LibrarySourceFilter>(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                secondary: Icon(
                  Icons.library_music_rounded,
                  color: _selectedFilter.type == LibrarySourceType.all
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  l10n.librarySourceAll,
                  style: TextStyle(
                    fontWeight: _selectedFilter.type == LibrarySourceType.all
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  l10n.librarySourceAllDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                value: LibrarySourceFilter.all,
                groupValue: _selectedFilter,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedFilter = val);
                  }
                },
              ),
              RadioListTile<LibrarySourceFilter>(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                secondary: Icon(
                  Icons.devices_rounded,
                  color: _selectedFilter.type == LibrarySourceType.local
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  l10n.librarySourceLocalOnly,
                  style: TextStyle(
                    fontWeight: _selectedFilter.type == LibrarySourceType.local
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  l10n.librarySourceLocalOnlyDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                value: LibrarySourceFilter.local,
                groupValue: _selectedFilter,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedFilter = val);
                  }
                },
              ),
              if (remoteServers.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    l10n.librarySourceIndexedRemote,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...remoteServers.map((server) {
                  final serverFilter = LibrarySourceFilter.remote(
                    serverId: server.serverId,
                    serverName: server.serverName,
                    serverType: server.serverType,
                  );
                  final isSelected = _selectedFilter == serverFilter;
                  final icon = server.serverType == RemoteServerType.smb
                      ? Icons.folder_shared_rounded
                      : Icons.cloud_rounded;

                  return RadioListTile<LibrarySourceFilter>(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    secondary: Icon(
                      icon,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      server.serverName,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      '${server.serverType.displayName} · ${l10n.songsCountFormat(server.totalSongs)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: serverFilter,
                    groupValue: _selectedFilter,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedFilter = val);
                      }
                    },
                  );
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            ref
                .read(librarySourceFilterProvider.notifier)
                .setFilter(_selectedFilter);
            Navigator.of(context).pop(_selectedFilter);
          },
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}
