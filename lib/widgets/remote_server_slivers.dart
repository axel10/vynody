import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dialogs/add_edit_remote_server_dialog.dart';
import '../l10n/app_localizations.dart';
import '../player/remote/remote_server_models.dart';
import '../player/remote/remote_server_riverpod.dart';
import '../player/settings/settings_service.dart';
import 'folder_grid_card.dart';
import 'folder_layout_utils.dart';
import 'app_context_menu.dart';
import 'pro/pro_badge.dart';
import '../player/pro/pro_license_service.dart';
import '../player/pro/pro_models.dart';

/// Shows a context menu or bottom sheet for a remote media server (Browse, Edit, Delete).
Future<void> showRemoteServerContextMenu({
  required BuildContext context,
  required Offset position,
  required RemoteServer server,
  required WidgetRef ref,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final isSubsonic = server.type == RemoteServerType.subsonic;
  final isJellyfin = server.type == RemoteServerType.jellyfin;
  final isSmb = server.type == RemoteServerType.smb;
  final isMobile = Platform.isAndroid || Platform.isIOS;

  // 面板头部用的品牌色 / 图标 / 类型名：弹窗与面板共用，避免两边图标各挑一个。
  final gradientColors = isSubsonic
      ? const [Color(0xFFFF5E3A), Color(0xFFFF2A68)]
      : (isJellyfin
          ? const [Color(0xFF00A4DC), Color(0xFFAA5CC3)]
          : (isSmb
              ? const [Color(0xFF00B09B), Color(0xFF96C93D)]
              : const [Color(0xFF0072FF), Color(0xFF00C6FF)]));
  final serverIcon = isSubsonic
      ? Icons.library_music_rounded
      : (isJellyfin
          ? Icons.movie_filter_outlined
          : (isSmb ? Icons.dns_outlined : Icons.cloud_queue_rounded));
  final typeLabel = isSubsonic
      ? 'Navidrome'
      : (isJellyfin ? 'Jellyfin' : (isSmb ? 'SMB' : 'WebDAV'));

  final groups = <List<ContextMenuAction>>[
    [
      ContextMenuAction(
        value: 'browse',
        label: l10n.browseServer,
        icon: isSubsonic
            ? Icons.library_music_rounded
            : (isSmb
                ? Icons.folder_shared_outlined
                : Icons.folder_copy_outlined),
        accentColor: isSubsonic
            ? Colors.orange
            : (isSmb ? Colors.teal : Colors.blue),
      ),
    ],
    [
      ContextMenuAction(
        value: 'edit',
        label: l10n.editRemoteServer,
        icon: Icons.edit_rounded,
      ),
    ],
    [
      ContextMenuAction(
        value: 'delete',
        label: l10n.delete,
        icon: Icons.delete_outline_rounded,
        accentColor: theme.colorScheme.error,
      ),
    ],
  ];

  final selected = isMobile
      ? await showAppActionSheet<String>(
          context: context,
          header: ActionSheetHeader(
            title: server.name,
            subtitle: '$typeLabel \u00b7 ${server.url}',
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                ),
                child: Icon(serverIcon, size: 26, color: Colors.white),
              ),
            ),
          ),
          itemsBuilder: (sheetContext) =>
              buildContextMenuSheetItems(sheetContext, groups),
        )
      : await AppContextMenu.show<String>(
          context: context,
          position: position,
          items: buildContextMenuPopupItems(context, groups),
        );

  if (!context.mounted || selected == null) return;

  if (selected == 'browse') {
    final allowed = await checkProGate(
      context,
      ref,
      feature: ProFeature.cloudLibrary,
    );
    if (!allowed) return;
    if (!context.mounted) return;

    final pwd = await ref
        .read(remoteServersProvider.notifier)
        .getPassword(server.id);
    if (!context.mounted) return;

    ref.read(activeRemoteSessionProvider.notifier).setSession(
      ActiveRemoteSession(
        server: server,
        password: pwd ?? '',
      ),
    );
  } else if (selected == 'edit') {
    AddEditRemoteServerDialog.show(context, server: server, ref: ref);
  } else if (selected == 'delete') {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteServerConfirm),
        content: Text(server.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(remoteServersProvider.notifier).deleteServer(server.id);
    }
  }
}

/// Renders a sleek section header and divider separating local root folders from remote servers.
class RemoteServersSectionHeaderSliver extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback? onAddServer;

  const RemoteServersSectionHeaderSliver({
    super.key,
    required this.title,
    this.count = 0,
    this.onAddServer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(
          left: isPortrait ? 12 : 16,
          right: isPortrait ? 12 : 16,
          top: 20,
          bottom: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Divider(
              height: 1,
              thickness: 1,
              color: theme.dividerColor.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cloud_sync_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const ProBadge(),
                      if (count > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onAddServer != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onAddServer,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(
                      l10n.addRemoteServer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders remote servers in grid or list view according to FolderViewMode / zoomScale.
class RemoteServersSliver extends ConsumerWidget {
  final List<RemoteServer> servers;
  final FolderViewMode? viewMode;
  final double? zoomScale;
  final bool isSortMode;
  final void Function(RemoteServer server) onOpenServer;
  final double bottomPadding;
  final double? crossAxisExtent;

  const RemoteServersSliver({
    super.key,
    required this.servers,
    this.viewMode,
    this.zoomScale,
    this.isSortMode = false,
    required this.onOpenServer,
    this.bottomPadding = 160.0,
    this.crossAxisExtent,
  });

  double get _effectiveZoomScale {
    if (zoomScale != null) return snapFolderZoomScale(zoomScale!);
    return switch (viewMode) {
      FolderViewMode.list => kFolderZoomTierStandardList,
      FolderViewMode.hybrid || FolderViewMode.grid || null =>
        kFolderZoomTierMediumGrid,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (servers.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final isProUnlocked = ref.watch(isProUnlockedProvider);
    final effectiveZoom = _effectiveZoomScale;
    final isGrid = isFolderZoomGrid(effectiveZoom);
    final width = crossAxisExtent ?? MediaQuery.sizeOf(context).width;

    if (isGrid) {
      final crossAxisCount =
          getFolderZoomGridCrossAxisCount(width, effectiveZoom);
      final childAspectRatio = calculateFolderGridChildAspectRatio(
        context,
        width,
        crossAxisCount,
        zoomScale: effectiveZoom,
      );

      if (isSortMode) {
            return SliverPadding(
              padding: EdgeInsets.only(
                top: 8,
                bottom: bottomPadding,
                left: kGridHorizontalPadding,
                right: kGridHorizontalPadding,
              ),
              sliver: SliverToBoxAdapter(
                child: ReorderableBuilder(
                  onReorder: (ReorderedListFunction reorderedListFunction) {
                    final reordered =
                        reorderedListFunction(servers) as List<RemoteServer>;
                    ref
                        .read(remoteServersProvider.notifier)
                        .reorderServers(reordered);
                  },
                  builder: (children) {
                    return GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: kGridCrossAxisSpacing,
                        mainAxisSpacing: kGridMainAxisSpacing,
                        childAspectRatio: childAspectRatio,
                      ),
                      children: children,
                    );
                  },
                  children: servers.map((server) {
                    return HoverableCard(
                      key: ValueKey('server_${server.id}'),
                      child: RemoteServerGridCard(
                        server: server,
                        isProUnlocked: isProUnlocked,
                        onTap: null,
                        onSecondaryTapDown: (details) {
                          showRemoteServerContextMenu(
                            context: context,
                            position: details.globalPosition,
                            server: server,
                            ref: ref,
                          );
                        },
                        onLongPressStart: (details) {
                          showRemoteServerContextMenu(
                            context: context,
                            position: details.globalPosition,
                            server: server,
                            ref: ref,
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          }

          return SliverPadding(
            padding: EdgeInsets.only(
              top: 8,
              bottom: bottomPadding,
              left: kGridHorizontalPadding,
              right: kGridHorizontalPadding,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: kGridCrossAxisSpacing,
                mainAxisSpacing: kGridMainAxisSpacing,
                childAspectRatio: childAspectRatio,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final server = servers[index];
                  return HoverableCard(
                    child: RemoteServerGridCard(
                      server: server,
                      isProUnlocked: isProUnlocked,
                      onTap: () => onOpenServer(server),
                      onSecondaryTapDown: (details) {
                        showRemoteServerContextMenu(
                          context: context,
                          position: details.globalPosition,
                          server: server,
                          ref: ref,
                        );
                      },
                      onLongPressStart: (details) {
                        showRemoteServerContextMenu(
                          context: context,
                          position: details.globalPosition,
                          server: server,
                          ref: ref,
                        );
                      },
                    ),
                  );
                },
                childCount: servers.length,
              ),
            ),
          );
    } else {
      final isPortrait =
          MediaQuery.of(context).orientation == Orientation.portrait;

      if (isSortMode) {
        return SliverPadding(
          padding: EdgeInsets.only(
            top: 0,
            bottom: bottomPadding,
            left: isPortrait ? 4 : 8,
            right: isPortrait ? 4 : 8,
          ),
          sliver: SliverReorderableList(
            itemCount: servers.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              final reordered = List<RemoteServer>.from(servers);
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              ref
                  .read(remoteServersProvider.notifier)
                  .reorderServers(reordered);
            },
            itemBuilder: (context, index) {
              final server = servers[index];
              return ReorderableDelayedDragStartListener(
                key: ValueKey('sort_server_${server.id}'),
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                  ),
                  child: RemoteServerListTile(
                    server: server,
                    isProUnlocked: isProUnlocked,
                    onTap: null,
                    trailing: ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    onSecondaryTapDown: (details) {
                      showRemoteServerContextMenu(
                        context: context,
                        position: details.globalPosition,
                        server: server,
                        ref: ref,
                      );
                    },
                    onLongPressStart: (details) {
                      showRemoteServerContextMenu(
                        context: context,
                        position: details.globalPosition,
                        server: server,
                        ref: ref,
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );
      }

      return SliverPadding(
        padding: EdgeInsets.only(
          top: 0,
          bottom: bottomPadding,
          left: isPortrait ? 4 : 8,
          right: isPortrait ? 4 : 8,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final server = servers[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                ),
                child: RemoteServerListTile(
                  server: server,
                  isProUnlocked: isProUnlocked,
                  onTap: () => onOpenServer(server),
                  onSecondaryTapDown: (details) {
                    showRemoteServerContextMenu(
                      context: context,
                      position: details.globalPosition,
                      server: server,
                      ref: ref,
                    );
                  },
                  onLongPressStart: (details) {
                    showRemoteServerContextMenu(
                      context: context,
                      position: details.globalPosition,
                      server: server,
                      ref: ref,
                    );
                  },
                ),
              );
            },
            childCount: servers.length,
          ),
        ),
      );
    }
  }
}

/// Rich Grid Card widget for a remote server.
class RemoteServerGridCard extends StatelessWidget {
  final RemoteServer server;
  final bool isProUnlocked;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final void Function(TapDownDetails)? onSecondaryTapDown;

  const RemoteServerGridCard({
    super.key,
    required this.server,
    this.isProUnlocked = true,
    this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onSecondaryTapDown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final isSubsonic = server.type == RemoteServerType.subsonic;
    final isJellyfin = server.type == RemoteServerType.jellyfin;
    final isSmb = server.type == RemoteServerType.smb;

    final gradientColors = isSubsonic
        ? const [Color(0xFFFF5E3A), Color(0xFFFF2A68)]
        : (isJellyfin
            ? const [Color(0xFF00A4DC), Color(0xFFAA5CC3)]
            : (isSmb
                ? const [Color(0xFF00B09B), Color(0xFF96C93D)]
                : const [Color(0xFF0072FF), Color(0xFF00C6FF)]));

    final serverIcon = isSubsonic
        ? Icons.library_music_rounded
        : (isJellyfin
            ? Icons.movie_filter_outlined
            : (isSmb ? Icons.dns_outlined : Icons.cloud_queue_rounded));

    final typeLabel = isSubsonic
        ? 'Navidrome'
        : (isJellyfin ? 'Jellyfin' : (isSmb ? 'SMB' : 'WebDAV'));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTapDown,
      onLongPressStart: onLongPressStart,
      onLongPress: onLongPress,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        enableFeedback: false,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
            border: Border.all(
              color: isSubsonic
                  ? Colors.orange.withValues(alpha: 0.3)
                  : Colors.blue.withValues(alpha: 0.3),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1.0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: gradientColors,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              serverIcon,
                              size: 46,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                        if (!isProUnlocked)
                          const Positioned(
                            top: 8,
                            left: 8,
                            child: ProBadge(),
                          ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSubsonic
                                      ? Icons.cloud_done_rounded
                                      : Icons.folder_shared_rounded,
                                  size: 11,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  typeLabel,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          server.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (isPortrait
                                  ? theme.textTheme.titleSmall
                                  : theme.textTheme.titleMedium)
                              ?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          server.url.isEmpty ? typeLabel : server.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (isPortrait
                                  ? theme.textTheme.bodySmall
                                  : theme.textTheme.bodyMedium)
                              ?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rich List Tile widget for a remote server.
class RemoteServerListTile extends StatelessWidget {
  final RemoteServer server;
  final bool isProUnlocked;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final Widget? trailing;

  const RemoteServerListTile({
    super.key,
    required this.server,
    this.isProUnlocked = true,
    this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onSecondaryTapDown,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSubsonic = server.type == RemoteServerType.subsonic;
    final isJellyfin = server.type == RemoteServerType.jellyfin;
    final isSmb = server.type == RemoteServerType.smb;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    final gradientColors = isSubsonic
        ? const [Color(0xFFFF5E3A), Color(0xFFFF2A68)]
        : (isJellyfin
            ? const [Color(0xFF00A4DC), Color(0xFFAA5CC3)]
            : (isSmb
                ? const [Color(0xFF00B09B), Color(0xFF96C93D)]
                : const [Color(0xFF0072FF), Color(0xFF00C6FF)]));

    final serverIcon = isSubsonic
        ? Icons.library_music_rounded
        : (isJellyfin
            ? Icons.movie_filter_outlined
            : (isSmb ? Icons.dns_outlined : Icons.cloud_queue_rounded));

    final typeLabel = isSubsonic
        ? 'Navidrome'
        : (isJellyfin ? 'Jellyfin' : (isSmb ? 'SMB' : 'WebDAV'));

    final leadingWidget = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        boxShadow: [
          BoxShadow(
            color: (isSubsonic
                    ? Colors.orange
                    : (isJellyfin ? const Color(0xFF00A4DC) : Colors.blue))
                .withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          serverIcon,
          size: 26,
          color: Colors.white,
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTapDown,
      onLongPressStart: onLongPressStart,
      onLongPress: onLongPress,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          enableFeedback: false,
          onTap: onTap,
          hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isPortrait ? 12 : 16,
              vertical: 8,
            ),
            child: Row(
              children: [
                leadingWidget,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        server.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$typeLabel · ${server.url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSubsonic
                        ? Colors.orange.withValues(alpha: 0.12)
                        : Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSubsonic ? Colors.orange.shade800 : Colors.blue.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!isProUnlocked) ...[
                  const ProBadge(),
                  const SizedBox(width: 8),
                ],
                trailing ??
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
