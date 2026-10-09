import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/player/rating/song_rating_service.dart';

/// Overlay widget placed at the bottom-left of the album cover carousel
/// for song rating (0-5 stars).
///
/// Desktop: Expands horizontally on mouse hover to reveal 5 stars, with live hover preview.
/// Mobile: Tap to expand 5 stars, tap a star to set rating, auto-collapses with haptic feedback.
/// Collapsed: Displays star icon + rating number (if rated > 0).
class SongRatingOverlay extends ConsumerStatefulWidget {
  final String songPath;

  const SongRatingOverlay({
    super.key,
    required this.songPath,
  });

  @override
  ConsumerState<SongRatingOverlay> createState() => _SongRatingOverlayState();
}

class _SongRatingOverlayState extends ConsumerState<SongRatingOverlay>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isExpandedMobile = false;
  int? _hoverPreviewStar;

  bool get _isDesktop {
    if (kIsWeb) return true;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  bool get _isExpanded => _isDesktop ? _isHovered : _isExpandedMobile;

  void _onStarTapped(int star, int currentRating) {
    if (!_isDesktop) {
      HapticFeedback.lightImpact();
    }
    final ratingService = ref.read(songRatingServiceProvider);
    // Clicking the same rating unrates (clears rating to 0)
    final newRating = (star == currentRating) ? 0 : star;
    ratingService.setRating(widget.songPath, newRating);

    if (!_isDesktop) {
      Future.delayed(const Duration(milliseconds: 260), () {
        if (mounted) {
          setState(() {
            _isExpandedMobile = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.songPath.isEmpty) {
      return const SizedBox.shrink();
    }

    final rating = ref.watch(songRatingProvider(widget.songPath));
    final hasRating = rating > 0;

    return MouseRegion(
      onEnter: (_) {
        if (_isDesktop) {
          setState(() {
            _isHovered = true;
          });
        }
      },
      onExit: (_) {
        if (_isDesktop) {
          setState(() {
            _isHovered = false;
            _hoverPreviewStar = null;
          });
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_isDesktop) {
            setState(() {
              _isExpandedMobile = !_isExpandedMobile;
            });
          }
        },
        onSecondaryTapDown: (_) {},
        onLongPressStart: (_) {},
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: 32,
              padding: EdgeInsets.symmetric(
                horizontal: (!_isExpanded && !hasRating) ? 13 : 8,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                  alpha: _isExpanded ? 0.38 : 0.18,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: _isExpanded ? 0.16 : 0.08,
                  ),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: _isExpanded ? 0.20 : 0.10,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: _isExpanded
                    ? _buildExpandedStars(rating)
                    : _buildCollapsedView(rating, hasRating),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedView(int rating, bool hasRating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          hasRating ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 19,
          color: hasRating
              ? const Color(0xFFFFC107)
              : Colors.white.withValues(alpha: 0.75),
        ),
        if (hasRating) ...[
          const SizedBox(width: 4),
          Text(
            '$rating',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 2),
        ],
      ],
    );
  }

  Widget _buildExpandedStars(int currentRating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final isHighlighted = _hoverPreviewStar != null
            ? starValue <= _hoverPreviewStar!
            : starValue <= currentRating;

        return MouseRegion(
          onEnter: (_) {
            if (_isDesktop) {
              setState(() {
                _hoverPreviewStar = starValue;
              });
            }
          },
          onExit: (_) {
            if (_isDesktop) {
              setState(() {
                _hoverPreviewStar = null;
              });
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onStarTapped(starValue, currentRating),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: AnimatedScale(
                scale: (_hoverPreviewStar == starValue) ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 140),
                child: Icon(
                  isHighlighted ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 20,
                  color: isHighlighted
                      ? const Color(0xFFFFC107)
                      : Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
