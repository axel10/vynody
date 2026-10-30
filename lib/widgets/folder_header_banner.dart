import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/metadata/artwork_resolver.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_service_providers.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/utils/blur_constants.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'folder_scan_widgets.dart';
import 'song_thumbnail.dart';

class FolderHeaderBanner extends ConsumerStatefulWidget {
  const FolderHeaderBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.songsCount,
    required this.totalDuration,
    required this.coverWidget,
    this.coverImagePath,
    this.representativeSong,
    this.songPath,
    this.songId,
    this.artworkPath,
    this.topHeader,
    required this.actionButtons,
    this.actionButtonsScrollable = false,
    required this.isSearching,
    required this.searchController,
    required this.searchQuery,
    required this.searchHintText,
    required this.onSearchQueryChanged,
    required this.onToggleSearch,
    this.heroTag,
    this.isHeroModeEnabled = true,
    this.isLowEndDevice,
  });

  final String title;
  final String subtitle;
  final int songsCount;
  final Duration totalDuration;
  final Widget coverWidget;
  final String? coverImagePath;
  final MusicFile? representativeSong;
  final String? songPath;
  final int? songId;
  final String? artworkPath;
  final Widget? topHeader;
  final List<Widget> actionButtons;
  final bool actionButtonsScrollable;
  final bool isSearching;
  final TextEditingController searchController;
  final String searchQuery;
  final String searchHintText;
  final ValueChanged<String> onSearchQueryChanged;
  final ValueChanged<bool> onToggleSearch;
  final String? heroTag;
  final bool isHeroModeEnabled;
  final bool? isLowEndDevice;

  @override
  ConsumerState<FolderHeaderBanner> createState() => _FolderHeaderBannerState();
}

class _FolderHeaderBannerState extends ConsumerState<FolderHeaderBanner> {
  double? _aspectRatio;
  String? _resolvedPath;
  RawArtwork? _rawArtwork;
  int _resolveGeneration = 0;

  @override
  void initState() {
    super.initState();
    _resolveInitialState();
  }

  @override
  void didUpdateWidget(FolderHeaderBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverImagePath != widget.coverImagePath ||
        oldWidget.representativeSong != widget.representativeSong ||
        oldWidget.songPath != widget.songPath ||
        oldWidget.artworkPath != widget.artworkPath ||
        oldWidget.songId != widget.songId) {
      _resolveInitialState();
    }
  }

  void _resolveInitialState() {
    final song = widget.representativeSong;
    final path = widget.coverImagePath ?? song?.thumbnailPath ?? song?.artworkPath;
    if (path != null && path.isNotEmpty) {
      // 库里存的是绝对路径，iOS 沙箱目录会随安装变化，必须先落到当前容器内，
      // 否则 File() 直接指向一个不存在的位置 —— 表现为封面始终空白。
      _resolvedPath = ScannerPathUtils.resolveIosSandboxPath(path);
    } else {
      _resolvedPath = null;
    }
    _checkImageAspectRatio();
    _loadHighResArtwork();
  }

  void _updateAspectRatioFromBytes(Uint8List bytes) {
    final memoryImage = MemoryImage(bytes);
    final stream = memoryImage.resolve(ImageConfiguration.empty);
    stream.addListener(ImageStreamListener((ImageInfo info, bool _) {
      if (mounted) {
        final w = info.image.width;
        final h = info.image.height;
        if (w > 0 && h > 0) {
          final ratio = w / h;
          if (_aspectRatio != ratio) {
            setState(() {
              _aspectRatio = ratio;
            });
          }
        }
      }
    }));
  }

  void _updateAspectRatioFromFile(String filePath) {
    if (filePath.isEmpty) return;
    final file = File(filePath);
    final fileImage = FileImage(file);
    final stream = fileImage.resolve(ImageConfiguration.empty);
    stream.addListener(ImageStreamListener((ImageInfo info, bool _) {
      if (mounted) {
        final w = info.image.width;
        final h = info.image.height;
        if (w > 0 && h > 0) {
          final ratio = w / h;
          if (_aspectRatio != ratio) {
            setState(() {
              _aspectRatio = ratio;
            });
          }
        }
      }
    }, onError: (_, _) {}));
  }

  void _checkImageAspectRatio() {
    final path = _resolvedPath;
    if (path != null && path.isNotEmpty) {
      _updateAspectRatioFromFile(path);
    } else if (_rawArtwork?.bytes != null && _rawArtwork!.bytes!.isNotEmpty) {
      _updateAspectRatioFromBytes(_rawArtwork!.bytes!);
    } else if (_rawArtwork?.filePath != null && _rawArtwork!.filePath!.isNotEmpty) {
      _updateAspectRatioFromFile(_rawArtwork!.filePath!);
    } else {
      setState(() {
        _aspectRatio = null;
      });
    }
  }

  Future<void> _loadHighResArtwork() async {
    final song = widget.representativeSong;
    final path = song?.path ?? widget.songPath;
    if (path == null || path.isEmpty) {
      return;
    }

    if (song?.artworkBytes != null && song!.artworkBytes!.isNotEmpty) {
      final raw = RawArtwork(bytes: song.artworkBytes);
      if (mounted) {
        setState(() {
          _rawArtwork = raw;
        });
        _updateAspectRatioFromBytes(song.artworkBytes!);
      }
      return;
    }

    final currentGen = ++_resolveGeneration;
    final targetId = song?.id ?? widget.songId;
    final targetArtworkPath = song?.artworkPath ?? widget.artworkPath;
    final targetThumbnailPath = song?.thumbnailPath ?? widget.coverImagePath;

    AudioCoreController? audioController;
    try {
      audioController = ref.read(audioServiceProvider).player;
    } catch (_) {}

    RemoteMediaResolver? remoteResolver;
    if (RemoteMediaResolver.isRemoteUri(path)) {
      try {
        remoteResolver = await ref.read(remoteMediaResolverProvider.future);
      } catch (_) {}
    }

    final raw = await ArtworkResolver.resolveForCarousel(
      path: path,
      id: targetId,
      artworkPath: targetArtworkPath,
      thumbnailPath: targetThumbnailPath,
      audioController: audioController,
      remoteResolver: remoteResolver,
    );

    if (!mounted || currentGen != _resolveGeneration) return;
    if (raw == null || !raw.isNotEmpty) return;

    setState(() {
      _rawArtwork = raw;
    });
    if (raw.bytes != null && raw.bytes!.isNotEmpty) {
      _updateAspectRatioFromBytes(raw.bytes!);
    } else if (raw.filePath != null && raw.filePath!.isNotEmpty) {
      _updateAspectRatioFromFile(raw.filePath!);
    }
  }

  String _formatDurationText(AppLocalizations l10n) {
    final hours = widget.totalDuration.inHours;
    final minutes = widget.totalDuration.inMinutes.remainder(60);
    final seconds = widget.totalDuration.inSeconds.remainder(60);

    if (l10n.localeName == 'zh') {
      if (hours > 0) {
        return '$hours小时$minutes分钟';
      } else if (minutes > 0) {
        return '$minutes分钟$seconds秒';
      } else {
        return '$seconds秒';
      }
    } else {
      if (hours > 0) {
        return '${hours}h ${minutes}m';
      } else if (minutes > 0) {
        return '${minutes}m ${seconds}s';
      } else {
        return '${seconds}s';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final durationText = _formatDurationText(l10n);

    final hasRawImage = _rawArtwork != null && _rawArtwork!.isNotEmpty;
    final hasLocalFile = _resolvedPath != null && _resolvedPath!.isNotEmpty;
    final hasImage = hasRawImage || hasLocalFile;
    final coverFile = hasLocalFile ? File(_resolvedPath!) : null;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isWideOrSquare = hasImage && (_aspectRatio == null || _aspectRatio! >= 0.85);
    final bool isLowEndDevice = widget.isLowEndDevice ?? ref.watch(isLowMidEndDeviceProvider);

    // 首帧占位图的解码尺寸。
    //
    // 转场第一帧时高清原图必然还没解析出来（要读标签 / 起 isolate），而裸
    // `Image.memory/Image.file` 在解码完成前画的是空白，所以整块 banner 会空
    // 一整个转场。这里按网格条目（[SongThumbnail]，size = [kZoomItemThumbnailSize]）
    // 完全相同的分桶算尺寸，让首帧能直接命中 ImageCache 里已经解码好的那一张，
    // 同步出图；高清到手后再由 gaplessPlayback 无缝替换。
    //
    // 尺寸信息必须与 [SongThumbnail] 同源（都读 metadataMap）：方形封面两边若
    // 一个走 cacheHeight、一个走 cacheWidth，算出来就是两个 key，缓存不命中。
    final (artWidth, artHeight) = ref.watch(
      scannerServiceProvider.select((s) {
        final meta =
            s.metadataMap[widget.representativeSong?.path ?? widget.songPath ?? ''];
        return (meta?.artworkWidth, meta?.artworkHeight);
      }),
    );
    final int seedPixels =
        (thumbnailBucketSizeFor(kZoomItemThumbnailSize) *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    final bool seedUsesCacheHeight =
        artWidth != null && artHeight != null && artWidth >= artHeight;

    return _OverscrollStretchBuilder(
      builder: (context, overscroll) {
        if (isLandscape) {
          return RepaintBoundary(
            child: _FolderLandscapeHeaderBanner(
              title: widget.title,
              subtitle: widget.subtitle,
              songsCount: widget.songsCount,
              durationText: durationText,
              coverWidget: widget.coverWidget,
              actionButtons: widget.actionButtons,
              actionButtonsScrollable: widget.actionButtonsScrollable,
              isSearching: widget.isSearching,
              searchController: widget.searchController,
              searchQuery: widget.searchQuery,
              searchHintText: widget.searchHintText,
              onSearchQueryChanged: widget.onSearchQueryChanged,
              onToggleSearch: widget.onToggleSearch,
              heroTag: widget.heroTag,
              isHeroModeEnabled: widget.isHeroModeEnabled,
              overscroll: overscroll,
            ),
          );
        }

        return RepaintBoundary(
          child: _FolderPortraitHeaderBanner(
            title: widget.title,
            subtitle: widget.subtitle,
            songsCount: widget.songsCount,
            durationText: durationText,
            coverWidget: widget.coverWidget,
            coverFile: coverFile,
            rawArtwork: _rawArtwork,
            hasImage: hasImage,
            isWideOrSquare: isWideOrSquare,
            seedCacheWidth: seedUsesCacheHeight ? null : seedPixels,
            seedCacheHeight: seedUsesCacheHeight ? seedPixels : null,
            topHeader: widget.topHeader,
            actionButtons: widget.actionButtons,
            actionButtonsScrollable: widget.actionButtonsScrollable,
            isSearching: widget.isSearching,
            searchController: widget.searchController,
            searchQuery: widget.searchQuery,
            searchHintText: widget.searchHintText,
            onSearchQueryChanged: widget.onSearchQueryChanged,
            onToggleSearch: widget.onToggleSearch,
            heroTag: widget.heroTag,
            isHeroModeEnabled: widget.isHeroModeEnabled,
            resolvedPath: _resolvedPath,
            totalDuration: widget.totalDuration,
            isLowEndDevice: isLowEndDevice,
            overscroll: overscroll,
          ),
        );
      },
    );
  }
}

/// Helper widget to observe overscroll from the ambient [Scrollable].
class _OverscrollStretchBuilder extends StatefulWidget {
  const _OverscrollStretchBuilder({required this.builder});

  final Widget Function(BuildContext context, double overscroll) builder;

  @override
  State<_OverscrollStretchBuilder> createState() => _OverscrollStretchBuilderState();
}

class _OverscrollStretchBuilderState extends State<_OverscrollStretchBuilder> {
  ScrollPosition? _position;
  double _lastOverscroll = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newPosition = Scrollable.maybeOf(context)?.position;
    if (_position != newPosition) {
      _position?.removeListener(_onScroll);
      _position = newPosition;
      _position?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    _position = null;
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    final pos = _position;
    final currentOverscroll = (pos != null && pos.hasPixels && pos.pixels < 0)
        ? -pos.pixels
        : 0.0;
    if (currentOverscroll != _lastOverscroll) {
      _lastOverscroll = currentOverscroll;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    double overscroll = 0.0;
    if (_position != null && _position!.hasPixels && _position!.pixels < 0) {
      overscroll = -_position!.pixels;
    }
    return widget.builder(context, overscroll);
  }
}

/// Decoupled Landscape Header Banner Component
class _FolderLandscapeHeaderBanner extends StatelessWidget {
  const _FolderLandscapeHeaderBanner({
    required this.title,
    required this.subtitle,
    required this.songsCount,
    required this.durationText,
    required this.coverWidget,
    required this.actionButtons,
    required this.actionButtonsScrollable,
    required this.isSearching,
    required this.searchController,
    required this.searchQuery,
    required this.searchHintText,
    required this.onSearchQueryChanged,
    required this.onToggleSearch,
    required this.heroTag,
    required this.isHeroModeEnabled,
    this.overscroll = 0.0,
  });

  final String title;
  final String subtitle;
  final int songsCount;
  final String durationText;
  final Widget coverWidget;
  final List<Widget> actionButtons;
  final bool actionButtonsScrollable;
  final bool isSearching;
  final TextEditingController searchController;
  final String searchQuery;
  final String searchHintText;
  final ValueChanged<String> onSearchQueryChanged;
  final ValueChanged<bool> onToggleSearch;
  final String? heroTag;
  final bool isHeroModeEnabled;
  final double overscroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final resolvedCover = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: coverWidget,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 680;

        final Widget bannerContent = isWideScreen
            ? Row(
                children: [
                  resolvedCover,
                  const SizedBox(width: 16),
                  Expanded(
                    child: _BannerInfoColumn(
                      title: title,
                      subtitle: subtitle,
                      songsCount: songsCount,
                      durationText: durationText,
                      isOverlay: false,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _FolderBannerActionScope(
                    isLandscape: true,
                    hasImage: false,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: isSearching
                          ? Row(
                              key: const ValueKey('wide-search-active'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 260,
                                  child: _BannerSearchTextField(
                                    controller: searchController,
                                    hintText: searchHintText,
                                    query: searchQuery,
                                    onChanged: onSearchQueryChanged,
                                    compact: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 20),
                                  onPressed: () {
                                    searchController.clear();
                                    onSearchQueryChanged('');
                                    onToggleSearch(false);
                                  },
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(32, 32),
                                    padding: EdgeInsets.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              key: const ValueKey('wide-actions-normal'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (actionButtonsScrollable)
                                  Flexible(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: actionButtons,
                                      ),
                                    ),
                                  )
                                else
                                  ...actionButtons,
                                const SizedBox(width: 8),
                                _BannerSearchIconButton(
                                  onPressed: () => onToggleSearch(true),
                                  tooltip: l10n.search,
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      resolvedCover,
                      const SizedBox(width: 16),
                      Expanded(
                        child: _BannerInfoColumn(
                          title: title,
                          subtitle: subtitle,
                          songsCount: songsCount,
                          durationText: durationText,
                          isOverlay: false,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _FolderBannerActionScope(
                    isLandscape: true,
                    hasImage: false,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: isSearching
                          ? Row(
                              key: const ValueKey('search-active-row'),
                              children: [
                                Expanded(
                                  child: _BannerSearchTextField(
                                    controller: searchController,
                                    hintText: searchHintText,
                                    query: searchQuery,
                                    onChanged: onSearchQueryChanged,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    searchController.clear();
                                    onSearchQueryChanged('');
                                    onToggleSearch(false);
                                  },
                                ),
                              ],
                            )
                          : Row(
                              key: const ValueKey('actions-normal-row'),
                              children: [
                                if (actionButtonsScrollable)
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: actionButtons,
                                      ),
                                    ),
                                  )
                                else ...[
                                  ...actionButtons,
                                  const Spacer(),
                                ],
                                const SizedBox(width: 8),
                                _BannerSearchIconButton(
                                  onPressed: () => onToggleSearch(true),
                                  tooltip: l10n.search,
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              );

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.5),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: bannerContent,
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: FolderBannerScanProgressBar(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Default cover image opacity values for light theme banner display
const double _kLightModeCoverOpacity = 0.35;
const double _kLightModeBlurredCoverOpacity = 0.35;

/// 目录页 banner 背景模糊层的 sigma。
///
/// 背景层只负责一层颜色氛围。原先取 `AppBlur.heavy`(16)，等于每帧对
/// 「全宽 × 约 200dp」的区域跑一次 sigma=16 的高斯；转场期间页面在缩放，
/// raster cache 每帧失效，单帧光栅成本 40~90ms。降到 6（低端机 3）视觉上
/// 几乎看不出差别，成本掉一个数量级。
const double _kBannerBackdropBlurSigma = 6.0;
const double _kBannerBackdropBlurSigmaLowEnd = 3.0;

/// 背景模糊层的解码宽度 = 屏幕物理宽度 × 该比例。
///
/// 该层最终会被糊成色块，不需要任何细节；按 1/8 宽度解码可把纹理像素量降到
/// 原来的 1/64，免掉「首次进入为原尺寸大图付一次解码 + 纹理上传」。
const double _kBannerBackdropDecodeScale = 0.125;
const int _kBannerBackdropDecodeMinWidth = 64;
const int _kBannerBackdropDecodeMaxWidth = 512;

/// 背景模糊层该按多宽解码（单位为物理像素，即 `Image.cacheWidth` 的语义）。
int _bannerBackdropDecodeWidth({
  required double logicalWidth,
  required double devicePixelRatio,
}) {
  return (logicalWidth * devicePixelRatio * _kBannerBackdropDecodeScale)
      .round()
      .clamp(
        _kBannerBackdropDecodeMinWidth,
        _kBannerBackdropDecodeMaxWidth,
      );
}

/// Decoupled Portrait Header Banner Component
class _FolderPortraitHeaderBanner extends StatelessWidget {
  const _FolderPortraitHeaderBanner({
    required this.title,
    required this.subtitle,
    required this.songsCount,
    required this.durationText,
    required this.coverWidget,
    required this.coverFile,
    this.rawArtwork,
    required this.hasImage,
    required this.isWideOrSquare,
    required this.seedCacheWidth,
    required this.seedCacheHeight,
    required this.topHeader,
    required this.actionButtons,
    required this.actionButtonsScrollable,
    required this.isSearching,
    required this.searchController,
    required this.searchQuery,
    required this.searchHintText,
    required this.onSearchQueryChanged,
    required this.onToggleSearch,
    required this.heroTag,
    required this.isHeroModeEnabled,
    required this.resolvedPath,
    required this.totalDuration,
    required this.isLowEndDevice,
    this.overscroll = 0.0,
  });

  final String title;
  final String subtitle;
  final int songsCount;
  final String durationText;
  final Widget coverWidget;
  final File? coverFile;
  final RawArtwork? rawArtwork;
  final bool hasImage;
  final bool isWideOrSquare;

  /// 首帧占位图的解码尺寸，与网格条目（[SongThumbnail]）同桶 —— 见调用处注释。
  final int? seedCacheWidth;
  final int? seedCacheHeight;
  final Widget? topHeader;
  final List<Widget> actionButtons;
  final bool actionButtonsScrollable;
  final bool isSearching;
  final TextEditingController searchController;
  final String searchQuery;
  final String searchHintText;
  final ValueChanged<String> onSearchQueryChanged;
  final ValueChanged<bool> onToggleSearch;
  final String? heroTag;
  final bool isHeroModeEnabled;
  final String? resolvedPath;
  final Duration totalDuration;
  final bool isLowEndDevice;
  final double overscroll;

  /// 高清封面源（标签内嵌原图 / 已落盘原图 / 远程 URL）。
  ImageProvider<Object>? _highResProvider({int? cacheWidth, int? cacheHeight}) {
    final raw = rawArtwork;
    if (raw != null && raw.isNotEmpty) {
      if (raw.bytes != null && raw.bytes!.isNotEmpty) {
        return ResizeImage.resizeIfNeeded(
          cacheWidth,
          cacheHeight,
          MemoryImage(raw.bytes!),
        );
      }
      if (raw.filePath != null && raw.filePath!.isNotEmpty) {
        return ResizeImage.resizeIfNeeded(
          cacheWidth,
          cacheHeight,
          FileImage(File(raw.filePath!)),
        );
      }
      if (raw.remoteUrl != null && raw.remoteUrl!.isNotEmpty) {
        return ResizeImage.resizeIfNeeded(
          cacheWidth,
          cacheHeight,
          NetworkImage(raw.remoteUrl!),
        );
      }
    }
    final file = coverFile;
    if (file != null) {
      return ResizeImage.resizeIfNeeded(
        cacheWidth,
        cacheHeight,
        FileImage(file),
      );
    }
    return null;
  }

  /// 首帧占位图源。
  ///
  /// key 必须与网格条目里那张 [SongThumbnail] 完全一致（同文件、同分桶尺寸），
  /// 才能命中全局 [ImageCache] 中已经解码好的纹理 —— 命中时图片是**同步**可用的，
  /// 于是转场第一帧就能出图，而不是空等到解码完成。
  ImageProvider<Object>? _seedProvider() {
    final path = resolvedPath;
    if (path == null || path.isEmpty) return null;
    // 远程路径没有本地文件可读，走不到缓存命中，交给高清层自己加载。
    if (RemoteMediaResolver.isRemoteUri(path)) return null;
    return ResizeImage.resizeIfNeeded(
      seedCacheWidth,
      seedCacheHeight,
      FileImage(File(path)),
    );
  }

  Widget _buildBannerImage({
    required BoxFit fit,
    Alignment alignment = Alignment.center,
    double? width,
    double? height,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    final provider = _highResProvider(
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
    if (provider == null) return const SizedBox.shrink();

    Widget buildSeed() {
      final seed = _seedProvider();
      if (seed == null) return const SizedBox.shrink();
      return Image(
        image: seed,
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }

    return Image(
      image: provider,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      // 高清还没解码完：先铺上网格条目那份（多半已在 ImageCache 里，同步可出）。
      // 解码完成后 frame != null，直接换成高清，中间不出现空白帧。
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return buildSeed();
      },
      // 高清源失效（文件被移走 / 远程 404）时至少保住低清那张。
      errorBuilder: (_, _, _) => buildSeed(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final desktopTitleBarHeight = isDesktop ? 28.0 : 0.0;
    final hasTopHeader = topHeader != null;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 680;

        return Container(
          margin: const EdgeInsets.only(left: 0, right: 0, top: 0, bottom: 12),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
          // 1. Background cover / backdrop layer with elastic overscroll stretch
          Positioned(
            top: -overscroll,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black.withValues(alpha: 0.12) : theme.colorScheme.shadow.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: isDark
                          ? Colors.black
                          : theme.colorScheme.surface,
                    ),
                    if (hasImage && !isWideOrSquare) ...[
                      Opacity(
                        opacity: isDark ? 1.0 : _kLightModeBlurredCoverOpacity,
                        child: ImageFiltered(
                          imageFilter: AppBlur.filter(
                            isLowEndDevice
                                ? _kBannerBackdropBlurSigmaLowEnd
                                : _kBannerBackdropBlurSigma,
                          ),
                          child: _buildBannerImage(
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            cacheWidth: _bannerBackdropDecodeWidth(
                              logicalWidth: constraints.maxWidth,
                              devicePixelRatio: devicePixelRatio,
                            ),
                          ),
                        ),
                      ),
                      if (isDark)
                        Container(
                          color: Colors.black.withValues(alpha: isWideOrSquare ? 0.25 : 0.45),
                        ),
                    ],
                    // Wide or Square cover extending across full width
                    if (isWideOrSquare && hasImage) ...[
                      Positioned.fill(
                        child: Opacity(
                          opacity: isDark ? 1.0 : _kLightModeCoverOpacity,
                          child: _buildBannerImage(
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            width: double.infinity,
                            height: double.infinity,
                            // 这条分支是把封面 1:1 铺满整宽，解码到「屏幕物理宽」
                            // 就是它的 1:1 显示尺寸；再大的源图只是把解码 + 纹理
                            // 上传的成本翻倍（封面常见 1000~3000px）。
                            cacheWidth: (constraints.maxWidth * devicePixelRatio)
                                .round(),
                          ),
                        ),
                      ),
                    ],
                    // Gradient overlay for text readability (Dark mode: dark gradient, Light mode: light surface gradient)
                    if (hasImage)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isDark
                                ? [
                                    Colors.black.withValues(alpha: 0.35),
                                    Colors.black.withValues(alpha: 0.55),
                                    Colors.black.withValues(alpha: 0.85),
                                  ]
                                : [
                                    theme.colorScheme.surface.withValues(alpha: 0.25),
                                    theme.colorScheme.surface.withValues(alpha: 0.60),
                                    theme.colorScheme.surface.withValues(alpha: 0.92),
                                  ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Foreground content layer
          Padding(
            padding: EdgeInsets.only(
              top: hasTopHeader
                  ? 0
                  : getTitleBarTopPadding(
                      context,
                      defaultWindowPadding: isDesktop
                          ? desktopTitleBarHeight + 16
                          : kDefaultWindowCaptionHeight + 8,
                      statusBarOffset: desktopTitleBarHeight + 8,
                    ),
              left: 16,
              right: 16,
                  bottom: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasTopHeader) topHeader!,
                    if (hasTopHeader) const SizedBox(height: 4),

                    if (isWideScreen) ...[
                      // Wide screen / desktop horizontal layout over cover backdrop
                      Row(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            margin: const EdgeInsets.only(right: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: coverWidget,
                            ),
                          ),
                          Expanded(
                            child: _BannerInfoColumn(
                              title: title,
                              subtitle: subtitle,
                              songsCount: songsCount,
                              durationText: durationText,
                              isOverlay: hasImage,
                            ),
                          ),
                          const SizedBox(width: 16),
                          _FolderBannerActionScope(
                            isLandscape: false,
                            hasImage: hasImage,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: isSearching
                                  ? Row(
                                      key: const ValueKey('wide-search-active'),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 260,
                                          child: _BannerSearchTextField(
                                            controller: searchController,
                                            hintText: searchHintText,
                                            query: searchQuery,
                                            onChanged: onSearchQueryChanged,
                                            compact: true,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: Icon(
                                            Icons.close_rounded,
                                            size: 20,
                                            color: (hasImage && isDark) ? Colors.white : theme.colorScheme.onSurface,
                                          ),
                                          onPressed: () {
                                            searchController.clear();
                                            onSearchQueryChanged('');
                                            onToggleSearch(false);
                                          },
                                        ),
                                      ],
                                    )
                                  : Row(
                                      key: const ValueKey('wide-actions-normal'),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (actionButtonsScrollable)
                                          Flexible(
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: actionButtons,
                                              ),
                                            ),
                                          )
                                        else
                                          ...actionButtons,
                                        const SizedBox(width: 8),
                                        _BannerSearchIconButton(
                                          onPressed: () => onToggleSearch(true),
                                          tooltip: l10n.search,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // Standard portrait column layout
                      if (!isWideOrSquare) ...[
                        Center(
                          child: Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: hasImage
                                  ? _buildBannerImage(
                                      fit: BoxFit.contain,
                                      cacheWidth: seedCacheWidth,
                                      cacheHeight: seedCacheHeight,
                                    )
                                  : coverWidget,
                            ),
                          ),
                        ),
                      ],

                      // Title & Subtitle & Metadata
                      _BannerInfoColumn(
                        title: title,
                        subtitle: subtitle,
                        songsCount: songsCount,
                        durationText: durationText,
                        isOverlay: hasImage,
                      ),

                      const SizedBox(height: 14),

                      // Actions / Search Row
                      _FolderBannerActionScope(
                        isLandscape: false,
                        hasImage: hasImage,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: isSearching
                              ? Row(
                                  key: const ValueKey('search-active-row'),
                                  children: [
                                    Expanded(
                                      child: _BannerSearchTextField(
                                        controller: searchController,
                                        hintText: searchHintText,
                                        query: searchQuery,
                                        onChanged: onSearchQueryChanged,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: (hasImage && isDark) ? Colors.white : theme.colorScheme.onSurface,
                                        shadows: (hasImage && isDark)
                                            ? const [
                                                Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black87),
                                              ]
                                            : null,
                                      ),
                                      onPressed: () {
                                        searchController.clear();
                                        onSearchQueryChanged('');
                                        onToggleSearch(false);
                                      },
                                    ),
                                  ],
                                )
                              : Row(
                                  key: const ValueKey('actions-normal-row'),
                                  children: [
                                    if (actionButtonsScrollable)
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: actionButtons,
                                          ),
                                        ),
                                      )
                                    else ...[
                                      ...actionButtons,
                                      const Spacer(),
                                    ],
                                    const SizedBox(width: 8),
                                    _BannerSearchIconButton(
                                      onPressed: () => onToggleSearch(true),
                                      tooltip: l10n.search,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            // 3. Hairline scanning progress bar at bottom of the banner
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                child: FolderBannerScanProgressBar(),
              ),
            ),
          ],
        ),
      );
      },
    );
  }
}

/// Information Text Column Sub-widget
class _BannerInfoColumn extends StatelessWidget {
  const _BannerInfoColumn({
    required this.title,
    required this.subtitle,
    required this.songsCount,
    required this.durationText,
    required this.isOverlay,
  });

  final String title;
  final String subtitle;
  final int songsCount;
  final String durationText;
  final bool isOverlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;
    final useWhiteText = isOverlay && isDark;

    final titleColor = useWhiteText ? Colors.white : theme.colorScheme.onSurface;
    final subtitleColor = useWhiteText
        ? Colors.white.withValues(alpha: 0.8)
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8);
    final countDurationColor = useWhiteText
        ? Colors.white.withValues(alpha: 0.85)
        : theme.colorScheme.onSurfaceVariant;

    final List<Shadow>? textShadows = useWhiteText
        ? const [
            Shadow(
              offset: Offset(0, 1),
              blurRadius: 4,
              color: Colors.black87,
            ),
          ]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: titleColor,
            shadows: textShadows,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: subtitleColor,
              shadows: textShadows,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 6),
        Text(
          '${l10n.songCount(songsCount)} | $durationText',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: countDurationColor,
            fontWeight: FontWeight.w600,
            fontSize: useWhiteText ? 13 : 14,
            shadows: textShadows,
          ),
        ),
      ],
    );
  }
}

/// Search Text Field Sub-widget
class _BannerSearchTextField extends StatelessWidget {
  const _BannerSearchTextField({
    required this.controller,
    required this.hintText,
    required this.query,
    required this.onChanged,
    this.compact = false,
  });

  final TextEditingController controller;
  final String hintText;
  final String query;
  final ValueChanged<String> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      autofocus: true,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 20),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 6 : 8,
        ),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }
}

/// Context scope for banner actions to coordinate landscape/portrait styling
class _FolderBannerActionScope extends InheritedWidget {
  const _FolderBannerActionScope({
    required this.isLandscape,
    required this.hasImage,
    required super.child,
  });

  final bool isLandscape;
  final bool hasImage;

  static _FolderBannerActionScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_FolderBannerActionScope>();
  }

  @override
  bool updateShouldNotify(_FolderBannerActionScope oldWidget) {
    return isLandscape != oldWidget.isLandscape || hasImage != oldWidget.hasImage;
  }
}

/// Search Icon Button Sub-widget
class _BannerSearchIconButton extends StatelessWidget {
  const _BannerSearchIconButton({
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scope = _FolderBannerActionScope.of(context);
    final isLandscape = scope?.isLandscape ?? (MediaQuery.of(context).orientation == Orientation.landscape);
    final hasImage = scope?.hasImage ?? false;
    final isLargeScreen = MediaQuery.of(context).size.width >= 1000;
    final buttonHeight = isLargeScreen ? 38.0 : 32.0;
    final iconSize = isLargeScreen ? 18.0 : 16.0;

    final Color bgColor;
    final Color fgColor;
    final BorderSide? borderSide;

    if (isLandscape) {
      // Landscape: secondaryContainer matching shuffle button
      bgColor = theme.colorScheme.secondaryContainer;
      fgColor = theme.colorScheme.onSecondaryContainer;
      borderSide = null;
    } else {
      if (hasImage && isDark) {
        bgColor = Colors.white.withValues(alpha: 0.14);
        fgColor = Colors.white.withValues(alpha: 0.9);
        borderSide = BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 0.8);
      } else if (hasImage && !isDark) {
        bgColor = theme.colorScheme.onSurface.withValues(alpha: 0.07);
        fgColor = theme.colorScheme.onSurfaceVariant;
        borderSide = BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2), width: 0.8);
      } else {
        bgColor = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
        fgColor = theme.colorScheme.onSurfaceVariant;
        borderSide = BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2), width: 0.8);
      }
    }

    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        Icons.search_rounded,
        size: iconSize,
        color: fgColor,
      ),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        side: borderSide,
        shape: const StadiumBorder(),
        minimumSize: Size(buttonHeight, buttonHeight),
        maximumSize: Size(buttonHeight, buttonHeight),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class FolderPlayActionButtons extends StatelessWidget {
  const FolderPlayActionButtons({
    super.key,
    required this.onPlayAll,
    required this.onShufflePlay,
    required this.totalSongsCount,
    this.primaryPlayInLandscape = true,
    this.showLabels,
  });

  final FutureOr<void> Function()? onPlayAll;
  final FutureOr<void> Function()? onShufflePlay;
  final int totalSongsCount;
  final bool primaryPlayInLandscape;
  final bool? showLabels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    // Show full capsule buttons (icon + label) when space is sufficient (>= 340px covers standard phones).
    // Gracefully collapse to icon-only circles on extremely narrow screens (< 340px).
    final isWiderScreen = showLabels ?? (screenWidth >= 340);
    final isLargeScreen = screenWidth >= 1000;
    final isDisabled = totalSongsCount == 0 || (onPlayAll == null && onShufflePlay == null);

    final scope = _FolderBannerActionScope.of(context);
    final isLandscape = scope?.isLandscape ?? (MediaQuery.of(context).orientation == Orientation.landscape);
    final hasImage = scope?.hasImage ?? false;

    final buttonHeight = isLargeScreen ? 38.0 : 32.0;
    final iconSize = isLargeScreen ? 18.0 : 16.0;
    final fontSize = isLargeScreen ? 13.0 : 11.5;
    final textStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
    );

    final Color playBg;
    final Color playFg;
    final BorderSide? playBorder;
    final Color shuffleBg;
    final Color shuffleFg;
    final BorderSide? shuffleBorder;

    if (isLandscape) {
      shuffleBg = theme.colorScheme.secondaryContainer;
      shuffleFg = theme.colorScheme.onSecondaryContainer;
      shuffleBorder = null;
      playBg = shuffleBg;
      playFg = shuffleFg;
      playBorder = shuffleBorder;
    } else {
      if (hasImage && isDark) {
        shuffleBg = Colors.white.withValues(alpha: 0.14);
        shuffleFg = Colors.white.withValues(alpha: 0.9);
        shuffleBorder = BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 0.8);
      } else if (hasImage && !isDark) {
        shuffleBg = theme.colorScheme.onSurface.withValues(alpha: 0.07);
        shuffleFg = theme.colorScheme.onSurfaceVariant;
        shuffleBorder = BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2), width: 0.8);
      } else {
        shuffleBg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
        shuffleFg = theme.colorScheme.onSurfaceVariant;
        shuffleBorder = BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2), width: 0.8);
      }
      playBg = shuffleBg;
      playFg = shuffleFg;
      playBorder = shuffleBorder;
    }

    final disabledBg = (!isLandscape && hasImage && isDark)
        ? Colors.white.withValues(alpha: 0.08)
        : null;
    final disabledFg = (!isLandscape && hasImage && isDark)
        ? Colors.white.withValues(alpha: 0.3)
        : null;

    final playAllButton = isWiderScreen
        ? FilledButton.icon(
            onPressed: isDisabled ? null : () => onPlayAll?.call(),
            icon: Icon(Icons.play_arrow_rounded, size: iconSize),
            label: Text(l10n.playAll),
            style: FilledButton.styleFrom(
              backgroundColor: playBg,
              foregroundColor: playFg,
              disabledBackgroundColor: disabledBg,
              disabledForegroundColor: disabledFg,
              side: playBorder,
              minimumSize: Size(0, buttonHeight),
              padding: EdgeInsets.symmetric(horizontal: isLargeScreen ? 16 : 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: const StadiumBorder(),
              textStyle: textStyle,
            ),
          )
        : Tooltip(
            message: l10n.playAll,
            child: FilledButton(
              onPressed: isDisabled ? null : () => onPlayAll?.call(),
              style: FilledButton.styleFrom(
                backgroundColor: playBg,
                foregroundColor: playFg,
                disabledBackgroundColor: disabledBg,
                disabledForegroundColor: disabledFg,
                side: playBorder,
                minimumSize: Size(buttonHeight, buttonHeight),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: const StadiumBorder(),
              ),
              child: Icon(Icons.play_arrow_rounded, size: iconSize),
            ),
          );

    final shuffleButton = isWiderScreen
        ? FilledButton.icon(
            onPressed: isDisabled ? null : () => onShufflePlay?.call(),
            icon: Icon(Icons.shuffle_rounded, size: iconSize),
            label: Text(l10n.shuffle),
            style: FilledButton.styleFrom(
              backgroundColor: shuffleBg,
              foregroundColor: shuffleFg,
              disabledBackgroundColor: disabledBg,
              disabledForegroundColor: disabledFg,
              side: shuffleBorder,
              minimumSize: Size(0, buttonHeight),
              padding: EdgeInsets.symmetric(horizontal: isLargeScreen ? 16 : 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: const StadiumBorder(),
              textStyle: textStyle,
            ),
          )
        : Tooltip(
            message: l10n.shuffle,
            child: FilledButton(
              onPressed: isDisabled ? null : () => onShufflePlay?.call(),
              style: FilledButton.styleFrom(
                backgroundColor: shuffleBg,
                foregroundColor: shuffleFg,
                disabledBackgroundColor: disabledBg,
                disabledForegroundColor: disabledFg,
                side: shuffleBorder,
                minimumSize: Size(buttonHeight, buttonHeight),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: const StadiumBorder(),
              ),
              child: Icon(Icons.shuffle_rounded, size: iconSize),
            ),
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        playAllButton,
        const SizedBox(width: 8),
        shuffleButton,
      ],
    );
  }
}
