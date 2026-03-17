import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../player/audio_service.dart';
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

class _CoverCarouselState extends State<CoverCarousel> {
  late PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.currentIndex;
    _pageController = PageController(
      viewportFraction: 0.9,
      initialPage: widget.currentIndex,
    );
  }

  @override
  void didUpdateWidget(CoverCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex &&
        widget.currentIndex != _currentPage) {
      _animateToPage(widget.currentIndex);
    }
  }

  void _animateToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
    widget.onPageChanged?.call(page);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.playlist.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: PageView.builder(
        clipBehavior: Clip.none,
        controller: _pageController,
        itemCount: widget.playlist.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          return _CoverItem(
            audioService: widget.audioService,
            musicFile: widget.playlist[index],
            pageController: _pageController,
            itemIndex: index,
            currentPage: _currentPage.toDouble(),
          );
        },
      ),
    );
  }
}

class _CoverItem extends StatelessWidget {
  const _CoverItem({
    required this.audioService,
    required this.musicFile,
    required this.pageController,
    required this.itemIndex,
    required this.currentPage,
  });

  final AudioService audioService;
  final MusicFile musicFile;
  final PageController pageController;
  final int itemIndex;
  final double currentPage;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        double pageOffset = 0;

        if (pageController.position.haveDimensions) {
          pageOffset = (pageController.page ?? currentPage) - itemIndex;
        } else {
          pageOffset = currentPage - itemIndex;
        }

        final double opacity = (1 - pageOffset.abs()).clamp(0.0, 1.0);
        final double scale = (1 - (pageOffset.abs() * 0.3)).clamp(0.7, 1.0);
        final double rotationY = pageOffset * -0.5;

        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(rotationY)
              ..setEntry(0, 0, scale)
              ..setEntry(1, 1, scale),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.black87,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15 + (0.1 * (1 - pageOffset.abs()))),
                          blurRadius: 50 * scale,
                          spreadRadius: 15 * scale,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildCoverImage(audioService, musicFile),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoverImage(AudioService audioService, MusicFile musicFile) {
    final artworkBytes = _getArtworkForFile(musicFile);
    final artworkPath = _getArtworkPathForFile(musicFile);

    if (artworkBytes != null) {
      return Image.memory(
        artworkBytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
      );
    } else if (artworkPath != null) {
      final file = File(artworkPath);
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

    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        child: const Icon(
          Icons.music_note,
          size: 40,
          color: Colors.white54,
        ),
      ),
    );
  }

  Uint8List? _getArtworkForFile(MusicFile musicFile) {
    if (audioService.currentFilePath == musicFile.path) {
      return audioService.currentArtworkBytes;
    }
    return null;
  }

  String? _getArtworkPathForFile(MusicFile musicFile) {
    if (audioService.currentFilePath == musicFile.path) {
      return audioService.currentArtworkPath;
    }
    return null;
  }
}
