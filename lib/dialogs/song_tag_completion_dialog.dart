import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../player/musicbrainz_tag_completion_service.dart';

class SongTagCompletionSheet extends StatefulWidget {
  const SongTagCompletionSheet({
    super.key,
    required this.songPath,
    required this.currentTitle,
    required this.currentArtist,
    required this.currentAlbum,
    required this.durationMillis,
  });

  final String songPath;
  final String? currentTitle;
  final String? currentArtist;
  final String? currentAlbum;
  final int? durationMillis;

  @override
  State<SongTagCompletionSheet> createState() => _SongTagCompletionSheetState();
}

class _SongTagCompletionSheetState extends State<SongTagCompletionSheet> {
  final MusicBrainzTagCompletionService _service =
      MusicBrainzTagCompletionService();

  List<MusicBrainzTrackMatch> _matches = const [];
  bool _isLoading = true;
  bool _isApplying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  String get _displayTitle {
    final title = widget.currentTitle?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return _cleanFallbackTitle(widget.songPath);
  }

  Future<void> _loadMatches() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await _service.searchMatches(
        songPath: widget.songPath,
        title: widget.currentTitle,
        artist: widget.currentArtist,
        album: widget.currentAlbum,
        durationMillis: widget.durationMillis,
      );

      if (!mounted) return;
      setState(() {
        _matches = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _applyMatch(MusicBrainzTrackMatch match) async {
    if (_isApplying) return;

    setState(() {
      _isApplying = true;
      _errorMessage = null;
    });

    try {
      final result = await _service.applySelection(
        songPath: widget.songPath,
        match: match,
        fallbackDurationMillis: widget.durationMillis,
      );

      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isApplying = false;
        _errorMessage = '保存失败：$e';
      });
    }
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '歌曲标签补全',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '根据当前时长和已有标签检索 MusicBrainz，然后选择最接近的结果。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isLoading ? null : _loadMatches,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: '刷新结果',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final chips = <Widget>[
      _InfoChip(label: '标题', value: _displayTitle),
      if ((widget.currentArtist ?? '').trim().isNotEmpty)
        _InfoChip(label: '艺术家', value: widget.currentArtist!.trim()),
      if ((widget.currentAlbum ?? '').trim().isNotEmpty)
        _InfoChip(label: '专辑', value: widget.currentAlbum!.trim()),
      if (widget.durationMillis != null)
        _InfoChip(
          label: '时长',
          value:
              '${(widget.durationMillis! ~/ 60000).toString().padLeft(2, '0')}:${((widget.durationMillis! ~/ 1000) % 60).toString().padLeft(2, '0')}',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }

    if (_errorMessage != null) {
      return _EmptyState(
        icon: Icons.wifi_off_rounded,
        title: '检索失败',
        subtitle: _errorMessage!,
        actionLabel: '重试',
        onAction: _loadMatches,
      );
    }

    if (_matches.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off_rounded,
        title: '没有找到匹配结果',
        subtitle: '可以稍后重试，或者确认当前歌曲标题/艺人信息是否更完整。',
        actionLabel: '重新搜索',
        onAction: _loadMatches,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: _matches.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final match = _matches[index];
        final durationText = match.durationLabel;
        final trackLabel = match.trackNumber != null
            ? 'Track ${match.trackNumber}'
            : 'Track --';

        return Material(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _isApplying ? null : () => _applyMatch(match),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: 0.18,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          match.title.isNotEmpty ? match.title : _displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (match.artist.isNotEmpty) match.artist,
                            if (match.album != null && match.album!.isNotEmpty)
                              match.album!,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          [
                            trackLabel,
                            durationText,
                            '评分 ${match.score}',
                            if (match.releaseDate != null &&
                                match.releaseDate!.isNotEmpty)
                              match.releaseDate!,
                            if (match.disambiguation != null &&
                                match.disambiguation!.isNotEmpty)
                              match.disambiguation!,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _ScoreBadge(score: match.score),
                      const SizedBox(height: 10),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.82),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    _buildSummary(context),
                    const SizedBox(height: 14),
                    Expanded(child: _buildBody(context)),
                  ],
                ),
                if (_isApplying)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.35),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _cleanFallbackTitle(String songPath) {
  final base = p.basenameWithoutExtension(songPath).trim();
  final stripped = base.replaceFirst(RegExp(r'^\s*(?:\d{1,3}[\s._-]*)+'), '');
  final candidate = stripped.trim();
  return candidate.isEmpty ? base : candidate;
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        '$label: $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.8),
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
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
