import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:metadata_god/metadata_god.dart';
import '../player/audio_service.dart';
import '../player/metadata_database.dart';
import '../models/music_file.dart';

class CoverCarousel extends StatefulWidget {
  const CoverCarousel({
    super.key,
    required this.playlist,
    required this.currentIndex,
    required this.audioService,
    this.onPageChanged,
    this.isLandscape = false,
    this.screenWidth,
    this.screenHeight,
  });

  final List<MusicFile> playlist;
  final int currentIndex;
  final AudioService audioService;
  final Function(int)? onPageChanged;
  final bool isLandscape;
  final double? screenWidth;
  final double? screenHeight;

  @override
  State<CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends State<CoverCarousel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late int _currentPage;
  bool _isDragging = false;

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
      lowerBound: -0.5,
      upperBound: widget.playlist.length.toDouble() - 0.5,
    );
  }

  @override
  void didUpdateWidget(CoverCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex &&
        widget.currentIndex != _currentPage) {
      _currentPage = widget.currentIndex;
      _animateToPage(widget.currentIndex);
    }
  }

  void _animateToPage(int page, {double? velocity}) {
    _animationController
        .animateTo(
      page.toDouble(),
      duration: Duration(
          milliseconds: velocity != null && velocity.abs() > 500 ? 250 : 400),
      curve: Curves.easeOutCubic,
    )
        .then((_) {
      if (mounted && _currentPage != page) {
        setState(() {
          _currentPage = page;
        });
        widget.onPageChanged?.call(page);
      }
    });
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
                children: [
                   ..._buildItems(width),
                ],
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

    // Add current, previous and next
    indices.add(center);
    if (center > 0) indices.add(center - 1);
    if (center < widget.playlist.length - 1) indices.add(center + 1);

    // Sort to ensure correct layering: items further from the current value are rendered first
    final List<int> uniqueIndices = indices.toSet().toList();
    uniqueIndices.sort((a, b) {
      final distA = (a - value).abs();
      final distB = (b - value).abs();
      return distB.compareTo(distA);
    });

    return uniqueIndices.map((index) {
      return _CoverItem(
        key: ValueKey(widget.playlist[index].path),
        audioService: widget.audioService,
        musicFile: widget.playlist[index],
        animation: _animationController,
        itemIndex: index,
        width: width,
      );
    }).toList();
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
  });

  final AudioService audioService;
  final MusicFile musicFile;
  final Animation<double> animation;
  final int itemIndex;
  final double width;

  @override
  State<_CoverItem> createState() => _CoverItemState();
}

class _CoverItemState extends State<_CoverItem> {
  Uint8List? _artworkBytes;
  String? _artworkPath;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(_CoverItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.musicFile.path != widget.musicFile.path) {
      _loadArtwork();
    } else if (_artworkBytes == null) {
      // Check if we should now load high-res artwork because we are "near" or "on" the current song
      final isCurrent =
          widget.audioService.currentFilePath == widget.musicFile.path;
      final diff = (widget.audioService.currentIndex - widget.itemIndex).abs();

      if (isCurrent) {
        if (widget.audioService.currentArtworkBytes != null) {
          setState(() {
            _artworkBytes = widget.audioService.currentArtworkBytes;
          });
        } else {
          _loadHighResMetadata();
        }
      } else if (diff <= 1) {
        _loadHighResMetadata();
      }
    }
  }

  Future<void> _loadArtwork() async {
    _isLoaded = false;

    // 1. Always start with database metadata (fast placeholder)
    final db = MetadataDatabase();
    final metadata = await db.getSongMetadata(widget.musicFile.path);

    if (mounted) {
      setState(() {
        _artworkPath = metadata?.artworkPath;
        _isLoaded = true;
      });
    }

    // 2. Load high-res immediately if we are current or neighbor
    final isCurrent =
        widget.audioService.currentFilePath == widget.musicFile.path;
    final diff = (widget.audioService.currentIndex - widget.itemIndex).abs();

    if (isCurrent && widget.audioService.currentArtworkBytes != null) {
      if (mounted) {
        setState(() {
          _artworkBytes = widget.audioService.currentArtworkBytes;
        });
      }
    } else if (isCurrent || diff <= 1) {
      _loadHighResMetadata();
    }

    // 3. For Android/iOS, query if we don't have a path
    if (Platform.isAndroid || Platform.isIOS) {
      if (_artworkPath == null && widget.musicFile.id != null) {
        final bytes = await OnAudioQuery().queryArtwork(
          widget.musicFile.id!,
          ArtworkType.AUDIO,
          size: 500,
        );
        if (mounted) {
          setState(() {
            _artworkBytes = bytes;
          });
        }
      }
    }
  }

  Future<void> _loadHighResMetadata() async {
    if (!Platform.isWindows) return;

    try {
      final metadataGod = await MetadataGod.readMetadata(
        file: widget.musicFile.path,
      );
      final bytes = metadataGod.picture?.data;
      if (bytes != null && mounted) {
        setState(() {
          _artworkBytes = bytes;
        });
      }
    } catch (_) {
      // Ignore background loading errors
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

        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..translate(translateX)
              ..rotateY(rotationY)
              ..setEntry(0, 0, scale)
              ..setEntry(1, 1, scale),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
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
                            alpha: 0.15 + (0.1 * (1 - pageOffset.abs())),
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
    // Always prefer AudioService if it's the current song and has bytes
    if (widget.audioService.currentFilePath == widget.musicFile.path &&
        widget.audioService.currentArtworkBytes != null) {
      return Image.memory(
        widget.audioService.currentArtworkBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
      );
    }

    if (_artworkBytes != null) {
      return Image.memory(
        _artworkBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
      );
    } else if (_artworkPath != null) {
      final file = File(_artworkPath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
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
