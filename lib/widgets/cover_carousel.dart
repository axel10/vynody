import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../player/audio_service.dart';
import '../player/metadata_helper.dart';
import '../models/music_file.dart';

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
  final ValueChanged<Uint8List?>? onAnimationComplete;
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
    final loadedBytes = _loadedCovers[page]?.bytes ?? currentSong.artworkBytes;

    if (loadedBytes != null) {
      widget.onAnimationComplete?.call(loadedBytes);
      return;
    }

    if (currentSong.artworkBytes == null && currentSong.artworkPath == null) {
      widget.onAnimationComplete?.call(null);
    }
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
              // 如果是当前播放曲目的封面加载完成，通知背景更新
              if (actualIndex == widget.currentIndex && bytes != null) {
                widget.onAnimationComplete?.call(bytes);
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
  Uint8List? _artworkBytes;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(_CoverItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the path changed, we must reset everything
    if (oldWidget.musicFile.path != widget.musicFile.path) {
      _artworkBytes = null;
      _loadArtwork();
    }
    // If the path is the same but artworkBytes or artworkPath appeared, we should update.
    // This happens when background processing completes.
    else if (widget.musicFile.artworkBytes !=
            oldWidget.musicFile.artworkBytes ||
        widget.musicFile.artworkPath != oldWidget.musicFile.artworkPath ||
        widget.musicFile.thumbnailPath != oldWidget.musicFile.thumbnailPath) {
      _loadArtwork();
    }
  }

  Future<void> _loadArtwork() async {
    _isLoaded = true;

    // If we have original HD bytes in cache, use them.
    final cachedBytes = widget.audioService.getCachedArtwork(
      widget.musicFile.path,
    );
    if (cachedBytes != null) {
      if (!mounted) return;
      setState(() => _artworkBytes = cachedBytes);
      widget.onArtworkLoaded?.call(cachedBytes, null);
      return;
    }

    if (widget.audioService.currentMusic?.path == widget.musicFile.path &&
        widget.audioService.currentMusic?.artworkBytes != null) {
      if (!mounted) return;
      setState(
        () => _artworkBytes = widget.audioService.currentMusic!.artworkBytes,
      );
      widget.onArtworkLoaded?.call(
        widget.audioService.currentMusic!.artworkBytes,
        null,
      );
      return;
    }

    // 3. Try artworkPath if it exists (high res local)
    final highResPath = widget.musicFile.artworkPath;
    if (highResPath != null) {
      try {
        final file = File(highResPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (!mounted) return;
          setState(() {
            _artworkBytes = bytes;
          });
          widget.onArtworkLoaded?.call(bytes, null);
          return;
        }
      } catch (e) {
        debugPrint('Error loading high res artwork from $highResPath: $e');
      }
    }

    // 4. Try thumbnailPath as a temporary display fallback only.
    // This does not promote thumbnail bytes into artworkBytes in the model.
    final thumbnailPath = widget.musicFile.thumbnailPath;
    if (thumbnailPath != null) {
      try {
        final file = File(thumbnailPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (!mounted) return;
          setState(() {
            _artworkBytes = bytes;
          });
          widget.onArtworkLoaded?.call(bytes, thumbnailPath);
          return;
        }
      } catch (e) {
        debugPrint('Error loading thumbnail artwork from $thumbnailPath: $e');
      }
    }

    // 5. Try system query (on_audio_query)
    if (Platform.isAndroid || Platform.isIOS) {
      if (widget.musicFile.id != null) {
        final bytes = await OnAudioQuery().queryArtwork(
          widget.musicFile.id!,
          ArtworkType.AUDIO,
          size: 800,
        );
        if (!mounted || bytes == null) return;
        setState(() {
          _artworkBytes = bytes;
        });
        widget.onArtworkLoaded?.call(bytes, null);
        return;
      }
    }

    // 6. Try extracting embedded artwork as last resort
    final embeddedBytes = await MetadataHelper.decodeEmbeddedArtwork(
      widget.musicFile.path,
    );
    if (embeddedBytes != null) {
      if (!mounted) return;
      setState(() {
        _artworkBytes = embeddedBytes;
      });
      widget.onArtworkLoaded?.call(embeddedBytes, null);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        final double pageOffset = widget.animation.value - widget.itemIndex;
        final double opacity = (1 - pageOffset.abs() * 1.2).clamp(0.0, 1.0);
        final double scale = (1 - (pageOffset.abs() * 0.3)).clamp(0.8, 1.0);
        final double rotationY = pageOffset * -0.3;
        final double translateX = pageOffset * -widget.width;

        return RepaintBoundary(
          child: Opacity(
            opacity: opacity,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..translateByDouble(translateX, 0, 0, 1.0)
                ..rotateY(rotationY)
                ..setEntry(0, 0, scale)
                ..setEntry(1, 1, scale),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.black26,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: 0.10 + (0.1 * (1 - pageOffset.abs())),
                          ),
                          blurRadius: 50 * scale,
                          spreadRadius: 15 * scale,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildCoverImage(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoverImage() {
    final double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final isPc = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final int limit = isPc ? 1200 : 800;

    final int cacheSize = widget.displaySize != null
        ? math.min((widget.displaySize! * devicePixelRatio).round(), limit)
        : limit;

    final cachedBytes = widget.audioService.getCachedArtwork(
      widget.musicFile.path,
    );
    if (cachedBytes != null) {
      return Image.memory(
        cachedBytes,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        cacheWidth: cacheSize,
      );
    }

    if (widget.audioService.currentMusic?.path == widget.musicFile.path &&
        widget.audioService.currentMusic?.artworkBytes != null) {
      return Image.memory(
        widget.audioService.currentMusic!.artworkBytes!,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        cacheWidth: cacheSize,
      );
    }

    if (_artworkBytes != null) {
      return Image.memory(
        _artworkBytes!,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        cacheWidth: cacheSize,
      );
    } else {
      // Prioritize high-res artwork path, but allow thumbnailPath as fallback
      // if the high-res file is not available yet.
      final imagePath = widget.musicFile.artworkPath;
      if (imagePath != null) {
        final file = File(imagePath);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            cacheWidth: cacheSize,
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
            cacheWidth: cacheSize,
          );
        }
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
