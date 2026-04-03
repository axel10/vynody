import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../utils/clean_helper.dart';
import '../player/musicbrainz_tag_completion_service.dart';
import '../player/acoustid_service.dart';
import '../player/metadata_helper.dart';
import '../player/metadata_database.dart';

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
  SongMetadata? _fileMetadata;
  AcoustIDResult? _acoustidResult;
  bool _isAcoustIDLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadAcoustIDResult();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _fileMetadata = await MetadataHelper.readMetadataFromFile(
        widget.songPath,
      );
    } catch (e) {
      debugPrint('Error reading file tags: $e');
    }

    _loadMatches();
  }

  String get _displayTitle {
    final fileTitle = _fileMetadata?.title.trim();
    if (fileTitle != null && fileTitle.isNotEmpty) {
      return fileTitle;
    }
    final title = widget.currentTitle?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return CleanHelper.deriveCleanTitleFromFileName(widget.songPath);
  }

  Future<void> _loadMatches() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await _service.searchMatches(
        songPath: widget.songPath,
        title: _fileMetadata?.title ?? widget.currentTitle,
        artist: _fileMetadata?.artist ?? widget.currentArtist,
        album: _fileMetadata?.album ?? widget.currentAlbum,
        durationMillis: _fileMetadata?.duration ?? widget.durationMillis,
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

  Future<void> _loadAcoustIDResult() async {
    try {
      final apiKeyFile = File('api_keys.json');
      String apiKey;
      if (await apiKeyFile.exists()) {
        final content = await apiKeyFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        apiKey = json['AcoustID_API_KEY'] as String? ?? '';
      } else {
        debugPrint('AcoustID: api_keys.json not found');
        if (!mounted) return;
        setState(() => _isAcoustIDLoading = false);
        return;
      }

      if (apiKey.isEmpty) {
        debugPrint('AcoustID: API key is empty');
        if (!mounted) return;
        setState(() => _isAcoustIDLoading = false);
        return;
      }

      final acoustidService = AcoustIDService(apiKey: apiKey);
      final durationSec = (_fileMetadata?.duration ?? widget.durationMillis ?? 0) ~/ 1000;
      final result = await acoustidService.lookupByFingerprint(
        filePath: widget.songPath,
        durationSeconds: durationSec,
      );

      if (!mounted) return;
      setState(() {
        _acoustidResult = result;
        _isAcoustIDLoading = false;
      });
    } catch (e) {
      debugPrint('AcoustID: Failed to load result: $e');
      if (!mounted) return;
      setState(() => _isAcoustIDLoading = false);
    }
  }

  Future<void> _applyAcoustIDMatch(AcoustIDResult result) async {
    if (_isApplying) return;

    setState(() {
      _isApplying = true;
      _errorMessage = null;
    });

    try {
      final updated = SongMetadata(
        path: widget.songPath,
        title: result.title.trim().isNotEmpty ? result.title.trim() : _displayTitle,
        artist: result.artist.isNotEmpty ? result.artist : 'Unknown Artist',
        album: result.album?.trim().isNotEmpty == true ? result.album!.trim() : 'Unknown Album',
        duration: result.durationMillis ?? widget.durationMillis,
      );

      await MetadataDatabase().insertOrUpdateSong(updated);

      if (!mounted) return;
      Navigator.of(context).pop(MusicBrainzTagSelectionResult(
        metadata: updated,
        artworkBytes: null,
        match: MusicBrainzTrackMatch(
          recordingId: result.recordingId,
          title: result.title,
          artist: result.artist,
          album: result.album,
          releaseId: null,
          releaseGroupId: null,
          releaseDate: null,
          country: null,
          durationMillis: result.durationMillis,
          trackNumber: null,
          score: (result.score * 100).round().clamp(0, 100),
          disambiguation: 'AcoustID',
          raw: result.raw,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isApplying = false;
        _errorMessage = '保存失败：$e';
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
                  '根据音频指纹检索 AcoustID，并根据当前时长和已有标签检索 MusicBrainz，然后选择最接近的结果。',
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
      _InfoChip(label: '本地标题', value: _displayTitle),
      if ((_fileMetadata?.artist ?? widget.currentArtist ?? '')
          .trim()
          .isNotEmpty)
        _InfoChip(
          label: '艺术家',
          value: (_fileMetadata?.artist ?? widget.currentArtist!).trim(),
        ),
      if ((_fileMetadata?.album ?? widget.currentAlbum ?? '').trim().isNotEmpty)
        _InfoChip(
          label: '专辑',
          value: (_fileMetadata?.album ?? widget.currentAlbum!).trim(),
        ),
      if (_fileMetadata?.duration != null || widget.durationMillis != null)
        _InfoChip(
          label: '时长',
          value:
              '${((_fileMetadata?.duration ?? widget.durationMillis!) ~/ 60000).toString().padLeft(2, '0')}:${(((_fileMetadata?.duration ?? widget.durationMillis!) ~/ 1000) % 60).toString().padLeft(2, '0')}',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading && _isAcoustIDLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }

    if (_errorMessage != null && _acoustidResult == null && _matches.isEmpty) {
      return _EmptyState(
        icon: Icons.wifi_off_rounded,
        title: '检索失败',
        subtitle: _errorMessage!,
        actionLabel: '重试',
        onAction: () {
          _loadMatches();
          _loadAcoustIDResult();
        },
      );
    }

    final items = <Widget>[];

    if (_isAcoustIDLoading) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        ),
      );
    } else if (_acoustidResult != null) {
      final result = _acoustidResult!;
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Material(
            color: const Color(0xFF46D27A).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _isApplying ? null : () => _applyAcoustIDMatch(result),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF46D27A).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.fingerprint_rounded,
                          color: Color(0xFF46D27A),
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  result.title.isNotEmpty ? result.title : _displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF46D27A).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF46D27A).withValues(alpha: 0.4)),
                                ),
                                child: const Text(
                                  'AcoustID',
                                  style: TextStyle(
                                    color: Color(0xFF46D27A),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (result.artist.isNotEmpty) result.artist,
                              if (result.album != null && result.album!.isNotEmpty) result.album!,
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
                              result.durationLabel,
                              '匹配度 ${(result.score * 100).round()}%',
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
                    Icon(
                      Icons.chevron_right_rounded,
                      color: const Color(0xFF46D27A).withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (!_isLoading && _matches.isEmpty && _acoustidResult == null) {
      items.add(
        Expanded(
          child: _EmptyState(
            icon: Icons.search_off_rounded,
            title: '没有找到匹配结果',
            subtitle: '可以稍后重试，或者确认当前歌曲标题/艺人信息是否更完整。',
            actionLabel: '重新搜索',
            onAction: () {
              _loadMatches();
              _loadAcoustIDResult();
            },
          ),
        ),
      );
    } else if (!_isLoading) {
      for (var i = 0; i < _matches.length; i++) {
        final match = _matches[i];
        final durationText = match.durationLabel;
        final trackLabel = match.trackNumber != null
            ? 'Track ${match.trackNumber}'
            : 'Track --';

        items.add(
          Material(
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
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _MatchCoverImage(
                            match: match,
                            service: _service,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(6),
                                bottomRight: Radius.circular(10),
                              ),
                            ),
                            child: Text(
                              '${_acoustidResult != null ? i + 1 : i + 1}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
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
          ),
        );

        if (i < _matches.length - 1) {
          items.add(const SizedBox(height: 8));
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
      children: items,
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

class _MatchCoverImage extends StatefulWidget {
  const _MatchCoverImage({required this.match, required this.service});

  final MusicBrainzTrackMatch match;
  final MusicBrainzTagCompletionService service;

  @override
  State<_MatchCoverImage> createState() => _MatchCoverImageState();
}

class _MatchCoverImageState extends State<_MatchCoverImage> {
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    if (widget.match.resolvedCover == null) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    if (_isResolving) return;
    setState(() => _isResolving = true);
    try {
      await widget.service.resolveCover(widget.match);
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.match.thumbnailUrl;
    if (url == null) {
      return const Icon(
        Icons.music_note_rounded,
        color: Colors.white24,
        size: 24,
      );
    }

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
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.music_note_rounded, color: Colors.white24, size: 24),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null && !_isResolving) return child;
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
}
