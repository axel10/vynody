import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/folder_header_banner.dart';
import 'folder_search_page.dart';
import '../widgets/song_thumbnail.dart';
import '../widgets/default_cover_art.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/utils/folder_helpers.dart';
import '../widgets/folder_header_nav_bar.dart';
import '../widgets/folder_layout_utils.dart';
import '../widgets/folder_content_slivers.dart';
import '../widgets/folder_zoom_gesture_layer.dart';
import '../widgets/remote_server_slivers.dart';
import '../dialogs/add_edit_remote_server_dialog.dart';
import '../utils/selection_utils.dart';
import '../widgets/playback_ui_tuning.dart';
import '../widgets/auto_hide_header.dart';
import '../widgets/folder_floating_action_button.dart';
import '../widgets/folder_scan_widgets.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/pro/pro_models.dart';

/// 同一页里两段网格各自的身份（与 `SliverAnimatedZoomGridDelegate.section` 对齐）。
///
/// 根目录与云服务器两段都参与缩放。换档时上面一段的高度变化要一起
/// 算进下游的位移里，所以必须由同一个 `FolderZoomSliverBuilder` 统一结算，靠它区分。
const Object _kRootFolderSection = 'folder-root.folders';
const Object _kRemoteServerSection = 'folder-root.servers';

class FolderRootView extends ConsumerStatefulWidget {
  const FolderRootView({
    super.key,
    required this.onOpenPlayback,
    required this.isSelectionMode,
    required this.selectedRootPaths,
    this.isCloudServerSelectionMode = false,
    this.selectedServerIds = const <String>{},
    required this.onToggleServerSelection,
    required this.onExitCloudServerSelection,
    required this.onSelectAllCloudServers,
    required this.onPickFolder,
    required this.onToggleRootSelection,
    required this.onToggleRootSelectionMode,
    required this.onDeleteSelectedRootFolders,
    required this.onNavigateTo,
    this.onLocateCurrentSong,
    required this.onShowFolderBottomSheet,
    required this.onShowFolderContextMenu,
  });

  final Future<void> Function()? onOpenPlayback;
  final bool isSelectionMode;
  final Set<String> selectedRootPaths;

  /// 云端媒体库段独立的多选整理态（与根目录多选互斥，由页面统一持有）。
  final bool isCloudServerSelectionMode;
  final Set<String> selectedServerIds;
  final void Function(String) onToggleServerSelection;
  final VoidCallback onExitCloudServerSelection;
  final void Function(Iterable<String>) onSelectAllCloudServers;

  final VoidCallback onPickFolder;
  final void Function(String) onToggleRootSelection;
  final VoidCallback onToggleRootSelectionMode;
  final Future<void> Function() onDeleteSelectedRootFolders;
  final void Function(MusicFolder) onNavigateTo;
  final VoidCallback? onLocateCurrentSong;
  final void Function(MusicFolder, {required bool isRoot}) onShowFolderBottomSheet;
  final void Function(MusicFolder, Offset, {required bool isRoot}) onShowFolderContextMenu;

  @override
  ConsumerState<FolderRootView> createState() => _FolderRootViewState();
}

class _FolderRootViewState extends ConsumerState<FolderRootView> {
  late final ScrollController _localScrollController;
  final ValueNotifier<bool> _showFloatingActions = ValueNotifier<bool>(false);
  int? _lastRootAnchorIndex;

  /// 多选整理态的重排状态机。只在本页内共享（手势层与根目录文件夹段在
  /// 同一个 build 里），不进 `FoldersPageState`。
  final ZoomReorderController _reorderController = ZoomReorderController();

  /// 云端媒体库段单独一个状态机：两个可重排网格不能共用，
  /// `_syncController()` 每帧会覆盖 itemCount / selectedIndices / geometry。
  final ZoomReorderController _cloudServerReorderController =
      ZoomReorderController();

  final ValueNotifier<double> _scrollProgress = ValueNotifier<double>(0.0);

  void _openSearchPage() {
    Navigator.of(context).push(
      (Platform.isIOS || Platform.isMacOS)
          ? CupertinoPageRoute<void>(
              settings: const RouteSettings(name: 'folder_search'),
              builder: (_) => const FolderSearchPage(),
            )
          : MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'folder_search'),
              builder: (_) => const FolderSearchPage(),
            ),
    );
  }

  @override
  void initState() {
    super.initState();
    final targetOffset = ref.read(scannerServiceProvider).getFolderScrollOffset('root');
    _localScrollController = ScrollController(initialScrollOffset: targetOffset);
    _scrollProgress.value = (targetOffset / 160.0).clamp(0.0, 1.0);
    _localScrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant FolderRootView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCloudServerSelectionMode &&
        !widget.isCloudServerSelectionMode) {
      _cloudServerReorderController.cancelDrag();
    }
  }

  /// 全量服务器列表：删除 / 编辑按 id 操作，不能被当前搜索过滤影响。
  List<RemoteServer> get _allCloudServers =>
      ref.read(remoteServersProvider).asData?.value ?? const <RemoteServer>[];

  void _editSelectedCloudServer() {
    if (widget.selectedServerIds.length != 1) return;
    final id = widget.selectedServerIds.single;
    for (final server in _allCloudServers) {
      if (server.id == id) {
        AddEditRemoteServerDialog.show(context, server: server, ref: ref);
        return;
      }
    }
  }

  Future<void> _deleteSelectedCloudServers() async {
    final ids = widget.selectedServerIds.toSet();
    if (ids.isEmpty) return;
    final targets =
        _allCloudServers.where((s) => ids.contains(s.id)).toList();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(
          '${targets.isEmpty ? '${ids.length}' : targets.map((s) => s.name).join('、')}'
          '\n\n${l10n.deleteServerConfirm}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await ref.read(remoteServersProvider.notifier).deleteServers(ids);
    if (!mounted) return;
    widget.onExitCloudServerSelection();
  }

  void _onScroll() {
    final offset = _localScrollController.offset;

    ref.read(scannerServiceProvider).setFolderScrollOffset(
      'root',
      offset,
    );

    final progress = (offset / 160.0).clamp(0.0, 1.0);
    _scrollProgress.value = progress;

    final shouldShowFab = offset > 70.0;
    if (shouldShowFab != _showFloatingActions.value) {
      _showFloatingActions.value = shouldShowFab;
    }
  }

  @override
  void dispose() {
    _localScrollController.removeListener(_onScroll);
    _localScrollController.dispose();
    _scrollProgress.dispose();
    _showFloatingActions.dispose();
    _reorderController.dispose();
    _cloudServerReorderController.dispose();
    super.dispose();
  }

  Future<void> _openRemoteServer(
    BuildContext context,
    RemoteServer server,
  ) async {
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
  }

  Future<void> _handleRefresh() async {
    final scanner = ref.read(scannerServiceProvider);
    HapticFeedback.lightImpact();
    if (Platform.isAndroid) {
      await Future.wait([
        scanner.scanSystemMedia(),
        scanner.scan(clearScannedRoots: false, rescanSystemMedia: true),
      ]);
    } else {
      await scanner.scan(clearScannedRoots: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 组合订阅「结构版本 + 根目录视图」：
    // rootFolders 是缓存视图实例，结构未变时判等成立，所以列表内缩略图
    // 逐张生成不会触发整页重建；带上结构版本是为了覆盖「歌曲总数变化」
    // 这类需要刷新曲目数/时长统计的场景。
    final rootFolderSnapshot = ref.watch(
      scannerServiceProvider.select(
        (s) => (s.structureRevision, s.rootFolders),
      ),
    );
    final rootFolders = rootFolderSnapshot.$2;
    final scanner = ref.read(scannerServiceProvider);
    final settings = ref.watch(settingsServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final isRootSelectionMode =
        ref.watch(librarySelectionScopeProvider) ==
        LibrarySelectionScope.folderRoot;
    // 退出多选整理态时收掉可能还在进行的拖拽，避免浮层与状态机卡住。
    ref.listen(librarySelectionScopeProvider, (previous, next) {
      if (previous == LibrarySelectionScope.folderRoot &&
          next != LibrarySelectionScope.folderRoot) {
        _reorderController.cancelDrag();
      }
    });
    final remoteServers =
        ref.watch(remoteServersProvider).asData?.value ?? [];
    final hasPermission = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.hasPermission),
    );
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    final isLargeScreen = MediaQuery.of(context).size.width >= 1000;
    final selectionLabel = l10n.selectedFolders(widget.selectedRootPaths.length);
    final hasPlayingMusic = currentMusic != null;
    final rootListBottomPadding = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: hasPlayingMusic,
      isSelectionMode: isRootSelectionMode,
      selectionPanelHeight: 120.0,
    );

    final systemFolder = MusicFolder(path: 'system', name: '');
    final systemSongCount = Platform.isAndroid
        ? scanner.getSongCountForFolder(systemFolder)
        : 0;
    final systemDurationMs = Platform.isAndroid
        ? scanner.getSongDurationForFolder(systemFolder)
        : 0;

    final totalSongsCount = rootFolders.fold<int>(
      systemSongCount,
      (sum, folder) => sum + scanner.getSongCountForFolder(folder),
    );
    final totalDurationMs = rootFolders.fold<int>(
      systemDurationMs,
      (sum, folder) => sum + scanner.getSongDurationForFolder(folder),
    );

    final selectedRootSongs = <MusicFile>[
      for (final folder in rootFolders)
        if (widget.selectedRootPaths.contains(folder.path))
          ...folder.allSongs,
    ];
    final allRootSongs = <MusicFile>[
      for (final folder in rootFolders)
        ...folder.allSongs,
    ];

    final representativeSong = () {
      if (Platform.isAndroid) {
        final systemRep = scanner.getRepresentativeSongForFolder(systemFolder);
        if (systemRep != null) return systemRep;
      }
      for (final folder in rootFolders) {
        final song = scanner.getRepresentativeSongForFolder(folder);
        if (song != null) return song;
      }
      return null;
    }();

    final double localFoldersBottomPadding =
        remoteServers.isNotEmpty ? 16.0 : rootListBottomPadding;
    final double remoteServersBottomPadding = rootListBottomPadding;

    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final double headerHeight = FolderNavBarScaffold.getBarHeight(context);

    final rootList = LayoutBuilder(
      builder: (context, constraints) {
        final double crossAxisExtent = constraints.maxWidth;
        return FolderZoomGestureLayer(
          reorderActive: _reorderController.reorderActive,
          zoomGesturesEnabled:
              !isRootSelectionMode && !widget.isCloudServerSelectionMode,
          child: FolderZoomSliverBuilder(
            zoomScale: snapFolderZoomScale(settings.folderZoomScale),
            width: crossAxisExtent,
            controller: _localScrollController,
            builder: (context, metrics) {
              return RefreshIndicator(
                edgeOffset: headerHeight,
                onRefresh: _handleRefresh,
                child: CustomScrollView(
        key: const PageStorageKey<String>('root_folders_scroll_view'),
        controller: _localScrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        cacheExtent: 1000.0,
        slivers: [
        if (!isPortrait)
          SliverToBoxAdapter(
            child: SizedBox(height: headerHeight),
          ),
        SliverToBoxAdapter(
          child: FolderHeaderBanner(
            title: l10n.scanDirectory,
            subtitle: '',
            songsCount: totalSongsCount,
            totalDuration: Duration(milliseconds: totalDurationMs),
            representativeSong: representativeSong,
            coverImagePath: representativeSong?.thumbnailPath ?? (representativeSong != null ? scanner.metadataMap[representativeSong.path]?.thumbnailPath : null),
            thumbnailSize: zoomItemThumbnailSizeFor(metrics),
            topHeader: isPortrait
                ? _buildBannerBreadcrumbs(context, headerHeight)
                : null,
            coverWidget: representativeSong != null
                ? SongThumbnail(
                    path: representativeSong.path,
                    id: representativeSong.id,
                    thumbnailPath: representativeSong.thumbnailPath,
                    bytes: representativeSong.artworkBytes,
                    size: 100,
                    width: 100,
                    height: 100,
                    borderRadius: BorderRadius.zero,
                    fallbackWidget: const DefaultCoverArt.systemFolder(
                      iconSize: 40,
                    ),
                  )
                : const SizedBox(
                    width: 100,
                    height: 100,
                    child: DefaultCoverArt.systemFolder(
                      iconSize: 40,
                    ),
                  ),
            actionButtons: [
              FilledButton.icon(
                onPressed: widget.onPickFolder,
                icon: Icon(Icons.add_circle_outline, size: isLargeScreen ? 18 : 16),
                label: Text(l10n.addRootDirectory),
                style: FilledButton.styleFrom(
                  minimumSize: Size(0, isLargeScreen ? 38 : 32),
                  padding: EdgeInsets.symmetric(horizontal: isLargeScreen ? 16 : 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  textStyle: TextStyle(
                    fontSize: isLargeScreen ? 13.0 : 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FolderPlayActionButtons(
                totalSongsCount: totalSongsCount,
                onPlayAll: () => _handlePlayAll(l10n),
                onShufflePlay: () => _handleShufflePlay(l10n),
              ),
            ],
            actionButtonsScrollable: true,
            onSearch: _openSearchPage,
            heroTag: 'folder-cover-root',
            isHeroModeEnabled: true,
          ),
        ),
        FolderSubfoldersSliver(
          folders: rootFolders,
          zoomScale: settings.folderZoomScale,
          section: _kRootFolderSection,
          scanner: scanner,
          isRoot: true,
          isSelectionMode: isRootSelectionMode,
          selectedFolderPaths: widget.selectedRootPaths,
          reorderController: _reorderController,
          showSystemMedia: Platform.isAndroid,
          hasPermission: hasPermission,
          systemMediaTitle: l10n.systemMediaLibrary,
          systemMediaSubtitle: l10n.needPermissionToScan,
          crossAxisExtent: crossAxisExtent,
          onNavigateTo: widget.onNavigateTo,
          onFolderTap: (folder, index) {
            SelectionActionHelper.handleItemTap(
              index: index,
              itemKey: folder.path,
              items: rootFolders,
              keySelector: (f) => f.path,
              isSelectionMode: isRootSelectionMode,
              selectedKeys: widget.selectedRootPaths,
              lastAnchorIndex: _lastRootAnchorIndex,
              onUpdateAnchor: (a) => setState(() => _lastRootAnchorIndex = a),
              onSetSelection: (keys) {
                for (final k in keys) {
                  if (!widget.selectedRootPaths.contains(k)) {
                    widget.onToggleRootSelection(k);
                  }
                }
              },
              onToggleSelection: (key) => widget.onToggleRootSelection(key),
              onEnterSelectionMode: () => widget.onToggleRootSelectionMode(),
              onNormalTap: () => widget.onNavigateTo(folder),
            );
          },
          onFolderLongPress: (folder, index) {
            _lastRootAnchorIndex = index;
            if (!isRootSelectionMode) {
              widget.onToggleRootSelectionMode();
            }
            widget.onToggleRootSelection(folder.path);
          },
          onToggleFolderSelection: widget.onToggleRootSelection,
          onToggleSelectionMode: widget.onToggleRootSelectionMode,
          onShowFolderContextMenu: widget.onShowFolderContextMenu,
          bottomPadding: localFoldersBottomPadding,
        ),
        if (remoteServers.isNotEmpty) ...[
          RemoteServersSectionHeaderSliver(
            title: l10n.tabCloudServers,
            count: remoteServers.length,
            onAddServer: () => AddEditRemoteServerDialog.show(context, ref: ref),
          ),
          RemoteServersSliver(
            servers: remoteServers,
            zoomScale: settings.folderZoomScale,
            section: _kRemoteServerSection,
            isSelectionMode: widget.isCloudServerSelectionMode,
            selectedServerIds: widget.selectedServerIds,
            onToggleServerSelection: widget.onToggleServerSelection,
            onExitSelectionMode: widget.onExitCloudServerSelection,
            reorderController: _cloudServerReorderController,
            crossAxisExtent: crossAxisExtent,
            onOpenServer: (server) => _openRemoteServer(context, server),
            bottomPadding: remoteServersBottomPadding,
          ),
        ],
      ],
      ),
              );
            },
          ),
        );
      },
    );

    final theme = Theme.of(context);

    return AutoHideHeaderScope(
      enabled: false,
      forceVisible: isRootSelectionMode,
      builder: (context, isHeaderVisible) => Scaffold(
        body: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: folderPageMaxWidth),
                child: rootList,
              ),
            ),
            if (!isPortrait)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AutoHideHeader(
                  isVisible: isHeaderVisible,
                  child: _buildRootTopHeader(
                    context,
                    isOverlay: true,
                    totalSongsCount: totalSongsCount,
                    onPlayAll: () => _handlePlayAll(l10n),
                    onShufflePlay: () => _handleShufflePlay(l10n),
                  ),
                ),
              ),
            if (isPortrait)
              FolderFloatingHeaderBar(
                visibleListenable: _showFloatingActions,
                isSelectionMode: isRootSelectionMode,
                showBack: false,
                contentMaxWidth: folderPageMaxWidth,
                trailingAction: PopupMenuButton<String>(
                  tooltip: l10n.more,
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: theme.colorScheme.onSurface,
                    size: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                    onSelected: (val) {
                      switch (val) {
                        case 'search':
                          _handleSearchAction();
                          break;
                        case 'locate':
                          widget.onLocateCurrentSong?.call();
                          break;
                        case 'refresh':
                          _handleRefresh();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'search',
                        child: Row(
                          children: [
                            const Icon(Icons.search_rounded, size: 20),
                            const SizedBox(width: 12),
                            Text(l10n.search),
                          ],
                        ),
                      ),
                      if (currentMusic != null &&
                          widget.onLocateCurrentSong != null)
                        PopupMenuItem(
                          value: 'locate',
                          child: Row(
                            children: [
                              const Icon(Icons.my_location_rounded, size: 20),
                              const SizedBox(width: 12),
                              Text(l10n.locateCurrentSong),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'refresh',
                        child: Row(
                          children: [
                            const Icon(Icons.refresh_rounded, size: 20),
                            const SizedBox(width: 12),
                            Text(l10n.refresh),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                reverseDuration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offsetAnimation = Tween<Offset>(
                    begin: const Offset(0, 1.0),
                    end: Offset.zero,
                  ).animate(animation);
                  return SlideTransition(position: offsetAnimation, child: child);
                },
                child: widget.isCloudServerSelectionMode
                    ? LibrarySelectionPanel(
                        key: const ValueKey('cloud-server-selection-panel'),
                        title:
                            '${l10n.multiSelect}  ·  ${widget.selectedServerIds.length} / ${remoteServers.length}',
                        onCancel: widget.onExitCloudServerSelection,
                        customActions: [
                          SelectionActionItem(
                            icon: (widget.selectedServerIds.length ==
                                        remoteServers.length &&
                                    remoteServers.isNotEmpty)
                                ? Icons.deselect_rounded
                                : Icons.select_all_rounded,
                            label: (widget.selectedServerIds.length ==
                                        remoteServers.length &&
                                    remoteServers.isNotEmpty)
                                ? l10n.deselectAll
                                : l10n.selectAll,
                            onPressed: () => widget.onSelectAllCloudServers(
                              remoteServers.map((s) => s.id),
                            ),
                          ),
                          SelectionActionItem(
                            icon: Icons.edit_rounded,
                            label: l10n.edit,
                            onPressed: widget.selectedServerIds.length == 1
                                ? _editSelectedCloudServer
                                : null,
                          ),
                          SelectionActionItem(
                            icon: Icons.delete_outline_rounded,
                            label: l10n.delete,
                            onPressed: widget.selectedServerIds.isEmpty
                                ? null
                                : () => unawaited(_deleteSelectedCloudServers()),
                            isDestructive: true,
                          ),
                        ],
                      )
                    : (isRootSelectionMode
                        ? LibrarySelectionPanel(
                            key: const ValueKey('root-selection-panel'),
                            selectedSongs: selectedRootSongs,
                            allSongs: allRootSongs,
                            title: selectionLabel,
                            isSelectionEmpty: widget.selectedRootPaths.isEmpty,
                            isAllSelected: widget.selectedRootPaths.length == rootFolders.length && rootFolders.isNotEmpty,
                            hideSongProperties: true,
                            onToggleSelectAll: () {
                              final isAllSelected =
                                  widget.selectedRootPaths.length == rootFolders.length;
                              if (isAllSelected) {
                                for (final f in rootFolders) {
                                  widget.onToggleRootSelection(f.path);
                                }
                              } else {
                                for (final f in rootFolders) {
                                  if (!widget.selectedRootPaths.contains(f.path)) {
                                    widget.onToggleRootSelection(f.path);
                                  }
                                }
                              }
                            },
                            onCancel: widget.onToggleRootSelectionMode,
                            onDelete: widget.selectedRootPaths.isEmpty
                                ? null
                                : widget.onDeleteSelectedRootFolders,
                            deleteLabel: l10n.delete,
                            onOpenLocation: widget.selectedRootPaths.length == 1
                                ? () => openFolderLocation(widget.selectedRootPaths.first)
                                : null,
                            openLocationLabel: l10n.openFolderLocation,
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('selection-panel-hidden'),
                          )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 竖屏下面包屑嵌进 Banner 顶部，随内容一起滚动。
  Widget _buildBannerBreadcrumbs(BuildContext context, double headerHeight) {
    final style = FolderNavBarStyle.overlay(context);
    final l10n = AppLocalizations.of(context)!;
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    // Banner 内容左内边距 16，固定顶栏是 8；向左补偿这 8px 才能和顶栏对齐
    const bannerHorizontalInsetCompensation = -8.0;
    return SizedBox(
      height: headerHeight,
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(
            top: FolderNavBarScaffold.getContentTopInset(context),
          ),
          child: Transform.translate(
            offset: const Offset(bannerHorizontalInsetCompensation, 0),
            child: Row(
              children: [
                FolderBreadcrumbItem(
                  style: style,
                  icon: Icons.home_rounded,
                  tooltip: l10n.scanDirectory,
                  onTap: () => AutoHideHeaderScope.scrollToTop(context),
                ),
                FolderBreadcrumbSeparator(style: style),
                FolderBreadcrumbItem(
                  style: style,
                  label: l10n.scanDirectory,
                ),
                const Spacer(),
                FolderScanSpinner(style: style),
                FolderNavActionMenu<String>(
                  style: style,
                  onSelected: (value) {
                    if (value == 'search') {
                      _handleSearchAction();
                    } else if (value == 'locate') {
                      widget.onLocateCurrentSong?.call();
                    } else if (value == 'refresh') {
                      _handleRefresh();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'search',
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, size: 20),
                          const SizedBox(width: 12),
                          Text(l10n.search),
                        ],
                      ),
                    ),
                    if (currentMusic != null &&
                        widget.onLocateCurrentSong != null)
                      PopupMenuItem(
                        value: 'locate',
                        child: Row(
                          children: [
                            const Icon(Icons.my_location_rounded, size: 20),
                            const SizedBox(width: 12),
                            Text(l10n.locateCurrentSong),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: Row(
                        children: [
                          const Icon(Icons.refresh_rounded, size: 20),
                          const SizedBox(width: 12),
                          Text(l10n.refresh),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handlePlayAll(AppLocalizations l10n) async {
    final scanner = ref.read(scannerServiceProvider);
    final audio = ref.read(audioServiceProvider);
    final songs = await scanner.getAllRootSongs();
    if (songs.isNotEmpty) {
      await audio.playPlaylist(
        songs,
        source: PlaybackSource(
          type: PlaybackSourceType.folder,
          id: 'root',
          name: l10n.scanDirectory,
        ),
      );
    }
  }

  Future<void> _handleShufflePlay(AppLocalizations l10n) async {
    final scanner = ref.read(scannerServiceProvider);
    final audio = ref.read(audioServiceProvider);
    final songs = await scanner.getAllRootSongs();
    if (songs.isNotEmpty) {
      await audio.playPlaylist(
        List.of(songs)..shuffle(),
        source: PlaybackSource(
          type: PlaybackSourceType.folder,
          id: 'root',
          name: l10n.scanDirectory,
        ),
      );
    }
  }

  void _handleSearchAction() {
    _openSearchPage();
  }

  Widget _buildRootTopHeader(
    BuildContext context, {
    bool isOverlay = true,
    int totalSongsCount = 0,
    VoidCallback? onPlayAll,
    VoidCallback? onShufflePlay,
  }) {
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    return Material(
      type: MaterialType.transparency,
      child: FolderHeaderNavBar(
        isOverlay: isOverlay,
        scrollProgress: _scrollProgress,
        onLocateCurrentSong: widget.onLocateCurrentSong,
        onRefresh: _handleRefresh,
        // 竖屏面包屑在 Banner 里；横屏仍由顶栏承载
        hideBreadcrumbs: isPortrait,
        onPlayAll: onPlayAll,
        onShufflePlay: onShufflePlay,
        onSearch: _handleSearchAction,
        totalSongsCount: totalSongsCount,
      ),
    );
  }
}
