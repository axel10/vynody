import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/player/metadata/acoustid_service.dart';
import 'package:vibe_flow/player/metadata/musicbrainz_tag_completion_service.dart';
import 'package:vibe_flow/utils/network_client.dart';
import '../widgets/query_condition_chip.dart';

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
    return QueryConditionChip(
      label: label,
      value: value,
      enabled: enabled,
      onTap: onTap,
      onEdit: onEdit,
      activeBackgroundColor: const Color(0xFF46D27A).withValues(alpha: 0.12),
      inactiveBackgroundColor: Colors.white.withValues(alpha: 0.04),
      activeBorderColor: const Color(0xFF46D27A).withValues(alpha: 0.28),
      inactiveBorderColor: Colors.white.withValues(alpha: 0.06),
      activeTextColor: Colors.white.withValues(alpha: 0.88),
      inactiveTextColor: Colors.white.withValues(alpha: 0.58),
      activeIconColor: const Color(0xFF46D27A),
      inactiveIconColor: Colors.white.withValues(alpha: 0.35),
      editTooltip: AppLocalizations.of(context)!.editQueryCondition,
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

class ProxyNetworkImage extends StatefulWidget {
  const ProxyNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.frameDuration = const Duration(milliseconds: 300),
  });

  final String url;
  final BoxFit fit;
  final Widget Function(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  )?
  errorBuilder;
  final Duration frameDuration;

  @override
  State<ProxyNetworkImage> createState() => _ProxyNetworkImageState();
}

class _ProxyNetworkImageState extends State<ProxyNetworkImage> {
  static final Map<String, Uint8List> _imageCache = {};
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  Uint8List? _bytes;
  Object? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProxyNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _error = null;
      _isLoading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final cached = _imageCache[widget.url];
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        _bytes = cached;
        _isLoading = false;
      });
      return;
    }

    final inFlight = _inFlight[widget.url];
    final future = inFlight ?? _fetchBytes(widget.url);
    _inFlight[widget.url] = future;

    try {
      final bytes = await future;
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _isLoading = false;
        if (bytes != null && bytes.isNotEmpty) {
          _imageCache[widget.url] = bytes;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    } finally {
      if (_inFlight[widget.url] == future) {
        _inFlight.remove(widget.url);
      }
    }
  }

  Future<Uint8List?> _fetchBytes(String url) async {
    final response = await NetworkClient.instance.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data ?? const <int>[];
    if (data.isEmpty) return null;
    return Uint8List.fromList(data);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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

    final bytes = _bytes;
    if (bytes == null || bytes.isEmpty) {
      final error = _error ?? StateError('Failed to load image bytes.');
      return widget.errorBuilder?.call(context, error, null) ??
          const Icon(Icons.image_not_supported_outlined, color: Colors.white24);
    }

    return AnimatedOpacity(
      opacity: 1,
      duration: widget.frameDuration,
      curve: Curves.easeOut,
      child: Image.memory(bytes, fit: widget.fit, gaplessPlayback: true),
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
      return ProxyNetworkImage(
        url: url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.music_note_rounded,
          color: Colors.white24,
          size: 24,
        ),
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
      child: ProxyNetworkImage(
        url: url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.fingerprint_rounded,
          color: Color(0xFF46D27A),
          size: 28,
        ),
      ),
    );
  }
}
