import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/utils/layout_constants.dart';
import 'folder_scan_widgets.dart';

class FolderHeaderBanner extends ConsumerStatefulWidget {
  const FolderHeaderBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.songsCount,
    required this.totalDuration,
    required this.coverWidget,
    this.coverImagePath,
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

  @override
  void initState() {
    super.initState();
    _checkImageAspectRatio();
  }

  @override
  void didUpdateWidget(FolderHeaderBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverImagePath != widget.coverImagePath) {
      _checkImageAspectRatio();
    }
  }

  void _checkImageAspectRatio() {
    final path = widget.coverImagePath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      _resolvedPath = path;
      final fileImage = FileImage(File(path));
      final stream = fileImage.resolve(ImageConfiguration.empty);
      stream.addListener(ImageStreamListener((ImageInfo info, bool _) {
        if (mounted) {
          final w = info.image.width;
          final h = info.image.height;
          if (w > 0 && h > 0) {
            setState(() {
              _aspectRatio = w / h;
            });
          }
        }
      }));
    } else {
      setState(() {
        _resolvedPath = null;
        _aspectRatio = null;
      });
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

    final hasImage = _resolvedPath != null && _resolvedPath!.isNotEmpty;
    final coverFile = hasImage ? File(_resolvedPath!) : null;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isWideOrSquare = hasImage && (_aspectRatio == null || _aspectRatio! >= 0.85);
    final bool isLowEndDevice = widget.isLowEndDevice ?? ref.watch(isLowMidEndDeviceProvider);



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
            hasImage: hasImage,
            isWideOrSquare: isWideOrSquare,
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

    Widget resolvedCover;
    if (heroTag != null) {
      resolvedCover = HeroMode(
        enabled: isHeroModeEnabled,
        child: Hero(
          tag: heroTag!,
          // Explicit linear rect tween for smooth 1:1 horizontal flight in landscape mode
          createRectTween: (begin, end) => SmoothRectTween(
            begin: begin,
            end: end,
            curve: Curves.linear,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: coverWidget,
          ),
        ),
      );
    } else {
      resolvedCover = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: coverWidget,
      );
    }

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

/// Decoupled Portrait Header Banner Component
class _FolderPortraitHeaderBanner extends StatelessWidget {
  const _FolderPortraitHeaderBanner({
    required this.title,
    required this.subtitle,
    required this.songsCount,
    required this.durationText,
    required this.coverWidget,
    required this.coverFile,
    required this.hasImage,
    required this.isWideOrSquare,
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
  final bool hasImage;
  final bool isWideOrSquare;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final desktopTitleBarHeight = isDesktop ? 28.0 : 0.0;
    final hasTopHeader = topHeader != null;

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
                          imageFilter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                          child: Image.file(
                            coverFile!,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
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
                          child: Image.file(
                            coverFile!,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            width: double.infinity,
                            height: double.infinity,
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
                            child: heroTag != null
                                ? HeroMode(
                                    enabled: isHeroModeEnabled,
                                    child: Hero(
                                      tag: heroTag!,
                                      createRectTween: (begin, end) => SmoothRectTween(
                                        begin: begin,
                                        end: end,
                                        curve: Curves.fastOutSlowIn,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: coverWidget,
                                      ),
                                    ),
                                  )
                                : ClipRRect(
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
                                  ? Image.file(
                                      coverFile!,
                                      fit: BoxFit.contain,
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

/// Custom RectTween with an explicit curve per hero transition context
class SmoothRectTween extends RectTween {
  SmoothRectTween({
    super.begin,
    super.end,
    required this.curve,
  });

  final Curve curve;

  @override
  Rect? lerp(double t) {
    return super.lerp(curve.transform(t));
  }
}
