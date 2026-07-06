import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:vynody/models/music_file.dart';
import 'package:audio_core/audio_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vynody/utils/memory_trace.dart';

class CoverCarousel extends StatefulWidget {
  const CoverCarousel({
    super.key,
    required this.playlist,
    required this.currentIndex,
    required this.audioService,
    this.onPageChanged,
    this.onAnimationComplete,
    this.isLandscape = false,
    this.isNext,
    this.displaySize,
  });

  final List<MusicFile> playlist;
  final int currentIndex;
  final AudioService audioService;
  final Function(int)? onPageChanged;
  final void Function(Uint8List? artworkBytes, String? sourcePath)?
  onAnimationComplete;
  final bool isLandscape;
  final bool? isNext;
  final double? displaySize;

  @override
  State<CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends State<CoverCarousel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late int _currentPage;
  bool _isDragging = false;
  final Map<int, int> _indexOverrides = {};
  final Map<int, ({Uint8List? bytes, String? path})> _loadedCovers = {};

  static const double _swipeThreshold = 0.2;
  static const double _resistanceFactor = 0.2;

  void _logCarouselTrace(String message) {
    if (!kDebugMode) return;
    debugPrint('[CoverCarousel][Trace] $message');
  }

  @override
  void initState() {
    super.initState();
    _currentPage = widget.currentIndex;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: widget.currentIndex.toDouble(),
      lowerBound: -1000.5,
      upperBound: widget.playlist.length.toDouble() + 1000.5,
    );
  }

  @override
  void didUpdateWidget(CoverCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _logCarouselTrace(
      'didUpdateWidget currentIndex ${oldWidget.currentIndex} -> ${widget.currentIndex} '
      'currentPage=$_currentPage animValue=${_animationController.value}',
    );
    if (widget.currentIndex != oldWidget.currentIndex &&
        widget.currentIndex != _currentPage) {
      _currentPage = widget.currentIndex;
      _animateToPage(widget.currentIndex, forceStepDirection: true);
    }
  }

  void _animateToPage(
    int page, {
    double? velocity,
    bool forceStepDirection = false,
  }) {
    _logCarouselTrace(
      '_animateToPage page=$page forceStepDirection=$forceStepDirection '
      'velocity=$velocity currentVal=${_animationController.value} '
      'currentPage=$_currentPage isNext=${widget.isNext}',
    );
    final double currentVal = _animationController.value;
    final int targetPage = page;
    final double diff = targetPage - currentVal;

    if (diff == 0) return;

    if (forceStepDirection || diff.abs() > 1.5) {
      final bool isForward = widget.isNext ?? (diff > 0);
      final int direction = isForward ? 1 : -1;
      final int virtualTarget = currentVal.round() + direction;

      _indexOverrides[virtualTarget] = targetPage;

      _animationController
          .animateTo(
            virtualTarget.toDouble(),
            duration: Duration(
              milliseconds: velocity != null && velocity.abs() > 500
                  ? 250
                  : 400,
            ),
            curve: Curves.easeOutCubic,
          )
          .then((_) {
            if (mounted) {
              _logCarouselTrace(
                '_animateToPage virtual complete -> targetPage=$targetPage '
                'virtualTarget=$virtualTarget currentVal=${_animationController.value}',
              );
              _animationController.value = targetPage.toDouble();
              _indexOverrides.clear();
              if (_currentPage != targetPage) {
                setState(() {
                  _currentPage = targetPage;
                });
                widget.onPageChanged?.call(targetPage);
              }
              _notifyAnimationComplete(targetPage);
            }
          });
    } else {
      _animationController
          .animateTo(
            page.toDouble(),
            duration: Duration(
              milliseconds: velocity != null && velocity.abs() > 500
                  ? 250
                  : 400,
            ),
            curve: Curves.easeOutCubic,
          )
          .then((_) {
            if (mounted) {
              _logCarouselTrace(
                '_animateToPage complete -> page=$page '
                'currentVal=${_animationController.value}',
              );
              if (_currentPage != page) {
                setState(() {
                  _currentPage = page;
                });
                widget.onPageChanged?.call(page);
              }
              _notifyAnimationComplete(page);
            }
          });
    }
  }

  void _notifyAnimationComplete(int page) {
    final currentSong = widget.playlist[page];
    final loadedPath = _loadedCovers[page]?.path ?? currentSong.artworkPath ?? currentSong.thumbnailPath;
    _logCarouselTrace(
      '_notifyAnimationComplete page=$page song=${currentSong.path} '
      'loadedPath=$loadedPath',
    );

    widget.onAnimationComplete?.call(null, loadedPath);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.playlist.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return GestureDetector(
          onHorizontalDragStart: (details) {
            _isDragging = true;
          },
          onHorizontalDragUpdate: (details) {
            if (!_isDragging) return;

            final delta = details.primaryDelta ?? 0;
            double adjustedDelta = delta;

            if (delta > 0 && _animationController.value <= 0) {
              adjustedDelta *= _resistanceFactor;
            } else if (delta < 0 &&
                _animationController.value >= widget.playlist.length - 1) {
              adjustedDelta *= _resistanceFactor;
            }

            _animationController.value -= adjustedDelta / width;
          },
          onHorizontalDragEnd: (details) {
            if (!_isDragging) return;

            final velocity = details.primaryVelocity ?? 0;
            int targetPage = _currentPage;
            final currentVal = _animationController.value;

            if (velocity.abs() > 500) {
              if (velocity < 0 && _currentPage < widget.playlist.length - 1) {
                targetPage = _currentPage + 1;
              } else if (velocity > 0 && _currentPage > 0) {
                targetPage = _currentPage - 1;
              }
            } else {
              final diff = currentVal - _currentPage;
              if (diff > _swipeThreshold &&
                  _currentPage < widget.playlist.length - 1) {
                targetPage = _currentPage + 1;
              } else if (diff < -_swipeThreshold && _currentPage > 0) {
                targetPage = _currentPage - 1;
              }
            }

            _isDragging = false;
            _animateToPage(targetPage, velocity: velocity);
          },
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Stack(
                clipBehavior: Clip.none,
                children: [..._buildItems(width)],
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _buildItems(double width) {
    final double value = _animationController.value;
    final int center = value.round();
    final List<int> indices = [];

    indices.add(center);
    indices.add(center - 1);
    indices.add(center + 1);

    final List<int> uniqueIndices = indices.toSet().toList();
    uniqueIndices.sort((a, b) {
      final distA = (a - value).abs();
      final distB = (b - value).abs();
      return distB.compareTo(distA);
    });

    return uniqueIndices
        .where((idx) {
          final actualIdx = _indexOverrides[idx] ?? idx;
          return actualIdx >= 0 && actualIdx < widget.playlist.length;
        })
        .map((index) {
          final actualIndex = _indexOverrides[index] ?? index;
          return _CoverItem(
            key: ValueKey('track_${actualIndex}_slot_$index'),
            audioService: widget.audioService,
            musicFile: widget.playlist[actualIndex],
            animation: _animationController,
            itemIndex: index,
            width: width,
            displaySize: widget.displaySize,
            onArtworkLoaded: (bytes, path) {
              _loadedCovers[index] = (bytes: bytes, path: path);
              _logCarouselTrace(
                'onArtworkLoaded slot=$index actual=$actualIndex '
                'path=${widget.playlist[actualIndex].path} '
                'sourcePath=${path ?? '-'} '
                'currentIndex=${widget.currentIndex}',
              );
              // 如果是当前播放曲目的封面加载完成，且轮播动画已静止，通知背景更新
              // 否则，由 _notifyAnimationComplete 在动画结束时统一通知，以维持背景延迟切换效果
              final isSettled = (_animationController.value - index).abs() < 0.01 &&
                  !_animationController.isAnimating &&
                  !_isDragging;
              if (actualIndex == widget.currentIndex && path != null && isSettled) {
                widget.onAnimationComplete?.call(
                  null,
                  path,
                );
              }
            },
          );
        })
        .toList();
  }
}

class _CoverItem extends StatefulWidget {
  const _CoverItem({
    super.key,
    required this.audioService,
    required this.musicFile,
    required this.animation,
    required this.itemIndex,
    required this.width,
    this.displaySize,
    this.onArtworkLoaded,
  });

  final AudioService audioService;
  final MusicFile musicFile;
  final Animation<double> animation;
  final int itemIndex;
  final double width;
  final double? displaySize;
  final void Function(Uint8List? bytes, String? path)? onArtworkLoaded;

  @override
  State<_CoverItem> createState() => _CoverItemState();
}

class _CoverItemState extends State<_CoverItem> {
  String? _artworkPath;
  bool _isLoaded = false;
  bool _hasLoadedHighRes = false;



  bool get _isSettled {
    final double pageOffset = widget.animation.value - widget.itemIndex;
    return pageOffset.abs() < 0.01 && !widget.animation.isAnimating;
  }

  void _handleAnimationUpdate() {
    if (!mounted) return;
    if (_isSettled && !_hasLoadedHighRes) {
      _loadHighResArtwork();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_handleAnimationUpdate);
    _loadArtwork();
  }

  @override
  void didUpdateWidget(_CoverItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_handleAnimationUpdate);
      widget.animation.addListener(_handleAnimationUpdate);
    }
    // If the path changed, we must reset everything
    if (oldWidget.musicFile.path != widget.musicFile.path) {
      _artworkPath = null;
      _isLoaded = false;
      _hasLoadedHighRes = false;
      _loadArtwork();
    }
    // If the path is the same but artworkPath appeared, we should update.
    // This happens when background processing completes.
    else if (widget.musicFile.artworkPath != oldWidget.musicFile.artworkPath) {
      if (_isSettled) {
        _loadArtwork();
      }
    }
  }

  @override
  void dispose() {
    widget.animation.removeListener(_handleAnimationUpdate);
    super.dispose();
  }

  Future<void> _loadArtwork() async {
    _isLoaded = true;
    if (kDebugMode) {
      debugPrint(
        '[CoverCarousel][Trace] _loadArtwork start path=${widget.musicFile.path} '
        'currentMusic=${widget.audioService.currentMusic?.path ?? '-'}',
      );
    }
    MemoryTrace.snapshot(
      'coverCarousel:loadArtwork:start',
      details: <String, Object?>{
        'path': widget.musicFile.path,
        'slot': widget.itemIndex,
      },
    );

    // 1. Try large artworkPath first
    final artworkPath = widget.musicFile.artworkPath;
    if (artworkPath != null && File(artworkPath).existsSync()) {
      if (!mounted) return;
      setState(() {
        _artworkPath = artworkPath;
        _hasLoadedHighRes = true;
      });
      widget.onArtworkLoaded?.call(null, artworkPath);
      return;
    }

    // 2. Try thumbnailPath next
    final thumbPath = widget.musicFile.thumbnailPath;
    if (thumbPath != null && File(thumbPath).existsSync()) {
      if (!mounted) return;
      setState(() {
        _artworkPath = thumbPath;
      });
      widget.onArtworkLoaded?.call(null, thumbPath);

      if (_isSettled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isSettled && !_hasLoadedHighRes) {
            _loadHighResArtwork();
          }
        });
      }
      return;
    }

    // 3. If no thumbnail exists, trigger high-res load immediately
    _loadHighResArtwork();
  }

  Future<void> _loadHighResArtwork() async {
    if (_hasLoadedHighRes) return;
    _hasLoadedHighRes = true;

    final highResPath = widget.musicFile.artworkPath;
    if (highResPath != null && File(highResPath).existsSync()) {
      if (!mounted) return;
      setState(() {
        _artworkPath = highResPath;
      });
      widget.onArtworkLoaded?.call(null, highResPath);
      return;
    }

    // Try system query (on_audio_query)
    if (Platform.isAndroid || Platform.isIOS) {
      if (widget.musicFile.id != null) {
        final bytes = await OnAudioQuery().queryArtwork(
          widget.musicFile.id!,
          ArtworkType.AUDIO,
          size: 800,
        );
        if (!mounted || bytes == null) return;

        final md5Hex = await calculateMd5(bytes: bytes);
        final supportDir = await getApplicationSupportDirectory();
        final thumbnailsDir = Directory('${supportDir.path}/thumbnails');
        if (!thumbnailsDir.existsSync()) {
          await thumbnailsDir.create(recursive: true);
        }
        final file = File('${thumbnailsDir.path}/${md5Hex}_thumb.jpg');
        if (!file.existsSync()) {
          await file.writeAsBytes(bytes);
        }
        final savedPath = file.path;

        if (!mounted) return;
        setState(() {
          _artworkPath = savedPath;
        });
        widget.onArtworkLoaded?.call(null, savedPath);
        return;
      }
    }

    // Try extracting embedded artwork as last resort
    final embeddedBytes = await MetadataHelper.decodeEmbeddedArtwork(
      widget.musicFile.path,
    );
    if (embeddedBytes != null) {
      if (!mounted) return;
      final md5Hex = await calculateMd5(bytes: embeddedBytes);
      final supportDir = await getApplicationSupportDirectory();
      final thumbnailsDir = Directory('${supportDir.path}/thumbnails');
      if (!thumbnailsDir.existsSync()) {
        await thumbnailsDir.create(recursive: true);
      }
      final file = File('${thumbnailsDir.path}/${md5Hex}_thumb.jpg');
      if (!file.existsSync()) {
        await file.writeAsBytes(embeddedBytes);
      }
      final savedPath = file.path;

      if (!mounted) return;
      setState(() {
        _artworkPath = savedPath;
      });
      widget.onArtworkLoaded?.call(null, savedPath);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        final double pageOffset = widget.animation.value - widget.itemIndex;
        final double opacity = (1 - pageOffset.abs() * 1.2).clamp(0.0, 1.0);
        final double scale = (1 - (pageOffset.abs() * 0.3)).clamp(0.8, 1.0);
        final double rotationY = pageOffset * -0.3;

        // Round translation to nearest physical pixel to avoid blurriness
        final double rawTranslateX = pageOffset * -widget.width;
        final double translateX =
            (rawTranslateX * devicePixelRatio).round() / devicePixelRatio;

        // Snapping scale to 1.0 and rotation to 0.0 when very close to 0 to ensure pixel-perfect rendering
        final bool isCentered = pageOffset.abs() < 0.001;
        final double effectiveScale = isCentered ? 1.0 : scale;
        final double effectiveRotationY = isCentered ? 0.0 : rotationY;

        // Only apply perspective if there is actual rotation
        final double perspective = effectiveRotationY != 0 ? 0.001 : 0.0;

        return RepaintBoundary(
          child: Opacity(
            opacity: opacity,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, perspective)
                ..translateByDouble(translateX, 0, 0, 1.0)
                ..rotateY(effectiveRotationY)
                ..scaleByDouble(
                  effectiveScale,
                  effectiveScale,
                  effectiveScale,
                  1.0,
                ),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.black26,
                      boxShadow: [
                        // Deep soft ambient shadow
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: (0.07 + 0.12 * (1 - pageOffset.abs())),
                          ),
                          blurRadius: 3 * scale,
                          spreadRadius: 2 * scale,
                          offset: Offset(0, 2 * scale),
                        ),
                        // Crisp contact shadow
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: (0.10 + 0.08 * (1 - pageOffset.abs())),
                          ),
                          blurRadius: 16 * scale,
                          spreadRadius: -4 * scale,
                          offset: Offset(0, 8 * scale),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildCoverImage(isCentered),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoverImage(bool isCentered) {
    final String? artworkPath = _artworkPath ?? widget.musicFile.artworkPath;
    if (artworkPath != null) {
      final file = File(artworkPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          filterQuality: isCentered ? FilterQuality.low : FilterQuality.medium,
        );
      }
    }

    final thumbPath = widget.musicFile.thumbnailPath;
    if (thumbPath != null) {
      final file = File(thumbPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          filterQuality: isCentered ? FilterQuality.low : FilterQuality.medium,
        );
      }
    }

    if (!_isLoaded) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
      );
    }

    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        child: const Icon(Icons.music_note, size: 40, color: Colors.white54),
      ),
    );
  }
}
