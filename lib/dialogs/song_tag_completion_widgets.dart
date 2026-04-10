import 'package:flutter/material.dart';

import '../player/acoustid_service.dart';
import '../player/musicbrainz_tag_completion_service.dart';

class SongTagScoreBadge extends StatelessWidget {
  const SongTagScoreBadge({super.key, required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 90
        ? const Color(0xFF46D27A)
        : score >= 75
        ? const Color(0xFFFFC94D)
        : const Color(0xFF6EA8FF);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$score',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class SongTagSummaryChip extends StatelessWidget {
  const SongTagSummaryChip({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
    this.onEdit,
  });

  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final accentColor = enabled
        ? const Color(0xFF46D27A)
        : Colors.white.withValues(alpha: 0.35);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF46D27A).withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: enabled
                ? const Color(0xFF46D27A).withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              enabled
                  ? Icons.check_circle_outline_rounded
                  : Icons.block_rounded,
              size: 13,
              color: accentColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$label: $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled
                      ? Colors.white.withValues(alpha: 0.88)
                      : Colors.white.withValues(alpha: 0.58),
                  fontSize: 12,
                  decoration: enabled
                      ? TextDecoration.none
                      : TextDecoration.lineThrough,
                ),
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                icon: Icon(
                  Icons.edit_rounded,
                  size: 13,
                  color: enabled
                      ? Colors.white.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.42),
                ),
                tooltip: '编辑查询文字',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SongTagEmptyState extends StatelessWidget {
  const SongTagEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Colors.white.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class SongTagMatchCoverImage extends StatefulWidget {
  const SongTagMatchCoverImage({
    super.key,
    required this.match,
    required this.service,
  });

  final MusicBrainzTrackMatch match;
  final MusicBrainzTagCompletionService service;

  @override
  State<SongTagMatchCoverImage> createState() => _SongTagMatchCoverImageState();
}

class _SongTagMatchCoverImageState extends State<SongTagMatchCoverImage> {
  bool _isResolving = false;
  bool _hasResolved = false;
  ResolvedCover? _resolvedCover;

  @override
  void initState() {
    super.initState();
    _resolvedCover = widget.match.resolvedCover;
    if (_resolvedCover == null) {
      _resolve();
    } else {
      _hasResolved = true;
    }
  }

  Future<void> _resolve() async {
    if (_isResolving || !mounted) return;
    setState(() => _isResolving = true);
    try {
      _resolvedCover = await widget.service.resolveCover(widget.match);
    } catch (_) {
      // Keep the fallback icon behavior if cover resolution fails.
    }
    if (!mounted) return;
    setState(() {
      _isResolving = false;
      _hasResolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasResolved) {
      return Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.white.withValues(alpha: 0.15),
            ),
          ),
        ),
      );
    }

    final resolvedCover = _resolvedCover;
    if (resolvedCover != null && resolvedCover.thumbnailUrl != null) {
      final url = resolvedCover.thumbnailUrl!;
      return Image.network(
        url,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.music_note_rounded,
          color: Colors.white24,
          size: 24,
        ),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withValues(alpha: 0.15),
                ),
              ),
            ),
          );
        },
      );
    }

    return const Icon(
      Icons.music_note_rounded,
      color: Colors.white24,
      size: 24,
    );
  }
}

class SongTagAcoustIDCoverImage extends StatelessWidget {
  const SongTagAcoustIDCoverImage({super.key, required this.result});

  final AcoustIDResult result;

  @override
  Widget build(BuildContext context) {
    final url = result.thumbnailUrl;
    if (url == null) {
      return const Center(
        child: Icon(
          Icons.fingerprint_rounded,
          color: Color(0xFF46D27A),
          size: 28,
        ),
      );
    }

    return Center(
      child: Image.network(
        url,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.fingerprint_rounded,
          color: Color(0xFF46D27A),
          size: 28,
        ),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color(0xFF46D27A).withValues(alpha: 0.5),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
