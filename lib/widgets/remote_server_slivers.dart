import 'dart:io';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dialogs/add_edit_remote_server_dialog.dart';
import '../l10n/app_localizations.dart';
import '../player/remote/remote_server_models.dart';
import '../player/remote/remote_server_riverpod.dart';
import 'folder_layout_utils.dart';
import 'app_context_menu.dart';
import 'library_selection_panel.dart';
import 'pro/pro_badge.dart';
import '../player/pro/pro_license_service.dart';
import '../player/pro/pro_models.dart';

/// Shows a context menu or bottom sheet for a remote media server (Browse, Edit, Delete).
Future<void> showRemoteServerContextMenu({
  required BuildContext context,
  required Offset position,
  required RemoteServer server,
  required WidgetRef ref,
  VoidCallback? onMultiSelect,
  bool isMultiSelectMode = false,
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
    // 没传回调的调用方不该看到一个点了没反应的「多选」项。
    if (onMultiSelect != null)
      [
        ContextMenuAction(
          value: isMultiSelectMode ? 'exit_multi_select' : 'multi_select',
          label: isMultiSelectMode ? l10n.exitMultiSelect : l10n.multiSelect,
          icon: isMultiSelectMode
              ? Icons.close_rounded
              : Icons.checklist_rounded,
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
  } else if (selected == 'multi_select' ||
      selected == 'exit_multi_select') {
    onMultiSelect?.call();
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
  final bool isSelectionMode;
  final Set<String> selectedServerIds;
  final void Function(String) onToggleServerSelection;
  final VoidCallback onExitSelectionMode;
  final ZoomReorderController? reorderController;
  final void Function(RemoteServer server) onOpenServer;
  final double bottomPadding;
  final double? crossAxisExtent;

  /// 本段身份，必须与 `SliverAnimatedZoomGridDelegate.section` 一致。
  final Object? section;

  const RemoteServersSliver({
    super.key,
    required this.servers,
    required this.zoomScale,
    this.isSelectionMode = false,
    this.selectedServerIds = const <String>{},
    required this.onToggleServerSelection,
    required this.onExitSelectionMode,
    this.reorderController,
    required this.onOpenServer,
    this.bottomPadding = 160.0,
    this.crossAxisExtent,
    this.section,
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

    return FolderZoomSectionHost(
      zoomScale: effectiveZoom,
      width: width,
      builder: (context, metrics) {
        final isGrid = metrics.isGridTarget;

        // 多选整理态：列表档与网格档共用同一个可重排网格，槽位几何与
        // SliverAnimatedZoomGridDelegate 同源。width 必须传内容宽度
        // （扣掉外层 SliverPadding），否则卡片宽 32px、插入位判定错位。
        if (isSelectionMode) {
          final hPad = isGrid
              ? kGridHorizontalPadding
              : folderContentHorizontalPadding(
                  isPortrait: isPortrait,
                  gridMorph: 0.0,
                );
          final contentWidth = width - hPad * 2;
          final selectedIndices = <int>{
            for (var i = 0; i < servers.length; i++)
              if (selectedServerIds.contains(servers[i].id)) i,
          };

          return SliverPadding(
            padding: EdgeInsets.only(
              top: isGrid ? 8.0 : 0.0,
              bottom: bottomPadding,
              left: hPad,
              right: hPad,
            ),
            sliver: ZoomReorderableSliverGrid(
              metrics: metrics,
              width: contentWidth,
              itemCount: servers.length,
              itemKeyBuilder: (index) => ValueKey<String>(servers[index].id),
              section: section,
              controller: reorderController,
              selectedIndices: selectedIndices,
              showHandles: true,
              handleChild: buildRemoteServerReorderHandle(context),
              previewBuilder: (context, _, count) =>
                  buildRemoteServerReorderPreview(context, count),
              onReorder: (draggedIndices, insertIndex) {
                final reordered = ZoomReorderController.applyReorder(
                  servers,
                  draggedIndices,
                  insertIndex,
                );
                ref
                    .read(remoteServersProvider.notifier)
                    .reorderServers(reordered);
              },
              itemBuilder: (context, index) {
                final server = servers[index];
                return RemoteServerZoomItem(
                  server: server,
                  metrics: metrics,
                  section: section,
                  index: index,
                  isProUnlocked: isProUnlocked,
                  isSelected: selectedServerIds.contains(server.id),
                  isSelectionMode: true,
                  onTap: () => onToggleServerSelection(server.id),
                  onSecondaryTapDown: (details) {
                    showRemoteServerContextMenu(
                      context: context,
                      position: details.globalPosition,
                      server: server,
                      ref: ref,
                      isMultiSelectMode: true,
                      onMultiSelect: onExitSelectionMode,
                    );
                  },
                );
              },
            ),
          );
        }

        // Unified SliverGrid for both List Mode (`gridMorph = 0.0`) and Grid Mode (`gridMorph = 1.0`)
        final hPad = folderContentHorizontalPadding(
          isPortrait: isPortrait,
          gridMorph: metrics.gridMorph,
        );
        // 段首内边距**必须与档位无关**：它落在缩放网格的 `SliverPadding` 上，会被
        // 包里的滚动补偿当作「与档位无关的固定内容」（`gapBefore` 只在稳态量一次，
        // 过渡期用它外推下游段位置）。随 `gridMorph` 变化 → 换档收尾那一帧要一次性
        // 补差额，表现为列表「往下沉一点」。回归见
        // `zoomable_sliver_grid/test/zoom_section_gap_test.dart`。
        const double topPad = 8.0;

        return SliverPadding(
          padding: EdgeInsets.only(
            top: topPad,
            bottom: bottomPadding,
            left: hPad,
            right: hPad,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverAnimatedZoomGridDelegate(
              metrics: metrics,
              section: section,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final server = servers[index];
                return RemoteServerZoomItem(
                  key: ValueKey('server_${server.id}'),
                  server: server,
                  metrics: metrics,
                  section: section,
                  index: index,
                  isProUnlocked: isProUnlocked,
                  onTap: () => onOpenServer(server),
                  onLongPress: () => onToggleServerSelection(server.id),
                  onSecondaryTapDown: (details) {
                    showRemoteServerContextMenu(
                      context: context,
                      position: details.globalPosition,
                      server: server,
                      ref: ref,
                      onMultiSelect: () =>
                          onToggleServerSelection(server.id),
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
  final bool isSelected;
  final bool isSelectionMode;
  final int? index;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final void Function(Offset position)? onContextMenu;
  final Widget? trailing;

  /// 本条目所属的网格段，必须与 `SliverAnimatedZoomGridDelegate.section` 一致。
  final Object? section;

  const RemoteServerZoomItem({
    super.key,
    required this.server,
    required this.metrics,
    this.isProUnlocked = true,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.index,
    this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onSecondaryTapDown,
    this.onContextMenu,
    this.trailing,
    this.section,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gridMorph = metrics.gridMorph;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final coverWidth = constraints.maxWidth;
          // 判定是否有足够空间容纳角标文字：
          // 胶囊文字（如 Navidrome）连同图标与边距约需 65-75px；
          // 若左上角有 ProBadge（宽度约 28px + 边距），安全宽度需约 120px；
          // 若已解锁 Pro，单侧显示文字也至少需要约 95px 宽度才不显得紧贴左边。
          final minWidthForText = isProUnlocked ? 95.0 : 120.0;
          final showBadgeText = coverWidth >= minWidthForText;

          final edgePadding = lerpDouble(4.0, 8.0, gridMorph)!;
          final maxBadgeWidth = (coverWidth -
                  edgePadding * 2 -
                  (isProUnlocked ? 0.0 : 34.0))
              .clamp(0.0, coverWidth);

          return Stack(
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
                              : (isJellyfin
                                  ? const Color(0xFF00A4DC)
                                  : Colors.blue))
                          .withValues(
                              alpha: lerpDouble(0.2, 0.08, gridMorph)!),
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
                    top: edgePadding,
                    left: edgePadding,
                    child: Opacity(
                      opacity: gridMorph.clamp(0.0, 1.0),
                      child: const ProBadge(),
                    ),
                  ),
                Positioned(
                  top: edgePadding,
                  right: edgePadding,
                  child: Opacity(
                    opacity: gridMorph.clamp(0.0, 1.0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxBadgeWidth),
                      child: Container(
                        padding: showBadgeText
                            ? EdgeInsets.symmetric(
                                horizontal: lerpDouble(5.0, 7.0, gridMorph)!,
                                vertical: lerpDouble(2.0, 3.0, gridMorph)!,
                              )
                            : EdgeInsets.all(lerpDouble(3.0, 4.5, gridMorph)!),
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
                            if (showBadgeText) ...[
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  typeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize:
                                        lerpDouble(8.5, 10.0, gridMorph)!,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );

    final listTrailingWidget = trailing ??
        Row(
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

    final double listTrailingEstimatedWidth =
        trailing != null ? 48.0 : (!isProUnlocked ? 130.0 : 90.0);

    // 多选整理态：封面层叠遮罩 + 复选框，位置与 ZoomItemCover 一致
    // （列表态居中、网格态左上角），避开右上角的排序手柄。
    final Widget cover;
    if (isSelectionMode) {
      cover = ClipRRect(
        borderRadius: coverRadius,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            coverStack,
            Positioned.fill(
              child: ColoredBox(
                color: isSelected
                    ? theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.42)
                    : Colors.black.withValues(alpha: 0.28),
              ),
            ),
            Align(
              alignment: Alignment.lerp(
                Alignment.center,
                Alignment.topLeft,
                gridMorph,
              )!,
              child: Padding(
                padding: EdgeInsets.all(lerpDouble(0.0, 8.0, gridMorph)!),
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onTap?.call(),
                    fillColor: WidgetStateProperty.all(Colors.white),
                    checkColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      cover = coverStack;
    }

    final scaffold = ZoomItemScaffold(
      metrics: metrics,
      section: section,
      index: index,
      cover: cover,
      titleText: server.name,
      subtitleText: server.url.isEmpty ? typeLabel : server.url,
      trailing: listTrailingWidget,
      trailingWidth: listTrailingEstimatedWidth,
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressStart: onLongPressStart,
      onSecondaryTapDown: onSecondaryTapDown,
      onContextMenu: onContextMenu,
    );
    return scaffold;
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

/// 多选整理态下条目右上角的排序手柄图标。
Widget buildRemoteServerReorderHandle(BuildContext context) {
  return Icon(
    Icons.drag_handle_rounded,
    size: 18,
    color: Theme.of(context).colorScheme.primary,
  );
}

/// 多条已选云服务器收拢成合集时的拖拽浮层。
Widget buildRemoteServerReorderPreview(BuildContext context, int count) {
  final theme = Theme.of(context);
  return Material(
    elevation: 8,
    borderRadius: BorderRadius.circular(14),
    color: theme.colorScheme.surfaceContainerHighest,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.cloud_queue_rounded,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    ),
  );
}

/// 云端媒体库多选整理态的底部操作面板。
///
/// 只有「全选 / 编辑 / 删除 / 退出」四项；编辑仅单选可用、删除仅在有选中时可用，
/// 底层直接复用 [LibrarySelectionPanel]，保证全应用多选体验与视觉规范统一。
class CloudServerSelectionPanel extends StatelessWidget {
  const CloudServerSelectionPanel({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.onSelectAll,
    required this.onDelete,
    required this.onEdit,
    required this.onCancel,
  });

  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isAllSelected = selectedCount == totalCount && totalCount > 0;
    return LibrarySelectionPanel(
      title: '${l10n.multiSelect}  ·  $selectedCount / $totalCount',
      onCancel: onCancel,
      customActions: [
        SelectionActionItem(
          icon: isAllSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
          label: isAllSelected ? l10n.deselectAll : l10n.selectAll,
          onPressed: onSelectAll,
        ),
        SelectionActionItem(
          icon: Icons.edit_rounded,
          label: l10n.edit,
          onPressed: onEdit,
        ),
        SelectionActionItem(
          icon: Icons.delete_outline_rounded,
          label: l10n.delete,
          onPressed: onDelete,
          isDestructive: true,
        ),
      ],
    );
  }
}
