import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/clients/webdav_client.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/services/remote_scan_root.dart';
import 'package:vynody/utils/remote_context_menu_utils.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';
import 'package:vynody/widgets/folder_zoom_item.dart';
import 'package:vynody/widgets/song_zoom_item.dart';

/// Renders WebDAV subfolders in unified zoom-driven grid or list view.
class WebDavSubfoldersSliver extends ConsumerWidget {
  /// 未接封面时的占位（永远为空）。
  ///
  /// 用常量而不是在 build 里 `?? const {}`：外部不传封面时也要走同一条
  /// `ValueListenableBuilder` 路径，否则根 Widget 类型会随参数切换，
  /// 整段网格被 deactivate 重建。
  static final ValueNotifier<Map<String, MusicFile>> _kNoFolderCovers =
      ValueNotifier<Map<String, MusicFile>>(const {});

  final List<WebDavFile> folders;
  final double zoomScale;
  final RemoteServer server;
  final String password;
  final bool isSelectionMode;
  final Set<String> selectedFolderPaths;
  final void Function(WebDavFile) onOpenFolder;
  final void Function(WebDavFile folder, int index)? onFolderTap;
  final void Function(WebDavFile folder, int index)? onFolderLongPress;
  final void Function(String folderPath)? onToggleFolderSelection;
  final VoidCallback? onToggleSelectionMode;
  final void Function(WebDavFile folder)? onShowFolderBottomSheet;
  final double? crossAxisExtent;

  /// 子目录的代表封面（键 = 目录 virtualUri）。
  ///
  /// 远程目录没有文件夹级封面元数据，这张表由页面按「缓存 → 索引 → 网络」补齐；
  /// 用 [ValueListenable] 是为了只重建这层网格，不惊动整页。
  final ValueListenable<Map<String, MusicFile>>? folderCoverSongs;

  /// 本段身份，必须与 `SliverAnimatedZoomGridDelegate.section` 一致。
  final Object? section;

  const WebDavSubfoldersSliver({
    super.key,
    required this.folders,
    required this.zoomScale,
    required this.server,
    required this.password,
    this.isSelectionMode = false,
    this.selectedFolderPaths = const {},
    required this.onOpenFolder,
    this.onFolderTap,
    this.onFolderLongPress,
    this.onToggleFolderSelection,
    this.onToggleSelectionMode,
    this.onShowFolderBottomSheet,
    this.crossAxisExtent,
    this.folderCoverSongs,
    this.section,
  });

  double get _effectiveZoomScale => snapFolderZoomScale(zoomScale);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(remoteScanRootsProvider);
    final scanRootsNotifier = ref.read(remoteScanRootsProvider.notifier);

    void openContextMenu(WebDavFile folder, Offset globalPosition) {
      showWebDavFolderContextMenu(
        context: context,
        globalPosition: globalPosition,
        ref: ref,
        server: server,
        password: password,
        folder: folder,
        onOpen: () => onOpenFolder(folder),
        onMultiSelect: (path) {
          if (!isSelectionMode) onToggleSelectionMode?.call();
          onToggleFolderSelection?.call(path);
        },
      );
    }

    final width = crossAxisExtent ?? MediaQuery.sizeOf(context).width;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final effectiveZoom = _effectiveZoomScale;

    return FolderZoomSectionHost(
      zoomScale: effectiveZoom,
      width: width,
      builder: (context, metrics) {
        final hPad = folderContentHorizontalPadding(
          isPortrait: isPortrait,
          gridMorph: metrics.gridMorph,
        );

        Widget buildGrid(Map<String, MusicFile> coverSongs) {
          return SliverPadding(
            padding: EdgeInsets.only(
              top: 8,
              bottom: 8,
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
                  final folder = folders[index];
                  final isSelected = selectedFolderPaths.contains(folder.path);
                  final isIndexed =
                      scanRootsNotifier.isFolderIndexed(server.id, folder.path);
                  final virtualUri =
                      RemoteMediaResolver.buildRemoteUri(server, folder.path);

                  return FolderZoomItem(
                    key: ValueKey('webdav_folder_${folder.path}'),
                    folder: MusicFolder(path: virtualUri, name: folder.name),
                    metrics: metrics,
                    section: section,
                    // 代表封面补齐前保持「Folder」，补齐后换成封面。
                    representativeSong: coverSongs[virtualUri],
                    subtitle: 'Folder',
                    enableHero: false,
                    isSelected: isSelected,
                    isSelectionMode: isSelectionMode,
                    isIndexed: isIndexed,
                    trailing: Builder(
                      builder: (btnContext) {
                        return IconButton(
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          tooltip: 'More',
                          onPressed: () {
                            final box =
                                btnContext.findRenderObject() as RenderBox?;
                            final pos = box != null
                                ? box.localToGlobal(
                                    Offset(
                                      box.size.width / 2,
                                      box.size.height / 2,
                                    ),
                                  )
                                : Offset.zero;
                            openContextMenu(folder, pos);
                          },
                        );
                      },
                    ),
                    onTap: onFolderTap != null
                        ? () => onFolderTap?.call(folder, index)
                        : (isSelectionMode
                            ? () => onToggleFolderSelection?.call(folder.path)
                            : () => onOpenFolder(folder)),
                    onSecondaryTapDown: (details) {
                      openContextMenu(folder, details.globalPosition);
                    },
                    onLongPress: onFolderLongPress != null
                        ? () => onFolderLongPress?.call(folder, index)
                        : () {
                            if (!isSelectionMode) {
                              onToggleSelectionMode?.call();
                              onToggleFolderSelection?.call(folder.path);
                            } else {
                              onToggleFolderSelection?.call(folder.path);
                            }
                          },
                  );
                },
                childCount: folders.length,
              ),
            ),
          );
        }

        // 包装层常量存在（覆盖永远为空也有），避免根 Widget 类型切换导致
        // 整段网格 deactivate 重建。
        return ValueListenableBuilder<Map<String, MusicFile>>(
          valueListenable: folderCoverSongs ?? _kNoFolderCovers,
          builder: (context, coverSongs, _) => buildGrid(coverSongs),
        );
      },
    );
  }
}

/// Renders songs & files in unified zoom-driven grid or list mode for WebDAV.
class WebDavSongsSliver extends ConsumerWidget {
  final List<WebDavFile> files;
  final double zoomScale;
  final RemoteServer server;
  final String password;
  final Map<String, SongMetadata> metadataMap;
  final String? currentMusicPath;
  final String? highlightedSongPath;
  final bool isAudioPlaying;
  final List<MusicFile> allAudioFiles;
  final bool isSelectionMode;
  final Set<String> selectedSongPaths;
  final void Function(WebDavFile, int) onSongTap;
  final void Function(WebDavFile)? onSongLongPress;
  final void Function(WebDavFile, TapDownDetails)? onSongSecondaryTapDown;
  final double bottomPadding;
  final double? crossAxisExtent;

  /// 本段身份，必须与 `SliverAnimatedZoomGridDelegate.section` 一致。
  final Object? section;

  const WebDavSongsSliver({
    super.key,
    required this.files,
    required this.zoomScale,
    required this.server,
    required this.password,
    required this.metadataMap,
    required this.currentMusicPath,
    this.highlightedSongPath,
    required this.isAudioPlaying,
    required this.allAudioFiles,
    this.isSelectionMode = false,
    this.selectedSongPaths = const {},
    required this.onSongTap,
    this.onSongLongPress,
    this.onSongSecondaryTapDown,
    required this.bottomPadding,
    this.crossAxisExtent,
    this.section,
  });

  double get _effectiveZoomScale => snapFolderZoomScale(zoomScale);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = crossAxisExtent ?? MediaQuery.sizeOf(context).width;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final effectiveZoom = _effectiveZoomScale;

    return FolderZoomSectionHost(
      zoomScale: effectiveZoom,
      width: width,
      builder: (context, metrics) {
        final hPad = folderContentHorizontalPadding(
          isPortrait: isPortrait,
          gridMorph: metrics.gridMorph,
        );

        return SliverPadding(
          padding: EdgeInsets.only(
            top: 8,
            bottom: 8,
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
                final file = files[index];
                final uri =
                    RemoteMediaResolver.buildRemoteUri(server, file.path);
                final isSelected = selectedSongPaths.contains(uri);

                // 目录加载时已把非音频文件（封面图、.cue/.nfo/.txt、系统文件）
                // 全部剔掉，走到这里的必然是音频。
                final meta = metadataMap[uri] ??
                    ref.watch(
                      scannerServiceProvider.select(
                        (s) => s.metadataMap[uri],
                      ),
                    );
                final musicFile = RemoteMediaResolver.buildMusicFile(
                  file,
                  server,
                  metadata: meta,
                );
                final isCurrent = currentMusicPath == uri;
                final isHighlighted = highlightedSongPath == uri;

                return SongZoomItem(
                  key: ValueKey('webdav_song_$uri'),
                  song: musicFile,
                  metrics: metrics,
                  section: section,
                  isCurrent: isCurrent,
                  isPlaying: isAudioPlaying,
                  isSelected: isSelected,
                  isSelectionMode: isSelectionMode,
                  selectedPaths: selectedSongPaths,
                  isHighlighted: isHighlighted,
                  onTap: () => onSongTap(file, index),
                  onLongPress: () => onSongLongPress?.call(file),
                  onSecondaryTapDown: (details) =>
                      onSongSecondaryTapDown?.call(file, details),
                );
              },
              childCount: files.length,
            ),
          ),
        );
      },
    );
  }
}
