import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dialogs/add_edit_remote_server_dialog.dart';
import '../l10n/app_localizations.dart';
import '../player/remote/remote_server_models.dart';
import '../player/remote/remote_server_riverpod.dart';
import 'folder_layout_utils.dart';
import 'hoverable_card.dart';
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

/// Renders remote servers in grid or list view with animated zoom item morphing.
class RemoteServersSliver extends ConsumerWidget {
  final List<RemoteServer> servers;
  final double zoomScale;
  final bool isSortMode;
  final void Function(RemoteServer server) onOpenServer;
  final double bottomPadding;
  final double? crossAxisExtent;

  const RemoteServersSliver({
    super.key,
    required this.servers,
    required this.zoomScale,
    this.isSortMode = false,
    required this.onOpenServer,
    this.bottomPadding = 160.0,
    this.crossAxisExtent,
  });

  double get _effectiveZoomScale => snapFolderZoomScale(zoomScale);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (servers.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final isProUnlocked = ref.watch(isProUnlockedProvider);
    final width = crossAxisExtent ?? MediaQuery.sizeOf(context).width;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final effectiveZoom = _effectiveZoomScale;

    return FolderZoomSliverBuilder(
      zoomScale: effectiveZoom,
      width: width,
      builder: (context, metrics) {
        final isGrid = metrics.isGridTarget;

        if (isSortMode) {
          if (isGrid) {
            final crossAxisCount = metrics.targetGridCols;
            final childAspectRatio = metrics.targetChildAspectRatio;

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
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: kGridCrossAxisSpacing,
                        mainAxisSpacing: kGridMainAxisSpacing,
                        childAspectRatio: childAspectRatio,
                      ),
                      children: children,
                    );
                  },
                  children: servers.map((server) {
                    return RemoteServerZoomItem(
                      key: ValueKey('sort_server_${server.id}'),
                      server: server,
                      metrics: metrics,
                      isProUnlocked: isProUnlocked,
                      isSortMode: true,
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
                    );
                  }).toList(),
                ),
              ),
            );
          } else {
            return SliverPadding(
              padding: EdgeInsets.only(
                top: 0,
                bottom: bottomPadding,
                left: isPortrait ? 4 : 8,
                right: isPortrait ? 4 : 8,
              ),
              sliver: SliverReorderableList(
                itemCount: servers.length,
                onReorderItem: (oldIndex, newIndex) {
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
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: SizedBox(
                        height: metrics.animatedListExtent,
                        child: RemoteServerZoomItem(
                          server: server,
                          metrics: metrics,
                          isProUnlocked: isProUnlocked,
                          isSortMode: true,
                          trailing: ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ),
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
                      ),
                    ),
                  );
                },
              ),
            );
          }
        }

        // Unified SliverGrid for both List Mode (`gridMorph = 0.0`) and Grid Mode (`gridMorph = 1.0`)
        final hPad = folderContentHorizontalPadding(
          isPortrait: isPortrait,
          gridMorph: metrics.gridMorph,
        );
        final topPad = lerpDouble(0.0, 8.0, metrics.gridMorph)!;

        return SliverPadding(
          padding: EdgeInsets.only(
            top: topPad,
            bottom: bottomPadding,
            left: hPad,
            right: hPad,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final server = servers[index];
                return RemoteServerZoomItem(
                  key: ValueKey('server_${server.id}'),
                  server: server,
                  metrics: metrics,
                  isProUnlocked: isProUnlocked,
                  isSortMode: false,
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
                );
              },
              childCount: servers.length,
            ),
          ),
        );
      },
    );
  }
}

/// Unified remote server item widget that smoothly morphs between List View and Grid View
/// based on [FolderZoomLayoutMetrics].
class RemoteServerZoomItem extends StatelessWidget {
  final RemoteServer server;
  final FolderZoomLayoutMetrics metrics;
  final bool isProUnlocked;
  final bool isSortMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final Widget? trailing;

  const RemoteServerZoomItem({
    super.key,
    required this.server,
    required this.metrics,
    this.isProUnlocked = true,
    this.isSortMode = false,
    this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onSecondaryTapDown,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final gridMorph = metrics.gridMorph;
    final isGridTarget = metrics.isGridTarget;

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

    final coverRadiusValue = lerpDouble(8.0, 14.0, gridMorph)!;
    final coverRadius = BorderRadius.circular(coverRadiusValue);

    final gridIconSize = switch (metrics.tier) {
      FolderZoomTier.smallGrid => 28.0,
      FolderZoomTier.mediumGrid => 38.0,
      FolderZoomTier.largeGrid || _ => 46.0,
    };
    final listIconSize = switch (metrics.tier) {
      FolderZoomTier.minimalList => 0.0,
      FolderZoomTier.compactList => 18.0,
      FolderZoomTier.standardList => 24.0,
      FolderZoomTier.largeList => 32.0,
      _ => 24.0,
    };
    final defaultIconSize = lerpDouble(listIconSize, gridIconSize, gridMorph)!;

    final coverStack = ClipRRect(
      borderRadius: coverRadius,
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
              boxShadow: [
                BoxShadow(
                  color: (isSubsonic
                          ? Colors.orange
                          : (isJellyfin ? const Color(0xFF00A4DC) : Colors.blue))
                      .withValues(alpha: lerpDouble(0.2, 0.08, gridMorph)!),
                  blurRadius: lerpDouble(8.0, 12.0, gridMorph)!,
                  offset: Offset(0, lerpDouble(2.0, 4.0, gridMorph)!),
                ),
              ],
            ),
            child: defaultIconSize > 1.0
                ? Center(
                    child: Icon(
                      serverIcon,
                      size: defaultIconSize,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (gridMorph > 0.05) ...[
            if (!isProUnlocked)
              Positioned(
                top: lerpDouble(4.0, 8.0, gridMorph)!,
                left: lerpDouble(4.0, 8.0, gridMorph)!,
                child: Opacity(
                  opacity: gridMorph.clamp(0.0, 1.0),
                  child: const ProBadge(),
                ),
              ),
            Positioned(
              top: lerpDouble(4.0, 8.0, gridMorph)!,
              right: lerpDouble(4.0, 8.0, gridMorph)!,
              child: Opacity(
                opacity: gridMorph.clamp(0.0, 1.0),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: lerpDouble(5.0, 7.0, gridMorph)!,
                    vertical: lerpDouble(2.0, 3.0, gridMorph)!,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
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
                        size: lerpDouble(9.0, 11.0, gridMorph)!,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: lerpDouble(8.5, 10.0, gridMorph)!,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final TextStyle titleStyle;
    final TextStyle subtitleStyle;
    if (!isGridTarget) {
      titleStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        height: 1.2,
      );
      subtitleStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: 12.0,
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.2,
      );
    } else {
      final fonts = folderGridFontSizes(metrics.targetCardWidth);
      titleStyle = ((isPortrait
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.titleMedium) ??
              const TextStyle())
          .copyWith(
        fontWeight: FontWeight.w600,
        fontSize: fonts.title,
        color: theme.colorScheme.onSurface,
        height: 1.25,
      );
      subtitleStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: fonts.subtitle,
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.2,
      );
    }

    final textColumn = Align(
      alignment: Alignment.centerLeft,
      child: OverflowBox(
        minHeight: 0.0,
        maxHeight: double.infinity,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              style: titleStyle,
              child: Text(
                server.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(height: lerpDouble(4.0, 2.0, gridMorph)!),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              style: subtitleStyle,
              child: Text(
                server.url.isEmpty ? typeLabel : server.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    Widget? listTrailingWidget;
    if (trailing != null) {
      listTrailingWidget = trailing;
    } else {
      listTrailingWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                color: isSubsonic
                    ? Colors.orange.shade800
                    : Colors.blue.shade800,
              ),
            ),
          ),
          if (!isProUnlocked) ...[
            const SizedBox(width: 8),
            const ProBadge(),
          ],
          const SizedBox(width: 8),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 13,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      );
    }

    final double listTrailingEstimatedWidth =
        trailing != null ? 48.0 : (!isProUnlocked ? 130.0 : 90.0);

    final itemContent = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTapDown,
      onLongPressStart: onLongPressStart,
      onLongPress: onLongPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(coverRadiusValue),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(coverRadiusValue),
          child: InkWell(
            borderRadius: BorderRadius.circular(coverRadiusValue),
            enableFeedback: false,
            onTap: onTap,
            hoverColor: gridMorph < 0.5
                ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                : Colors.transparent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final W = constraints.maxWidth;
                final H = constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : metrics.animatedListExtent;

                final listPadH = isPortrait ? 12.0 : 16.0;
                final listCoverSize = getFolderListCoverSize(
                  metrics.animatedZoomScale,
                ).clamp(0.0, math.max(0.0, H - 8.0));
                final listCoverLeft = listPadH;
                final listCoverTop =
                    ((H - listCoverSize) / 2.0).clamp(0.0, H);

                final gridCoverSize = math.max(
                  0.0,
                  math.min(W, H - metrics.animatedGridTextHeight),
                );
                final gridCoverLeft = (W - gridCoverSize) / 2.0;
                const gridCoverTop = 0.0;

                final coverLeft =
                    lerpDouble(listCoverLeft, gridCoverLeft, gridMorph)!;
                final coverTop =
                    lerpDouble(listCoverTop, gridCoverTop, gridMorph)!;
                final coverSize =
                    lerpDouble(listCoverSize, gridCoverSize, gridMorph)!;

                final trailingSpace =
                    lerpDouble(listTrailingEstimatedWidth, 0.0, gridMorph)!;

                final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
                final listCoverGap = 16.0 * coverProgress;

                final listTextLeft =
                    listCoverLeft + listCoverSize + listCoverGap;
                final listTextHeight =
                    math.max(listCoverSize, math.max(0.0, H - 8.0));
                final listTextTop =
                    ((H - listTextHeight) / 2.0).clamp(0.0, H);
                final listTextWidth = math.max(
                  0.0,
                  W - listTextLeft - listPadH - trailingSpace,
                );

                const gridTextLeft = 0.0;
                final gridTextTop = gridCoverSize + 4.0;
                final gridTextWidth = W;
                final gridTextHeight = math.max(0.0, H - gridTextTop);

                final textLeft =
                    lerpDouble(listTextLeft, gridTextLeft, gridMorph)!;
                final textTop =
                    lerpDouble(listTextTop, gridTextTop, gridMorph)!;
                final textWidth =
                    lerpDouble(listTextWidth, gridTextWidth, gridMorph)!;
                final textHeight =
                    lerpDouble(listTextHeight, gridTextHeight, gridMorph)!;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (coverSize > 0.5)
                      Positioned(
                        left: coverLeft,
                        top: coverTop,
                        width: coverSize,
                        height: coverSize,
                        child: coverStack,
                      ),
                    Positioned(
                      left: textLeft,
                      top: textTop,
                      width: textWidth,
                      height: textHeight,
                      child: textColumn,
                    ),
                    if (gridMorph < 0.99 && listTrailingWidget != null)
                      Positioned(
                        right: listPadH,
                        top: 0,
                        bottom: 0,
                        child: Opacity(
                          opacity: (1.0 - gridMorph).clamp(0.0, 1.0),
                          child: Center(child: listTrailingWidget),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    return isGridTarget ? HoverableCard(child: itemContent) : itemContent;
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
